-- The viewer window, with switchyard's own split and (when sidekick.nvim is
-- installed in the usual pack folder) sidekick's terminal.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/view.lua
local sidekick = vim.fn.glob(vim.fn.stdpath("data") .. "/site/pack/*/*/sidekick.nvim", false, true)[1]
local view = require("switchyard.view")

-- No tmux: the "agent" is a sleeping process in the terminal
require("switchyard.tmux").attach_cmd = function()
	return { "sleep", "30" }
end
local session = { pid = 1, cwd = vim.fn.getcwd(), agent = { name = "fake", cmd = { "fake" } }, tmux = "fake", pane = "%1", started = 0 }

local function check(backend)
	require("switchyard").setup({ viewer = { backend = backend } })
	assert(view.backend() == backend, "backend " .. backend)

	view.show(session)
	assert(view.is_open(), backend .. ": shows the viewer")
	assert(#vim.api.nvim_list_wins() == 2, backend .. ": next to the editor")

	-- Hiding next to the editor: the window goes
	view.hide()
	assert(not view.is_open() and #vim.api.nvim_list_wins() == 1, backend .. ": hides the window")

	-- The viewer as the last window (the editor was closed): no E444, an empty window
	view.show(session)
	vim.cmd.stopinsert()
	vim.cmd("wincmd p")
	vim.cmd("close")
	assert(#vim.api.nvim_list_wins() == 1, backend .. ": only the viewer is left")
	view.hide()
	assert(not view.is_open(), backend .. ": hidden")
	assert(vim.bo.buftype == "", backend .. ": the last window now holds an editor buffer")
end

check("builtin")
if sidekick then
	vim.opt.rtp:append(sidekick)
	require("sidekick").setup({ nes = { enabled = false } })
	check("sidekick")
	-- The terminal sidekick keeps alive comes back, with the agent tabs on top
	view.show(session)
	assert(vim.wo[vim.api.nvim_get_current_win()].winbar:find("switchyard"), "our winbar")
	assert(vim.bo.filetype == "sidekick_terminal", "sidekick's terminal")
	print("view: ok (builtin + sidekick)")
else
	print("view: ok (builtin; sidekick.nvim not installed)")
end
