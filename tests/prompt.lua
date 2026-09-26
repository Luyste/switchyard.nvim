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

---------------------------------------------------------------------------
-- Contexts
---------------------------------------------------------------------------

local file = vim.fn.getcwd() .. "/ctx_test.lua"
vim.cmd.edit(file)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local a = 1", "local b = 2", "local c = 3", "return a + b + c" })
local source = vim.api.nvim_get_current_buf()
vim.bo[source].filetype = "lua" -- -u NONE: no filetype detection

-- Visual selection of lines 2-3, through the public entry point
-- (like Cmd+L: a mapping that runs while visual mode is still on)
vim.keymap.set("x", "<F9>", function()
	require("switchyard").prompt()
end)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("Vj<F9>", true, false, true), "x", false)
assert(vim.api.nvim_win_get_config(0).relative ~= "", "builder opened")
assert(#vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_get_namespaces().switchyard_prompt, 0, -1, {}) > 0, "range highlighted")
local header = vim.tbl_filter(function(w)
	return vim.api.nvim_win_get_config(w).focusable == false
end, vim.api.nvim_list_wins())
assert(#header == 1, "context list shown")
assert(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(header[1]), 0, 1, false)[1] == " ctx_test.lua:2-3 (2 lines)", "context described")

-- The line with a diagnostic
vim.api.nvim_set_current_win(editor)
vim.wait(50)
assert(prompt.draft_status() == "DRAFT 1", "draft with one context")
vim.diagnostic.set(vim.api.nvim_create_namespace("t"), source, { { lnum = 3, col = 0, message = "unused", severity = 2 } })
vim.api.nvim_win_set_cursor(0, { 4, 0 })
require("switchyard").prompt_line()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "why?" })

prompt.send()
assert(sent == table.concat({
	"why?",
	"",
	"From ctx_test.lua:2-3:",
	"```lua",
	"local b = 2",
	"local c = 3",
	"```",
	"",
	"From ctx_test.lua:4:",
	"```lua",
	"return a + b + c",
	"```",
	"- WARN: unused",
}, "\n"), "message with contexts:\n" .. tostring(sent))
assert(#vim.api.nvim_buf_get_extmarks(source, vim.api.nvim_get_namespaces().switchyard_prompt, 0, -1, {}) == 0, "highlights gone")
assert(prompt.draft_status() == "", "contexts cleared after sending")

print("contexts: ok")

-- Ctrl-F: the file the builder was opened from, once, as a path
vim.api.nvim_set_current_win(editor)
vim.api.nvim_set_current_buf(source)
prompt.open()
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-f><C-f>", true, false, true), "x", false)
assert(prompt.draft_status() == "" , "builder open: no marker")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "look" })
prompt.send()
assert(sent == "look\n\nFile: ctx_test.lua", "whole file as a path, once:\n" .. tostring(sent))

print("file: ok")
