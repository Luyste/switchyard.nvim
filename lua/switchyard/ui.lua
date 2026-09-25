local M = {}

local function color(name, attr)
	return vim.api.nvim_get_hl(0, { name = name, link = false })[attr]
end

-- Relative luminance of a 0xRRGGBB color, 0 (black) to 1 (white), as in WCAG
local function luminance(rgb)
	local function channel(shift)
		local c = math.floor(rgb / shift) % 256 / 255
		return c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channel(0x10000) + 0.7152 * channel(0x100) + 0.0722 * channel(1)
end

-- How readable a on b is: 1 (same color) to 21 (black on white)
local function contrast(a, b)
	local la, lb = luminance(a), luminance(b)
	return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05)
end

-- A badge: background from `source`'s text color, and as text the theme's
-- light or dark color, whichever reads better on it
local function badge(group, source)
	local bg = color(source, "fg")
	local light = color("Normal", "fg") or 0xffffff
	local dark = color("Normal", "bg") or 0x000000
	local fg = (bg and contrast(light, bg) > contrast(dark, bg)) and light or dark
	vim.api.nvim_set_hl(0, group, { fg = fg, bg = bg, bold = true })
end

function M.set_highlights()
	badge("SwitchyardFilterBadge", "Directory")
	badge("SwitchyardNormalBadge", "DiagnosticOk")
	badge("SwitchyardLinkedBadge", "DiagnosticOk")
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
