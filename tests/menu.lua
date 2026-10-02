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

-- `/` filters fuzzily; Enter in the filter line takes the best match
local picked
menu.open({
	title = "continue a session",
	items = {
		{ label = "claude  Website concepts review", action = function()
			picked = 1
		end },
		{ label = "pi  fix the router tests", action = function()
			picked = 2
		end },
		{ label = "claude  Remove statusbar", action = function()
			picked = 3
		end },
	},
})
local list = vim.api.nvim_get_current_buf()
keys("/rtt")
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = vim.api.nvim_get_current_buf() })
local shown = vim.api.nvim_buf_get_lines(list, 0, -1, false)
-- best match first; "Website concepts review" has no r…t…t in order
assert(shown[1]:find("router tests") and not table.concat(shown):find("Website"), vim.inspect(shown))
keys("A<CR>") -- fed keys leave insert mode: back in, then Enter
vim.wait(100, function()
	return picked ~= nil
end)
assert(picked == 2, "picked the match: " .. tostring(picked))
assert(vim.api.nvim_get_current_win() == editor, "focus back after filtering")

print("menu: ok")

