-- Opening and closing the yard. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/yard.lua
require("switchyard").setup({})
local yard = require("switchyard.yard")

local function floats()
	return #vim.tbl_filter(function(w)
		return vim.api.nvim_win_get_config(w).relative ~= ""
	end, vim.api.nvim_list_wins())
end

local editor = vim.api.nvim_get_current_win()
yard.open()
assert(yard.is_open() and floats() == 1, "opens one window")
yard.close()
assert(not yard.is_open() and floats() == 0, "closes its window")
assert(vim.api.nvim_get_current_win() == editor, "back in the window it was opened from")

yard.open()
yard.open() -- again while open: focuses it, no second window
assert(floats() == 1, "no second yard")
yard.close()

print("yard: ok")
