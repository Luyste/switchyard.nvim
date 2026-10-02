-- Menus and the input, in fzf-lua (fzf really runs in a terminal here).
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/menu.lua
local fzf = vim.fn.glob(vim.fn.stdpath("data") .. "/site/pack/*/*/fzf-lua", false, true)[1]
if not fzf then
	return print("menu: skipped (fzf-lua not installed)")
end
vim.opt.rtp:append(fzf)
vim.o.columns, vim.o.lines = 120, 40
local menu = require("switchyard.menu")
local editor = vim.api.nvim_get_current_win()

-- Type into fzf (its terminal), once it's there
local function type(text)
	assert(vim.wait(5000, function()
		return vim.bo.filetype == "fzf" and vim.bo.channel > 0
	end, 20), "fzf opened")
	vim.wait(1000) -- fzf drops keys typed before it's ready
	local channel = vim.bo.channel
	local typed, last = text:match("^(.-)([\r\27]?)$")
	vim.api.nvim_chan_send(channel, typed)
	vim.wait(500) -- the filter runs before Enter accepts
	vim.api.nvim_chan_send(channel, last)
end
local function wait(fn)
	assert(vim.wait(5000, fn, 20), "answered")
	vim.wait(100)
end

-- A choice: filter, Enter runs that item's action, focus goes back
local chosen
menu.open({
	title = "which agent",
	items = {
		{ label = "pi", action = function()
			chosen = "pi"
		end },
		{ label = "claude", key = "linked", action = function()
			chosen = "claude"
		end },
	},
})
type("cla\r")
wait(function()
	return chosen ~= nil
end)
assert(chosen == "claude", tostring(chosen))
assert(vim.api.nvim_get_current_win() == editor, "focus back")

-- Esc: no action, on_cancel instead
local cancelled = false
menu.open({ title = "confirm", items = { { label = "Yes", action = function()
	chosen = "yes"
end } }, on_cancel = function()
	cancelled = true
end })
type("\27")
wait(function()
	return cancelled
end)
assert(chosen == "claude", "no action on cancel")

-- Input: the default can be edited, Enter confirms
local answer
menu.input({ title = "branch", default = "feature" }, function(text)
	answer = text
end)
type("/x\r")
wait(function()
	return answer ~= nil
end)
assert(answer == "feature/x", "confirmed text: " .. tostring(answer))

-- Esc cancels: nil
answer = "unset"
menu.input({ title = "branch" }, function(text)
	answer = text
end)
type("abc\27")
wait(function()
	return answer ~= "unset"
end)
assert(answer == nil, "cancelled")
assert(vim.api.nvim_get_current_win() == editor, "focus back after cancel")

print("menu: ok")
