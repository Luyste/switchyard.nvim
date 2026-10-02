-- The running agent sessions (from tmux, see snapshot.lua), the one the
-- editor is linked to, and the rules for linking and following.
local M = {}

-- The last snapshot: { agent, pid, pane, tmux, cwd, started } per session.
-- `generation` counts snapshots, so a missing linked session only counts as
-- ended once a snapshot was taken after linking it.
local cache, generation, fingerprint = {}, 0, nil
local refreshing, waiting = false, {}

-- The linked session (a cached copy; `linked()` refreshes it from the cache)
local link, link_generation = nil, 0

-- The linked agent's folder as the last snapshot showed it, and where it
-- moved to while we couldn't follow yet (unsaved changes)
local seen_cwd, follow_to = nil, nil

-- A one-time hold: arriving in this folder keeps the current link (peek)
local hold = nil

-- When each agent was last shown in the viewer: pid -> counter (higher = later)
local viewed, view_count = {}, 0

function M.describe(session)
	return session.agent.name .. " · " .. vim.fn.fnamemodify(session.cwd, ":~")
end

-- A session's name for people: its tmux session
function M.name(session)
	return session.tmux
end

---------------------------------------------------------------------------
-- Looking up sessions (all from the cache: cheap, no waiting)
---------------------------------------------------------------------------

function M.all()
	return vim.list_slice(cache)
end

function M.in_folder(dir)
	return vim.tbl_filter(function(s)
		return s.cwd == dir
	end, cache)
end

-- The linked session as the last snapshot saw it. nil if none, or if it ended.
function M.linked()
	if not link then
		return nil
	end
	for _, s in ipairs(cache) do
		if s.pid == link.pid then
			link = s -- its folder may have changed
			return s
		end
	end
	if generation > link_generation then
		link = nil -- the session ended
		vim.cmd("redrawstatus")
	end
	return link
end

-- For statuslines: the linked session's process ID
function M.linked_pid()
	return link and link.pid
end

---------------------------------------------------------------------------
-- Linking
---------------------------------------------------------------------------

-- Link to `session` (or unlink with nil). `quiet` skips the message.
function M.link(session, quiet)
	local changed = (link and link.pid) ~= (session and session.pid)
	link, link_generation = session, generation
	seen_cwd, follow_to = session and session.cwd, nil
	vim.cmd("redrawstatus")
	if changed then
		vim.api.nvim_exec_autocmds("User", { pattern = "SwitchyardLinkChanged" })
	end
	if not quiet then
		vim.cmd("redraw")
		vim.notify(session and ("switchyard: linked to " .. M.name(session)) or "switchyard: unlinked")
	end
end

-- For the statusline: uses the cached link, so it's cheap on every redraw
function M.status()
	if not link then
		return ""
	end
	local where = link.cwd ~= vim.fn.getcwd() and (" (in " .. vim.fn.fnamemodify(link.cwd, ":t") .. ")") or ""
	return M.name(link) .. where
end

-- The viewer showed this agent (it wins when a worktree has several agents)
function M.viewed(pid)
	view_count = view_count + 1
	viewed[pid] = view_count
end

-- Of several agents in one worktree: the one last shown in the viewer, else
-- the most recently started
local function preferred(list)
	table.sort(list, function(a, b)
		local va, vb = viewed[a.pid] or 0, viewed[b.pid] or 0
		if va ~= vb then
			return va > vb
		end
		return a.started > b.started
	end)
	return list[1]
end

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------

-- An agent's process exists before its screen takes input: text typed into a
-- session that just started waits until it's this old (seconds)
local WARM_UP = 4

-- Type `text` into the session and submit it: callback(ok, error_message)
function M.send(session, text, callback)
	-- ponytail: a fixed warm-up from the tmux session's start; watch the pane's
	-- content settle instead if an agent ever needs longer
	local wait = math.max(0, session.started + WARM_UP - os.time())
	vim.defer_fn(function()
		require("switchyard.tmux").submit(session.pane, text, callback)
	end, wait * 1000)
