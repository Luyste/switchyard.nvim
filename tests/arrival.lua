-- Arrival rules, peek, and following a moving agent.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/arrival.lua

-- The viewer, faked: what the arrival rules ask of it
local viewer = { open = false, shown = 0, hidden = 0 }
package.loaded["switchyard.view"] = {
	is_open = function()
		return viewer.open
	end,
	sync = function()
		viewer.open, viewer.shown = true, viewer.shown + 1
	end,
	hide = function()
		viewer.open, viewer.hidden = false, viewer.hidden + 1
	end,
}
local sessions = require("switchyard.sessions")
require("switchyard.config").setup({})
sessions.setup()

-- No tmux here: the cache is filled by hand (what a snapshot would find)
sessions.refresh = function(callback)
	if callback then
		callback()
	end
end
local switched_to
require("switchyard.projects").switch = function(dir)
	switched_to = dir
	return true
end

-- resolve: macOS temp dirs are symlinks, getcwd() returns the real path
local function folder()
	local dir = vim.fn.resolve(vim.fn.tempname())
	vim.fn.mkdir(dir, "p")
	return dir
end
local a, b, c = folder(), folder(), folder()

local fake = { name = "fake", cmd = { "fake" } }
local function agent(pid, cwd, started)
	return { pid = pid, cwd = cwd, agent = fake, tmux = "fake-" .. pid, pane = "%" .. pid, started = started or 100 }
end
local agent_a, agent_b = agent(1, a), agent(2, b)
local list = { agent_a, agent_b }
sessions.update(list)

local function arrive(dir)
	vim.cmd.cd(dir)
	vim.wait(50) -- DirChanged, then the arrival rules
end
local function linked()
	return sessions.linked_pid()
end

sessions.link(agent_a, true)

-- Peek into b: the link stays on a
sessions.keep_link_for(b)
arrive(b)
assert(linked() == 1, "peek keeps the link")

-- The hold is used up: a normal arrival in b links b's agent and shows it
arrive(a)
local shown = viewer.shown
arrive(b)
assert(linked() == 2, "normal switch moves the link")
assert(viewer.shown == shown + 1 and viewer.open, "and shows it in the viewer")

-- No agent in c: unlink and close the viewer
arrive(c)
assert(linked() == nil, "no agent: unlinked")
assert(not viewer.open, "no agent: viewer closed")

-- Peek with the viewer open: link and viewer stay, the viewer comes back
arrive(b)
sessions.keep_link_for(c)
arrive(c)
assert(linked() == 2 and viewer.open, "peek keeps link and viewer")

-- A hold for another folder is discarded by the next arrival
sessions.link(agent_a, true)
arrive(a)
sessions.keep_link_for(b)
arrive(c)
arrive(b)
assert(linked() == 2, "stale hold discarded")

-- Several agents in b, linked elsewhere: the most recently started one...
local old_b = agent(3, b, 50)
table.insert(list, old_b)
sessions.update(list)
sessions.link(agent_a, true)
arrive(a)
arrive(b)
assert(linked() == 2, "several: most recently started")

-- ...unless another one was used (shown in the viewer, linked) last
sessions.viewed(old_b.pid)
sessions.link(agent_a, true)
arrive(a)
arrive(b)
assert(linked() == 3, "several: last used wins")

-- Linked to one of them already (the link lives in b, the editor comes from c): keep it
sessions.link(agent_b, true)
arrive(c)
arrive(b)
assert(linked() == 2, "several: keeps a link that is already here")

-- link_here after a peek: takes b's preferred agent (agent_b was linked last)
sessions.link(agent_a, true)
arrive(a)
sessions.keep_link_for(b)
arrive(b)
assert(linked() == 1, "peeked")
sessions.link_here()
assert(linked() == 2, "link_here takes the last used agent here")

-- Following: the linked agent moves to c (a new snapshot shows it there)
sessions.link(agent_a, true)
switched_to = nil
list[1] = agent(1, c)
sessions.update(list)
assert(switched_to == c, "the editor follows a moved linked agent")

-- A snapshot where nothing changed doesn't follow again
switched_to = nil
sessions.update(vim.deepcopy(list))
assert(switched_to == nil, "no change, no follow")

-- An agent that isn't linked moving: nothing to follow
list[2] = agent(2, a)
sessions.update(list)
assert(switched_to == nil, "only the linked agent is followed")

-- The linked session ends: the next snapshot unlinks
sessions.update({ agent_b })
assert(linked() == nil, "ended session unlinked")

print("arrival: ok")
