-- The yard as fzf-lua pickers: two views of this repo, fuzzy search, a preview.
--   worktrees: the repo's worktrees (preview: git status and recent commits)
--   agents:    the repo's running agents (preview: the agent's screen)
-- Tab switches views. Every key comes from one action list per view (below),
-- so a new action shows up in the keys, the header and fzf-lua's help (F1).
local M = {}

-- The view survives closing: the yard reopens where you left it
local view = nil

-- The rows of the last listing, by key (worktree path or "pid:<n>")
local rows = {}

local function sessions()
	return require("switchyard.sessions")
end
local function keys()
	return require("switchyard.config").options.keys.yard
end
local function warn(message)
	vim.notify("switchyard: " .. message, vim.log.levels.WARN)
end

---------------------------------------------------------------------------
-- Rows and lines
---------------------------------------------------------------------------

local function color(hl, text)
	return (require("fzf-lua.utils").ansi_from_hl(hl, text))
end

-- One fzf line: the visible text, a tab, the row's key (hidden by --with-nth)
local function line(left, right, width, key)
	local gap = right and string.rep(" ", math.max(width - vim.fn.strdisplaywidth(left.plain) + 2, 2)) or ""
	return left.text .. gap .. (right or "") .. "\t" .. key
end

-- A left part with its plain text (for aligning the right parts)
local function part()
	local p = { text = "", plain = "" }
	function p.add(text, hl)
		p.text = p.text .. (hl and color(hl, text) or text)
		p.plain = p.plain .. text
	end
	return p
end

local function worktree_lines(worktrees)
	local all, linked = sessions().all(), sessions().linked_pid()
	local lefts, width = {}, 0
	for i, wt in ipairs(worktrees) do
		local agents = vim.tbl_filter(function(s)
			return s.cwd == wt.path
		end, all)
		rows[wt.path] = { kind = "worktree", worktree = wt, agents = agents, key = wt.path, path = wt.path }
		local left = part()
		left.add(wt.current and "@ " or "  ", "SwitchyardCurrent")
		left.add(wt.branch, wt.current and "SwitchyardCurrent" or nil)
		if wt.symbols ~= "" then
			left.add("  " .. wt.symbols, "SwitchyardSymbols")
		end
		lefts[i] = left
		width = math.max(width, vim.fn.strdisplaywidth(left.plain))
	end
	local lines = {}
	for i, wt in ipairs(worktrees) do
		local agents, right = rows[wt.path].agents, nil
		local linked_here = vim.iter(agents):find(function(s)
			return s.pid == linked
		end)
		if linked_here then
			local more = #agents > 1 and (" +" .. (#agents - 1)) or ""
			right = color("SwitchyardLinked", "● " .. sessions().name(linked_here) .. more)
		elseif #agents > 0 then
			right = color("SwitchyardAgent", "● " .. #agents)
		end
		lines[i] = line(lefts[i], right, width, wt.path)
	end
	return lines
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
	local lefts, width = {}, 0
	for i, s in ipairs(mine) do
		local left = part()
		local hl = s.pid == linked and "SwitchyardLinked" or "SwitchyardAgent"
		left.add("● ", hl)
		left.add(sessions().name(s), s.pid == linked and hl or nil)
		lefts[i] = left
		width = math.max(width, vim.fn.strdisplaywidth(left.plain))
	end
	local lines = {}
	for i, s in ipairs(mine) do
		local key = "pid:" .. s.pid
		rows[key] = { kind = "agent", session = s, key = key, path = s.cwd }
		lines[i] = line(lefts[i], color("SwitchyardDim", branch_of[s.cwd] or "removed worktree"), width, key)
	end
	return lines
end

-- The row an fzf line stands for
local function row_of(selected)
	local text = selected and selected[1]
	return text and rows[text:match("\t(.*)$")] or nil
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------

-- Switch the editor but keep the current link
local function peek(path)
	if path == vim.fn.getcwd() then
		return
	end
	sessions().keep_link_for(path)
	if not require("switchyard.projects").switch(path) then
		sessions().keep_link_for(nil) -- blocked (unsaved changes): no arrival follows
	end
end

-- Enter (alt = the alternative key) on `row`.
--   worktree: switch (the link moves along) / peek (the link stays)
--   agent:    go to it (switch to its worktree + link) / link only, stay here
local function activate(row, alt)
	if row.kind == "agent" and alt then
		return sessions().link(row.session)
	end
	if row.kind == "worktree" then
		return alt and peek(row.path) or require("switchyard.projects").switch(row.path)
	end
	local moved = row.path ~= vim.fn.getcwd()
	if require("switchyard.projects").switch(row.path) then
		-- Before the (scheduled) arrival rules run, so they keep this link
		sessions().link(row.session, moved) -- quiet after a switch: the statusline shows it
	end
end

local function reopen()
	M.open()
end

-- Choose one of this repo's worktrees (the current one first, `except` left
-- out), or create a new one. callback(worktree): { path, branch }
local function with_worktree(title, except, callback)
	require("switchyard.worktrees").list(vim.fn.getcwd(), function(worktrees)
		local list = vim.tbl_filter(function(wt)
			return wt.path ~= except
		end, worktrees or {})
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
		table.insert(items, {
			label = "  new worktree…",
			action = function()
				require("switchyard.actions").create_worktree(vim.fn.getcwd(), function(path, branch)
					callback({ path = path, branch = branch })
				end)
			end,
		})
		require("switchyard.menu").open({ title = title, items = items })
	end)
