local M = {}

M.defaults = {
	yard = {
		view = "worktrees", -- the view the yard opens in first: "worktrees" or "folders"
	},
	-- Optional plugins switchyard works with. Each one: true = when installed,
	-- false = never.
	integrations = {
		sidekick = true, -- after a switch, sidekick's agent window shows the new folder's agent
	},
	keys = {
		-- Inside the yard (buffer-local)
		yard = {
			activate = "<CR>", -- switch the editor to the row's folder
			enter = "l", -- folders: look inside (a repo: its worktrees)
			up = "h", -- worktrees: the folders around the repo · folders: one level up
			toggle_view = "<Tab>",
			filter = "/",
			refresh = "<C-r>",
			close = "q",
			actions = ".", -- menu with the selected row's actions
			help = "?", -- every key of the current view
			new = "n", -- worktrees: new worktree
			remove = "D", -- worktrees: remove worktree
			copy_path = "y",
		},
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
