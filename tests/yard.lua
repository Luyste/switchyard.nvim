-- Opening and closing the yard. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/yard.lua
require("switchyard").setup({})
local yard = require("switchyard.yard")

local function floats()
	return #vim.tbl_filter(function(w)
		return vim.api.nvim_win_get_config(w).relative ~= ""
	end, vim.api.nvim_list_wins())
end

local editor = vim.api.nvim_get_current_win()
yard.open()
assert(yard.is_open() and floats() == 1, "opens one window")
yard.close()
assert(not yard.is_open() and floats() == 0, "closes its window")
assert(vim.api.nvim_get_current_win() == editor, "back in the window it was opened from")

yard.open()
yard.open() -- again while open: focuses it, no second window
assert(floats() == 1, "no second yard")
yard.close()

-- Worktrees and folders, in a temporary repo with a worktree next to it
local root = vim.fn.resolve(vim.fn.tempname())
local function git(dir, ...)
	local res = vim.system(vim.list_extend({ "git", "-C", dir }, { ... }), { text = true }):wait()
	assert(res.code == 0, table.concat({ ... }, " ") .. ": " .. (res.stderr or ""))
end
for _, dir in ipairs({ "repo", "notes/deep", ".hidden" }) do
	vim.fn.mkdir(root .. "/" .. dir, "p")
end
git(root .. "/repo", "init", "-q", "-b", "main")
git(root .. "/repo", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
git(root .. "/repo", "worktree", "add", "-q", "-b", "feat", root .. "/repo.feat")
vim.cmd.cd(root .. "/repo")

local function lines()
	return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), 0, -1, false), "|")
end
local function shows(pattern)
	assert(vim.wait(5000, function()
		return lines():find(pattern) ~= nil
	end, 20), "expected " .. pattern .. " in: " .. lines())
end
local function press(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end

yard.open()
shows("@ main")
shows("feat")
press("h") -- the folders around the repo: the worktree folder and dot folders left out
shows("notes/")
assert(lines():find("@ repo") and not lines():find("repo%.feat") and not lines():find("hidden"), lines())
press("ggl") -- inside notes, a plain folder
shows("deep/")
press("hh") -- up twice: the root's parent, the root itself selected
press("l")
shows("notes/")
press("Gl") -- inside the repo: its worktrees
shows("@ main")
yard.close()

print("yard: ok")
