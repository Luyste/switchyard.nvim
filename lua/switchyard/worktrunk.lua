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

		local worktrees = {}
		for _, item in ipairs(data.items or {}) do
			-- Skip branches without a worktree, and detached worktrees without a branch
			if type(item.worktree) == "table" and type(item.branch) == "string" then
				table.insert(worktrees, to_worktree(item))
			end
		end
		callback(worktrees)
	end)
end

-- Create a branch and worktree with `wt switch --create`.
-- callback(path) on success, callback(nil, error_message) on failure.
function M.create(cwd, branch, callback)
	local cmd = { "wt", "switch", "--create", branch, "--no-cd", "--yes" }
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

-- Remove a worktree (and its branch, if merged) with `wt remove`.
-- callback(true) on success, callback(false, error_message) on failure.
function M.remove(cwd, branch, callback)
	util.run({ "wt", "remove", branch, "--yes" }, { cwd = cwd }, function(ok, _, stderr)
		callback(ok, not ok and vim.trim(stderr) or nil)
	end)
end

return M
