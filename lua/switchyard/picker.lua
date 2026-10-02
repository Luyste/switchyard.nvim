-- The yard: one fzf-lua picker with three views, chosen by a prefix typed
-- first in the search (like fzf-lua's global picker, but our own):
--   worktrees (&): this repo's worktrees (preview: git status, recent commits)
--   agents    (*): this repo's running agents (preview: the agent's screen)
--   projects  (%): git repos on this machine, pinned and recent folders
-- No prefix shows `yard.view`. The keys are bound once and act on the kind of
-- row under the cursor, from one action list per kind (below), so a new
-- action shows up in the keys and fzf-lua's help (F1).
local M = {}

local state = {
	view = nil, -- the view shown now
	rows = {}, -- the rows of the last listings, by key (path or "pid:<n>")
	start = {}, -- per view: the line to start on (the current one)
}

local function sessions()
	return require("switchyard.sessions")
end
local function config()
	return require("switchyard.config").options
end
local function keys()
	return config().keys.yard
end
local function warn(message)
	vim.notify("switchyard: " .. message, vim.log.levels.WARN)
end

---------------------------------------------------------------------------
-- Lines: colored text, a tab, the row's key (hidden by --with-nth)
---------------------------------------------------------------------------

local function color(hl, text)
	return (require("fzf-lua.utils").ansi_from_hl(hl, text))
end

-- A left part, with its plain text for aligning the right parts
local function part()
	local p = { text = "", plain = "" }
	function p.add(text, hl)
		p.text = p.text .. (hl and color(hl, text) or text)
		p.plain = p.plain .. text
	end
	return p
end

local function line(left, right, width, key)
	local gap = right and string.rep(" ", math.max(width - vim.fn.strdisplaywidth(left.plain) + 2, 2)) or ""
	return left.text .. gap .. (right or "") .. "\t" .. key
end

-- Lines from { left, right?, key } parts, right parts aligned
local function aligned(parts)
	local width = 0
	for _, p in ipairs(parts) do
		width = math.max(width, vim.fn.strdisplaywidth(p.left.plain))
	end
	return vim.tbl_map(function(p)
		return line(p.left, p.right, width, p.key)
	end, parts)
end

-- The editor's folder as a worktree, when it isn't in a git repo (a config
-- folder): agents can still be started and listed there
local function plain_folder()
	local cwd = vim.fn.getcwd()
	return { { path = cwd, branch = vim.fn.fnamemodify(cwd, ":t"), current = true, main = true, symbols = "", plain = true } }
end

