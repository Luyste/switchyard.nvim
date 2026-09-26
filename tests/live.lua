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

---------------------------------------------------------------------------
-- Follow edits
---------------------------------------------------------------------------

local root = vim.fn.resolve(vim.fn.tempname()) -- macOS temp dirs are symlinks
vim.fn.mkdir(root, "p")
local function git(...)
	vim.system(vim.list_extend({ "git", "-C", root }, { ... })):wait()
end
local lines = {}
for i = 1, 10 do
	lines[i] = "line " .. i
end
vim.fn.writefile(lines, root .. "/tracked.txt")
vim.fn.writefile({ "ignored.txt" }, root .. "/.gitignore")
git("init", "-q")
git("add", ".")
git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-qm", "init")
vim.cmd.cd(root)
vim.cmd.enew()
local editor = vim.api.nvim_get_current_win()

local function shown()
	return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(editor)), ":t")
end
local function wait_shown(name)
	return vim.wait(3000, function()
		return shown() == name
	end, 20)
end

live.follow_edits(true)
assert(live.following_edits(), "following")
vim.wait(300) -- FSEvents needs a moment before it reports

-- An agent edits line 7 of a file that isn't open: compared with git's version
lines[7] = "changed"
vim.fn.writefile(lines, root .. "/tracked.txt")
assert(wait_shown("tracked.txt"), "opens the changed file")
assert(vim.api.nvim_win_get_cursor(editor)[1] == 7, "cursor on the changed line (git)")

-- Now it's open: the next edit (line 3) is found through live reload's snapshot
lines[3] = "changed too"
vim.fn.writefile(lines, root .. "/tracked.txt")
assert(vim.wait(3000, function()
	return vim.api.nvim_win_get_cursor(editor)[1] == 3
end, 20), "cursor on the changed line (snapshot)")

-- Ignored files never open
vim.fn.writefile({ "x" }, root .. "/ignored.txt")
vim.wait(600)
assert(shown() == "tracked.txt", "ignores gitignored files")

-- A new file opens at the top
vim.fn.writefile({ "a", "b" }, root .. "/new.txt")
assert(wait_shown("new.txt"), "opens a new file")

-- Unsaved changes in the editor window: never replaced
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "mine" })
lines[9] = "again"
vim.fn.writefile(lines, root .. "/tracked.txt")
vim.wait(600)
assert(shown() == "new.txt", "keeps a buffer with unsaved changes")
vim.cmd("silent! write")

live.follow_edits(false)
assert(not live.following_edits(), "stopped")

print("follow: ok")
