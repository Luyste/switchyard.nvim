-- Claude Code. Running sessions register themselves in ~/.claude/sessions
-- (one <pid>.json each); prompts go in through tmux, like typing them.
local SESSIONS_DIR = vim.fn.expand("~/.claude/sessions")

local M = {
	name = "claude",
	cmd = "claude",
	watch_dir = SESSIONS_DIR,
	hint = "In a folder it hasn't seen, Claude Code first asks whether you trust it: "
		.. "open it with v in the yard's agents view and answer.",
}

---------------------------------------------------------------------------
-- Starting sessions
---------------------------------------------------------------------------

function M.new_cmd()
	return { "claude" }
end

-- A new session that starts on `task` right away
function M.task_cmd(task)
	return { "claude", task }
end

function M.continue_cmd()
	return { "claude", "--continue" }
end

-- A copy of a running session's conversation, in the folder it's started in
function M.fork_cmd(session)
	return session.session_id and { "claude", "--resume", session.session_id, "--fork-session" } or nil
end

---------------------------------------------------------------------------
-- Finding running sessions
---------------------------------------------------------------------------

-- Milliseconds since 1970 as an ISO time, like pi's (they sort together)
local function iso(ms)
	return os.date("!%Y-%m-%dT%H:%M:%S", math.floor(ms / 1000))
end

-- Running interactive sessions: a list of { adapter, pid, cwd, session_id,
-- started, status } (status: "busy" or "idle")
function M.sessions()
	local list = {}
	for _, file in ipairs(vim.fn.glob(SESSIONS_DIR .. "/*.json", false, true)) do
		local ok, info = pcall(function()
			return vim.json.decode(table.concat(vim.fn.readfile(file), ""))
		end)
		if
			ok
			and type(info) == "table"
			and info.kind == "interactive" -- not `claude -p` runs
			and type(info.pid) == "number"
			and type(info.cwd) == "string"
			and vim.uv.kill(info.pid, 0) == 0 -- still running
		then
			table.insert(list, {
				adapter = M,
				pid = info.pid,
				cwd = info.cwd,
				session_id = type(info.sessionId) == "string" and info.sessionId or nil,
				started = type(info.startedAt) == "number" and iso(info.startedAt) or "",
				status = type(info.status) == "string" and info.status or nil,
			})
		end
	end
	return list
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- Type `message` into the session and submit it (it must run in tmux):
-- callback(ok, error_message)
function M.send(session, message, callback)
	require("switchyard.sessions").with_tmux_name(session, function(name)
		require("switchyard.tmux").submit(name, message, callback)
	end)
end

return M
