-- The viewer window. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/view.lua
require("switchyard").setup({})
vim.o.number, vim.o.scrolloff, vim.o.statuscolumn = true, 19, "%l " -- like a real config
local view = require("switchyard.view")
local sessions = require("switchyard.sessions")

-- No tmux: the "agent" is a sleeping process in the terminal
require("switchyard.tmux").attach_cmd = function()
	return { "sleep", "30" }
end
local session = { pid = 1, cwd = vim.fn.getcwd(), agent = { name = "fake", cmd = { "fake" } }, tmux = "fake", pane = "%1", started = 0 }

view.show(session)
assert(view.is_open(), "shows the viewer")
assert(#vim.api.nvim_list_wins() == 2, "next to the editor")
-- Terminal window options, also when the editor's are different (set globally)
local win = vim.api.nvim_get_current_win()
assert(not vim.wo[win].number and vim.wo[win].scrolloff == 0 and vim.wo[win].statuscolumn == "", "terminal options")

-- Hiding next to the editor: the window goes
view.hide()
assert(not view.is_open() and #vim.api.nvim_list_wins() == 1, "hides the window")

-- The viewer as the last window (the editor was closed): no E444, an empty window
view.show(session)
vim.cmd.stopinsert()
vim.cmd("wincmd p")
vim.cmd("close")
assert(#vim.api.nvim_list_wins() == 1, "only the viewer is left")
view.hide()
assert(not view.is_open(), "hidden")
assert(vim.bo.buftype == "", "the last window now holds an empty editor buffer")

-- layout = "float": a float on the right, below the yard and menus; hiding closes it
require("switchyard.config").options.viewer.layout = "float"
view.hide()
vim.cmd("only")
-- Without a terminal to reuse, the float starts with a placeholder buffer
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.bo[buf].buftype == "terminal" then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end
view.show(session)
assert(view.is_open(), "shows the floating viewer")
local float = vim.api.nvim_win_get_config(vim.api.nvim_get_current_win())
assert(float.relative == "editor" and float.zindex == 40, "a float under the yard and menus")
assert(vim.bo.buftype == "terminal", "the terminal is in the float")
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	assert(vim.bo[buf].buftype ~= "nofile", "no placeholder buffer left over")
end
view.hide()
assert(not view.is_open() and #vim.api.nvim_list_wins() == 1, "hiding closes the float")
view.show(session)
assert(vim.bo.buftype == "terminal", "shown again, same terminal")

print("view: ok")
