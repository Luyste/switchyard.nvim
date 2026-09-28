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

M.presets = {
	pi = {
		name = "pi",
		cmd = { "pi" },
		continue = { "pi", "--continue" },
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
