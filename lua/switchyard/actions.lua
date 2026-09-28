-- Actions on worktrees and agents, shared by the yard and the prompt builder.
-- Each takes an optional on_done, called after the action succeeded.
local worktrees = require("switchyard.worktrees")

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

-- The agent to start: the only installed one, or ask. callback(agent)
function M.with_agent(callback)
	local list = require("switchyard.agents").installed()
	if #list == 0 then
		return vim.notify("switchyard: none of the configured agents is installed", vim.log.levels.WARN)
	elseif #list == 1 then
		return callback(list[1])
	end
	require("switchyard.menu").open({
		title = "which agent?",
		items = vim.tbl_map(function(agent)
			return {
				label = agent.name,
				action = function()
					callback(agent)
				end,
			}
		end, list),
	})
end

-- Ask for a branch name and create a worktree for it (the editor stays put).
-- on_done(path, branch)
function M.create_worktree(cwd, on_done)
	require("switchyard.menu").input({ title = "new worktree: branch name" }, function(branch)
		if not branch or branch == "" then
			return
		end
		require("switchyard.util").progress("switchyard: creating " .. branch .. " …")
		worktrees.create(cwd, branch, function(path, err)
			if not path then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			vim.notify("switchyard: created " .. branch)
			if on_done then
				on_done(path, branch)
			end
		end)
	end)
end

-- End the tmux session `session` runs in (without asking). callback(name)
-- once it's gone.
local function kill(session, callback)
	require("switchyard.tmux").kill(session.tmux, function(ok, err)
		if not ok then
			return vim.notify("switchyard: tmux: " .. err, vim.log.levels.ERROR)
		end
		require("switchyard.sessions").refresh()
		callback(session.tmux)
	end)
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
		require("switchyard.util").progress("switchyard: removing " .. wt.branch .. " …")
		worktrees.remove(cwd, wt, function(ok, err)
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
	local name = require("switchyard.sessions").name(session)
	M.confirm("stop " .. name .. "?", "Stop " .. name, function()
		kill(session, function(killed)
			vim.notify("switchyard: stopped " .. killed)
			if on_done then
				on_done()
			end
		end)
	end)
end

return M
