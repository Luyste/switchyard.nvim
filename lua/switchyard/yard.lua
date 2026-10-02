-- The yard: one small floating window with three views.
--   worktrees: the current repo's worktrees, with a summary of their agents
--              (outside a repo: the folder itself)
--   agents:    this repo's running agents
--   projects:  git repos on this machine, pinned and recent folders
-- Tab cycles the views; `/` shows a filter line above the list while
-- filtering (fuzzy: the letters in order, best matches first).
local ui = require("switchyard.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("switchyard_yard")

-- The view survives closing: the yard reopens where you left it. So does
-- the agents view's scope: this repo's agents ("repo") or every agent in tmux
-- ("all").
local view = nil
local agent_scope = "repo"

local state = {
	win = nil, -- the list
	buf = nil,
	input_win = nil, -- the filter line, only while filtering
	input_buf = nil,
	worktrees = nil, -- the last worktrees.list() result
	err = nil,
	projects = {}, -- project folders in the order found
	project_seen = {},
	projects_state = nil, -- nil (not looked for yet) | "loading" | "done"
	rows = {}, -- one entry per list line
	total = 0, -- rows in this view without the filter
	filter = "",
	selected = {}, -- per view: the key of the selected row (path or "pid:<n>")
	origin = nil, -- the window the yard was opened from
}

local function keys()
	return require("switchyard.config").options.keys.yard
end
local function sessions()
	return require("switchyard.sessions")
end
local function valid(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.is_open()
	return valid(state.win)
end

---------------------------------------------------------------------------
-- Building lines: text plus highlight ranges
---------------------------------------------------------------------------

local function builder()
	local b = { text = "", hls = {} }
	function b.add(text, hl)
		if not text or text == "" then
			return
		end
		if hl then
			table.insert(b.hls, { #b.text, #b.text + #text, hl })
		end
		b.text = b.text .. text
	end
	return b
end

local function width_of(text)
	return vim.fn.strdisplaywidth(text)
end

local function truncate(text, width)
	if width_of(text) <= width then
		return text
	end
	return vim.fn.strcharpart(text, 0, math.max(width - 1, 0)) .. "…"
end

-- How `text` matches the filter, fuzzily (its letters in order, not
-- necessarily next to each other; Neovim's matchfuzzypos): the score and the
-- matched characters (0-based character indexes as keys), or nil
local function match(text)
	if state.filter == "" then
		return nil
	end
	local result = vim.fn.matchfuzzypos({ text }, state.filter)
	if #result[1] == 0 then
		return nil
	end
	local positions = {}
	for _, i in ipairs(result[2][1]) do
		positions[i] = true
	end
	return result[3][1], positions
end

-- Add `text`, highlighting the characters that match the filter
local function add_matched(b, text, hl)
	local _, positions = match(text)
	if not positions then
		return b.add(text, hl)
	end
	for i = 0, vim.fn.strchars(text) - 1 do
		b.add(vim.fn.strcharpart(text, i, 1), positions[i] and "SwitchyardMatch" or hl)
	end
end

-- With a filter: the rows where one of `texts_of(row)` matches, best match
-- first (ties keep their order). Without: all rows.
local function filtered(rows, texts_of)
	state.total = #rows -- for the filter's "n / total"
	if state.filter == "" then
		return rows
	end
	local kept = {}
	for i, row in ipairs(rows) do
		local top
		for _, text in ipairs(texts_of(row)) do
			local score = match(text)
			if score and (not top or score > top) then
				top = score
			end
		end
		if top then
			table.insert(kept, { row = row, score = top, i = i })
		end
	end
	table.sort(kept, function(a, b)
		if a.score ~= b.score then
			return a.score > b.score
		end
		return a.i < b.i
	end)
	return vim.tbl_map(function(k)
		return k.row
	end, kept)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

-- The editor's folder as the one "worktree" when it isn't in a git repo (a
-- config folder): agents can still be started and listed there
local function plain_folder()
	local cwd = vim.fn.getcwd()
	return { { path = cwd, branch = vim.fn.fnamemodify(cwd, ":t"), current = true, main = true, symbols = "", plain = true } }
end

-- The worktrees to show: git's, or the folder itself outside a repo
local function worktree_list()
	return state.worktrees or (state.err and plain_folder()) or {}
end

local function worktree_rows(all)
	local rows = {}
	for _, wt in ipairs(worktree_list()) do
		local agents = vim.tbl_filter(function(s)
			return s.cwd == wt.path
		end, all)
		table.insert(rows, { kind = "worktree", worktree = wt, agents = agents, key = wt.path, path = wt.path })
	end
	return filtered(rows, function(row)
		local texts = { row.worktree.branch }
		for _, s in ipairs(row.agents) do
			table.insert(texts, sessions().name(s))
		end
		return texts
	end)
end

-- Where an agent works, for the right side of its row: its branch in this
-- repo; elsewhere its project, and its folder when that's a worktree of it
local function agent_where(s, branch_of)
	if branch_of[s.cwd] then
		return branch_of[s.cwd]
	elseif vim.fn.isdirectory(s.cwd) == 0 then
		return "removed worktree"
	end
	local root = require("switchyard.projects").root(s.cwd)
	local project, folder = vim.fn.fnamemodify(root, ":t"), vim.fn.fnamemodify(s.cwd, ":t")
	return folder == project and project or (project .. " · " .. folder)
end

-- This repo's agents (agent_scope "repo"), or every agent in tmux ("all"):
-- the linked one first, then this repo's, then by folder. Agents whose folder
-- is gone (kept running after "remove worktree") are listed too, so they can
-- still be forked or stopped.
local function agent_rows(all)
	local branch_of = {}
	for _, wt in ipairs(worktree_list()) do
		branch_of[wt.path] = wt.branch
	end
	local mine = agent_scope == "all" and vim.list_slice(all)
		or vim.tbl_filter(function(s)
			return branch_of[s.cwd] ~= nil or vim.fn.isdirectory(s.cwd) == 0
		end, all)
	local linked = sessions().linked_pid()
	table.sort(mine, function(a, b)
		if (a.pid == linked) ~= (b.pid == linked) then
			return a.pid == linked
		end
		if (branch_of[a.cwd] ~= nil) ~= (branch_of[b.cwd] ~= nil) then
			return branch_of[a.cwd] ~= nil
		end
		if a.cwd ~= b.cwd then
			return a.cwd < b.cwd
		end
		return a.pid < b.pid
	end)
	local rows = {}
	for _, s in ipairs(mine) do
		local where = agent_where(s, branch_of)
		table.insert(rows, { kind = "agent", session = s, where = where, key = "pid:" .. s.pid, path = s.cwd })
	end
	return filtered(rows, function(row)
		return { sessions().name(row.session), row.where }
	end)
end

-- Add a project folder (once, if it exists). True when it was new.
local function add_project(path)
	path = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("/$", "")
	if state.project_seen[path] or vim.fn.isdirectory(path) == 0 then
		return false
	end
	state.project_seen[path] = true
	table.insert(state.projects, path)
	return true
end

-- The projects, first the ones known right away (the current one, pinned,
-- recent, the last scan), then what fd finds now (redrawn as they come)
local function load_projects()
	if state.projects_state then
		return
	end
	state.projects_state = "loading"
	local projects = require("switchyard.projects")
	add_project(projects.root(vim.fn.getcwd()))
	for _, list in ipairs({ require("switchyard.config").options.projects.pinned, projects.recent(), projects.cached() }) do
		for _, path in ipairs(list) do
			add_project(path)
		end
	end
	local pending = false
	projects.find(function(path)
		if add_project(path) and not pending then
			pending = true
			vim.defer_fn(function()
				pending = false
				M.render()
			end, 100)
		end
	end, function()
		state.projects_state = "done"
		M.render()
	end)
end

local function project_rows(all)
	local projects = require("switchyard.projects")
	local count = {}
	for _, s in ipairs(all) do
		local root = projects.root(s.cwd)
		count[root] = (count[root] or 0) + 1
	end
	for root in pairs(count) do
		add_project(root) -- projects with agents belong in the list
	end
	local current = projects.root(vim.fn.getcwd())
	local rows = {}
	for _, path in ipairs(state.projects) do
		table.insert(rows, {
			kind = "project",
			key = path,
			path = path,
			name = vim.fn.fnamemodify(path, ":t"),
			current = path == current,
			agents = count[path] or 0,
		})
	end
	return filtered(rows, function(row)
		return { row.name } -- not the path: fuzzy letters match almost any path
	end)
end

-- One line: a left part (builder) and an optional right part { text, hl }
-- The left margin of every row
local function number(b)
	b.add(" ")
end

local function worktree_line(i, row, linked)
	local wt, b = row.worktree, builder()
	number(b)
	b.add(wt.current and "@ " or "  ", "SwitchyardCurrent")
	add_matched(b, wt.branch, wt.current and "SwitchyardCurrent" or nil)
	if wt.symbols ~= "" then
		b.add("  ")
		b.add(wt.symbols, "SwitchyardSymbols")
	end
	local linked_here = vim.iter(row.agents):find(function(s)
		return s.pid == linked
	end)
	if linked_here then
		local more = #row.agents > 1 and (" +" .. (#row.agents - 1)) or ""
		return b, { "● " .. sessions().name(linked_here) .. more, "SwitchyardLinked" }
	elseif #row.agents > 0 then
		return b, { "● " .. #row.agents, "SwitchyardAgent" }
	end
	return b
end

local function project_line(i, row)
	local b = builder()
	number(b)
	b.add(row.current and "@ " or "  ", "SwitchyardCurrent")
	add_matched(b, row.name, row.current and "SwitchyardCurrent" or nil)
	if row.agents > 0 then
		b.add("  ● " .. row.agents, "SwitchyardAgent")
	end
	return b, { vim.fn.fnamemodify(row.path, ":~:h"), "SwitchyardDim" }
end

local function agent_line(i, row, linked)
	local s, b = row.session, builder()
	local is_linked = s.pid == linked
	number(b)
	b.add("● ", is_linked and "SwitchyardLinked" or "SwitchyardAgent")
	add_matched(b, sessions().name(s), is_linked and "SwitchyardLinked" or nil)
	return b, { row.where, "SwitchyardDim" }
end

---------------------------------------------------------------------------
-- Title, footer, layout
---------------------------------------------------------------------------

local views = { "worktrees", "agents", "projects" } -- in key order: 1, 2, 3

-- The title: the views as tabs with their keys, the shown one highlighted
local function title()
	local parts = { { " switchyard  ", "SwitchyardHeading" } }
	local k = keys()
	for _, name in ipairs(views) do
		local shown = name == view
		table.insert(parts, { k["view_" .. name] .. " ", shown and "SwitchyardKey" or "SwitchyardDim" })
		local label = (name == "agents" and agent_scope == "all") and "agents (all)" or name
		table.insert(parts, { label .. "  ", shown and "SwitchyardHeading" or "SwitchyardDim" })
	end
	return parts
end

local function hints(width)
	local text = ({
		worktrees = " ⏎ switch  ⇧⏎ peek  a agent  / filter  . actions  ? keys",
		agents = agent_scope == "all" and " ⏎ go to  ⇧⏎ link  ⇥ this repo  / filter  . actions  ? keys"
			or " ⏎ go to  ⇧⏎ link  ⇥ all agents  / filter  . actions  ? keys",
		projects = " ⏎ switch  ⇧⏎ peek  a agent  / filter  . actions  ? keys",
	})[view]
	return truncate(text, width - 1)
end

local function layout(width, height)
	local cols, lines = vim.o.columns, vim.o.lines
	local filtering = valid(state.input_win)
	-- Centered, a bit above the middle; room for the filter line above it
	local row = math.max(filtering and 4 or 1, math.floor((lines - height) / 2) - 2)
	local col = math.floor((cols - width) / 2)
	vim.api.nvim_win_set_config(state.win, {
		relative = "editor",
		row = row,
		col = col,
		width = width,
		height = height + 2, -- + the title line and the hints line
	})
	ui.title(state.win, title())
	ui.hints(state.buf, hints(width))
	if filtering then
		vim.api.nvim_win_set_config(state.input_win, { relative = "editor", row = row - 3, col = col, width = width, height = 1 })
	end
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function write(builders)
	local lines = {}
	for i, b in ipairs(builders) do
		lines[i] = b.text
	end
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.bo[state.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
	for i, b in ipairs(builders) do
		for _, h in ipairs(b.hls) do
			vim.api.nvim_buf_set_extmark(state.buf, ns, i - 1, h[1], { end_col = h[2], hl_group = h[3] })
		end
	end
end

local function update_count()
	if not valid(state.input_win) then
		return
	end
	vim.api.nvim_buf_clear_namespace(state.input_buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(state.input_buf, ns, 0, 0, {
		virt_text = { { "› ", "SwitchyardKey" } },
		virt_text_pos = "inline",
	})
	vim.api.nvim_buf_set_extmark(state.input_buf, ns, 0, 0, {
		virt_text = { { ("%d / %d "):format(#state.rows, state.total), "SwitchyardDim" } },
		virt_text_pos = "right_align",
	})
end

local function render()
	if not M.is_open() then
		return
	end
	local all = sessions().all()
	if view == "projects" then
		state.rows = project_rows(all)
	elseif view == "agents" then
		state.rows = agent_rows(all)
	else
		state.rows = worktree_rows(all)
	end

	-- Lines, and the width they need
	local linked = sessions().linked_pid()
	local parts, want = {}, 0
	for i, row in ipairs(state.rows) do
		local b, right
		if row.kind == "worktree" then
			b, right = worktree_line(i, row, linked)
		elseif row.kind == "project" then
			b, right = project_line(i, row)
		else
			b, right = agent_line(i, row, linked)
		end
		parts[i] = { b = b, right = right }
		want = math.max(want, width_of(b.text) + (right and width_of(right[1]) + 4 or 1))
	end
	if #parts == 0 then
		local message = (state.worktrees or state.err) and "No matches" or "Loading…"
		if view == "agents" and state.filter == "" and (state.worktrees or state.err) then
			message = agent_scope == "repo" and "No agents in this repo  (⇥ all agents)" or "No agents running"
		elseif view == "projects" then
			message = state.projects_state == "done" and "No matches" or "Looking for projects…"
		end
		local b = builder()
		b.add("   " .. message, "SwitchyardDim")
		parts[1] = { b = b }
	end

	-- As small as possible: sized to the content (and the title), within limits
	local title_width = 0
	for _, part in ipairs(title()) do
		title_width = title_width + width_of(part[1])
	end
	want = math.max(want, title_width + 1)
	local width = math.min(math.max(50, math.min(90, want)), vim.o.columns - 4)
	local height = math.max(1, math.min(#parts, math.floor(vim.o.lines * 0.6)))

	-- Right parts aligned to the right edge
	local builders = {}
	for i, p in ipairs(parts) do
		if p.right then
			p.b.add(string.rep(" ", math.max(width - width_of(p.b.text) - width_of(p.right[1]) - 1, 2)))
			p.b.add(p.right[1], p.right[2])
		end
		builders[i] = p.b
	end
	write(builders)
	layout(width, height)

	-- Put the selection back on the same row, if it's still there
	local target = 1
	for i, row in ipairs(state.rows) do
		if row.key == state.selected[view] then
			target = i
		end
	end
	vim.api.nvim_win_set_cursor(state.win, { target, 0 })
	state.selected[view] = state.rows[target] and state.rows[target].key
	update_count()
end
M.render = render -- for the projects scan, which finishes later

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

local function selected_index()
	return vim.api.nvim_win_get_cursor(state.win)[1]
end

local function move(delta)
	if #state.rows == 0 then
		return
	end
	local index = math.max(1, math.min(#state.rows, selected_index() + delta))
	vim.api.nvim_win_set_cursor(state.win, { index, 0 })
	state.selected[view] = state.rows[index].key
end

-- Switch the editor but keep the current link
local function peek(path)
	if path == vim.fn.getcwd() then
		return
	end
	vim.schedule(function()
		sessions().keep_link_for(path)
		if not require("switchyard.projects").switch(path) then
			sessions().keep_link_for(nil) -- blocked (unsaved changes): no arrival follows
		end
	end)
end

-- Enter (alt = Shift+Enter) on `row`.
--   worktree, project: switch (the link moves along) / peek (the link stays)
--   agent:    go to it (switch to its worktree + link) / link only, stay here
local function activate(row, alt)
	if row.kind == "agent" and alt then
		sessions().link(row.session)
		return render()
	end
	M.close()
	if row.kind ~= "agent" then
		if alt then
			return peek(row.path)
		end
		return vim.schedule(function()
			require("switchyard.projects").switch(row.path)
		end)
	end
	vim.schedule(function()
		local moved = row.path ~= vim.fn.getcwd()
		if require("switchyard.projects").switch(row.path) then
			-- Before the (scheduled) arrival rules run, so they keep this link
			sessions().link(row.session, moved) -- quiet after a switch: the statusline shows it
		end
	end)
end

local function show_view(name)
	view = name
	if view == "projects" then
		load_projects()
	end
	render()
end

-- Tab, in the agents view only: this repo's agents or all of them
local function toggle_view()
	if view ~= "agents" then
		return
	end
	agent_scope = agent_scope == "all" and "repo" or "all"
	state.selected.agents = nil
	render()
end

-- Worktrees and agents, both looked at again (Ctrl-R, and on opening)
local function refresh()
	sessions().refresh() -- redraws through SwitchyardSessionsChanged when agents changed
	if view == "projects" and state.projects_state == "done" then
		state.projects, state.project_seen, state.projects_state = {}, {}, nil
		load_projects()
	end
	require("switchyard.worktrees").list(vim.fn.getcwd(), function(worktrees, err)
		state.worktrees, state.err = worktrees, err
		if not state.selected.worktrees then
			for _, wt in ipairs(worktrees or {}) do
				if wt.current then
					state.selected.worktrees = wt.path
				end
			end
		end
		render()
	end)
end

---------------------------------------------------------------------------
-- Filtering: a line above the list, only while filtering
---------------------------------------------------------------------------

local function stop_filter()
	state.filter = ""
	if valid(state.input_win) then
		vim.api.nvim_win_close(state.input_win, true)
	end
	if state.input_buf and vim.api.nvim_buf_is_valid(state.input_buf) then
		vim.api.nvim_buf_delete(state.input_buf, { force = true })
	end
	state.input_win, state.input_buf = nil, nil
	vim.cmd.stopinsert()
	if M.is_open() then
		vim.api.nvim_set_current_win(state.win)
		render()
	end
end

local function start_filter()
	if valid(state.input_win) then
		vim.api.nvim_set_current_win(state.input_win)
		return vim.cmd("startinsert!")
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "switchyard"
	state.input_buf = buf
	state.input_win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 50,
		height = 1,
		style = "minimal",
		border = "rounded",
	})

	local function map(key, fn)
		vim.keymap.set("i", key, fn, { buffer = buf, nowait = true, silent = true })
	end
	local k = keys()
	local function act(alt)
		local row = state.rows[selected_index()]
		if row then
			vim.cmd.stopinsert()
			activate(row, alt)
		end
	end
	map("<CR>", function()
		act(false)
	end)
	map(k.alt_activate, function()
		act(true)
	end)
	map("<C-n>", function()
		move(1)
	end)
	map("<C-p>", function()
		move(-1)
	end)
	map("<Down>", function()
		move(1)
	end)
	map("<Up>", function()
		move(-1)
	end)
	map("<Tab>", toggle_view)
	map("<Esc>", stop_filter)
	map("<C-c>", stop_filter)

	vim.api.nvim_create_autocmd("TextChangedI", {
		buffer = buf,
		callback = function()
			state.filter = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
			state.selected[view] = nil -- a new filter selects the first row
			render()
		end,
	})
	render()
	vim.cmd("startinsert!")
end

---------------------------------------------------------------------------
-- Actions per view. The keys, the `.` menu and the `?` list come from here.
---------------------------------------------------------------------------

local function warn(message)
	vim.notify("switchyard: " .. message, vim.log.levels.WARN)
end

-- Choose one of this repo's worktrees (the current one first, `except` left
-- out), or create a new one. callback(worktree): { path, branch }
local function with_worktree(title, except, callback)
	local list = vim.tbl_filter(function(wt)
		return wt.path ~= except
	end, worktree_list())
	table.sort(list, function(a, b)
		return a.current and not b.current
	end)
	local items = vim.tbl_map(function(wt)
		return {
			label = (wt.current and "@ " or "  ") .. wt.branch,
			action = function()
				callback(wt)
			end,
		}
	end, list)
	if not state.err then -- a git repo: a new worktree can be made
		table.insert(items, {
			label = "  new worktree…",
			key = keys().new,
			action = function()
				require("switchyard.actions").create_worktree(vim.fn.getcwd(), function(path, branch)
					refresh()
					callback({ path = path, branch = branch })
				end)
			end,
		})
	end
	require("switchyard.menu").open({ title = title, items = items })
end

-- Per view: { key = name in keys.yard, label, run = function(row), danger?,
-- any_row? (also works on an empty list; row is nil then) }
local actions = {
	worktrees = {
		{
			key = "activate",
			label = "switch here",
			run = activate,
		},
		{
			key = "alt_activate",
			label = "peek: switch, keep the link",
			run = function(row)
				activate(row, true) -- Shift+Enter
			end,
		},
		{
			key = "new",
			label = "new worktree",
			any_row = true,
			run = function()
				require("switchyard.actions").create_worktree(vim.fn.getcwd(), refresh)
			end,
		},
		{
			key = "dispatch",
			label = "dispatch: a task for a new agent in a new worktree",
			any_row = true,
			run = function()
				M.close()
				require("switchyard.prompt").open_dispatch()
			end,
		},
		{
			key = "start_agent",
			label = "start an agent here",
			run = function(row)
				require("switchyard.actions").with_agent(function(agent)
					require("switchyard.launch").new(agent, row.path)
				end)
			end,
		},
		{
			key = "continue_agent",
			label = "continue an earlier session here",
			run = function(row)
				require("switchyard.actions").continue_agent(row.path)
			end,
		},
		{
			key = "fork",
			label = "fork the linked agent here",
			run = function(row)
				local linked = sessions().linked()
				if not linked then
					return warn("no linked agent to fork")
				elseif linked.cwd == row.path then
					return warn("the linked agent already works here")
				end
				require("switchyard.launch").fork(linked, row.path)
			end,
		},
		{
			key = "copy_path",
			label = "copy path",
			run = function(row)
				vim.fn.setreg("+", row.path)
				vim.fn.setreg('"', row.path)
				vim.notify("switchyard: copied " .. vim.fn.fnamemodify(row.path, ":~"))
			end,
		},
		{
			key = "remove",
			label = "remove worktree",
			danger = true,
			run = function(row)
				require("switchyard.actions").remove_worktree(vim.fn.getcwd(), row.worktree, refresh, row.agents)
			end,
		},
	},
	agents = {
		{
			key = "activate",
			label = "go to: switch to its worktree and link",
			run = activate,
		},
		{
			key = "alt_activate",
			label = "link only, stay here",
			run = function(row)
				activate(row, true) -- Shift+Enter
			end,
		},
		{
			key = "view",
			label = "view in the split",
			run = function(row)
				M.close()
				require("switchyard.view").show(row.session)
			end,
		},
		{
			key = "external",
			label = "open in an external terminal",
			run = function(row)
				require("switchyard.view").external(row.session)
			end,
		},
		{
			key = "new",
			label = "new agent in a worktree…",
			any_row = true,
			run = function()
				with_worktree("new agent in", nil, function(wt)
					require("switchyard.actions").with_agent(function(agent)
						require("switchyard.launch").new(agent, wt.path)
					end)
				end)
			end,
		},
		{
			key = "fork",
			label = "fork into another worktree…",
			run = function(row)
				with_worktree("fork " .. sessions().name(row.session) .. " into", row.path, function(wt)
					require("switchyard.launch").fork(row.session, wt.path)
				end)
			end,
		},
		{
			key = "dispatch",
			label = "dispatch: a task for a new agent in a new worktree",
			any_row = true,
			run = function()
				M.close()
				require("switchyard.prompt").open_dispatch()
			end,
		},
		{
			key = "send",
			label = "write a prompt for it",
			run = function(row)
				M.close()
				require("switchyard.prompt").open_for(row.session)
			end,
		},
		{
			key = "rename",
			label = "rename its tmux session",
			run = function(row)
				local old = row.session.tmux
				require("switchyard.menu").input({ title = "rename " .. old, default = old }, function(new)
					if not new or new == "" or new == old then
						return
					end
					new = new:gsub("[%.:]", "_") -- tmux doesn't allow . and : in names
					require("switchyard.tmux").rename(old, new, function(ok, err)
						if not ok then
							return warn("tmux: " .. err)
						end
						require("switchyard.view").renamed(old, new)
						sessions().refresh()
					end)
				end)
			end,
		},
		{
			key = "remove",
			label = "stop agent",
			danger = true,
			run = function(row)
				require("switchyard.actions").stop_agent(row.session)
			end,
		},
	},
	projects = {
		{
			key = "activate",
			label = "switch to the project",
			run = activate,
		},
		{
			key = "alt_activate",
			label = "peek: switch, keep the link",
			run = function(row)
				activate(row, true) -- Shift+Enter
			end,
		},
		{
			key = "start_agent",
			label = "start an agent there (the editor stays)",
			run = function(row)
				require("switchyard.actions").with_agent(function(agent)
					require("switchyard.launch").new(agent, row.path)
				end)
			end,
		},
		{
			key = "copy_path",
			label = "copy path",
			run = function(row)
				vim.fn.setreg("+", row.path)
				vim.fn.setreg('"', row.path)
				vim.notify("switchyard: copied " .. vim.fn.fnamemodify(row.path, ":~"))
			end,
		},
	},
}

-- Run the current view's action for key name `name` on the selected row
local function run(name)
	local row = state.rows[selected_index()]
	for _, action in ipairs(actions[view]) do
		if action.key == name and (row or action.any_row) then
			return action.run(row)
		end
	end
end

-- How a key reads in menus and hints
local function key_label(name)
	local key = keys()[name]
	local pretty = { ["<CR>"] = "⏎", ["<S-CR>"] = "⇧⏎", ["<Tab>"] = "⇥", ["<C-r>"] = "^R" }
	return pretty[key] or key
end

-- `.`: the selected row's actions. `?`: every key of this view.
local function open_menu(all_keys)
	local row = state.rows[selected_index()]
	local items = {}
	for _, action in ipairs(actions[view]) do
		if row or action.any_row then
			table.insert(items, {
				label = action.label,
				key = key_label(action.key),
				danger = action.danger,
				action = function()
					action.run(row)
				end,
			})
		end
	end
	if all_keys then
		for _, name in ipairs(views) do
			if name ~= view then
				table.insert(items, {
					label = name .. " view",
					key = keys()["view_" .. name],
					action = function()
						show_view(name)
					end,
				})
			end
		end
		if view == "agents" then
			table.insert(items, { label = "this repo / all agents", key = key_label("toggle_view"), action = toggle_view })
		end
		for _, nav in ipairs({
			{ "filter", "filter", start_filter },
			{ "refresh", "refresh", refresh },
			{ "close", "close the yard", M.close },
		}) do
			table.insert(items, { label = nav[2], key = key_label(nav[1]), action = nav[3] })
		end
	end
	local subject = row
			and ((row.kind == "worktree" and row.worktree.branch) or (row.kind == "project" and row.name) or sessions().name(row.session))
		or view
	require("switchyard.menu").open({ title = all_keys and (view .. " · keys") or subject, items = items })
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

function M.close()
	ui.show_cursor()
	pcall(vim.api.nvim_del_augroup_by_name, "switchyard_yard")
	-- Closed from inside the yard: go back where it was opened. Otherwise Neovim
	-- picks a window itself (often the file tree). Closed because you went to
	-- another window: stay there.
	local current = vim.api.nvim_get_current_win()
	local inside = current == state.win or current == state.input_win
	-- Not ipairs over { input_win, win }: it stops at the first nil
	for _, win in pairs({ input = state.input_win, list = state.win }) do
		if valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	for _, buf in pairs({ input = state.input_buf, list = state.buf }) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	state.win, state.buf, state.input_win, state.input_buf = nil, nil, nil, nil
	state.filter = ""
	-- Before going back: returning to the viewer starts typing there again
	-- (its BufEnter), which a later stopinsert would undo
	vim.cmd.stopinsert()
	if inside and valid(state.origin) then
		vim.api.nvim_set_current_win(state.origin)
	end
end

local function set_keymaps()
	local k = keys()
	local function map(key, fn)
		vim.keymap.set("n", key, fn, { buffer = state.buf, nowait = true, silent = true })
	end
	map("<C-n>", function()
		move(1)
	end)
	map("<C-p>", function()
		move(-1)
	end)
	-- Every action key of both views; `run` picks the current view's action
	local names = {}
	for _, list in pairs(actions) do
		for _, action in ipairs(list) do
			names[action.key] = true
		end
	end
	for name in pairs(names) do
		map(k[name], function()
			run(name)
		end)
	end
	for _, name in ipairs(views) do
		map(k["view_" .. name], function()
			show_view(name)
		end)
	end
	map(k.actions, function()
		open_menu(false)
	end)
	map(k.help, function()
		open_menu(true)
	end)
	map(k.toggle_view, toggle_view)
	map(k.filter, start_filter)
	map(k.refresh, refresh)
	map(k.close, M.close)
	map("<Esc>", M.close)
end

local function set_autocmds()
	local group = vim.api.nvim_create_augroup("switchyard_yard", { clear = true })

	-- The list only moves up and down; keep the selection in sync
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = state.buf,
		callback = function()
			local pos = vim.api.nvim_win_get_cursor(0)
			if pos[2] ~= 0 then
				vim.api.nvim_win_set_cursor(0, { pos[1], 0 })
			end
			local row = state.rows[pos[1]]
			state.selected[view] = row and row.key
		end,
	})

	-- No visible cursor while the list has focus
	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, { group = group, buffer = state.buf, callback = ui.hide_cursor })
	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, { group = group, buffer = state.buf, callback = ui.show_cursor })

	-- Leaving for a normal editor window closes the yard (floating windows don't)
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			vim.schedule(function()
				local win = vim.api.nvim_get_current_win()
				if M.is_open() and win ~= state.win and win ~= state.input_win then
					if vim.api.nvim_win_get_config(win).relative == "" then
						M.close()
					end
				end
			end)
		end,
	})

	-- Agents starting, stopping, moving or getting their tmux name
	vim.api.nvim_create_autocmd("User", { group = group, pattern = "SwitchyardSessionsChanged", callback = render })
	vim.api.nvim_create_autocmd("VimResized", { group = group, callback = render })
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = ui.set_highlights })
end

function M.open()
	if M.is_open() then
		return vim.api.nvim_set_current_win(state.win)
	end
	view = view or require("switchyard.config").options.yard.view
	vim.cmd.stopinsert() -- opened from a terminal (the viewer): the yard works in normal mode
	ui.set_highlights()
	state.origin = vim.api.nvim_get_current_win()
	state.filter, state.rows, state.worktrees, state.err = "", {}, nil, nil
	state.projects, state.project_seen, state.projects_state = {}, {}, nil
	-- Start on the linked agent / the current worktree / the current project
	local linked = sessions().linked_pid()
	state.selected = {
		agents = linked and ("pid:" .. linked) or nil,
		projects = require("switchyard.projects").root(vim.fn.getcwd()),
	}

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.bo[state.buf].bufhidden = "hide"
	vim.bo[state.buf].filetype = "switchyard" -- lets statuslines recognise the yard
	state.win = vim.api.nvim_open_win(state.buf, true, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 50,
		height = 1,
		style = "minimal",
		border = "rounded",
	})
	vim.wo[state.win].cursorline = true
	vim.wo[state.win].winhighlight = "CursorLine:SwitchyardSelection"

	set_keymaps()
	set_autocmds()
	ui.hide_cursor() -- the WinEnter autocmd came too late for this first entry
	if view == "projects" then
		load_projects()
	end
	render()
	refresh()
end

return M
