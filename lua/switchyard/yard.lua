-- The yard: one small floating window with two views.
--   worktrees: the current repo's worktrees, with a summary of their agents
--   agents:    this repo's running agents
-- Tab switches views; `/` shows a filter line above the list while filtering.
local ui = require("switchyard.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("switchyard_yard")

-- The view survives closing: the yard reopens where you left it
local view = nil

local state = {
	win = nil, -- the list
	buf = nil,
	input_win = nil, -- the filter line, only while filtering
	input_buf = nil,
	worktrees = nil, -- the last `wt list` result
	err = nil,
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

-- Where the filter matches `text` (case-insensitive), or nil
local function match(text)
	if state.filter == "" then
		return nil
	end
	return text:lower():find(state.filter:lower(), 1, true)
end

-- Add `text`, highlighting the part that matches the filter
local function add_matched(b, text, hl)
	local s, e = match(text)
	if not s then
		return b.add(text, hl)
	end
	b.add(text:sub(1, s - 1), hl)
	b.add(text:sub(s, e), "SwitchyardMatch")
	b.add(text:sub(e + 1), hl)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function agent_name(session)
	return sessions().tmux_name(session) or session.adapter.name
end

local function worktree_rows(all)
	state.total = #(state.worktrees or {})
	local rows = {}
	for _, wt in ipairs(state.worktrees or {}) do
		local agents = vim.tbl_filter(function(s)
			return s.cwd == wt.path
		end, all)
		local shown = state.filter == ""
			or match(wt.branch)
			or vim.iter(agents):any(function(s)
				return match(agent_name(s)) ~= nil
			end)
		if shown then
			table.insert(rows, { kind = "worktree", worktree = wt, agents = agents, key = wt.path, path = wt.path })
		end
	end
	return rows
end

-- This repo's agents: the linked one first, then by worktree. Agents whose
-- folder is gone (kept running after "remove worktree") are listed too, so
-- they can still be forked or stopped.
local function agent_rows(all)
	local branch_of = {}
	for _, wt in ipairs(state.worktrees or {}) do
		branch_of[wt.path] = wt.branch
	end
	local mine = vim.tbl_filter(function(s)
		return branch_of[s.cwd] ~= nil or vim.fn.isdirectory(s.cwd) == 0
	end, all)
	local linked = sessions().linked_pid()
	table.sort(mine, function(a, b)
		if (a.pid == linked) ~= (b.pid == linked) then
			return a.pid == linked
		end
		if a.cwd ~= b.cwd then
			return a.cwd < b.cwd
		end
		return a.pid < b.pid
	end)
	state.total = #mine -- for the filter's "n / total"
	local rows = {}
	for _, s in ipairs(mine) do
		local where = branch_of[s.cwd] or "removed worktree"
		if state.filter == "" or match(agent_name(s)) or match(where) then
			table.insert(rows, { kind = "agent", session = s, where = where, key = "pid:" .. s.pid, path = s.cwd })
		end
	end
	return rows
end

-- One line: a left part (builder) and an optional right part { text, hl }
local function number(b, i)
	b.add(i <= 9 and (" " .. i .. " ") or "   ", "SwitchyardDim")
end

local function worktree_line(i, row, linked)
	local wt, b = row.worktree, builder()
	number(b, i)
	b.add(wt.current and "@ " or "  ", "SwitchyardCurrent")
	add_matched(b, wt.branch, wt.current and "SwitchyardCurrent" or nil)
	if wt.symbols ~= "" then
		b.add("  ")
		b.add(wt.symbols, "SwitchyardSymbols")
	end
	local linked_here = vim.iter(row.agents):any(function(s)
		return s.pid == linked
	end)
	if linked_here then
		local more = #row.agents > 1 and (" +" .. (#row.agents - 1)) or ""
		return b, { "● linked" .. more, "SwitchyardLinked" }
	elseif #row.agents > 0 then
		return b, { "● " .. #row.agents, "SwitchyardAgent" }
	end
	return b
end

local function agent_line(i, row, linked)
	local s, b = row.session, builder()
	local is_linked = s.pid == linked
	number(b, i)
	b.add("● ", is_linked and "SwitchyardLinked" or "SwitchyardAgent")
	add_matched(b, agent_name(s), is_linked and "SwitchyardLinked" or nil)
	return b, { row.where, "SwitchyardDim" }
end

---------------------------------------------------------------------------
-- Title, footer, layout
---------------------------------------------------------------------------

local function title()
	local parts = { { " switchyard ", "SwitchyardHeading" } }
	if view == "worktrees" then
		table.insert(parts, { "· " .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t") .. " ", "SwitchyardDim" })
	end
	table.insert(parts, { "· " .. view .. " ", "SwitchyardDim" })
	return parts
end

local function footer(width)
	local hints = view == "worktrees" and " ⏎ switch  ⇧⏎ peek  ⇥ agents  / filter  . actions  ? keys "
		or " ⏎ go to  ⇧⏎ link  ⇥ worktrees  / filter  . actions  ? keys "
	return { { truncate(hints, width - 2), "SwitchyardDim" } }
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
		height = height,
		title = title(),
		title_pos = "left",
		footer = footer(width),
		footer_pos = "left",
	})
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
	for _, s in ipairs(all) do
		sessions().resolve_tmux(s)
	end
	state.rows = view == "agents" and agent_rows(all) or worktree_rows(all)

	-- Lines, and the width they need
	local linked = sessions().linked_pid()
	local parts, want = {}, 0
	for i, row in ipairs(state.rows) do
		local b, right
		if row.kind == "worktree" then
			b, right = worktree_line(i, row, linked)
		else
			b, right = agent_line(i, row, linked)
		end
		parts[i] = { b = b, right = right }
		want = math.max(want, width_of(b.text) + (right and width_of(right[1]) + 4 or 1))
	end
	if #parts == 0 then
		local message = state.worktrees and "No matches" or (state.err or "Loading…")
		if view == "agents" and state.filter == "" and state.worktrees then
			message = "No agents running"
		end
		local b = builder()
		b.add("   " .. message, "SwitchyardDim")
		parts[1] = { b = b }
	end

	-- As small as possible: sized to the content, within limits
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
--   worktree: switch (the link moves along) / peek (the link stays)
--   agent:    go to it (switch to its worktree + link) / link only, stay here
local function activate(row, alt)
	if row.kind == "agent" and alt then
		sessions().link(row.session)
		return render()
	end
	M.close()
	if row.kind == "worktree" then
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

local function toggle_view()
	view = view == "worktrees" and "agents" or "worktrees"
	render()
end

local function refresh()
	require("switchyard.worktrunk").list(vim.fn.getcwd(), function(worktrees, err)
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

-- The adapter to start: the only installed one, or ask. callback(adapter)
local function with_adapter(callback)
	local list = require("switchyard.adapters").active()
	if #list == 0 then
		return warn("no agents installed")
	elseif #list == 1 then
		return callback(list[1])
	end
	require("switchyard.menu").open({
		title = "which agent?",
		items = vim.tbl_map(function(adapter)
			return {
				label = adapter.name,
				action = function()
					callback(adapter)
				end,
			}
		end, list),
	})
end

-- Choose one of this repo's worktrees (the current one first, `except` left
-- out), or create a new one. callback(worktree): { path, branch }
local function with_worktree(title, except, callback)
	local list = vim.tbl_filter(function(wt)
		return wt.path ~= except
	end, state.worktrees or {})
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
	require("switchyard.menu").open({ title = title, items = items })
end

-- Per view: { key = name in keys.yard, label, run = function(row), danger?,
-- any_row? (also works on an empty list; row is nil then) }
local actions = {
	worktrees = {
		{
			key = "activate",
			label = "switch here",
			run = function(row)
				activate(row)
			end,
		},
		{
			key = "alt_activate",
			label = "peek: switch, keep the link",
			run = function(row)
				activate(row, true)
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
			key = "start_agent",
			label = "start an agent here",
			run = function(row)
				with_adapter(function(adapter)
					require("switchyard.launch").new(adapter, row.path)
				end)
			end,
		},
		{
			key = "continue_agent",
			label = "continue the last session here",
			run = function(row)
				with_adapter(function(adapter)
					require("switchyard.launch").continue(adapter, row.path)
				end)
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
			run = function(row)
				activate(row)
			end,
		},
		{
			key = "alt_activate",
			label = "link only, stay here",
			run = function(row)
				activate(row, true)
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
					with_adapter(function(adapter)
						require("switchyard.launch").new(adapter, wt.path)
					end)
				end)
			end,
		},
		{
			key = "fork",
			label = "fork into another worktree…",
			run = function(row)
				with_worktree("fork " .. agent_name(row.session) .. " into", row.path, function(wt)
					require("switchyard.launch").fork(row.session, wt.path)
				end)
			end,
		},
		{
			key = "rename",
			label = "rename its tmux session",
			run = function(row)
				local s = row.session
				local old = sessions().tmux_name(s)
				if not old then
					return warn(agent_name(s) .. " isn't running in tmux")
				end
				vim.ui.input({ prompt = "Rename to: ", default = old }, function(new)
					if not new or new == "" or new == old then
						return
					end
					new = new:gsub("[%.:]", "_") -- tmux doesn't allow . and : in names
					require("switchyard.tmux").rename(old, new, function(ok, err)
						if not ok then
							return warn("tmux: " .. err)
						end
						require("switchyard.view").renamed(old, new)
						sessions().renamed(s, new)
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
		local other = view == "worktrees" and "agents" or "worktrees"
		for _, nav in ipairs({
			{ "toggle_view", other .. " view", toggle_view },
			{ "filter", "filter", start_filter },
			{ "refresh", "refresh", refresh },
			{ "close", "close the yard", M.close },
		}) do
			table.insert(items, { label = nav[2], key = key_label(nav[1]), action = nav[3] })
		end
	end
	local subject = row and (row.kind == "worktree" and row.worktree.branch or agent_name(row.session)) or view
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
	if inside and valid(state.origin) then
		vim.api.nvim_set_current_win(state.origin)
	end
	vim.cmd.stopinsert()
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
	for i = 1, 9 do
		map(tostring(i), function()
			if state.rows[i] then
				activate(state.rows[i])
			end
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
	ui.set_highlights()
	state.origin = vim.api.nvim_get_current_win()
	state.filter, state.rows, state.worktrees, state.err = "", {}, nil, nil
	-- Start on the linked agent / the current worktree
	local linked = sessions().linked_pid()
	state.selected = { agents = linked and ("pid:" .. linked) or nil }

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
	render()
	refresh()
end

return M