local function worktree_lines(worktrees)
	local all, linked = sessions().all(), sessions().linked_pid()
	local parts = {}
	for _, wt in ipairs(worktrees) do
		local agents = vim.tbl_filter(function(s)
			return s.cwd == wt.path
		end, all)
		state.rows[wt.path] = { kind = "worktree", worktree = wt, agents = agents, path = wt.path }
		local left = part()
		left.add(wt.current and "@ " or "  ", "SwitchyardCurrent")
		left.add(wt.branch, wt.current and "SwitchyardCurrent" or nil)
		if wt.symbols ~= "" then
			left.add("  " .. wt.symbols, "SwitchyardSymbols")
		end
		local right
		local linked_here = vim.iter(agents):find(function(s)
			return s.pid == linked
		end)
		if linked_here then
			local more = #agents > 1 and (" +" .. (#agents - 1)) or ""
			right = color("SwitchyardLinked", "● " .. sessions().name(linked_here) .. more)
		elseif #agents > 0 then
			right = color("SwitchyardAgent", "● " .. #agents)
		end
		table.insert(parts, { left = left, right = right, key = wt.path })
	end
	return aligned(parts)
end

-- This repo's agents: the linked one first, then by worktree. Agents whose
-- folder is gone (kept running after "remove worktree") are listed too, so
-- they can still be forked or stopped.
local function agent_lines(worktrees)
	local branch_of = {}
	for _, wt in ipairs(worktrees) do
		branch_of[wt.path] = wt.branch
	end
	local mine = vim.tbl_filter(function(s)
		return branch_of[s.cwd] ~= nil or vim.fn.isdirectory(s.cwd) == 0
	end, sessions().all())
	local linked = sessions().linked_pid()
	table.sort(mine, function(a, b)
		if (a.pid == linked) ~= (b.pid == linked) then
			return a.pid == linked
		end
		if a.cwd ~= b.cwd then
			return a.cwd < b.cwd
		end
		return a.pid < b.pid
	end)
	local parts = {}
	for _, s in ipairs(mine) do
		local key = "pid:" .. s.pid
		state.rows[key] = { kind = "agent", session = s, path = s.cwd }
		local left = part()
		local hl = s.pid == linked and "SwitchyardLinked" or "SwitchyardAgent"
		left.add("● ", hl)
		left.add(sessions().name(s), s.pid == linked and hl or nil)
		table.insert(parts, { left = left, right = color("SwitchyardDim", branch_of[s.cwd] or "removed worktree"), key = key })
	end
	return aligned(parts)
end

-- The lines of the worktrees or agents view. callback(lines, start index)
function M.lines(name, callback)
	require("switchyard.worktrees").list(vim.fn.getcwd(), function(worktrees)
		worktrees = worktrees or plain_folder()
		local lines = name == "agents" and agent_lines(worktrees) or worktree_lines(worktrees)
		local start = 1
		for i, l in ipairs(lines) do
			local row = state.rows[l:match("\t(.*)$")]
			if (row.kind == "worktree" and row.worktree.current) or (row.kind == "agent" and row.session.pid == sessions().linked_pid()) then
				start = i
				break
			end
		end
		callback(lines, start)
	end)
end

-- A project line: its name, ● with its agents, its folder (dim) on the right
local function project_line(path, by_root)
	state.rows[path] = { kind = "project", path = path }
	local current = require("switchyard.projects").root(vim.fn.getcwd()) == path
	local left = part()
	left.add(current and "@ " or "  ", "SwitchyardCurrent")
	left.add(vim.fn.fnamemodify(path, ":t"), current and "SwitchyardCurrent" or nil)
	local count = by_root[path] or 0
	if count > 0 then
		left.add("  ● " .. count, "SwitchyardAgent")
	end
	return line(left, color("SwitchyardDim", vim.fn.fnamemodify(path, ":~:h")), 32, path)
end

-- The projects view, streamed: the current project, pinned folders, projects
-- with agents and recent ones first, then the ones found last time, then
-- whatever fd finds now. on_line(line) per project, on_done() at the end.
function M.project_lines(on_line, on_done)
	local projects = require("switchyard.projects")
	local by_root = {}
	for _, s in ipairs(sessions().all()) do
		local root = projects.root(s.cwd)
		by_root[root] = (by_root[root] or 0) + 1
	end
	local seen = {}
	local function add(path)
		path = vim.fn.fnamemodify(vim.fn.expand(path), ":p"):gsub("/$", "")
		if not seen[path] and vim.fn.isdirectory(path) == 1 then
			seen[path] = true
			on_line(project_line(path, by_root))
		end
	end
	add(projects.root(vim.fn.getcwd()))
	for _, path in ipairs(config().projects.pinned) do
		add(path)
	end
	for root in pairs(by_root) do
		add(root)
	end
	for _, list in ipairs({ projects.recent(), projects.cached() }) do
		for _, path in ipairs(list) do
			add(path)
		end
	end
	projects.find(add, on_done)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Switch the editor but keep the current link (and the viewer)
local function peek(path)
	if path == vim.fn.getcwd() then
		return
	end
	sessions().keep_link_for(path)
	if not require("switchyard.projects").switch(path) then
		sessions().keep_link_for(nil) -- blocked (unsaved changes): no arrival follows
	end
end

local function switch(row)
	require("switchyard.projects").switch(row.path)
end

local function copy_path(row)
	vim.fn.setreg("+", row.path)
	vim.fn.setreg('"', row.path)
	vim.notify("switchyard: copied " .. vim.fn.fnamemodify(row.path, ":~"))
end

local function start_agent(row)
	require("switchyard.actions").with_agent(function(agent)
		require("switchyard.launch").new(agent, row.path)
	end)
end

local function dispatch()
	require("switchyard.prompt").open_dispatch()
end

local function reopen()
	M.open(state.view)
end

-- Choose one of this repo's worktrees (the current one first, `except` left
-- out), or create a new one. callback(worktree): { path, branch }
local function with_worktree(title, except, callback)
	require("switchyard.worktrees").list(vim.fn.getcwd(), function(worktrees)
		local list = vim.tbl_filter(function(wt)
			return wt.path ~= except
		end, worktrees or plain_folder())
		table.sort(list, function(a, b)
			return a.current and not b.current
		end)
		local items = vim.tbl_map(function(wt)
			return {
				label = (wt.current and "@ " or "  ") .. wt.branch,
				action = function()
					callback(wt)
				end,
			}
		end, list)
		if worktrees then
			table.insert(items, {
				label = "  new worktree…",
				action = function()
					require("switchyard.actions").create_worktree(vim.fn.getcwd(), function(path, branch)
						callback({ path = path, branch = branch })
					end)
				end,
			})
		end
		require("switchyard.menu").open({ title = title, items = items })
	end)