end

---------------------------------------------------------------------------
-- Arriving in a folder
---------------------------------------------------------------------------

-- After a peek: link to an agent in the editor's worktree after all, the way
-- a normal switch would have (last viewed, else most recently started)
function M.link_here()
	local here = M.in_folder(vim.fn.getcwd())
	if #here == 0 then
		return vim.notify("switchyard: no agent in this worktree", vim.log.levels.WARN)
	end
	M.link(preferred(here))
end

-- Peek: the next arrival in `dir` keeps the current link, whatever is there.
-- nil clears it. Any other arrival discards it.
function M.keep_link_for(dir)
	hold = dir and vim.fn.fnamemodify(dir, ":p"):gsub("/$", "") or nil
end

local function on_arrival()
	local cwd = vim.fn.getcwd()
	local held = hold
	hold = nil
	if held == cwd then
		return
	end
	local here = M.in_folder(cwd)
	local current = M.linked()

	if #here > 0 then
		-- Already linked to one of them: keep it. Otherwise the link moves along.
		local linked_here = current and current.cwd == cwd
		if not linked_here then
			M.link(preferred(here), true)
		end
	elseif current and current.cwd ~= cwd then
		if require("switchyard.config").options.empty_worktree == "unlink" then
			M.link(nil, true)
		end
		-- "keep": nothing to do, the statusline shows where the linked agent is
	end
end

---------------------------------------------------------------------------
-- Following the linked session
---------------------------------------------------------------------------

-- Follow the linked agent only when it *moved*. Comparing with the editor's
-- folder instead would pull the editor back after "keep link" in another worktree.
local function follow()
	if not require("switchyard.config").options.follow then
		return
	end
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

---------------------------------------------------------------------------
-- Refreshing the cache
---------------------------------------------------------------------------

-- What a snapshot looks like, to tell whether anything changed
local function fingerprint_of(list)
	local parts = vim.tbl_map(function(s)
		return table.concat({ s.pid, s.pane, s.tmux, s.cwd }, "\t")
	end, list)
	table.sort(parts)
	return table.concat(parts, "\n")
end

-- Use a new snapshot: fire SwitchyardSessionsChanged when something changed,
-- and follow the linked agent when it moved. (Separate for the tests.)
function M.update(list)
	cache, generation = list, generation + 1
	M.linked() -- the link sees its session's new folder, or that it ended
	local new = fingerprint_of(list)
	if new ~= fingerprint then
		fingerprint = new
		follow()
		vim.cmd("redrawstatus")
		vim.api.nvim_exec_autocmds("User", { pattern = "SwitchyardSessionsChanged" })
	end
end

-- Take a new snapshot now; callback() once the cache has it. Calls while one
-- is running wait for that one.
function M.refresh(callback)
	if callback then
		table.insert(waiting, callback)
	end
	if refreshing then
		return
	end
	refreshing = true
	require("switchyard.snapshot").take(require("switchyard.agents").configured(), function(list)
		refreshing = false
		M.update(list)
		local callbacks = waiting
		waiting = {}
		for _, fn in ipairs(callbacks) do
			fn()
		end
	end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

local timer = nil

function M.setup()
	local group = vim.api.nvim_create_augroup("switchyard_sessions", { clear = true })

	-- Arriving: decide with a fresh snapshot
	vim.api.nvim_create_autocmd("VimEnter", {
		group = group,
		callback = function()
			M.refresh(on_arrival)
		end,
	})
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		pattern = "global",
		callback = function()
			M.refresh(on_arrival)
		end,
	})
	-- Following waits when there are unsaved changes; saving retries it
	vim.api.nvim_create_autocmd("BufWritePost", { group = group, callback = follow })

	-- Agents start, stop and move on their own: look every 2 seconds
	-- ponytail: a fixed interval; slow it down when Neovim isn't focused if it ever matters
	if not timer then
		timer = vim.uv.new_timer()
		timer:start(2000, 2000, vim.schedule_wrap(function()
			M.refresh()
		end))
	end
end

return M
