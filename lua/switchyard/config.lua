local M = {}

M.defaults = {
	-- Agents that run in tmux: preset names ("pi", "claude", "codex") or your
	-- own tables (see lua/switchyard/agents.lua). Only installed ones are used.
	agents = { "pi", "claude", "codex" },
	follow = true,
	terminal = "auto",
	live_reload = true, -- open files follow changes made by agents
	yard = {
		view = "worktrees", -- the view without a prefix: "worktrees" | "agents" | "projects"
		-- Typed first in the search, a prefix shows another view
		prefixes = { worktrees = "&", agents = "*", projects = "%" },
	},
	-- The projects view (`%`): git repos under `roots` (found with fd, skipping
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
		-- Inside the yard (an fzf-lua picker): fzf key names. Plain letters
		-- type into the search, so actions use alt- (macOS: left Option as Meta).
		yard = {
			activate = "enter", -- worktrees: switch · agents: go to (switch + link)
			alt_activate = "alt-enter", -- worktrees: peek (keep link) · agents: link only
			refresh = "ctrl-r",
			-- Same key, same idea in both views
			new = "alt-n", -- worktrees: new worktree · agents: new agent in a worktree
			remove = "ctrl-x", -- worktrees: remove worktree · agents: stop agent
			fork = "alt-f", -- worktrees: fork the linked agent here · agents: fork this one elsewhere
			dispatch = "alt-d", -- a task for a new agent in a new worktree
			-- worktrees view
			start_agent = "alt-a",
			continue_agent = "alt-c",
			copy_path = "alt-y",
			-- agents view
			view = "alt-v", -- in the split
			external = "alt-g", -- in an external terminal
			rename = "alt-r", -- its tmux session
			send = "alt-s", -- the prompt builder aimed at this agent
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