end

-- Per kind of row: { key = name in keys.yard, label, run = function(row),
-- any_row? (also on an empty list of this view; row is nil then), stay? (the
-- picker stays open and reloads) }. Everything else closes the picker first.
local actions = {
	worktree = {
		{ key = "activate", label = "switch here", run = switch },
		{ key = "alt_activate", label = "peek: switch, keep the link", run = function(row)
			peek(row.path)
		end },
		{
			key = "new",
			label = "new worktree",
			any_row = true,
			run = function()
				require("switchyard.actions").create_worktree(vim.fn.getcwd(), reopen)
			end,
		},
		{ key = "dispatch", label = "dispatch: a task for a new agent in a new worktree", any_row = true, run = dispatch },
		{ key = "start_agent", label = "start an agent here", run = start_agent },
		{
			key = "continue_agent",
			label = "continue an earlier session here",
			run = function(row)
				require("switchyard.actions").continue_agent(row.path)
			end,
		},
		{
			key = "fork",
			label = "fork the linked agent here",
			run = function(row)
				local linked = sessions().linked()
				if not linked then
					return warn("no linked agent to fork")
				elseif linked.cwd == row.path then
					return warn("the linked agent already works here")
				end
				require("switchyard.launch").fork(linked, row.path)
			end,
		},
		{ key = "copy_path", label = "copy path", stay = true, run = copy_path },
		{
			key = "remove",
			label = "remove worktree",
			run = function(row)
				if row.worktree.plain then
					return warn("not a git worktree")
				end
				require("switchyard.actions").remove_worktree(vim.fn.getcwd(), row.worktree, reopen, row.agents)
			end,
		},
	},
	agent = {
		{
			key = "activate",
			label = "go to: switch to its worktree and link",
			run = function(row)
				local moved = row.path ~= vim.fn.getcwd()
				if require("switchyard.projects").switch(row.path) then
					-- Before the (scheduled) arrival rules run, so they keep this link
					sessions().link(row.session, moved) -- quiet after a switch: the statusline shows it
				end
			end,
		},
		{ key = "alt_activate", label = "link only, stay here", stay = true, run = function(row)
			sessions().link(row.session)
		end },
		{ key = "view", label = "view in the split", run = function(row)
			require("switchyard.view").show(row.session)
		end },
		{ key = "external", label = "open in an external terminal", stay = true, run = function(row)
			require("switchyard.view").external(row.session)
		end },
		{
			key = "new",
			label = "new agent in a worktree…",
			any_row = true,
			run = function()
				with_worktree("new agent in", nil, function(wt)
					start_agent(wt)
				end)
			end,
		},
		{
			key = "fork",
			label = "fork into another worktree…",
			run = function(row)
				with_worktree("fork " .. sessions().name(row.session) .. " into", row.path, function(wt)
					require("switchyard.launch").fork(row.session, wt.path)
				end)
			end,
		},
		{ key = "dispatch", label = "dispatch: a task for a new agent in a new worktree", any_row = true, run = dispatch },
		{ key = "send", label = "write a prompt for it", run = function(row)
			require("switchyard.prompt").open_for(row.session)
		end },
		{
			key = "rename",
			label = "rename its tmux session",
			run = function(row)
				local old = row.session.tmux
				require("switchyard.menu").input({ title = "rename " .. old, default = old }, function(new)
					if not new or new == "" or new == old then
						return reopen()
					end
					new = new:gsub("[%.:]", "_") -- tmux doesn't allow . and : in names
					require("switchyard.tmux").rename(old, new, function(ok, err)
						if not ok then
							return warn("tmux: " .. err)
						end
						require("switchyard.view").renamed(old, new)
						sessions().refresh(reopen)
					end)
				end)
			end,
		},
		{
			key = "remove",
			label = "stop agent",
			run = function(row)
				require("switchyard.actions").stop_agent(row.session, function()
					sessions().refresh(reopen)
				end)
			end,
		},
	},
	project = {
		{ key = "activate", label = "switch to the project", run = switch },
		{ key = "alt_activate", label = "peek: switch, keep the link", run = function(row)
			peek(row.path)
		end },
		{ key = "start_agent", label = "start an agent there (the editor stays)", run = start_agent },
		{ key = "copy_path", label = "copy path", stay = true, run = copy_path },
	},
}

