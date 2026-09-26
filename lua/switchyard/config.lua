local M = {}

M.defaults = {
	projects_dirs = { "~/code" }, -- folders that hold your repos
	agents = { "pi", "claude" },
	follow = true,
	empty_worktree = "keep",
	terminal = "auto",
	live_reload = true, -- open files follow changes made by agents
	yard = {
		view = "worktrees", -- the view the yard opens in first: "worktrees" or "agents"
	},
	viewer = {
		width = 0.45, -- share of the editor's width for the viewer split
	},
	keys = {
		picker = {
			new_worktree = "alt-n",
			remove_worktree = "alt-d",
		},
		-- Inside the yard (buffer-local). More arrive with the yard's actions.
		yard = {
			activate = "<CR>", -- worktrees: switch · agents: go to (switch + link)
			alt_activate = "<S-CR>", -- worktrees: peek (keep link) · agents: link only
			toggle_view = "<Tab>",
			filter = "/",
			refresh = "<C-r>",
			close = "q",
			actions = ".", -- menu with the selected row's actions
			help = "?", -- every key of the current view
			-- Same key, same idea in both views
			new = "n", -- worktrees: new worktree · agents: new agent in a worktree
			remove = "D", -- worktrees: remove worktree · agents: stop agent
			fork = "f", -- worktrees: fork the linked agent here · agents: fork this one elsewhere
			-- worktrees view
			start_agent = "a",
			continue_agent = "c",
			copy_path = "y",
			-- agents view
			view = "v", -- in the split
			external = "g", -- in an external terminal
			rename = "r", -- its tmux session
		},
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	opts = opts or {}
	M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts)

	-- Lists are replaced, not merged
	if opts.agents then
		M.options.agents = opts.agents
	end
	if opts.projects_dirs then
		M.options.projects_dirs = opts.projects_dirs
	end

	-- Accept a single folder as a string, too
	if type(M.options.projects_dirs) == "string" then
		M.options.projects_dirs = { M.options.projects_dirs }
	end

	-- Full paths, once
	M.options.projects_dirs = vim.tbl_map(vim.fn.expand, M.options.projects_dirs)
end

return M
