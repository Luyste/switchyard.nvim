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

-- Remove worktree `wt` after confirming. Never the current or the main one.
function M.remove_worktree(cwd, wt, on_done)
	if wt.current then
		return vim.notify("switchyard: you're in this worktree. Switch away first.", vim.log.levels.WARN)
	end
	if wt.main then
		return vim.notify("switchyard: the main worktree can't be removed.", vim.log.levels.WARN)
	end
	M.confirm("remove worktree " .. wt.branch .. "?", "Remove " .. wt.branch, function()
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
	end)
end

-- Stop an agent after confirming, by ending its tmux session (so its shell
-- goes too). Agents outside tmux aren't ours to kill.
function M.stop_agent(session, on_done)
	local sessions = require("switchyard.sessions")
	local tmux = require("switchyard.tmux")
	local function stop(name)
		if not name then
			return vim.notify("switchyard: " .. sessions.describe(session) .. " isn't running in tmux", vim.log.levels.WARN)
		end
		M.confirm("stop " .. name .. "?", "Stop " .. name, function()
			tmux.kill(name, function(ok, err)
				if not ok then
					return vim.notify("switchyard: tmux: " .. err, vim.log.levels.ERROR)
				end
				vim.notify("switchyard: stopped " .. name)
				if on_done then
					on_done()
				end
			end)
		end)
	end
	local known = sessions.tmux_name(session)
	if known then
		return stop(known)
	end
	tmux.session_of_pid(session.pid, stop)
end

return M
