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

-- viewer.bar: the linked agent while the viewer is closed, gone while it's open
require("switchyard.config").options.viewer.bar = true
sessions.linked = function()
	return vim.tbl_extend("force", session, { activity = os.time() })
end
local function bar_win()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, 1, false)[1] or ""
		if line:find("working", 1, true) or line:find("idle", 1, true) then
			return w, line
		end
	end
end
view.hide()
local w, line = bar_win()
assert(w and line == " ● fake  working ", "the bar shows the linked agent, working: " .. tostring(line))
assert(vim.api.nvim_win_get_config(w).focusable == false, "not in <C-w>w")
view.show(session)
assert(not bar_win(), "no bar while the viewer is open")

print("view: ok")
