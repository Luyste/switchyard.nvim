-- Actions on worktrees and agents, shared by the pickers and the yard.
-- Each takes an optional on_done, called after the action succeeded.
local worktrunk = require("switchyard.worktrunk")

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
-- on_done(path)
function M.create_worktree(cwd, on_done)
	vim.ui.input({ prompt = "New branch: " }, function(branch)
		if not branch or branch == "" then
			return
		end
		vim.api.nvim_echo({ { "switchyard: creating " .. branch .. " …" } }, false, {})
		worktrunk.create(cwd, branch, function(path, err)
			if not path then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			vim.notify("switchyard: created " .. branch)
			if on_done then
				on_done(path)
			end
		end)
	end)
end

-- End the tmux session `session` runs in (without asking). callback(ok)
local function kill(session, callback)
	local sessions = require("switchyard.sessions")
	local tmux = require("switchyard.tmux")
	local function stop(name)
		if not name then
			vim.notify("switchyard: " .. sessions.describe(session) .. " isn't running in tmux", vim.log.levels.WARN)
			return callback(false)
		end
		tmux.kill(name, function(ok, err)
			if not ok then
				vim.notify("switchyard: tmux: " .. err, vim.log.levels.ERROR)
			end
			callback(ok, name)
		end)
	end
	local known = sessions.tmux_name(session)
	if known then
		return stop(known)
	end
	tmux.session_of_pid(session.pid, stop)
end

-- Remove worktree `wt` after confirming. Never the current or the main one.
-- `agents`: the sessions working in it (optional). You choose whether they
-- stop too, or keep running (with their history) to continue elsewhere.
function M.remove_worktree(cwd, wt, on_done, agents)
	if wt.current then
		return vim.notify("switchyard: you're in this worktree. Switch away first.", vim.log.levels.WARN)
	end
	if wt.main then
		return vim.notify("switchyard: the main worktree can't be removed.", vim.log.levels.WARN)
	end
	agents = agents or {}

	local function remove(stop_agents)
		for _, session in ipairs(stop_agents and agents or {}) do
			kill(session, function() end)
		end
		vim.api.nvim_echo({ { "switchyard: removing " .. wt.branch .. " …" } }, false, {})
		worktrunk.remove(cwd, wt.branch, function(ok, err)
			if not ok then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			vim.notify("switchyard: removed " .. wt.branch)
			if on_done then
				on_done()
			end
		end)
	end

	local items = { { label = "No", action = function() end } }
	if #agents == 0 then
		table.insert(items, { label = "Remove " .. wt.branch, danger = true, action = remove })
	else
		local count = #agents == 1 and "its agent" or (#agents .. " agents")
		table.insert(items, {
			label = "Remove " .. wt.branch .. ", keep " .. count .. " running",
			danger = true,
			action = function()
				remove(false)
			end,
		})
		table.insert(items, {
			label = "Remove " .. wt.branch .. " and stop " .. count,
			danger = true,
			action = function()
				remove(true)
			end,
		})
	end
	require("switchyard.menu").open({ title = "remove worktree " .. wt.branch .. "?", items = items })
end

-- Stop an agent after confirming, by ending its tmux session (so its shell
-- goes too). Agents outside tmux aren't ours to kill.
function M.stop_agent(session, on_done)
	local name = require("switchyard.sessions").tmux_name(session) or session.adapter.name
	M.confirm("stop " .. name .. "?", "Stop " .. name, function()
		kill(session, function(ok, killed)
			if ok then
				vim.notify("switchyard: stopped " .. killed)
				if on_done then
					on_done()
				end
			end
		end)
	end)
end

return M
