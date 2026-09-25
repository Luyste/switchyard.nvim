local tmux = require("switchyard.tmux")
local sessions = require("switchyard.sessions")

local M = {}

-- Check every 500 ms for a new session from `adapter` in `cwd`.
-- `known` holds the process IDs that existed before the launch.
-- callback(session), or callback(nil) after 30 seconds.
local function wait_for_session(adapter, cwd, known, callback)
	local tries = 0
	local timer = vim.uv.new_timer()
	timer:start(
		500,
		500,
		vim.schedule_wrap(function()
			tries = tries + 1
			for _, s in ipairs(adapter.sessions()) do
				if s.cwd == cwd and not known[s.pid] then
					timer:stop()
					timer:close()
					return callback(s)
				end
			end
			if tries >= 60 then
				timer:stop()
				timer:close()
				callback(nil)
			end
		end)
	)
end

-- Start `cmd` for `adapter` in a new tmux session in the current folder,
-- then link to it. callback(session, tmux_name) is optional.
function M.start(adapter, cmd, label, callback)
	local cwd = vim.fn.getcwd()
	local known = {}
	for _, s in ipairs(adapter.sessions()) do
		known[s.pid] = true
	end

	tmux.free_name(adapter.name .. "-" .. vim.fn.fnamemodify(cwd, ":t"), function(name)
		tmux.new(name, cwd, cmd, function(ok, err)
			if not ok then
				return vim.notify("switchyard: tmux: " .. err, vim.log.levels.ERROR)
			end
			vim.api.nvim_echo({ { ("switchyard: starting %s (tmux: %s) …"):format(label, name) } }, false, {})

			wait_for_session(adapter, cwd, known, function(s)
				if not s then
					return vim.notify(
						("switchyard: %s is running in tmux session %s but didn't register. %s"):format(
							adapter.name,
							name,
							adapter.hint or ""
						),
						vim.log.levels.WARN
					)
				end
				sessions.link(s)
				if callback then
					callback(s, name)
				end
			end)
		end)
	end)
end

function M.new(adapter)
	M.start(adapter, adapter.new_cmd(), "new " .. adapter.name)
end

function M.continue(adapter)
	M.start(adapter, adapter.continue_cmd(), adapter.name .. " (continue)")
end

-- Fork a running session from another folder into the current one
function M.fork(source)
	local cmd = source.adapter.fork_cmd and source.adapter.fork_cmd(source)
	if not cmd then
		return vim.notify("switchyard: can't fork " .. sessions.describe(source), vim.log.levels.WARN)
	end
	local here = vim.fn.getcwd()
	M.start(source.adapter, cmd, "fork of " .. sessions.describe(source), function(s)
		-- The history is full of paths from the source worktree: tell the fork where it is now
		local note = (
			"Note: this session was forked from %s and now runs in %s. "
			.. "Absolute paths in the history refer to the original worktree; work in the new one."
		):format(source.cwd, here)
		s.adapter.send(s, note, function() end)
	end)
end

-- Pick what to start in the current folder
function M.pick()
	local cwd = vim.fn.getcwd()
	local choices = {}
	for _, adapter in ipairs(require("switchyard.adapters").active()) do
		table.insert(choices, {
			label = "New " .. adapter.name,
			run = function()
				M.new(adapter)
			end,
		})
		table.insert(choices, {
			label = "Continue " .. adapter.name,
			run = function()
				M.continue(adapter)
			end,
		})
	end
	for _, s in ipairs(sessions.all()) do
		if s.cwd ~= cwd and s.adapter.fork_cmd then
			table.insert(choices, {
				label = "Fork " .. sessions.describe(s),
				run = function()
					M.fork(s)
				end,
			})
		end
	end
	if #choices == 0 then
		return vim.notify("switchyard: no agents installed", vim.log.levels.WARN)
	end
	require("switchyard.menu").open({
		title = "start agent in " .. vim.fn.fnamemodify(cwd, ":t"),
		items = vim.tbl_map(function(c)
			return { label = c.label, action = c.run }
		end, choices),
	})
end

return M
