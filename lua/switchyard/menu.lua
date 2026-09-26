local ui = require("switchyard.ui")

local M = {}

local ns = vim.api.nvim_create_namespace("switchyard_menu")

-- Show a menu in the yard's style.
-- opts.title: text in the border
-- opts.items: list of { label, action, key? (shown on the right), danger? }
-- opts.on_cancel: optional, called when closed without choosing
function M.open(opts)
	ui.set_highlights()
	local from = vim.api.nvim_get_current_win() -- focus goes back here
	local items = opts.items

	local label_width = 0
	for _, item in ipairs(items) do
		label_width = math.max(label_width, vim.fn.strdisplaywidth(item.label))
	end
	local width = math.min(math.max(label_width + 14, 44), math.floor(vim.o.columns * 0.7))

	-- Lines: " 1  label ............ key"
	local lines, marks = {}, {}
	for i, item in ipairs(items) do
		local number = ((#items > 9 and "%2d" or " %d") .. "  "):format(i) -- aligned past 9
		local key = item.key and (item.key .. " ") or ""
		local gap = width - vim.fn.strdisplaywidth(number .. item.label) - vim.fn.strdisplaywidth(key)
		lines[i] = number .. item.label .. string.rep(" ", math.max(gap, 1)) .. key
		marks[i] = {
			{ 0, #number, "SwitchyardDim" },
			item.danger and { #number, #number + #item.label, "SwitchyardDanger" } or nil,
			item.key and { #lines[i] - #key, #lines[i], "SwitchyardKey" } or nil,
		}
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = "switchyard"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	for i, line_marks in ipairs(marks) do
		for _, m in pairs(line_marks) do
			vim.api.nvim_buf_set_extmark(buf, ns, i - 1, m[1], { end_col = m[2], hl_group = m[3] })
		end
	end

	-- Opened from a float (the yard): right below it, or above when there's no
	-- room, so both stay readable. Otherwise centered.
	local row = math.max(1, math.floor((vim.o.lines - #items) / 2) - 3)
	local col = math.floor((vim.o.columns - width) / 2)
	local anchor = vim.api.nvim_win_get_config(from)
	if anchor.relative ~= "" then
		local height = #items + 2 -- + title and hints lines
		local below = anchor.row + anchor.height + 2
		if below + height + 2 <= vim.o.lines - 2 then
			row = below
		elseif anchor.row - height - 2 >= 0 then
			row = anchor.row - height - 2
		end
		col = anchor.col
	end
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = #items + 2, -- + the title line and the hints line
		row = row,
		col = col,
		style = "minimal",
		border = "rounded",
		zindex = 100, -- above the yard (50): same-level floats overlap badly in Neovide
	})
	ui.title(win, { { " switchyard ", "SwitchyardHeading" }, { "· " .. opts.title, "SwitchyardDim" } })
	ui.hints(buf, " ⏎ choose  ^N/^P move  1-9 pick  esc cancel")
	vim.wo[win].cursorline = true
	vim.wo[win].winhighlight = "CursorLine:SwitchyardSelection"
	ui.hide_cursor()

	local done = false
	local function close()
		if done then
			return
		end
		done = true
		ui.show_cursor()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
		if vim.api.nvim_win_is_valid(from) then
			vim.api.nvim_set_current_win(from)
		end
	end
	local function choose(index)
		local item = items[index or vim.api.nvim_win_get_cursor(win)[1]]
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
	for i = 1, math.min(#items, 9) do
		map(tostring(i), function()
			choose(i)
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
end

return M
