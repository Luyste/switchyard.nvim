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
-- callback(pane_id) on success, callback(nil, error_message) on failure.
function M.new(name, cwd, cmd, callback)
	local shell = vim.env.SHELL or "/bin/zsh"
	local line = "cd "
		.. vim.fn.shellescape(cwd)
		.. " && "
		.. table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
		.. "; exec "
		.. shell
	local args = { "new-session", "-d", "-P", "-F", "#{pane_id}", "-s", name, "-c", cwd, shell, "-l", "-i", "-c", line }
	tmux(args, function(ok, stdout, stderr)
		if not ok then
			return callback(nil, vim.trim(stderr))
		end
		callback(vim.trim(stdout))
	end)
end

-- Paste `text` into `pane` (e.g. "%3") as if it were typed: bracketed paste,
-- so newlines don't submit; no Enter at the end. callback(ok, error_message)
function M.paste(pane, text, callback)
	util.run({ "tmux", "load-buffer", "-b", "switchyard", "-" }, { stdin = text }, function(ok, _, stderr)
		if not ok then
			return callback(false, vim.trim(stderr))
		end
		tmux({ "paste-buffer", "-p", "-d", "-b", "switchyard", "-t", pane }, function(pasted, _, err)
			callback(pasted, not pasted and vim.trim(err) or nil)
		end)
	end)
end

-- Paste `text` into `pane` and press Enter: how prompts reach an agent.
-- The short pause lets the agent take in the paste before the Enter.
-- callback(ok, error_message)
function M.submit(pane, text, callback)
	M.paste(pane, text, function(ok, err)
		if not ok then
			return callback(false, err)
		end
		vim.defer_fn(function()
			tmux({ "send-keys", "-t", pane, "Enter" }, function(sent, _, stderr)
				callback(sent, not sent and vim.trim(stderr) or nil)
			end)
		end, 50)
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

-- The command that attaches to a session (for a terminal split or Ghostty)
function M.attach_cmd(name)
	return { "tmux", "attach-session", "-t", target(name) }
end

return M
