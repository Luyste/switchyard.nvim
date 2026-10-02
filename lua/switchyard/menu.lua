local ui = require("switchyard.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("switchyard_menu")

-- Where a window of `width` x `height` goes: opened from a float (the yard),
-- right below it, or above when there's no room, so both stay readable.
-- Otherwise centered. Returns row, col.
local function place(from, width, height)
	local row = math.max(1, math.floor((vim.o.lines - height) / 2) - 3)
	local col = math.floor((vim.o.columns - width) / 2)
	local anchor = vim.api.nvim_win_get_config(from)
	if anchor.relative ~= "" then
		local below = anchor.row + anchor.height + 2
		if below + height + 2 <= vim.o.lines - 2 then
			row = below
		elseif anchor.row - height - 2 >= 0 then
			row = anchor.row - height - 2
		end
		col = anchor.col
	end
	return row, col
end

-- A switchyard float holding `lines`, placed for window `from`, with the title
-- and key hints on lines of their own. Returns buf, win.
local function float(from, width, lines, title, hints)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "switchyard"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local height = #lines + 2 -- + the title line and the hints line
	local row, col = place(from, width, height)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		zindex = 100, -- above the yard (50): same-level floats overlap badly in Neovide
	})
	ui.title(win, { { " switchyard ", "SwitchyardHeading" }, { "· " .. title, "SwitchyardDim" } })
	ui.hints(buf, hints)
	return buf, win
end

-- Close float `win` and go back to window `from`
local function leave(win, from)
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if vim.api.nvim_win_is_valid(from) then
		vim.api.nvim_set_current_win(from)
	end
end

