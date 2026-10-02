-- Starting agents: wait for the agent in its own pane, link when it's here.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/launch.lua
local tmux = require("switchyard.tmux")
local sessions = require("switchyard.sessions")
local launch = require("switchyard.launch")
local agents = require("switchyard.agents")
require("switchyard.config").setup({})

-- No real tmux: "starting" puts an agent in a new pane, and the next
-- snapshot finds it there (after one empty look, like a slow start)
local fake = { name = "fake", cmd = { "fake" }, task = true }
local running, panes, looks = {}, 0, 0
tmux.free_name = function(base, callback)
	callback(base)
end
local started_cmd
tmux.new = function(name, cwd, cmd, callback)
	panes = panes + 1
	started_cmd = cmd
	local pane = "%" .. panes
	table.insert(running, { agent = fake, pid = 100 + panes, pane = pane, tmux = name, cwd = cwd, started = 0 })
	callback(pane)
end
sessions.refresh = function(callback)
	looks = looks + 1
	sessions.update(looks == 1 and {} or vim.deepcopy(running))
	if callback then
		callback()
	end
end
local linked
sessions.link = function(s)
	linked = s
end

local here = vim.fn.getcwd()
local elsewhere = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(elsewhere, "p")

local function start(cmd, cwd)
	local done
	looks = 0
	launch.start(fake, cmd, "fake", cwd, function(s)
		done = s
	end)
	assert(vim.wait(3000, function()
		return done ~= nil
	end, 20), "the agent showed up in its pane")
	return done
end

-- In the editor's folder (the default): links
local s = start({ "fake" }, nil)
assert(s.cwd == here and s.pane == "%1" and linked == s, "links an agent started here")

-- In another worktree: no link
linked = nil
s = start({ "fake" }, elsewhere)
assert(s.cwd == elsewhere and s.pane == "%2" and linked == nil, "doesn't link an agent started elsewhere")

-- A task goes after the command; an agent without `task` can't take one
assert(vim.deep_equal(agents.task_cmd(fake, "do it"), { "fake", "do it" }), "task appended")
assert(agents.task_cmd({ name = "x", cmd = { "x" } }, "do it") == nil, "no task support")
assert(vim.deep_equal(agents.task_cmd({ name = "y", cmd = { "y" }, task = function(t)
	return { "y", "--prompt", t }
end }, "go"), { "y", "--prompt", "go" }), "task as a function")

-- Fork: the note is the copy's first message, in its start command
local source = { agent = { name = "f", cmd = { "f" }, fork = function(session, note)
	return { "f", "--fork", tostring(session.pid), note }
end }, pid = 7, cwd = here, tmux = "f-main", pane = "%7", started = 0 }
launch.fork(source, elsewhere)
vim.wait(1000, function()
	return started_cmd and started_cmd[2] == "--fork"
end, 20)
assert(started_cmd[3] == "7" and started_cmd[4]:find("forked from " .. here, 1, true), "fork note in the command")

-- Agents config: presets by name, own tables, unknown names skipped
require("switchyard.config").setup({ agents = { "pi", { name = "mine", cmd = { "mine" } }, "nope" } })
local names = vim.tbl_map(function(a)
	return a.name
end, agents.configured())
assert(vim.deep_equal(names, { "pi", "mine" }), "configured: " .. table.concat(names, ","))

print("launch: ok")
