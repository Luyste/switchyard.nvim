local M = {}

M.defaults = {
	-- Agents that run in tmux: preset names ("pi", "claude", "codex") or your
	-- own tables (see lua/switchyard/agents.lua). Only installed ones are used.
	agents = { "pi", "claude", "codex" },
	follow = true,
	terminal = "auto",
	-- Who makes and removes worktrees: "auto" (worktrunk's `wt` when installed,
	-- else git) | "wt" | "git". wt brings its path template and hooks.
	worktrees = "auto",
	live_reload = true, -- open files follow changes made by agents
	yard = {
		view = "worktrees", -- the view the yard opens in first: "worktrees" | "agents"
	},
	viewer = {
		width = 0.45, -- share of the editor's width for the viewer
		layout = "split", -- "split" (a window on the right) | "float" (floating on the right)
		bar = false, -- while the viewer is closed: the linked agent and working/idle, bottom right
	},
	keys = {
		-- Inside the yard (buffer-local). More arrive with the yard's actions.
		yard = {
			activate = "<CR>", -- worktrees: switch · agents: go to (switch + link)
			alt_activate = "<S-CR>", -- worktrees: peek (keep link) · agents: link only
			view_worktrees = "1", -- show a view
			view_agents = "2",
			toggle_view = "<Tab>", -- worktrees ⇄ agents
			filter = "/",
			refresh = "<C-r>",
			close = "q",
			actions = ".", -- menu with the selected row's actions
			help = "?", -- every key of the current view
			-- Same key, same idea in both views
			new = "n", -- worktrees: new worktree · agents: new agent in a worktree
			remove = "D", -- worktrees: remove worktree · agents: stop agent
			fork = "f", -- worktrees: fork the linked agent here · agents: fork this one elsewhere
			dispatch = "N", -- a task for a new agent in a new worktree
			-- worktrees view
			start_agent = "a",
			continue_agent = "c",
			copy_path = "y",
			-- agents view
			view = "v", -- in the split
			external = "g", -- in an external terminal
			rename = "r", -- its tmux session
			send = "s", -- the prompt builder aimed at this agent
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
end

return M
