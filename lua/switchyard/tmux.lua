local util = require("switchyard.util")

local M = {}

local function tmux(args, callback)
	util.run(vim.list_extend({ "tmux" }, args), {}, callback)
end

-- "=name" targets exactly this session; a bare name also matches prefixes
local function target(name)
	return "=" .. name
end

-- All sessions: callback(list of { name, path, attached })
function M.list(callback)
	local format = "#{session_name}\t#{session_path}\t#{session_attached}"
	tmux({ "list-sessions", "-F", format }, function(ok, stdout)
		local sessions = {}
		-- Not ok usually means "no server running": simply no sessions yet
		if ok then
			for line in stdout:gmatch("[^\n]+") do
				local name, path, attached = line:match("^(.-)\t(.-)\t(%d+)$")
				if name then
					table.insert(sessions, { name = name, path = path, attached = tonumber(attached) })
				end
			end
		end
		callback(sessions)
	end)
end

-- A session name based on `base` that isn't taken yet: callback(name)
function M.free_name(base, callback)
	base = base:gsub("[%.:%s]", "_") -- tmux doesn't allow . and : in names
	M.list(function(sessions)
		local taken = {}
		for _, s in ipairs(sessions) do
			taken[s.name] = true
		end
		local name, n = base, 1
		while taken[name] do
			n = n + 1
			name = base .. "-" .. n
		end
		callback(name)
	end)
end

-- Start `cmd` (a list, e.g. { "pi", "--continue" }) in a new background session.
-- It runs through your login shell, so it gets the same PATH as your terminal.
-- When the command exits, the pane drops into a normal shell instead of closing.
-- callback(ok, error_message)
function M.new(name, cwd, cmd, callback)
	local shell = vim.env.SHELL or "/bin/zsh"
	local line = "cd "
		.. vim.fn.shellescape(cwd)
		.. " && "
		.. table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
		.. "; exec "
		.. shell
	local args = { "new-session", "-d", "-s", name, "-c", cwd, shell, "-l", "-i", "-c", line }
	tmux(args, function(ok, _, stderr)
		callback(ok, not ok and vim.trim(stderr) or nil)
	end)
end

-- Paste `text` into the session's active pane as if it were typed (bracketed
-- paste, so newlines don't submit; no Enter at the end): callback(ok, error)
function M.paste(name, text, callback)
	util.run({ "tmux", "load-buffer", "-b", "switchyard", "-" }, { stdin = text }, function(ok, _, stderr)
		if not ok then
			return callback(false, vim.trim(stderr))
		end
		-- "=name:" = the current window of exactly this session
		tmux({ "paste-buffer", "-p", "-d", "-b", "switchyard", "-t", target(name) .. ":" }, function(pasted, _, err)
			callback(pasted, not pasted and vim.trim(err) or nil)
		end)
	end)
end

-- Rename a session: callback(ok, error_message)
function M.rename(name, new_name, callback)
	tmux({ "rename-session", "-t", target(name), new_name }, function(ok, _, stderr)
		callback(ok, not ok and vim.trim(stderr) or nil)
	end)
end

-- End a session and everything running in it: callback(ok, error_message)
function M.kill(name, callback)
	tmux({ "kill-session", "-t", target(name) }, function(ok, _, stderr)
		callback(ok, not ok and vim.trim(stderr) or nil)
	end)
end

-- Which tmux sessions are these processes running in?
-- Walks up each process's parents until it reaches a tmux pane, so agents
-- started through wrappers (scripts, version managers) are found too.
-- callback(map of pid -> session name); processes outside tmux are left out
function M.sessions_for_pids(pids, callback)
	if #pids == 0 then
		return callback({})
	end
	tmux({ "list-panes", "-a", "-F", "#{session_name}\t#{pane_pid}" }, function(ok, panes)
		if not ok then
			return callback({})
		end
		local by_pane = {}
		for line in panes:gmatch("[^\n]+") do
			local name, pane_pid = line:match("^(.-)\t(%d+)$")
			if name then
				by_pane[tonumber(pane_pid)] = name
			end
		end

		-- Every process and its parent, in one call
		util.run({ "ps", "-A", "-o", "pid=,ppid=" }, {}, function(_, out)
			local parent = {}
			for line in out:gmatch("[^\n]+") do
				local pid, ppid = line:match("(%d+)%s+(%d+)")
				if pid then
					parent[tonumber(pid)] = tonumber(ppid)
				end
			end

			local result = {}
			for _, pid in ipairs(pids) do
				local current, steps = pid, 0
				while current and current > 1 and steps < 20 do
					if by_pane[current] then
						result[pid] = by_pane[current]
						break
					end
					current, steps = parent[current], steps + 1
				end
			end
			callback(result)
		end)
	end)
end

-- Which session is process `pid` running in? callback(name) or callback(nil)
function M.session_of_pid(pid, callback)
	M.sessions_for_pids({ pid }, function(names)
		callback(names[pid])
	end)
end
-- The command that attaches to a session (for a terminal split or Ghostty)
function M.attach_cmd(name)
	return { "tmux", "attach-session", "-t", target(name) }
end

return M
