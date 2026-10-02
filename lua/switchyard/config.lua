local M = {}

M.defaults = {
	-- Agents that run in tmux: preset names ("pi", "claude", "codex") or your
	-- own tables (see lua/switchyard/agents.lua). Only installed ones are used.
	agents = { "pi", "claude", "codex" },
	follow = true,
	terminal = "auto",
	live_reload = true, -- open files follow changes made by agents
	yard = {
		view = "worktrees", -- the view the yard opens in first: "worktrees" | "agents" | "projects"
	},
	-- The projects view: git repos under `roots` (found with fd, skipping
	-- `exclude`), plus `pinned` folders (git or not) and the ones you went to
	projects = {
		roots = { "~" },
		exclude = { "Library", "node_modules", ".cache", ".Trash", ".local/share/nvim", ".oh-my-zsh", ".claude/plugins" },
		pinned = {}, -- e.g. { "~/.config/nvim" }
	},
	viewer = {
		width = 0.45, -- share of the editor's width for the viewer split
	},
	keys = {
		-- Inside the yard (buffer-local). More arrive with the yard's actions.
		yard = {
			activate = "<CR>", -- worktrees, projects: switch · agents: go to (switch + link)
			alt_activate = "<S-CR>", -- worktrees, projects: peek (keep link) · agents: link only
			view_worktrees = "1", -- show a view
			view_agents = "2",
			view_projects = "3",
			toggle_view = "<Tab>", -- agents view: this repo's agents ⇄ all agents in tmux
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
	for _, key in ipairs({ "roots", "exclude", "pinned" }) do
		if opts.projects and opts.projects[key] then
			M.options.projects[key] = opts.projects[key]
		end
	end
end

return M