end

-- Per view: { key = name in keys.yard, label, run = function(row), any_row?
-- (also works on an empty list; row is nil then), stay? (the picker stays
-- open and reloads) }. Everything else closes the picker first.
local actions = {
	worktrees = {
		{ key = "activate", label = "switch here", run = activate },
		{
			key = "alt_activate",
			label = "peek: switch, keep the link",
			run = function(row)
				activate(row, true)
			end,
		},
		{
			key = "new",
			label = "new worktree",
			any_row = true,
			run = function()
				require("switchyard.actions").create_worktree(vim.fn.getcwd(), reopen)
			end,
		},
		{
			key = "dispatch",
			label = "dispatch: a task for a new agent in a new worktree",
			any_row = true,
			run = function()
				require("switchyard.prompt").open_dispatch()
			end,
		},
		{
			key = "start_agent",
			label = "start an agent here",
			run = function(row)
				require("switchyard.actions").with_agent(function(agent)
					require("switchyard.launch").new(agent, row.path)
				end)
			end,
		},
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
		{
			key = "copy_path",
			label = "copy path",
			stay = true,
			run = function(row)
				vim.fn.setreg("+", row.path)
				vim.fn.setreg('"', row.path)
				vim.notify("switchyard: copied " .. vim.fn.fnamemodify(row.path, ":~"))
			end,
		},
		{
			key = "remove",
			label = "remove worktree",
			run = function(row)
				require("switchyard.actions").remove_worktree(vim.fn.getcwd(), row.worktree, reopen, row.agents)
			end,
		},
	},
	agents = {
		{ key = "activate", label = "go to: switch to its worktree and link", run = activate },
		{
			key = "alt_activate",
			label = "link only, stay here",
			stay = true,
			run = function(row)
				activate(row, true)
			end,
		},
		{
			key = "view",
			label = "view in the split",
			run = function(row)
				require("switchyard.view").show(row.session)
			end,
		},
		{
			key = "external",
			label = "open in an external terminal",
			stay = true,
			run = function(row)
				require("switchyard.view").external(row.session)
			end,
		},
		{
			key = "new",
			label = "new agent in a worktree…",
			any_row = true,
			run = function()
				with_worktree("new agent in", nil, function(wt)
					require("switchyard.actions").with_agent(function(agent)
						require("switchyard.launch").new(agent, wt.path)
					end)
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
		{
			key = "dispatch",
			label = "dispatch: a task for a new agent in a new worktree",
			any_row = true,
			run = function()
				require("switchyard.prompt").open_dispatch()
			end,
		},
		{
			key = "send",
			label = "write a prompt for it",
			run = function(row)
				require("switchyard.prompt").open_for(row.session)
			end,
		},
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
}

M.actions = actions -- for tests

-- fzf-lua actions for `name`'s view: our list, plus Tab and refresh
local function fzf_actions(name)
	local k, result = keys(), {}
	for _, action in ipairs(actions[name]) do
		local fn = function(selected)
			local row = row_of(selected)
			if row or action.any_row then
				-- Closing the picker and reopening windows: after fzf-lua is done
				vim.schedule(function()
					action.run(row)
				end)
			end
		end
		if action.stay then
			-- Runs while the picker stays open; the list is read again after it
			result[k[action.key]] = {
				fn = function(selected)
					local row = row_of(selected)
					if row or action.any_row then
						action.run(row)
					end
				end,
				reload = true,
				desc = action.label,
			}
		else
			result[k[action.key]] = { fn = fn, desc = action.label }
		end
	end
	result[k.toggle_view] = {
		fn = function()
			view = name == "worktrees" and "agents" or "worktrees"
			vim.schedule(M.open)
		end,
		desc = "other view",
	}
	result[k.refresh] = { fn = function() end, reload = true, desc = "refresh" }
	return result
end

-- How a key reads in the header
local function pretty(key)
	return ({ enter = "⏎", ["alt-enter"] = "⌥⏎", tab = "⇥" })[key] or key:gsub("^alt%-", "⌥"):gsub("^ctrl%-", "^")
end

local function header(name)
	local k = keys()
	local parts = name == "worktrees"
			and { { "activate", "switch" }, { "alt_activate", "peek" }, { "toggle_view", "agents" }, { "start_agent", "agent" } }
		or { { "activate", "go to" }, { "alt_activate", "link" }, { "toggle_view", "worktrees" }, { "view", "view" } }
	return table.concat(
		vim.tbl_map(function(p)
			return pretty(k[p[1]]) .. " " .. p[2]
		end, parts),
		"  "
	) .. "  F1 keys"
end

---------------------------------------------------------------------------
-- Previews (shell commands fzf runs for the line under the cursor)
---------------------------------------------------------------------------

local function preview(name)
	return {
		type = "cmd",
		fn = function(items)
			local row = row_of(items)
			if not row then
				return "true"
			elseif name == "agents" then
				return "tmux capture-pane -p -e -t " .. vim.fn.shellescape(row.session.pane)
			end
			local dir = vim.fn.shellescape(row.path)
			return ("git -C %s -c color.status=always status -sb; echo; git -C %s log --oneline --color=always -15"):format(dir, dir)
		end,
	}
end

---------------------------------------------------------------------------
-- Opening
---------------------------------------------------------------------------

-- The lines for view `name`, and the index of the line to start on (the
-- current worktree / the linked agent). callback(lines, index)
function M.lines(name, callback)
	require("switchyard.worktrees").list(vim.fn.getcwd(), function(worktrees, err)
		if not worktrees then
			return callback({}, 1, err)
		end
		rows = {}
		local lines = name == "agents" and agent_lines(worktrees) or worktree_lines(worktrees)
		local start = 1
		for i, l in ipairs(lines) do
			local row = row_of({ l })
			if (row.kind == "worktree" and row.worktree.current) or (row.kind == "agent" and row.session.pid == sessions().linked_pid()) then
				start = i
				break
			end
		end
		callback(lines, start)
	end)
end

function M.open()
	view = view or require("switchyard.config").options.yard.view
	local name = view
	require("switchyard.ui").set_highlights()
	vim.cmd.stopinsert() -- opened from a terminal (the viewer)
	sessions().refresh()
	M.lines(name, function(_, start, err)
		if err then
			return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
		end
		require("fzf-lua").fzf_exec(function(fzf_cb)
			M.lines(name, function(lines)
				for _, l in ipairs(lines) do
					fzf_cb(l)
				end
				fzf_cb()
			end)
		end, {
			prompt = name .. "❯ ",
			header = header(name),
			actions = fzf_actions(name),
			preview = preview(name),
			fzf_opts = {
				["--delimiter"] = "\t",
				["--with-nth"] = "1",
				["--no-multi"] = true,
			},
			keymap = { fzf = { load = "pos(" .. start .. ")" } }, -- start on the current one
			winopts = {
				title = false, -- Neovide draws border titles over the border
				height = 0.6,
				width = 0.8,
				preview = { layout = "horizontal", horizontal = "right:55%" },
			},
		})
	end)
end

return M
