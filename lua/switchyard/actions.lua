-- Actions on worktrees and agents, shared by the yard and the prompt builder.
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

-- The adapter to start: the only installed one, or ask. callback(adapter)
function M.with_adapter(callback)
	local list = require("switchyard.adapters").active()
	if #list == 0 then
		return vim.notify("switchyard: no agents installed", vim.log.levels.WARN)
	elseif #list == 1 then
		return callback(list[1])
	end
	require("switchyard.menu").open({
		title = "which agent?",
		items = vim.tbl_map(function(adapter)
			return {
				label = adapter.name,
				action = function()
					callback(adapter)
				end,
			}
		end, list),
	})
end

-- How to show a worktree's changes: a function(worktree), or nil when there's
-- no way (then `d` isn't offered). See the `diff` option.
function M.diff_viewer()
	local choice = require("switchyard.config").options.diff
	if type(choice) == "function" then
		return choice
	end
	local codediff = require("switchyard.integrations.codediff")
	if (choice == "auto" or choice == "codediff") and codediff.available() then
		return codediff.open
	end
end

-- Ask for a branch name and make a worktree for it: an existing branch is
-- checked out there, a new name becomes a new branch (the editor stays put).
-- on_done(path, branch)
function M.create_worktree(cwd, on_done)
	require("switchyard.menu").input({ title = "worktree for a branch (new or existing)" }, function(branch)
		if not branch or branch == "" then
			return
		end
		require("switchyard.util").progress("switchyard: creating " .. branch .. " …")
		worktrunk.create(cwd, branch, function(path, err)
			if not path then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			vim.notify("switchyard: worktree for " .. branch)
			if on_done then
				on_done(path, branch)
			end
		end)
	end)
end

-- End the tmux session `session` runs in (without asking). callback(name)
-- once it's gone.
local function kill(session, callback)
	require("switchyard.sessions").with_tmux_name(session, function(name)
		require("switchyard.tmux").kill(name, function(ok, err)
			if not ok then
				return vim.notify("switchyard: tmux: " .. err, vim.log.levels.ERROR)
			end
			callback(name)
		end)
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