-- Show a menu in the yard's style. `/` filters it fuzzily (like the yard).
-- opts.title: the title line
-- opts.items: list of { label, action, key? (shown on the right), danger? }
-- opts.on_cancel: optional, called when closed without choosing
function M.open(opts)
	ui.set_highlights()
	local from = vim.api.nvim_get_current_win() -- focus goes back here
	-- Opened while typing (the prompt builder): the menu works in normal mode,
	-- else Ctrl-N/Ctrl-P are insert-mode completion (E21 on a read-only buffer)
	local was_typing = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
	vim.cmd.stopinsert()
	local items = opts.items
	local hints = " ⏎ choose  ^N/^P move  1-9 pick  / filter  esc cancel"

	local label_width = 0
	for _, item in ipairs(items) do
		label_width = math.max(label_width, vim.fn.strdisplaywidth(item.label))
	end
	local width = math.min(math.max(label_width + 14, 52), math.floor(vim.o.columns * 0.7))
	-- Long lists (earlier sessions) scroll
	local max_height = math.max(3, math.min(15, vim.o.lines - 12))

	local buf, win = float(from, width, vim.fn["repeat"]({ "" }, math.min(#items, max_height)), opts.title, hints)
	vim.wo[win].cursorline = true
	vim.wo[win].winhighlight = "CursorLine:SwitchyardSelection"
	ui.hide_cursor()

	-- The items shown (indexes into `items`), in order: all of them, or the
	-- ones matching the filter, best first
	local shown, filter = {}, ""

	local function render()
		shown = {}
		local matched = {} -- item index -> set of matched character indexes
		if filter == "" then
			for i = 1, #items do
				shown[i] = i
			end
		else
			local scored = {}
			for i, item in ipairs(items) do
				local result = vim.fn.matchfuzzypos({ item.label }, filter)
				if #result[1] > 0 then
					table.insert(scored, { i = i, score = result[3][1] })
					matched[i] = {}
					for _, pos in ipairs(result[2][1]) do
						matched[i][pos] = true
					end
				end
			end
			table.sort(scored, function(a, b)
				if a.score ~= b.score then
					return a.score > b.score
				end
				return a.i < b.i
			end)
			for n, entry in ipairs(scored) do
				shown[n] = entry.i
			end
		end

		-- Lines: " 1  label ............ key"
		local lines, marks = {}, {}
		for n, i in ipairs(shown) do
			local item = items[i]
			local number = ((#shown > 9 and "%2d" or " %d") .. "  "):format(n) -- aligned past 9
			local key = item.key and (item.key .. " ") or ""
			local gap = width - vim.fn.strdisplaywidth(number .. item.label) - vim.fn.strdisplaywidth(key)
			lines[n] = number .. item.label .. string.rep(" ", math.max(gap, 1)) .. key
			marks[n] = {
				{ 0, #number, "SwitchyardDim" },
				item.danger and { #number, #number + #item.label, "SwitchyardDanger" } or nil,
				item.key and { #lines[n] - #key, #lines[n], "SwitchyardKey" } or nil,
			}
			for pos in pairs(matched[i] or {}) do
				local s, e = vim.fn.byteidx(item.label, pos), vim.fn.byteidx(item.label, pos + 1)
				table.insert(marks[n], { #number + s, #number + e, "SwitchyardMatch" })
			end
		end
		if #lines == 0 then
			lines[1], marks[1] = "    No matches", { { 0, 14, "SwitchyardDim" } }
		end

		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
		for n, line_marks in ipairs(marks) do
			for _, m in pairs(line_marks) do
				vim.api.nvim_buf_set_extmark(buf, ns, n - 1, m[1], { end_col = m[2], hl_group = m[3] })
			end
		end
		ui.hints(buf, hints)
		vim.api.nvim_win_set_config(win, { height = math.min(#lines, max_height) + 2 }) -- + title and hints
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
	end

	local input_win = nil -- the filter line, only while filtering
	local done = false
	local function close_input()
		if input_win and vim.api.nvim_win_is_valid(input_win) then
			vim.api.nvim_win_close(input_win, true)
		end
		input_win = nil
	end
	local function close()
		if done then
			return
		end
		done = true
		vim.cmd.stopinsert()
		close_input()
		ui.show_cursor()
		leave(win, from)
		if was_typing and vim.api.nvim_get_current_win() == from then
			vim.cmd("startinsert!") -- typing on where you were
		end
	end
	local function choose(n)
		local item = items[shown[n or vim.api.nvim_win_get_cursor(win)[1]]]
		close()
		if item then
			vim.schedule(item.action)
		end
	end
	local function cancel()
		close()
		if opts.on_cancel then
			vim.schedule(opts.on_cancel)
		end
	end
	local function move(delta)
		local row = vim.api.nvim_win_get_cursor(win)[1] + delta
		vim.api.nvim_win_set_cursor(win, { math.max(1, math.min(math.max(#shown, 1), row)), 0 })
	end

	-- `/`: a line right above the menu (below when there's no room); typing
	-- filters, Enter chooses, Esc clears the filter and goes back to the list
	local function start_filter()
		if input_win then
			return vim.api.nvim_set_current_win(input_win)
		end
		local input_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[input_buf].bufhidden = "wipe"
		vim.bo[input_buf].filetype = "switchyard"
		local config = vim.api.nvim_win_get_config(win)
		local row = config.row >= 3 and config.row - 3 or config.row + config.height + 2
		input_win = vim.api.nvim_open_win(input_buf, true, {
			relative = "editor",
			row = row,
			col = config.col,
			width = config.width,
			height = 1,
			style = "minimal",
			border = "rounded",
			zindex = 101,
		})
		local function imap(key, fn)
			vim.keymap.set("i", key, fn, { buffer = input_buf, nowait = true, silent = true })
		end
		imap("<CR>", function()
			choose()
		end)
		imap("<Esc>", function()
			vim.cmd.stopinsert()
			close_input()
			filter = ""
			render()
			vim.api.nvim_set_current_win(win)
		end)
		imap("<C-n>", function()
			move(1)
		end)
		imap("<C-p>", function()
			move(-1)
		end)
		imap("<Down>", function()
			move(1)
		end)
		imap("<Up>", function()
			move(-1)
		end)
		vim.api.nvim_create_autocmd("TextChangedI", {
			buffer = input_buf,
			callback = function()
				filter = vim.api.nvim_buf_get_lines(input_buf, 0, 1, false)[1] or ""
				render()
			end,
		})
		vim.cmd("startinsert!")
	end

	local function map(key, fn)
		vim.keymap.set("n", key, fn, { buffer = buf, nowait = true, silent = true })
	end
	map("<CR>", function()
		choose()
	end)
	map("<C-n>", "j")
	map("<C-p>", "k")
	map("q", cancel)
	map("<Esc>", cancel)
	map("/", start_filter)
	for i = 1, 9 do
		map(tostring(i), function()
			if shown[i] then
				choose(i)
			end
		end)
	end

	-- Only up and down; cursor hidden while the menu has focus
	vim.api.nvim_create_autocmd("CursorMoved", {
		buffer = buf,
		callback = function()
			local pos = vim.api.nvim_win_get_cursor(0)
			if pos[2] ~= 0 then
				vim.api.nvim_win_set_cursor(0, { pos[1], 0 })
			end
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", { buffer = buf, callback = ui.hide_cursor })
	vim.api.nvim_create_autocmd("BufLeave", { buffer = buf, callback = ui.show_cursor })
	vim.api.nvim_create_autocmd("BufWipeout", { buffer = buf, callback = ui.show_cursor })
	render()
end

-- Ask for one line of text in the yard's style (instead of vim.ui.input at the
-- bottom of the screen). opts.title, opts.default. callback(text), or
-- callback(nil) when cancelled.
function M.input(opts, callback)
	ui.set_highlights()
	local from = vim.api.nvim_get_current_win()
	local default = opts.default or ""
	local width = math.min(math.max(44, vim.fn.strdisplaywidth(default) + 10), math.floor(vim.o.columns * 0.7))

	local buf, win = float(from, width, { default }, opts.title, " ⏎ confirm  esc cancel")

	local done = false
	local function finish(value)
		if done then
			return
		end
		done = true
		vim.cmd.stopinsert()
		leave(win, from)
		vim.schedule(function()
			callback(value)
		end)
	end
	local function confirm()
		finish(vim.trim(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""))
	end
	local function map(modes, key, fn)
		vim.keymap.set(modes, key, fn, { buffer = buf, nowait = true, silent = true })
	end
	map({ "i", "n" }, "<CR>", confirm)
	map("i", "<Esc>", function()
		finish(nil)
	end)
	map("n", "<Esc>", function()
		finish(nil)
	end)
	map("n", "q", function()
		finish(nil)
	end)
	-- Clicking elsewhere cancels
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = buf,
		once = true,
		callback = function()
			finish(nil)
		end,
	})
	vim.cmd("startinsert!")
end

return M
