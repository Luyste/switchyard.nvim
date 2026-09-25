local SOCKETS_DIR = "/tmp/pi-nvim-sockets"

local M = {
	name = "pi",
	cmd = "pi",
	watch_dir = SOCKETS_DIR,
	hint = "Install the pi-nvim extension: pi install npm:pi-nvim",
}

---------------------------------------------------------------------------
-- Starting sessions
---------------------------------------------------------------------------

function M.new_cmd()
	return { "pi" }
end

function M.continue_cmd()
	return { "pi", "--continue" }
end

-- pi stores sessions per folder in ~/.pi/agent/sessions/--<path>--/
local function session_dir(cwd)
	local path = vim.uv.fs_realpath(cwd) or cwd
	local safe = "--" .. path:gsub("^[/\\]", ""):gsub("[/\\:]", "-") .. "--"
	return vim.fn.expand("~/.pi/agent/sessions/") .. safe
end

-- A running session writes to its file constantly, so the newest file is the live one
local function latest_session_file(cwd)
	local newest, newest_time
	for _, file in ipairs(vim.fn.glob(session_dir(cwd) .. "/*.jsonl", false, true)) do
		local t = vim.fn.getftime(file)
		if not newest_time or t > newest_time then
			newest, newest_time = file, t
		end
	end
	return newest
end

-- Command that forks a running session into the current folder, or nil
function M.fork_cmd(session)
	local file = latest_session_file(session.cwd)
	return file and { "pi", "--fork", file } or nil
end

---------------------------------------------------------------------------
-- Finding running sessions
---------------------------------------------------------------------------

local function read_json(path)
	local ok, data = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(path), ""))
	end)
	return ok and type(data) == "table" and data or nil
end

local function alive(pid)
	return vim.uv.kill(pid, 0) == 0
end

-- Running pi sessions: a list of { adapter, pid, cwd, socket, started }
function M.sessions()
	local by_pid = {}
	for _, file in ipairs(vim.fn.glob(SOCKETS_DIR .. "/*.info", false, true)) do
		local info = read_json(file)
		-- Newer pi-nvim writes the socket path; older versions don't,
		-- but the socket always sits next to its .info file
		local socket = info and (info.socket or file:gsub("%.info$", ""))
		if info and info.pid and info.cwd and alive(info.pid) then
			local started = info.startedAt or ""
			local current = by_pid[info.pid]
			if not current or started > current.started then
				by_pid[info.pid] = {
					adapter = M,
					pid = info.pid,
					cwd = info.cwd,
					socket = socket,
					started = started,
				}
			end
		end
	end
	return vim.tbl_values(by_pid)
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- Send a message to a running session: callback(ok, error_message)
function M.send(session, message, callback)
	local pipe = vim.uv.new_pipe(false)
	pipe:connect(session.socket, function(err)
		if err then
			pipe:close()
			return vim.schedule(function()
				callback(false, err)
			end)
		end
		local payload = vim.json.encode({ type = "prompt", message = message }) .. "\n"
		pipe:write(payload, function(write_err)
			pipe:shutdown(function()
				pipe:close()
			end)
			vim.schedule(function()
				callback(not write_err, write_err)
			end)
		end)
	end)
end

return M
