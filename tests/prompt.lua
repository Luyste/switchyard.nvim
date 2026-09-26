-- The prompt builder. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/prompt.lua
require("switchyard").setup({})
local prompt = require("switchyard.prompt")
local sessions = require("switchyard.sessions")

local sent
local agent = {
	pid = 1,
	cwd = vim.fn.getcwd(),
	adapter = {
		name = "fake",
		send = function(_, message, callback)
			sent = message
			callback(true)
		end,
	},
}
sessions.linked = function()
	return agent
end

local editor = vim.api.nvim_get_current_win()
local function builder_open()
	return vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative ~= ""
end

prompt.open()
assert(builder_open(), "opens with focus")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "fix the parser", "and add a test" })

-- Focus elsewhere: the window goes, the draft stays
vim.api.nvim_set_current_win(editor)
vim.wait(100)
assert(#vim.api.nvim_list_wins() == 1, "gone on focus loss")
assert(prompt.draft_status() == "DRAFT", "draft kept and shown")

-- Back again: same text, cursor at the end
prompt.open()
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[2] == "and add a test", "draft back")
assert(vim.api.nvim_win_get_cursor(0)[1] == 2, "cursor at the end")

-- Send: the linked agent gets it, the draft is cleared
prompt.send()
assert(sent == "fix the parser\nand add a test", "sent the draft")
assert(prompt.draft_status() == "" and #vim.api.nvim_list_wins() == 1, "cleared and closed")

print("prompt: ok")
