-- Worktrees for new and existing branches, against real git and worktrunk.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/worktrunk.lua
if vim.fn.executable("wt") == 0 then
	print("worktrunk: skipped (wt not installed)")
	return
end
local worktrunk = require("switchyard.worktrunk")

local root = vim.fn.resolve(vim.fn.tempname())
local repo = root .. "/repo"
local function git(...)
	local res = vim.system(vim.list_extend({ "git", "-C", repo }, { ... }), { text = true }):wait()
	assert(res.code == 0, table.concat({ ... }, " ") .. ": " .. (res.stderr or ""))
end
vim.fn.mkdir(repo, "p")
git("init", "-q", "-b", "main")
git("-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
git("branch", "feat/existing")

local function create(branch)
	local result
	worktrunk.create(repo, branch, function(path, err)
		result = { path = path, err = err }
	end)
	assert(vim.wait(20000, function()
		return result ~= nil
	end, 50), "wt answered")
	return result
end

local existing = create("feat/existing")
assert(existing.path and vim.fn.isdirectory(existing.path) == 1, "worktree for an existing branch: " .. tostring(existing.err))

local new = create("feat/new")
assert(new.path and vim.fn.isdirectory(new.path) == 1, "worktree for a new branch: " .. tostring(new.err))

print("worktrunk: ok")
