-- Linking after a launch. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/launch.lua
local tmux = require("switchyard.tmux")
local sessions = require("switchyard.sessions")
local launch = require("switchyard.launch")

-- No real tmux: "starting" makes the fake adapter report a session there
local running = {}
local adapter = {
	name = "fake",
	sessions = function()
		return running
	end,
}
tmux.free_name = function(base, callback)
	callback(base)
end
tmux.new = function(_, cwd, _, callback)
	table.insert(running, { adapter = adapter, pid = #running + 100, cwd = cwd })
	callback(true)
end
local linked
sessions.link = function(s)
	linked = s
end

local here = vim.fn.getcwd()
local elsewhere = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(elsewhere, "p")

local function start(cwd)
	local done
	launch.start(adapter, { "fake" }, "fake", cwd, function(s)
		done = s
	end)
	assert(vim.wait(3000, function()
		return done ~= nil
	end, 50), "registered")
	return done
end

-- In the editor's folder (the default): links
local s = start(nil)
assert(s.cwd == here and linked == s, "links an agent started here")

-- In another worktree: no link
linked = nil
s = start(elsewhere)
assert(s.cwd == elsewhere and linked == nil, "doesn't link an agent started elsewhere")

print("launch: ok")
