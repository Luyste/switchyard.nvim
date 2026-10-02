-- Actions on worktrees, used by the yard.
-- Each takes an optional on_done, called after the action succeeded.
local worktrees = require("switchyard.worktrees")

local M = {}

-- Ask before something destructive. "No" comes first, so Enter is safe.
function M.confirm(title, yes_label, on_yes)
	require("switchyard.menu").open({
		title = title,
		items = {
			{ label = "No", action = function() end },
			{ label = yes_label, action = on_yes, danger = true },
		},
	})
end

-- Ask for a branch name and create a worktree for it (the editor stays put).
-- on_done(path, branch)
function M.create_worktree(cwd, on_done)
	require("switchyard.menu").input({ title = "new worktree: branch name" }, function(branch)
		if not branch or branch == "" then
			return
		end
		require("switchyard.util").progress("switchyard: creating " .. branch .. " …")
		worktrees.create(cwd, branch, function(path, err)
			if not path then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			vim.notify("switchyard: created " .. branch)
			if on_done then
				on_done(path, branch)
			end
		end)
	end)
end

-- Remove worktree `wt` after confirming. Never the current or the main one.
function M.remove_worktree(cwd, wt, on_done)
	if wt.current then
		return vim.notify("switchyard: you're in this worktree. Switch away first.", vim.log.levels.WARN)
	end
	if wt.main then
		return vim.notify("switchyard: the main worktree can't be removed.", vim.log.levels.WARN)
	end
	M.confirm("remove worktree " .. wt.branch .. "?", "Remove " .. wt.branch, function()
		require("switchyard.util").progress("switchyard: removing " .. wt.branch .. " …")
		worktrees.remove(cwd, wt, function(ok, err)
			if not ok then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			vim.notify("switchyard: removed " .. wt.branch)
			if on_done then
				on_done()
			end
		end)
	end)
end

return M
