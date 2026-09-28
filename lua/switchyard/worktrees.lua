-- Worktrees with plain git: list them, make one for a branch, remove one.
-- A worktree: { path, branch, current, main, symbols } (symbols: "*" when it
-- has uncommitted changes).
local util = require("switchyard.util")

local M = {}

local function git(cwd, args, callback)
	util.run(vim.list_extend({ "git" }, args), { cwd = cwd }, callback)
end

-- `git worktree list --porcelain` as a list of { path, branch?, bare?, locked? }
function M.parse(text)
	local list, current = {}, nil
	for line in (text .. "\n"):gmatch("([^\n]*)\n") do
		local key, value = line:match("^(%S+)%s?(.*)$")
		if key == "worktree" then
			current = { path = value }
			table.insert(list, current)
		elseif current and key == "branch" then
			current.branch = value:gsub("^refs/heads/", "")
		elseif current and (key == "bare" or key == "locked" or key == "detached") then
			current[key] = true
		end
	end
	return list
end

-- The worktrees of the repo at `cwd`, newest information each call.
-- callback(worktrees) or callback(nil, error_message)
function M.list(cwd, callback)
	git(cwd, { "rev-parse", "--show-toplevel" }, function(_, toplevel)
		git(cwd, { "worktree", "list", "--porcelain" }, function(ok, out, err)
			if not ok then
				return callback(nil, vim.trim(err))
			end
			local worktrees = {}
			for i, wt in ipairs(M.parse(out)) do
				-- A bare repo or a detached checkout has no branch to show
				if wt.branch and not wt.bare then
					table.insert(worktrees, {
						path = wt.path,
						branch = wt.branch,
						main = i == 1, -- git lists the main worktree first
						current = wt.path == vim.trim(toplevel),
						symbols = "",
					})
				end
			end
			-- Mark the ones with uncommitted changes (one git status each, side by side)
			local pending = #worktrees
			if pending == 0 then
				return callback(worktrees)
			end
			for _, wt in ipairs(worktrees) do
				git(wt.path, { "status", "--porcelain" }, function(_, status)
					wt.symbols = vim.trim(status) ~= "" and "*" or ""
					pending = pending - 1
					if pending == 0 then
						callback(worktrees)
					end
				end)
			end
		end)
	end)
end

-- The repo's default branch: origin's HEAD, else main or master. callback(name or nil)
local function default_branch(cwd, callback)
	git(cwd, { "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD" }, function(ok, out)
		if ok and vim.trim(out) ~= "" then
			return callback((vim.trim(out):gsub("^origin/", "")))
		end
		git(cwd, { "for-each-ref", "--format=%(refname:short)", "refs/heads/main", "refs/heads/master" }, function(_, found)
			callback(found:match("[^\n]+"))
		end)
	end)
end

-- A worktree for `branch`, next to the main one as "<repo>.<branch>" (the
-- layout worktrunk uses too). An existing branch (local, or only on a remote)
-- is checked out there; a new name becomes a branch off the default branch.
-- A branch that already has a worktree just gives its path.
-- callback(path) or callback(nil, error_message)
function M.create(cwd, branch, callback)
	M.list(cwd, function(worktrees, err)
		if not worktrees then
			return callback(nil, err)
		end
		local main
		for _, wt in ipairs(worktrees) do
			if wt.branch == branch then
				return callback(wt.path)
			end
			main = main or (wt.main and wt)
		end
		if not main then
			return callback(nil, "no main worktree found")
		end
		local path = vim.fs.dirname(main.path) .. "/" .. vim.fs.basename(main.path) .. "." .. branch:gsub("/", "-")

		local function add(args)
			git(cwd, args, function(ok, _, stderr)
				if not ok then
					return callback(nil, vim.trim(stderr))
				end
				callback(path)
			end)
		end
		local refs = { "for-each-ref", "--format=%(refname)", "refs/heads/" .. branch, "refs/remotes/*/" .. branch }
		git(cwd, refs, function(_, found)
			if vim.trim(found) ~= "" then
				-- git makes a local tracking branch for a remote-only one by itself
				return add({ "worktree", "add", path, branch })
			end
			default_branch(cwd, function(base)
				local args = { "worktree", "add", "-b", branch, path }
				if base then
					table.insert(args, base)
				end
				add(args)
			end)
		end)
	end)
end

-- Remove worktree `wt` ({ path, branch }), and its branch when that's merged.
-- git refuses a worktree with uncommitted changes. callback(ok, error_message)
function M.remove(cwd, wt, callback)
	git(cwd, { "worktree", "remove", wt.path }, function(ok, _, stderr)
		if not ok then
			return callback(false, vim.trim(stderr))
		end
		git(cwd, { "branch", "-d", wt.branch }, function()
			callback(true) -- an unmerged branch stays: nothing lost
		end)
	end)
end

return M
