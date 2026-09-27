local util = require("switchyard.util")

local M = {}

-- One `wt list` item, turned into switchyard's own shape
local function to_worktree(item)
	local display = type(item.display) == "table" and item.display or {}
	return {
		branch = item.branch,
		path = item.worktree.path,
		current = item.worktree.current == true,
		main = item.worktree.main == true,
		symbols = type(display.symbols) == "string" and display.symbols or "",
	}
end

-- List the worktrees of the repo at `cwd`.
-- callback(worktrees) on success, callback(nil, error_message) on failure.
function M.list(cwd, callback)
	util.run({ "wt", "list", "--format=json" }, { cwd = cwd }, function(ok, stdout, stderr)
		if not ok then
			return callback(nil, vim.trim(stderr))
		end

		local decoded, data = pcall(vim.json.decode, stdout, { luanil = { object = true, array = true } })
		if not decoded or type(data) ~= "table" then
			return callback(nil, "couldn't read wt output")
		end

		-- The list, plus the repo's default branch as a field (for diffs)
		local repo = type(data.repo) == "table" and data.repo or {}
		local worktrees = { default_branch = type(repo.default_branch) == "string" and repo.default_branch or nil }
		for _, item in ipairs(data.items or {}) do
			-- Skip branches without a worktree, and detached worktrees without a branch
			if type(item.worktree) == "table" and type(item.branch) == "string" then
				table.insert(worktrees, to_worktree(item))
			end
		end
		callback(worktrees)
	end)
end

-- Run `wt switch …` and find the worktree it made: callback(path) or
-- callback(nil, error_message)
local function switch(cmd, cwd, branch, callback)
	util.run(cmd, { cwd = cwd }, function(ok, _, stderr)
		if not ok then
			return callback(nil, vim.trim(stderr))
		end
		-- wt doesn't print the new path in a stable format, so look it up
		M.list(cwd, function(worktrees, err)
			if not worktrees then
				return callback(nil, err)
			end
			for _, wt in ipairs(worktrees) do
				if wt.branch == branch then
					return callback(wt.path)
				end
			end
			callback(nil, "created " .. branch .. ", but couldn't find its worktree")
		end)
	end)
end

-- A worktree for `branch` with `wt switch`: an existing branch (local, or only
-- on a remote) gets a worktree; a new name is created first (`--create`).
-- callback(path) on success, callback(nil, error_message) on failure.
function M.create(cwd, branch, callback)
	local refs = { "git", "for-each-ref", "--format=%(refname)", "refs/heads/" .. branch, "refs/remotes/*/" .. branch }
	util.run(refs, { cwd = cwd }, function(_, found)
		local cmd = { "wt", "switch", branch, "--no-cd", "--yes" }
		if vim.trim(found) == "" then
			table.insert(cmd, 3, "--create")
		end
		switch(cmd, cwd, branch, callback)
	end)
end

-- Remove a worktree (and its branch, if merged) with `wt remove`.
-- callback(true) on success, callback(false, error_message) on failure.
function M.remove(cwd, branch, callback)
	util.run({ "wt", "remove", branch, "--yes" }, { cwd = cwd }, function(ok, _, stderr)
		callback(ok, not ok and vim.trim(stderr) or nil)
	end)
end

return M
