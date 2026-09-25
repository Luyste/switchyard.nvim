-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/live.lua
local live = require("switchyard.live")
live.setup()

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local path = dir .. "/a.txt"
vim.fn.writefile({ "one" }, path)
vim.cmd.edit(path)
local buf = vim.api.nvim_get_current_buf()
assert(live.watched_count() == 1, "folder watched")

local function wait_for(line)
	return vim.wait(2000, function()
		return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == line
	end, 20)
end

-- Plain write
vim.fn.writefile({ "two" }, path)
assert(wait_for("two"), "reloads after a write")

-- Write to a temp file and rename it over the original (atomic save)
vim.fn.writefile({ "three" }, path .. ".tmp")
vim.uv.fs_rename(path .. ".tmp", path)
assert(wait_for("three"), "reloads after a rename")

-- Unsaved changes are never touched
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "mine" })
vim.fn.writefile({ "four" }, path)
vim.wait(500)
assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "mine", "keeps unsaved changes")

-- Deleting the buffer stops the watcher
vim.cmd("bwipeout!")
assert(live.watched_count() == 0, "watcher stopped")

print("live: ok")
