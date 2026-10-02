local tmux = require("switchyard.tmux")
local sessions = require("switchyard.sessions")

local M = {}

-- Look every 500 ms for an agent process in `pane`, up to 30 seconds.
-- callback(session), or callback(nil) when none showed up.
local function wait_for_pane(pane, callback)
	local tries = 0
	local function look()
		tries = tries + 1
		sessions.refresh(function()
			for _, s in ipairs(sessions.all()) do
				if s.pane == pane then
					return callback(s)
				end
			end
			if tries >= 60 then
				return callback(nil)
			end
			vim.defer_fn(look, 500)
		end)
	end
	look()
end

-- A short tmux session name for an agent in folder `cwd`: "<repo>.<branch>"
-- worktree folders drop the "<repo>." part; at most 32 characters
local function session_name(agent, cwd)
	local folder = vim.fn.fnamemodify(cwd, ":t")
	local branch = folder:match("^[^.]+%.(.+)$") or folder -- ponytail: a repo name with a dot keeps its tail
	return (agent.name .. "-" .. branch):sub(1, 32)
end

-- Start `cmd` for `agent` in a new tmux session in `cwd` (default: the
-- editor's folder). Once the agent runs, it's linked when it's where the
-- editor is (and shown in the viewer); an agent started in another worktree
-- only gets a message.
-- callback(session) is optional.
function M.start(agent, cmd, label, cwd, callback)
	cwd = cwd or vim.fn.getcwd()
	tmux.free_name(session_name(agent, cwd), function(name)
		tmux.new(name, cwd, cmd, function(pane, err)
			if not pane then
				return vim.notify("switchyard: tmux: " .. err, vim.log.levels.ERROR)
			end
			require("switchyard.util").progress(("switchyard: starting %s …"):format(label))

			wait_for_pane(pane, function(s)
				if not s then
					return vim.notify(
						("switchyard: no %s running in tmux session %s. Is `%s` the right command?"):format(
							agent.name,
							name,
							table.concat(cmd, " "):sub(1, 40)
						),
						vim.log.levels.WARN
					)
				end
				-- Compared now, not at launch: the editor may have switched meanwhile
				if s.cwd == vim.fn.getcwd() then
					sessions.link(s)
					require("switchyard.view").sync(true) -- watch it work
				else
					vim.notify("switchyard: started " .. name)
				end
				if callback then
					callback(s)
				end
			end)
		end)
	end)
end

-- `cwd` is optional everywhere: default the editor's folder
function M.new(agent, cwd)
	M.start(agent, agent.cmd, "new " .. agent.name, cwd)
end

-- Fork a running session into `cwd`. The copy starts with a note about where
-- it runs now (the history is full of paths from the original worktree).
function M.fork(source, cwd)
	local here = cwd or vim.fn.getcwd()
	local note = (
		"Note: this session was forked from %s and now runs in %s. "
		.. "Absolute paths in the history refer to the original worktree; work in the new one."
	):format(source.cwd, here)
	local cmd = source.agent.fork and source.agent.fork(source, note)
	if not cmd then
		return vim.notify("switchyard: can't fork " .. sessions.describe(source), vim.log.levels.WARN)
	end
	M.start(source.agent, cmd, "fork of " .. sessions.name(source), here)
end

return M
