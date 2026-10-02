-- The yard's fzf-lua pickers: their lines and keys (fzf itself isn't run).
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/picker.lua
local fzf = vim.fn.glob(vim.fn.stdpath("data") .. "/site/pack/*/*/fzf-lua", false, true)[1]
if not fzf then
	return print("picker: skipped (fzf-lua not installed)")
end
vim.opt.rtp:append(fzf)
vim.opt.rtp:prepend(vim.fn.getcwd()) -- the test cds away: "." would point elsewhere
require("switchyard").setup({})
local picker = require("switchyard.picker")
local sessions = require("switchyard.sessions")

-- A repo with a second worktree next to it
local root = vim.fn.resolve(vim.fn.tempname())
local function git(dir, ...)
	local res = vim.system(vim.list_extend({ "git", "-C", dir }, { ... }), { text = true }):wait()
	assert(res.code == 0, table.concat({ ... }, " ") .. ": " .. (res.stderr or ""))
end
vim.fn.mkdir(root .. "/repo", "p")
git(root .. "/repo", "init", "-q", "-b", "main")
git(root .. "/repo", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
git(root .. "/repo", "worktree", "add", "-q", "-b", "feat", root .. "/repo.feat")
vim.cmd.cd(root .. "/repo.feat")

-- Two agents: one linked in feat, one in main
local agent = { name = "pi", cmd = { "pi" } }
local linked = { pid = 2, cwd = root .. "/repo.feat", agent = agent, tmux = "pi-feat", pane = "%2", started = 0 }
local other = { pid = 1, cwd = root .. "/repo", agent = agent, tmux = "pi-main", pane = "%1", started = 0 }
sessions.all = function()
	return { other, linked }
end
sessions.linked_pid = function()
	return 2
end

local function lines(view)
	local result
	picker.lines(view, function(l, start)
		result = { lines = l, start = start }
	end)
	assert(vim.wait(5000, function()
		return result ~= nil
	end, 20), "lines for " .. view)
	-- What fzf shows: the part before the tab, without colors
	result.shown = vim.tbl_map(function(l)
		return (l:match("^(.-)\t"):gsub("\27%[[%d;]*m", ""))
	end, result.lines)
	return result
end

local wt = lines("worktrees")
assert(#wt.lines == 2, vim.inspect(wt.shown))
assert(wt.shown[1]:find("main") and wt.shown[1]:find("● 1"), wt.shown[1])
assert(wt.shown[2]:find("@ feat") and wt.shown[2]:find("● pi%-feat"), wt.shown[2])
assert(wt.start == 2, "starts on the current worktree")

local ag = lines("agents")
assert(#ag.lines == 2 and ag.shown[1]:find("pi%-feat") and ag.shown[1]:find("feat$"), vim.inspect(ag.shown))
assert(ag.start == 1, "starts on the linked agent")

-- Projects: the current one first, pinned folders, the agents' projects, then
-- what fd finds (faked here)
local projects = require("switchyard.projects")
projects.find = function(on_found, on_done)
	on_found(root .. "/other")
	on_done()
end
projects.recent = function()
	return {}
end
projects.cached = function()
	return {}
end
vim.fn.mkdir(root .. "/other", "p")
vim.fn.mkdir(root .. "/notes", "p")
require("switchyard.config").options.projects.pinned = { root .. "/notes" }
local found, done = {}, false
picker.project_lines(function(l)
	table.insert(found, (l:match("^(.-)\t"):gsub("\27%[[%d;]*m", "")))
end, function()
	done = true
end)
assert(done and #found == 3, vim.inspect(found))
assert(found[1]:find("@ repo") and found[1]:find("● 2"), "the current project (a worktree's repo) first, with its agents: " .. found[1])
assert(found[2]:find("notes") and found[3]:find("other"), vim.inspect(found))

-- Outside a git repo: the folder itself is the one "worktree"
vim.cmd.cd(root .. "/notes")
local plain = lines("worktrees")
assert(#plain.lines == 1 and plain.shown[1]:find("@ notes"), vim.inspect(plain.shown))

-- Every action has a key, and keys don't collide within a kind
local keys = require("switchyard.config").options.keys.yard
for view, list in pairs(picker.actions) do
	local seen = { [keys.refresh] = true }
	for _, action in ipairs(list) do
		local key = keys[action.key]
		assert(key, view .. ": no key for " .. action.key)
		assert(not seen[key], view .. ": " .. key .. " used twice")
		seen[key] = true
	end
end

print("picker: ok")
