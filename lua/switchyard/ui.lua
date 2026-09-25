local M = {}

local function color(name, attr)
	return vim.api.nvim_get_hl(0, { name = name, link = false })[attr]
end

function M.set_highlights()
	local bg = color("NormalFloat", "bg") or color("Normal", "bg")
	vim.api.nvim_set_hl(0, "SwitchyardFilterBadge", { fg = bg, bg = color("Directory", "fg"), bold = true })
	vim.api.nvim_set_hl(0, "SwitchyardNormalBadge", { fg = bg, bg = color("DiagnosticOk", "fg"), bold = true })
	vim.api.nvim_set_hl(0, "SwitchyardLinkedBadge", { fg = bg, bg = color("DiagnosticOk", "fg"), bold = true })
	vim.api.nvim_set_hl(0, "SwitchyardHiddenCursor", { blend = 100, nocombine = true })
	local links = {
		SwitchyardSelection = "PmenuSel",
		SwitchyardHeading = "Title",
		SwitchyardDim = "Comment",
		SwitchyardLabel = "Comment",
		SwitchyardCurrent = "Directory",
		SwitchyardSymbols = "DiagnosticWarn",
		SwitchyardAgent = "Statement",
		SwitchyardLinked = "DiagnosticOk",
		SwitchyardMatch = "Special",
		SwitchyardKey = "Special",
		SwitchyardDanger = "DiagnosticError",
	}
	for group, target in pairs(links) do
		vim.api.nvim_set_hl(0, group, { link = target, default = true })
	end
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
