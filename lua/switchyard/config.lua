local M = {}

M.defaults = {
	projects_dirs = { "~/code" }, -- folders that hold your repos
	agents = { "pi", "claude" },
	follow = true,
	empty_worktree = "keep",
	terminal = "auto",
	live_reload = true, -- open files follow changes made by agents
	viewer = {
		width = 0.45, -- share of the editor's width for the viewer split
	},
	keys = {
		picker = {
			new_worktree = "alt-n",
			remove_worktree = "alt-d",
		},
		yard = {
			activate = "<CR>",
			peek = "<S-CR>",
			toggle = "o",
			filter = "i",
			close = "q",
			refresh = "<C-r>",
			new_worktree = "%",
			remove = "D",
			new_agent = "n",
			continue_agent = "c",
			fork_agent = "f",
			copy_path = "y",
			view = "v",
			external = "g",
			send = "s",
			move = "m",
			spin_off = "F",
			rename = "r",
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
