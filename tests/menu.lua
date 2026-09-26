-- Menus and the input. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/menu.lua
local menu = require("switchyard.menu")
local editor = vim.api.nvim_get_current_win()
local function keys(k)
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(k, true, false, true), "x", false)
end

-- Input: the default can be edited, Enter confirms, focus goes back
local answer
menu.input({ title = "branch", default = "feature" }, function(text)
	answer = text
end)
assert(vim.api.nvim_win_get_config(0).relative ~= "", "input opens as a float")
keys("A/x<CR>")
vim.wait(100, function()
	return answer ~= nil
end)
assert(answer == "feature/x", "confirmed text: " .. tostring(answer))
assert(vim.api.nvim_get_current_win() == editor, "focus back")

-- Esc cancels
answer = "unset"
menu.input({ title = "branch" }, function(text)
	answer = text
end)
keys("abc<Esc>")
vim.wait(100, function()
	return answer ~= "unset"
end)
assert(answer == nil, "cancelled")
assert(#vim.api.nvim_list_wins() == 1, "closed")

print("menu: ok")
