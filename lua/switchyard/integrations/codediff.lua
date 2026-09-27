-- codediff.nvim (https://github.com/esmuellert/codediff.nvim), optional.
local M = {}

function M.available()
	return (pcall(require, "codediff"))
end

-- A worktree's changes against `worktree.base`: its working tree, so the
-- agent's uncommitted work shows too. Opens in codediff's own view.
function M.open(worktree)
	vim.cmd({ cmd = "CodeDiff", args = { "--repo", worktree.path, worktree.base } })
end

return M