M.actions = actions -- for tests

local kind_of_view = { worktrees = "worktree", agents = "agent", projects = "project" }

-- The action for key name `name` on the row of fzf line `selected`, or, on
-- an empty view, an any_row action of that view's kind
local function find(name, selected)
	local text = selected and selected[1]
	local row = text and state.rows[text:match("\t(.*)$")]
	local kind = row and row.kind or kind_of_view[state.view]
	for _, action in ipairs(actions[kind]) do
		if action.key == name and (row or action.any_row) then
			return action, row
		end
	end
end

-- fzf-lua actions: one per key name used by any kind. Keys that may leave the
-- picker open (stay) are reload actions; the rest close it first.
local function fzf_actions()
	local k, result, stays = keys(), {}, {}
	for _, list in pairs(actions) do
		for _, action in ipairs(list) do
			stays[action.key] = stays[action.key] or action.stay or false
		end
	end
	for name, stay in pairs(stays) do
		if stay then
			result[k[name]] = {
				fn = function(selected)
					local action, row = find(name, selected)
					if action then
						if action.stay then
							action.run(row)
						else -- this kind closes for it: after the picker is gone
							vim.schedule(function()
								require("fzf-lua").hide()
								action.run(row)
							end)
						end
					end
				end,
				reload = true,
			}
		else
			result[k[name]] = function(selected)
				local action, row = find(name, selected)
				if action then
					-- Windows and questions: after fzf-lua is done closing
					vim.schedule(function()
						action.run(row)
					end)
				end
			end
		end
	end
	result[k.refresh] = { fn = function() end, reload = true }
	return result
end

---------------------------------------------------------------------------
-- Previews (shell commands fzf runs for the line under the cursor)
---------------------------------------------------------------------------

local function preview(items)
	local text = items and items[1]
	local row = text and state.rows[text:match("\t(.*)$")]
	if not row then
		return "true"
	elseif row.kind == "agent" then
		return "tmux capture-pane -p -e -t " .. vim.fn.shellescape(row.session.pane)
	end
	local dir = vim.fn.shellescape(row.path)
	if vim.fn.isdirectory(row.path .. "/.git") == 0 and vim.fn.filereadable(row.path .. "/.git") == 0 then
		return "ls -1p " .. dir
	end
	return ("git -C %s -c color.status=always status -sb; echo; git -C %s log --oneline --color=always -15"):format(dir, dir)
end

---------------------------------------------------------------------------
-- Opening, and switching views by prefix
---------------------------------------------------------------------------

