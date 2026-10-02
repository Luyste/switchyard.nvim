local M = {}

function M.set_highlights()
	vim.api.nvim_set_hl(0, "SwitchyardHiddenCursor", { blend = 100, nocombine = true })
	-- Some themes (vague) make PmenuSel `reverse` without colors: on a row with
	-- colored text that turns every colored piece into a block. Use Visual then.
	local pmenu_sel = vim.api.nvim_get_hl(0, { name = "PmenuSel", link = false })
	local links = {
		SwitchyardSelection = (pmenu_sel.bg and not pmenu_sel.reverse) and "PmenuSel" or "Visual",
		SwitchyardHeading = "Title",
		SwitchyardDim = "Comment",
		SwitchyardCurrent = "Directory",
		SwitchyardSymbols = "DiagnosticWarn",
		SwitchyardRepo = "Directory",
		SwitchyardMatch = "Special",
		SwitchyardKey = "Special",
		SwitchyardDanger = "DiagnosticError",
	}
	for group, target in pairs(links) do
		vim.api.nvim_set_hl(0, group, { link = target, default = true })
	end
end

---------------------------------------------------------------------------
-- Titles and hints on lines of their own (text in the border covers it)
---------------------------------------------------------------------------

local hint_ns = vim.api.nvim_create_namespace("switchyard_hints")

-- { { text, hl }, ... } as statusline/winbar text
local function bar_text(chunks)
	local out = {}
	for _, chunk in ipairs(chunks) do
		table.insert(out, "%#" .. (chunk[2] or "NormalFloat") .. "#" .. chunk[1]:gsub("%%", "%%%%"))
	end
	return table.concat(out) .. "%*"
end

-- The title on the top line of float `win` (its winbar). `right`: chunks for
-- the right end. Adds one line to the window's height.
function M.title(win, chunks, right)
	local highlights = vim.wo[win].winhighlight
	if not highlights:find("WinBar:", 1, true) then
		-- WinBar is a statusline color in many themes; in a float it should blend in
		vim.wo[win].winhighlight = (highlights ~= "" and highlights .. "," or "") .. "WinBar:NormalFloat,WinBarNC:NormalFloat"
	end
	vim.wo[win].winbar = bar_text(chunks) .. (right and ("%=" .. bar_text(right)) or "")
end

-- Key hints on a virtual line below the last line of `buf`. Adds one line to
-- the height of the window showing it. Call again after changing the buffer.
function M.hints(buf, text)
	vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
	local last = vim.api.nvim_buf_line_count(buf) - 1
	vim.api.nvim_buf_set_extmark(buf, hint_ns, last, 0, { virt_lines = { { { text, "SwitchyardDim" } } } })
end

local saved_guicursor = nil

function M.hide_cursor()
	if saved_guicursor then
		return
	end
	saved_guicursor = vim.o.guicursor
	vim.o.guicursor = "a:SwitchyardHiddenCursor"
end

function M.show_cursor()
	if not saved_guicursor then
		return
	end
	vim.o.guicursor = saved_guicursor
	saved_guicursor = nil
end

return M
