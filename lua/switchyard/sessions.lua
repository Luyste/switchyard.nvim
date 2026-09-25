local M = {}

-- The linked session (a cached copy; `linked()` refreshes it)
local link = nil

-- The linked agent's folder as `follow` last saw it (set in `link` too), and
-- where it moved to while we couldn't follow yet (unsaved changes)
local seen_cwd, follow_to = nil, nil

-- tmux session names by process ID: a name, false (not in tmux), or nil (not looked up yet)
local tmux_names = {}

-- Look up (once) which tmux session this session runs in
function M.resolve_tmux(session)
	if tmux_names[session.pid] ~= nil then
		return
	end
	tmux_names[session.pid] = false -- "being looked up": only ask once
	require("switchyard.tmux").session_of_pid(session.pid, function(name)
		tmux_names[session.pid] = name or false
		vim.cmd("redrawstatus")
		vim.api.nvim_exec_autocmds("User", { pattern = "SwitchyardSessionsChanged" })
	end)
end

-- The tmux session a session runs in, if known
function M.tmux_name(session)
	return tmux_names[session.pid] or nil
end

local function adapters()
	return require("switchyard.adapters").active()
end

function M.describe(session)
	return session.adapter.name .. " · " .. vim.fn.fnamemodify(session.cwd, ":~")
end

---------------------------------------------------------------------------
-- Looking up sessions
---------------------------------------------------------------------------

-- All running sessions, from every installed adapter
function M.all()
	local list = {}
	for _, adapter in ipairs(adapters()) do
		vim.list_extend(list, adapter.sessions())
	end
	return list
end

-- Running sessions in one folder
function M.in_folder(dir)
	return vim.tbl_filter(function(s)
		return s.cwd == dir
	end, M.all())
end

-- The linked session, freshly looked up. nil if none, or if it has ended.
function M.linked()
	if not link then
		return nil
	end
	for _, s in ipairs(link.adapter.sessions()) do
		if s.pid == link.pid then
			link = s -- refresh: its folder may have changed
			return s
		end
	end
	link = nil -- the session ended
	vim.cmd("redrawstatus")
	return nil
end

---------------------------------------------------------------------------
-- Linking
---------------------------------------------------------------------------

-- Link to `session` (or unlink with nil). `quiet` skips the message.
function M.link(session, quiet)
	link = session
	seen_cwd, follow_to = session and session.cwd, nil
	if session then
		M.resolve_tmux(session)
	end

	vim.cmd("redrawstatus")
	if not quiet then
		vim.cmd("redraw")
		vim.notify(session and ("switchyard: linked to " .. M.describe(session)) or "switchyard: unlinked")
	end
end

-- For statuslines: the linked session's process ID, from the cache
function M.linked_pid()
	return link and link.pid
end

-- For the statusline: uses the cached link, so it's cheap to call on every redraw
function M.status()
	if not link then
		return ""
	end
	local label = tmux_names[link.pid] or link.adapter.name
	local where = link.cwd ~= vim.fn.getcwd() and (" (in " .. vim.fn.fnamemodify(link.cwd, ":t") .. ")") or ""
	return label .. where
end
-- Pick any running session to link to
function M.pick()
	local sessions = M.all()
	if #sessions == 0 then
		return vim.notify("switchyard: no running agent sessions", vim.log.levels.WARN)
	end
	vim.ui.select(sessions, { prompt = "Link to agent", format_item = M.describe }, function(s)
		if s then
			vim.schedule(function()
				M.link(s)
			end)
		end
	end)
end

---------------------------------------------------------------------------
-- Arriving in a folder
---------------------------------------------------------------------------

local function ask_about_link(current)
	local launch = require("switchyard.launch")
	local choices = {
		{ label = "Stay linked to " .. M.describe(current), action = function() end },
	}
	if current.adapter.fork_cmd then
		table.insert(choices, {
			label = "Fork " .. M.describe(current) .. " into this worktree",
			action = function()
				launch.fork(current)
			end,
		})
	end
	for _, adapter in ipairs(require("switchyard.adapters").active()) do
		table.insert(choices, {
			label = "Start a new " .. adapter.name .. " here",
			action = function()
				launch.new(adapter)
			end,
		})
	end
	table.insert(choices, {
		label = "Unlink",
		action = function()
			M.link(nil)
		end,
	})

	vim.ui.select(choices, {
		prompt = "No agent in this worktree",
		format_item = function(c)
			return c.label
		end,
	}, function(choice)
		if choice then
			vim.schedule(choice.action)
		end
	end)
end

local function on_arrival()
	local cwd = vim.fn.getcwd()
	local here = M.in_folder(cwd)
	local current = M.linked()

	if #here == 1 then
		if not current or current.pid ~= here[1].pid then
			M.link(here[1], true)
		end
	elseif #here == 0 and current and current.cwd ~= cwd then
		local mode = require("switchyard.config").options.empty_worktree
		if mode == "ask" then
			ask_about_link(current)
		elseif mode == "unlink" then
			M.link(nil, true)
		end
		-- "keep": nothing to do, the statusline shows where the linked agent is
	end -- Several agents here: keep the current link
end

---------------------------------------------------------------------------
-- Following the linked session
---------------------------------------------------------------------------

-- Follow the linked agent only when it *moved*. Comparing with the editor's
-- folder instead would pull the editor back after "keep link" in another worktree.
local function follow()
	local s = M.linked()
	if s and s.cwd ~= seen_cwd then
		seen_cwd, follow_to = s.cwd, s.cwd
	end
	if not follow_to or vim.fn.isdirectory(follow_to) == 0 then
		follow_to = nil
		return
	end
	if require("switchyard.projects").switch(follow_to) then
		follow_to = nil
	end
end

local function watch(dir)
	vim.fn.mkdir(dir, "p")
	local handle = vim.uv.new_fs_event()
	local pending = false
	-- Runs in a fast context: defer_fn schedules back onto the main loop
	handle:start(dir, {}, function()
		if pending then
			return
		end
		pending = true
		vim.defer_fn(function()
			pending = false
			follow()
			vim.api.nvim_exec_autocmds("User", { pattern = "SwitchyardSessionsChanged" })
		end, 300)
	end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function M.setup()
	local group = vim.api.nvim_create_augroup("switchyard_sessions", { clear = true })

	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		callback = function()
			vim.schedule(on_arrival)
		end,
	})
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		pattern = "global",
		callback = function()
			vim.schedule(on_arrival)
		end,
	})

	if require("switchyard.config").options.follow then
		for _, adapter in ipairs(adapters()) do
			if adapter.watch_dir then
				watch(adapter.watch_dir)
			end
		end
		-- Following waits when there are unsaved changes; saving retries it
		vim.api.nvim_create_autocmd("BufWritePost", { group = group, callback = follow })
	end
end

return M
