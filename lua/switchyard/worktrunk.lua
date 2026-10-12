-- Worktrees through worktrunk (`wt`), used instead of plain git when it's
-- installed (config `worktrees`). wt adds its own path template, hooks
-- (post-create: copy .env, install dependencies, …) and status symbols.
-- Same shapes as worktrees.lua: { path, branch, current, main, symbols }.
local util = require("switchyard.util")

local M = {}

local function decode(text)
	local ok, data = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
	return ok and type(data) == "table" and data or nil
end

-- The worktrees of the repo at `cwd`. callback(worktrees) or callback(nil, error_message)
function M.list(cwd, callback)
	util.run({ "wt", "list", "--format=json" }, { cwd = cwd }, function(ok, stdout, stderr)
		if not ok then
			return callback(nil, vim.trim(stderr))
		end
		local data = decode(stdout)
		if not data then
			return callback(nil, "couldn't read wt output")
		end
		local worktrees = {}
		for _, item in ipairs(data.items or {}) do
			-- Skip branches without a worktree, and detached worktrees without a branch
			if type(item.worktree) == "table" and type(item.branch) == "string" then
				local display = type(item.display) == "table" and item.display or {}
				table.insert(worktrees, {
					branch = item.branch,
					path = item.worktree.path,
					current = item.worktree.current == true,
					main = item.worktree.main == true,
					symbols = type(display.symbols) == "string" and display.symbols or "",
				})
			end
		end
		callback(worktrees)
	end)
end

-- A worktree for `branch`: an existing one (local or remote) is checked out,
-- a new name becomes a branch off the default branch, one that already has a
-- worktree gives its path. callback(path) or callback(nil, error_message)
function M.create(cwd, branch, callback)
	local function switch(create)
		local cmd = { "wt", "switch", branch, "--no-cd", "--yes", "--format", "json" }
		if create then
			table.insert(cmd, 3, "--create")
		end
		util.run(cmd, { cwd = cwd }, function(ok, stdout, stderr)
			if not ok then
				if not create and stderr:find("No branch named", 1, true) then
					return switch(true)
				end
				return callback(nil, vim.trim(stderr))
			end
			-- The JSON result is the last line starting with "{" (hooks may print too)
			local result
			for line in stdout:gmatch("[^\n]+") do
				result = line:match("^{") and decode(line) or result
			end
			if not (result and result.path) then
				return callback(nil, "couldn't read wt output")
			end
			callback(result.path)
		end)
	end
	switch(false)
end

-- Remove worktree `wt` ({ path, branch }), and its branch when that's merged.
-- wt refuses a worktree with uncommitted changes. callback(ok, error_message)
function M.remove(cwd, wt, callback)
	-- --foreground: done when the callback runs (wt removes in the background otherwise)
	util.run({ "wt", "remove", wt.branch, "--yes", "--foreground" }, { cwd = cwd }, function(ok, _, stderr)
		callback(ok, not ok and vim.trim(stderr) or nil)
	end)
end

return M
