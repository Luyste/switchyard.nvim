-- Which agents run where: one look at tmux and ps, no agent plugins needed.
-- Every tmux pane whose process tree contains an agent becomes a session:
-- { agent, pid, pane, tmux, cwd, started }.
local util = require("switchyard.util")

local M = {}

-- tmux list-panes -a output, one pane per line
M.panes_format = "#{pane_id}\t#{pane_pid}\t#{session_name}\t#{session_created}\t#{pane_current_path}"

-- Programs that run an agent written as a script: `node /opt/homebrew/bin/pi`
local interpreters = { node = true, bun = true, deno = true, python = true, python3 = true, ruby = true }

-- Does command line `command` run `agent`? With agent.match (a Lua pattern)
-- that decides. Otherwise the program must be named like agent.cmd[1], or be
-- an interpreter running a script of that name (so `grep pi` doesn't count).
local function matches(agent, command)
	if agent.match then
		return command:find(agent.match) ~= nil
	end
	local first, second = command:match("^(%S+)%s*(%S*)")
	local name = agent.cmd[1]
	if not first then
		return false
	elseif vim.fs.basename(first) == name then
		return true
	end
	return interpreters[vim.fs.basename(first):gsub("^%-", "")] == true and vim.fs.basename(second) == name
end

-- The sessions in `panes` (list-panes output) given `ps` output
-- (`pid ppid command` per line) and the configured `agents`.
function M.parse(panes, ps, agents)
	local command, children = {}, {}
	for line in ps:gmatch("[^\n]+") do
		local pid, ppid, cmd = line:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
		if pid then
			pid, ppid = tonumber(pid), tonumber(ppid)
			command[pid] = cmd
			children[ppid] = children[ppid] or {}
			table.insert(children[ppid], pid)
		end
	end

	local sessions = {}
	for line in panes:gmatch("[^\n]+") do
		local pane, pane_pid, name, created, path = unpack(vim.split(line, "\t", { plain = true }))
		-- Walk down from the pane's process, nearest first: the first agent found
		-- is the session (its own helper processes below it don't count again)
		local queue, i, found = { tonumber(pane_pid) }, 1, nil
		while queue[i] and not found do
			local pid = queue[i]
			for _, agent in ipairs(agents) do
				if command[pid] and matches(agent, command[pid]) then
					found = { agent = agent, pid = pid }
					break
				end
			end
			vim.list_extend(queue, children[pid] or {})
			i = i + 1
		end
		if found and path then
			table.insert(sessions, {
				agent = found.agent,
				pid = found.pid,
				pane = pane,
				tmux = name,
				cwd = path,
				started = tonumber(created) or 0, -- seconds since 1970
			})
		end
	end
	return sessions
end

-- Take a snapshot now (tmux and ps run side by side): callback(sessions).
-- No tmux server running means no sessions.
function M.take(agents, callback)
	local panes, ps
	local function done()
		if panes and ps then
			callback(M.parse(panes, ps, agents))
		end
	end
	util.run({ "tmux", "list-panes", "-a", "-F", M.panes_format }, {}, function(ok, out)
		panes = ok and out or ""
		done()
	end)
	util.run({ "ps", "-A", "-o", "pid=,ppid=,command=" }, {}, function(_, out)
		ps = out
		done()
	end)
end

return M
