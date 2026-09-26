-- Arrival rules and peek. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/arrival.lua
local sessions = require("switchyard.sessions")
require("switchyard.config").setup({ follow = false })
sessions.setup()

-- resolve: macOS temp dirs are symlinks, getcwd() returns the real path
local a = vim.fn.resolve(vim.fn.tempname())
local b = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(a, "p")
vim.fn.mkdir(b, "p")

-- Fake agents: one in a (linked), one in b
local agent_a = { pid = 1, cwd = a, adapter = { name = "fake" }, started = "2026-01-01T10:00" }
local agent_b = { pid = 2, cwd = b, adapter = { name = "fake" }, started = "2026-01-01T10:00" }
local agents = { agent_a, agent_b }
sessions.in_folder = function(dir)
	return vim.tbl_filter(function(s)
		return s.cwd == dir
	end, agents)
end
sessions.linked = function()
	return sessions._link
end
sessions.link = function(s)
	sessions._link = s
end
sessions._link = agent_a

local function arrive(dir)
	vim.cmd.cd(dir)
	vim.wait(100) -- on_arrival is scheduled
end

-- Peek into b: the link stays on a
sessions.keep_link_for(b)
arrive(b)
assert(sessions._link == agent_a, "peek keeps the link")

-- The hold is used up: a normal arrival in b links b's agent
arrive(a)
arrive(b)
assert(sessions._link == agent_b, "normal switch moves the link")

-- A hold for another folder is discarded by the next arrival
local c = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(c, "p")
sessions._link = agent_a
arrive(a)
sessions.keep_link_for(b)
arrive(c)
arrive(b)
assert(sessions._link == agent_b, "stale hold discarded")

-- Several agents in b, linked elsewhere: the most recently started one...
local old_b = { pid = 3, cwd = b, adapter = { name = "fake" }, started = "2026-01-01T09:00" }
table.insert(agents, old_b)
sessions._link = agent_a
arrive(a)
arrive(b)
assert(sessions._link == agent_b, "several: most recently started")

-- ...unless the viewer showed another one last
sessions.viewed(old_b.pid)
sessions._link = agent_a
arrive(a)
arrive(b)
assert(sessions._link == old_b, "several: last viewed wins")

-- Linked to one of them already (the link lives in b, the editor comes from c): keep it
sessions._link = agent_b
arrive(c)
arrive(b)
assert(sessions._link == agent_b, "several: keeps a link that is already here")

print("arrival: ok")
