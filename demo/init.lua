-- A minimal Neovim config for recording the demos: nvim -u demo/init.lua
-- Terminal-friendly keys (<Space> as leader, Ctrl-] to leave the agent's
-- terminal), no other plugins.
local repo = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(repo)

vim.g.mapleader = " "
vim.o.termguicolors = true
vim.o.number = true
vim.o.signcolumn = "yes"
vim.o.laststatus = 3
vim.o.showmode = false
vim.o.swapfile = false
vim.o.shortmess = vim.o.shortmess .. "I"

require("switchyard").setup({})

-- Statusline: file on the left, switchyard on the right
function _G.demo_statusline()
	local sy = require("switchyard")
	local right = {}
	if sy.following_edits() then
		table.insert(right, "FOLLOW")
	end
	if sy.draft_status() ~= "" then
		table.insert(right, sy.draft_status())
	end
	if sy.status() ~= "" then
		table.insert(right, "→ " .. sy.status())
	end
	local branch = vim.fn.fnamemodify(vim.fn.getcwd(), ":t")
	return " " .. branch .. "  %f %m%=" .. table.concat(right, "   ") .. " "
end
vim.o.statusline = "%!v:lua.demo_statusline()"

local function sy(name)
	return function()
		require("switchyard")[name]()
	end
end
local map = vim.keymap.set
map("n", "<leader>y", sy("open_yard"), { desc = "the yard" })
map("n", "<leader>v", sy("toggle_view"), { desc = "show/hide the agent" })
map("n", "<leader>j", sy("focus_view"), { desc = "jump to the agent" })
map("t", "<C-]>", sy("focus_view"), { desc = "jump back to the code" })
map({ "n", "x" }, "<leader>p", sy("prompt"), { desc = "prompt (+ selection)" })
map({ "n", "x" }, "<leader>d", sy("dispatch"), { desc = "dispatch a task" })
map("n", "<leader>f", sy("follow_edits"), { desc = "follow edits" })