-- The view a query asks for, and the query without its prefix
local function parse(query)
	for name, prefix in pairs(config().yard.prefixes) do
		if prefix ~= "" and vim.startswith(query, prefix) then
			return name, query:sub(#prefix + 1)
		end
	end
	return config().yard.view, query
end

local function pretty(key)
	return ({ enter = "⏎", ["alt-enter"] = "⌥⏎" })[key] or key:gsub("^alt%-", "⌥"):gsub("^ctrl%-", "^")
end

-- Short words for the key hints; an action without one shows the first word
-- of its label
local hint_words = {
	worktree = { activate = "switch", alt_activate = "peek", start_agent = "agent", continue_agent = "continue" },
	agent = { activate = "go to", alt_activate = "link", external = "terminal", send = "prompt" },
	project = { activate = "switch", alt_activate = "peek", start_agent = "agent" },
}

-- The header: the views and their prefixes, the shown one highlighted
local function header(name)
	local p, views = config().yard.prefixes, {}
	for _, view in ipairs({ "worktrees", "agents", "projects" }) do
		local label = p[view] .. view
		table.insert(views, view == name and color("SwitchyardHeading", label) or color("SwitchyardDim", label))
	end
	return table.concat(views, "  ")
end

-- The footer: every key of this view, wrapped to the list's width. No
-- parentheses: it goes into fzf's change-footer(...)
local function footer(name)
	local kind, k = kind_of_view[name], keys()
	local hints = {}
	for _, action in ipairs(actions[kind]) do
		local word = hint_words[kind][action.key] or action.label:match("^[%w]+")
		table.insert(hints, color("SwitchyardKey", pretty(k[action.key])) .. " " .. word)
	end
	table.insert(hints, color("SwitchyardKey", pretty(k.refresh)) .. " refresh")
	table.insert(hints, color("SwitchyardKey", "F1") .. " help")
	-- The list takes the window's width minus the preview (55%)
	local width = math.floor(vim.o.columns * 0.8 * 0.45) - 4
	local lines, current, current_width = {}, "", 0
	for _, hint in ipairs(hints) do
		local w = vim.fn.strdisplaywidth((hint:gsub("\27%[[%d;]*m", "")))
		if current_width > 0 and current_width + 2 + w > width then
			table.insert(lines, current)
			current, current_width = "", 0
		end
		current = current_width > 0 and (current .. "  " .. hint) or hint
		current_width = current_width + (current_width > 0 and 2 or 0) + w
	end
	table.insert(lines, current)
	return table.concat(lines, "\n")
end

-- The contents of the view shown now (fzf reloads it when the view changes)
local function contents(fzf_cb)
	if state.view == "projects" then
		return M.project_lines(function(l)
			fzf_cb(l)
		end, function()
			fzf_cb()
		end)
	end
	local name = state.view
	M.lines(name, function(lines, start)
		state.start[name] = start
		for _, l in ipairs(lines) do
			fzf_cb(l)
		end
		fzf_cb()
	end)
end

-- Open the yard, in view `name` (default: the view without a prefix)
function M.open(name)
	local fzf = require("fzf-lua")
	name = name or config().yard.view
	state.view, state.rows = name, {}
	require("switchyard.ui").set_highlights()
	vim.cmd.stopinsert() -- opened from a terminal (the viewer)
	local prefix = name ~= config().yard.view and config().yard.prefixes[name] or ""

	local _, cmd, opts = fzf.fzf_exec(contents, {
		_start = false, -- fzf_wrap below starts it, with the prefix binds added
		prompt = "yard❯ ",
		query = prefix,
		header = header(name),
		actions = fzf_actions(),
		preview = { type = "cmd", fn = preview },
		fzf_opts = {
			["--delimiter"] = "\t",
			["--with-nth"] = "1",
			["--no-multi"] = true,
			["--footer"] = footer(name), -- the keys, below the list
		},
		winopts = {
			title = false, -- Neovide draws border titles over the border
			height = 0.6,
			width = 0.8,
			preview = { layout = "horizontal", horizontal = "right:55%" },
		},
	})
	if not opts then
		return
	end
	opts._start = nil

	-- Typing: a new prefix reloads the list with that view, the rest searches
	local on_change = fzf.shell.stringify_data(function(args)
		local view, search = parse(args[1] or "")
		local out = ""
		if view ~= state.view then
			state.view = view
			out = ("reload(%s)+change-header(%s)+change-footer(%s)+"):format(cmd, header(view), footer(view))
		end
		return out .. "search:" .. search -- last in the chain: any text goes
	end, opts, "{q}")
	-- A list loaded: start on the current worktree / the linked agent
	local on_load = fzf.shell.stringify_data(function()
		local start = state.start[state.view]
		return start and ("pos(" .. start .. ")") or ""
	end, opts, "{q}")
	local shellescape = require("fzf-lua.libuv").shellescape
	opts._fzf_cli_args = opts._fzf_cli_args or {}
	table.insert(opts._fzf_cli_args, "--bind=" .. shellescape("start:+transform:" .. on_change))
	table.insert(opts._fzf_cli_args, "--bind=" .. shellescape("change:+transform:" .. on_change))
	table.insert(opts._fzf_cli_args, "--bind=" .. shellescape("load:+transform:" .. on_load))
	require("fzf-lua.core").fzf_wrap(cmd, opts)
end

return M
