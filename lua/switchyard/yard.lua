local ui = require("switchyard.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("switchyard_yard")

local state = {
	mode = "filter", -- "filter" or "normal"
	wins = {}, -- input, list, detail
	bufs = {},
	worktrees = nil, -- the last `wt list` result
	err = nil,
	rows = {}, -- one entry per list line
	expanded = {}, -- worktree path -> true
	filter = "",
	selected_key = nil, -- keeps the selection on the same row across redraws
}

local function keys()
	return require("switchyard.config").options.keys.yard
end
local function valid(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

function M.is_open()
	return valid(state.wins.list)
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

local function pad(text, width)
	return text .. string.rep(" ", math.max(width - width_of(text), 0))
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
-- Rows: which worktrees and agents are shown
---------------------------------------------------------------------------

local function agent_name(session)
	return require("switchyard.sessions").tmux_name(session) or session.adapter.name
end

local function build_rows()
	local sessions = require("switchyard.sessions")
	local all = sessions.all()
	for _, s in ipairs(all) do
		sessions.resolve_tmux(s)
	end

	local rows = {}
	for _, wt in ipairs(state.worktrees or {}) do
		local agents = vim.tbl_filter(function(s)
			return s.cwd == wt.path
		end, all)
		local wt_matches = state.filter == "" or match(wt.branch) ~= nil
		local matching_agents = vim.tbl_filter(function(s)
			return state.filter == "" or match(agent_name(s)) ~= nil
		end, agents)

		if wt_matches or #matching_agents > 0 then
			-- A worktree shown only because an agent matches opens by itself
			local open = state.expanded[wt.path] or (not wt_matches and #matching_agents > 0)
			table.insert(rows, { kind = "worktree", worktree = wt, agents = agents, open = open, key = wt.path })
			if open then
				for _, s in ipairs(wt_matches and agents or matching_agents) do
					table.insert(rows, { kind = "agent", session = s, worktree = wt, key = "pid:" .. s.pid })
				end
			end
		end
	end
	return rows
end

local function worktree_line(row, width, linked_pid)
	local wt, b = row.worktree, builder()
	local compact = state.mode == "filter"
	b.add(" ")
	b.add(#row.agents > 0 and (row.open and "▾ " or "▸ ") or "  ", "SwitchyardDim")
	b.add(wt.current and "@ " or "  ", "SwitchyardCurrent")

	local name_width = width - (compact and 40 or 18)
	local name = truncate(wt.branch, name_width)
	add_matched(b, name, wt.current and "SwitchyardCurrent" or nil)
	b.add(string.rep(" ", name_width - width_of(name) + 2))
	b.add(pad(truncate(wt.symbols, 8), 9), "SwitchyardSymbols")

	if compact and #row.agents > 0 then
		local linked_here = false
		for _, s in ipairs(row.agents) do
			if s.pid == linked_pid then
				linked_here = true
			end
		end
		local summary = (#row.agents == 1 and "1 agent" or (#row.agents .. " agents"))
			.. (linked_here and " · linked" or "")
		b.add(summary, linked_here and "SwitchyardLinked" or "SwitchyardAgent")
	end
	return b
end

local function agent_line(row, linked_pid)
	local s, b = row.session, builder()
	local is_linked = s.pid == linked_pid
	b.add("       ")
	b.add("● ", is_linked and "SwitchyardLinked" or "SwitchyardAgent")
	add_matched(b, agent_name(s), nil)
	if is_linked then
		b.add("  ")
		b.add(" LINKED ", "SwitchyardLinkedBadge")
	end
	return b
end

---------------------------------------------------------------------------
-- Writing to buffers
---------------------------------------------------------------------------

local function write(buf, builders)
	local lines = {}
	for i, b in ipairs(builders) do
		lines[i] = b.text
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for i, b in ipairs(builders) do
		for _, h in ipairs(b.hls) do
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, h[1], { end_col = h[2], hl_group = h[3] })
		end
	end
end

local function selected_row()
	if not M.is_open() then
		return nil
	end
	return state.rows[vim.api.nvim_win_get_cursor(state.wins.list)[1]]
end

---------------------------------------------------------------------------
-- The detail panel (normal mode only)
---------------------------------------------------------------------------

local function render_detail()
	if state.mode ~= "normal" or not valid(state.wins.detail) then
		return
	end
	local k, out = keys(), {}
	local function line(parts)
		local b = builder()
		for _, p in ipairs(parts) do
			b.add(p[1], p[2])
		end
		table.insert(out, b)
	end
	local function actions(list)
		line({ { " ACTIONS", "SwitchyardLabel" } })
		for _, a in ipairs(list) do
			line({ { "   " .. pad(a[1], 7), "SwitchyardKey" }, { a[2], a[3] and "SwitchyardDanger" or nil } })
		end
	end

	local row = selected_row()
	if not row then
		line({ { " Nothing selected", "SwitchyardDim" } })
	elseif row.kind == "worktree" then
		local wt = row.worktree
		line({ { " WORKTREE", "SwitchyardLabel" } })
		line({ { " " .. wt.branch, "SwitchyardHeading" } })
		line({ { " " .. vim.fn.fnamemodify(wt.path, ":~"), "SwitchyardDim" } })
		line({})
		line({
			{ " Status   ", "SwitchyardLabel" },
			{ wt.symbols ~= "" and wt.symbols or "clean", "SwitchyardSymbols" },
		})
		line({ { " Agents   ", "SwitchyardLabel" }, { tostring(#row.agents) } })
		line({})
		actions({
			{ k.activate, "switch editor here" },
			{ k.toggle, "expand / collapse agents" },
			{ k.new_agent, "new agent here" },
			{ k.continue_agent, "continue last session here" },
			{ k.fork_agent, "fork linked agent here" },
			{ k.new_worktree, "new worktree" },
			{ k.copy_path, "copy path" },
			{ k.remove, "remove worktree", true },
		})
	else
		local s = row.session
		local linked = require("switchyard.sessions").linked()
		local is_linked = linked and linked.pid == s.pid
		line({ { " AGENT", "SwitchyardLabel" } })
		line({ { " " .. agent_name(s), "SwitchyardHeading" } })
		line({ { " " .. s.adapter.name .. " · in " .. row.worktree.branch, "SwitchyardDim" } })
		line({})
		line({
			{ " Editor   ", "SwitchyardLabel" },
			is_linked and { "linked", "SwitchyardLinked" } or { "not linked", "SwitchyardDim" },
		})
		line({})
		actions({
			{ k.activate, "link editor to this agent" },
			{ k.view, "view in split" },
			{ k.external, "open in external terminal" },
			{ k.send, "send a prompt" },
			{ k.move, "move to another worktree" },
			{ k.spin_off, "spin off into new worktree" },
			{ k.rename, "rename session" },
			{ k.remove, "stop agent", true },
		})
	end
	write(state.bufs.detail, out)
end

---------------------------------------------------------------------------
-- Layout: sizes and positions for the current mode
---------------------------------------------------------------------------

local function title()
	local repo = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
	local badge = state.mode == "normal" and { " NORMAL ", "SwitchyardNormalBadge" }
		or { " FILTER ", "SwitchyardFilterBadge" }
	return {
		{ " switchyard ", "SwitchyardHeading" },
		{ "· " .. repo .. " ", "SwitchyardDim" },
		badge,
		{ " ", "FloatBorder" },
	}
end

local function footer()
	local k = keys()
	if state.mode == "normal" then
		return {
			{
				(" j/k move  %s expand  %s switch  %s filter  %s close "):format(k.toggle, "⏎", k.filter, k.close),
				"SwitchyardDim",
			},
		}
	end
	return { { " ⏎ switch  ^N/^P move  ⇥ expand  esc manage ", "SwitchyardDim" } }
end

local function layout()
	if not M.is_open() then
		return
	end
	local cols, lines = vim.o.columns, vim.o.lines
	local normal = state.mode == "normal"

	local width = normal and math.floor(cols * 0.86) or math.min(100, math.floor(cols * 0.62))
	local list_height = normal and (math.floor(lines * 0.74) - 3) or math.max(3, math.min(#state.rows, 16))
	local total = 3 + list_height + 2
	local top = math.max(1, math.floor((lines - total) / 2) - (normal and 0 or 3))
	local left = math.floor((cols - width) / 2)
	local list_width = normal and math.floor(width * 0.5) or width

	vim.api.nvim_win_set_config(state.wins.input, {
		relative = "editor",
		row = top,
		col = left,
		width = width,
		height = 1,
		title = title(),
		title_pos = "left",
	})
	vim.api.nvim_win_set_config(state.wins.list, {
		relative = "editor",
		row = top + 3,
		col = left,
		width = list_width,
		height = list_height,
		footer = footer(),
		footer_pos = "left",
	})

	if normal then
		local detail = {
			relative = "editor",
			row = top + 3,
			col = left + list_width + 2,
			width = width - list_width - 2,
			height = list_height,
			style = "minimal",
			border = "rounded",
		}
		if valid(state.wins.detail) then
			vim.api.nvim_win_set_config(state.wins.detail, detail)
		else
			state.wins.detail = vim.api.nvim_open_win(state.bufs.detail, false, detail)
		end
	elseif valid(state.wins.detail) then
		vim.api.nvim_win_close(state.wins.detail, true)
		state.wins.detail = nil
	end
end

---------------------------------------------------------------------------
-- Rendering the list
---------------------------------------------------------------------------

local function update_count()
	local buf = state.bufs.input
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	vim.api.nvim_buf_set_extmark(
		buf,
		ns,
		0,
		0,
		{ virt_text = { { "› ", "SwitchyardKey" } }, virt_text_pos = "inline" }
	)
	local shown = 0
	for _, row in ipairs(state.rows) do
		if row.kind == "worktree" then
			shown = shown + 1
		end
	end
	vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, {
		virt_text = { { ("%d / %d "):format(shown, #(state.worktrees or {})), "SwitchyardDim" } },
		virt_text_pos = "right_align",
	})
end

local function render()
	if not M.is_open() then
		return
	end
	state.rows = build_rows()
	layout()

	local linked = require("switchyard.sessions").linked()
	local linked_pid = linked and linked.pid
	local width = vim.api.nvim_win_get_width(state.wins.list)
	local out = {}
	for _, row in ipairs(state.rows) do
		table.insert(
			out,
			row.kind == "worktree" and worktree_line(row, width, linked_pid) or agent_line(row, linked_pid)
		)
	end
	if #out == 0 then
		local b = builder()
		b.add(state.worktrees and "  No matches" or ("  " .. (state.err or "Loading…")), "SwitchyardDim")
		out = { b }
	end
	write(state.bufs.list, out)

	-- Put the selection back on the same row, if it's still there
	local target = 1
	for i, row in ipairs(state.rows) do
		if row.key == state.selected_key then
			target = i
		end
	end
	vim.api.nvim_win_set_cursor(state.wins.list, { target, 0 })
	state.selected_key = state.rows[target] and state.rows[target].key

	update_count()
	render_detail()
end

M.render = render

---------------------------------------------------------------------------
-- Actions available in part 1
---------------------------------------------------------------------------

local function move(delta)
	if #state.rows == 0 then
		return
	end
	local row = vim.api.nvim_win_get_cursor(state.wins.list)[1] + delta
	row = math.max(1, math.min(#state.rows, row))
	vim.api.nvim_win_set_cursor(state.wins.list, { row, 0 })
	state.selected_key = state.rows[row].key
	render_detail()
end

local function toggle()
	local row = selected_row()
	if not row then
		return
	end
	local path = row.worktree.path
	if row.kind == "agent" then
		state.selected_key = path -- collapsing: select the worktree
	end
	state.expanded[path] = not state.expanded[path]
	render()
end

local function activate()
	local row = selected_row()
	if not row then
		return
	end
	if row.kind == "worktree" then
		M.close()
		vim.schedule(function()
			require("switchyard.projects").switch(row.worktree.path)
		end)
	else
		require("switchyard.sessions").link(row.session, true)
		render()
	end
end

---------------------------------------------------------------------------
-- Modes
---------------------------------------------------------------------------

local function enter_normal()
	state.mode = "normal"
	vim.cmd.stopinsert()
	render()
	vim.api.nvim_set_current_win(state.wins.list)
end

local function enter_filter()
	state.mode = "filter"
	render()
	vim.api.nvim_set_current_win(state.wins.input)
	vim.cmd("startinsert!")
end

function M.close()
	ui.show_cursor()
	pcall(vim.api.nvim_del_augroup_by_name, "switchyard_yard")
	for _, win in pairs(state.wins) do
		if valid(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	for _, buf in pairs(state.bufs) do
		if vim.api.nvim_buf_is_valid(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	state.wins, state.bufs = {}, {}
	vim.cmd.stopinsert()
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------

local function set_keymaps()
	local k = keys()
	local function map(buf, modes, key, fn)
		vim.keymap.set(modes, key, fn, { buffer = buf, nowait = true, silent = true })
	end

	-- Input (filter mode): typing edits the filter, these keys drive the list
	local input = state.bufs.input
	map(input, "i", "<C-n>", function()
		move(1)
	end)
	map(input, "i", "<C-p>", function()
		move(-1)
	end)
	map(input, "i", "<Down>", function()
		move(1)
	end)
	map(input, "i", "<Up>", function()
		move(-1)
	end)
	map(input, "i", "<CR>", activate)
	map(input, "i", "<Tab>", toggle)
	map(input, { "i", "n" }, "<Esc>", enter_normal)
	map(input, "i", "<C-c>", M.close)

	-- List (normal mode)
	local list = state.bufs.list
	map(list, "n", "<C-n>", function()
		move(1)
	end)
	map(list, "n", "<C-p>", function()
		move(-1)
	end)
	map(list, "n", k.activate, activate)
	map(list, "n", k.toggle, toggle)
	map(list, "n", "<Tab>", toggle)
	map(list, "n", k.filter, enter_filter)
	map(list, "n", "/", enter_filter)
	map(list, "n", k.close, M.close)
	map(list, "n", "<Esc>", M.close)
end

local function set_autocmds()
	local group = vim.api.nvim_create_augroup("switchyard_yard", { clear = true })
	local list, input = state.bufs.list, state.bufs.input

	-- The filter is whatever the input line contains
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		group = group,
		buffer = input,
		callback = function()
			state.filter = vim.api.nvim_buf_get_lines(input, 0, 1, false)[1] or ""
			state.selected_key = nil -- a new filter selects the first row
			render()
		end,
	})

	-- The list only moves up and down; keep the selection in sync
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = list,
		callback = function()
			local pos = vim.api.nvim_win_get_cursor(0)
			if pos[2] ~= 0 then
				vim.api.nvim_win_set_cursor(0, { pos[1], 0 })
			end
			local row = state.rows[pos[1]]
			state.selected_key = row and row.key
			render_detail()
		end,
	})

	-- No visible cursor while the list has focus
	vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, { group = group, buffer = list, callback = ui.hide_cursor })
	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, { group = group, buffer = list, callback = ui.show_cursor })

	-- Leaving for a normal editor window closes the yard (floating windows don't)
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			vim.schedule(function()
				if not M.is_open() then
					return
				end
				local win = vim.api.nvim_get_current_win()
				for _, w in pairs(state.wins) do
					if w == win then
						return
					end
				end
				if vim.api.nvim_win_get_config(win).relative == "" then
					M.close()
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
		return vim.api.nvim_set_current_win(state.mode == "normal" and state.wins.list or state.wins.input)
	end

	ui.set_highlights()
	state.mode, state.filter, state.rows = "filter", "", {}
	state.worktrees, state.err, state.selected_key = nil, nil, nil

	for _, name in ipairs({ "input", "list", "detail" }) do
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].bufhidden = "hide"
		state.bufs[name] = buf
	end
	vim.bo[state.bufs.list].filetype = "switchyard"

	local base =
		{ relative = "editor", row = 1, col = 1, width = 40, height = 1, style = "minimal", border = "rounded" }
	state.wins.input = vim.api.nvim_open_win(state.bufs.input, true, base)
	state.wins.list = vim.api.nvim_open_win(state.bufs.list, false, vim.tbl_extend("force", base, { height = 3 }))
	vim.wo[state.wins.list].cursorline = true
	vim.wo[state.wins.list].winhighlight = "CursorLine:SwitchyardSelection"

	set_keymaps()
	set_autocmds()
	render()
	vim.cmd("startinsert")

	require("switchyard.worktrunk").list(vim.fn.getcwd(), function(worktrees, err)
		state.worktrees, state.err = worktrees, err
		for _, wt in ipairs(worktrees or {}) do
			if wt.current then
				state.expanded[wt.path] = true -- the current worktree starts expanded
				state.selected_key = wt.path -- and selected
			end
		end
		render()
	end)
end

return M
