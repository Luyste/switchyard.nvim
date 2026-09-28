-- Worktrees with plain git. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/worktrees.lua
local worktrees = require("switchyard.worktrees")

-- Parsing `git worktree list --porcelain`
local parsed = worktrees.parse(table.concat({
	"worktree /r/repo",
	"HEAD abc",
	"branch refs/heads/main",
	"",
	"worktree /r/repo.feat-x",
	"HEAD def",
	"branch refs/heads/feat/x",
	"locked",
	"",
	"worktree /r/detached",
	"HEAD 123",
	"detached",
	"",
}, "\n"))
assert(#parsed == 3, "three entries")
assert(parsed[1].path == "/r/repo" and parsed[1].branch == "main", "main")
assert(parsed[2].branch == "feat/x" and parsed[2].locked, "branch with a slash, locked")
assert(parsed[3].detached and not parsed[3].branch, "detached")

-- For real, in a temporary repo with a remote
local root = vim.fn.resolve(vim.fn.tempname())
local repo = root .. "/repo"
local function git(dir, ...)
	local res = vim.system(vim.list_extend({ "git", "-C", dir }, { ... }), { text = true }):wait()
	assert(res.code == 0, table.concat({ ... }, " ") .. ": " .. (res.stderr or ""))
	return vim.trim(res.stdout or "")
end
local function wait(fn)
	local result
	fn(function(...)
		result = { ... }
	end)
	assert(vim.wait(10000, function()
		return result ~= nil
	end, 20), "git answered")
	return unpack(result)
end
vim.fn.mkdir(root, "p")
git(root, "init", "-q", "--bare", "origin.git")
git(root, "clone", "-q", root .. "/origin.git", "repo")
git(repo, "checkout", "-q", "-b", "main")
git(repo, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
git(repo, "push", "-q", "origin", "main")
git(repo, "branch", "feat/existing")
git(repo, "checkout", "-q", "-b", "feat/remote-only")
git(repo, "push", "-q", "origin", "feat/remote-only")
git(repo, "checkout", "-q", "main")
git(repo, "branch", "-q", "-D", "feat/remote-only")

local list = wait(function(cb)
	worktrees.list(repo, cb)
end)
assert(#list == 1 and list[1].main and list[1].current and list[1].branch == "main", "one worktree: main, current")
assert(list[1].symbols == "", "clean")

local new = wait(function(cb)
	worktrees.create(repo, "feat/new", cb)
end)
assert(new == root .. "/repo.feat-new", "new branch, next to the repo: " .. tostring(new))
assert(git(new, "rev-parse", "--abbrev-ref", "HEAD") == "feat/new", "on the new branch")

local existing = wait(function(cb)
	worktrees.create(repo, "feat/existing", cb)
end)
assert(existing == root .. "/repo.feat-existing", "existing branch")

local remote = wait(function(cb)
	worktrees.create(repo, "feat/remote-only", cb)
end)
assert(remote and git(remote, "rev-parse", "--abbrev-ref", "@{u}") == "origin/feat/remote-only", "remote-only branch, tracking")

local again = wait(function(cb)
	worktrees.create(repo, "feat/new", cb)
end)
assert(again == new, "a branch that already has a worktree: its path")

-- Uncommitted changes show as "*"; the list knows which one is current
vim.fn.writefile({ "x" }, new .. "/file.txt")
list = wait(function(cb)
	worktrees.list(new, cb)
end)
local by_branch = {}
for _, wt in ipairs(list) do
	by_branch[wt.branch] = wt
end
assert(#list == 4, "four worktrees")
assert(by_branch["feat/new"].symbols == "*" and by_branch["feat/new"].current, "dirty and current")
assert(by_branch.main.main and not by_branch.main.current, "main is main")

-- Removing: git refuses uncommitted changes; a clean one goes, with its merged branch
local ok = wait(function(cb)
	worktrees.remove(repo, by_branch["feat/new"], cb)
end)
assert(ok == false, "refuses a worktree with changes")
ok = wait(function(cb)
	worktrees.remove(repo, by_branch["feat/existing"], cb)
end)
assert(ok == true and vim.fn.isdirectory(existing) == 0, "removed")
assert(git(repo, "branch", "--list", "feat/existing") == "", "merged branch deleted")

print("worktrees: ok")
