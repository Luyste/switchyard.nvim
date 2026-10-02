-- Agents are CLI programs that run in tmux; switchyard only needs to know how
-- to start them. An agent is a table:
--   name      shown in the yard and used in tmux session names
--   cmd       start a new session: { "pi" }
--   continue  optional: continue the last session in this folder
--   task      optional: true = the task goes after `cmd` as its first message,
--             or function(task) returning the command
--   fork      optional: function(session, note) returning the command that
--             starts a copy of `session`'s conversation with `note` as its
--             first message (nil when it can't)
--   history   optional: function(cwd, running) returning this folder's earlier
--             sessions, newest first: { { time, title, cmd } } (`running` = the
--             agent's sessions running there now, left out of the list)
--   match     optional: a Lua pattern for its process command line (default:
--             the program named like cmd[1], see snapshot.lua)
local M = {}

-- pi keeps each folder's sessions in ~/.pi/agent/sessions/--<path>--/*.jsonl;
-- the newest file is the live one
local function latest_pi_session(cwd)
	local path = vim.uv.fs_realpath(cwd) or cwd
	local dir = vim.fn.expand("~/.pi/agent/sessions/") .. "--" .. path:gsub("^/", ""):gsub("[/:]", "-") .. "--"
	local newest, newest_time
	for _, file in ipairs(vim.fn.glob(dir .. "/*.jsonl", false, true)) do
		local t = vim.fn.getftime(file)
		if not newest_time or t > newest_time then
			newest, newest_time = file, t
		end
	end
	return newest
end

-- Claude Code registers each running session in ~/.claude/sessions/<pid>.json
local function claude_session_id(pid)
	local ok, info = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(vim.fn.expand("~/.claude/sessions/") .. pid .. ".json"), ""))
	end)
	return ok and type(info) == "table" and type(info.sessionId) == "string" and info.sessionId or nil
end

-- The JSON lines of a chunk of `file`: its first `size` bytes, or its last
-- (`from_end`). Session files grow to megabytes; titles sit near an end.
-- The chunk's cut lines don't decode and are skipped.
local function json_lines(file, size, from_end)
	local fd = vim.uv.fs_open(file, "r", 438)
	if not fd then
		return {}
	end
	local stat = vim.uv.fs_fstat(fd)
	local data = vim.uv.fs_read(fd, size, from_end and math.max(0, stat.size - size) or 0) or ""
	vim.uv.fs_close(fd)
	local list = {}
	for line in data:gmatch("[^\n]+") do
		local ok, value = pcall(vim.json.decode, line)
		if ok and type(value) == "table" then
			table.insert(list, value)
		end
	end
	return list
end

-- The session files matching `glob`, newest first: { { file, time } }
local function newest_first(glob)
	local list = vim.tbl_map(function(file)
		return { file = file, time = vim.fn.getftime(file) }
	end, vim.fn.glob(glob, false, true))
	table.sort(list, function(a, b)
		return a.time > b.time
	end)
	return list
end

-- pi: a session's title is its first prompt. The newest files are the
-- running sessions' (ponytail: assumes the running ones are the newest).
local function pi_history(cwd, running)
	local path = vim.uv.fs_realpath(cwd) or cwd
	local dir = vim.fn.expand("~/.pi/agent/sessions/") .. "--" .. path:gsub("^/", ""):gsub("[/:]", "-") .. "--"
	local list = {}
	for i, entry in ipairs(newest_first(dir .. "/*.jsonl")) do
		if i > #running then
			local title
			for _, line in ipairs(json_lines(entry.file, 32768)) do
				local message = line.type == "message" and line.message or {}
				if message.role == "user" and type(message.content) == "table" then
					title = (message.content[1] or {}).text
					break
				end
			end
			table.insert(list, { time = entry.time, title = title, cmd = { "pi", "--session", entry.file } })
		end
	end
	return list
end

-- Claude Code: ~/.claude/projects/<path, every non-alphanumeric a "-">/<id>.jsonl;
-- the title is the last custom title (/rename), else the last AI title, else
-- the last prompt. No title = no conversation (only local commands): left out.
local function claude_history(cwd, running)
	local path = vim.uv.fs_realpath(cwd) or cwd
	local live = {}
	for _, s in ipairs(running) do
		live[claude_session_id(s.pid) or ""] = true
	end
	local list = {}
	for _, entry in ipairs(newest_first(vim.fn.expand("~/.claude/projects/") .. path:gsub("[^%w]", "-") .. "/*.jsonl")) do
		local id = vim.fn.fnamemodify(entry.file, ":t:r")
		if not live[id] then
			local custom, ai, prompt
			for _, line in ipairs(json_lines(entry.file, 65536, true)) do
				custom = line.customTitle or custom
				ai = line.aiTitle or ai
				prompt = line.lastPrompt or prompt
			end
			local title = custom or ai or prompt
			if title then
				table.insert(list, { time = entry.time, title = title, cmd = { "claude", "--resume", id } })
			end
		end
	end
	return list
end

M.presets = {
	pi = {
		name = "pi",
		cmd = { "pi" },
		continue = { "pi", "--continue" },
		history = pi_history,
		task = true,
		fork = function(session, note)
			local file = latest_pi_session(session.cwd)
			return file and { "pi", "--fork", file, note } or nil
		end,
	},
	claude = {
		name = "claude",
		cmd = { "claude" },
		continue = { "claude", "--continue" },
		history = claude_history,
		task = true,
		fork = function(session, note)
			local id = claude_session_id(session.pid)
			return id and { "claude", "--resume", id, "--fork-session", note } or nil
		end,
	},
	codex = {
		name = "codex",
		cmd = { "codex" },
		continue = { "codex", "resume", "--last" },
		task = true,
	},
}

-- The configured agents (preset names or agent tables), all of them
function M.configured()
	local list = {}
	for _, entry in ipairs(require("switchyard.config").options.agents) do
		local agent = type(entry) == "string" and M.presets[entry] or entry
		if type(agent) == "table" and agent.name and type(agent.cmd) == "table" then
			table.insert(list, agent)
		end
	end
	return list
end

-- The configured agents that are installed (their program is found)
function M.installed()
	return vim.tbl_filter(function(agent)
		return vim.fn.executable(agent.cmd[1]) == 1
	end, M.configured())
end

-- The command that starts `agent` on `task`, or nil when it can't
function M.task_cmd(agent, task)
	if type(agent.task) == "function" then
		return agent.task(task)
	elseif agent.task == true then
		return vim.list_extend(vim.deepcopy(agent.cmd), { task })
	end
end

return M
