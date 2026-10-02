-- Finding agents in tmux panes. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/snapshot.lua
local snapshot = require("switchyard.snapshot")

local pi = { name = "pi", cmd = { "pi" } }
local claude = { name = "claude", cmd = { "claude" } }
local agents = { pi, claude }

local panes = table.concat({
	"%0\t100\tpi-main\t1790000000\t/repo",
	"%1\t200\tclaude-main\t1790000100\t/repo",
	"%2\t300\tshell\t1790000200\t/repo",
	"%3\t400\tclaude-feat\t1790000300\t/repo.feat",
	"%4\t999\tgone\t1790000400\t/repo", -- its process isn't in ps
}, "\n")
local ps = table.concat({
	"  100     1 -zsh",
	"  101   100 node /opt/homebrew/bin/pi", -- pi through volta: node runs it...
	"  102   101 pi", -- ...and pi names itself
	"  103   102 node /usr/lib/mcp-server --stdio", -- a helper of pi
	"  200     1 claude",
	"  300     1 -zsh",
	"  301   300 nvim pi.lua", -- not an agent: pi is an argument
	"  302   300 grep pi notes.txt",
	"  400     1 /bin/zsh -l -i -c cd '/repo.feat' && 'claude'; exec /bin/zsh", -- how switchyard starts one
	"  401   400 claude",
}, "\n")

local sessions = snapshot.parse(panes, ps, agents)
local by_pane = {}
for _, s in ipairs(sessions) do
	assert(not by_pane[s.pane], "one session per pane: " .. s.pane)
	by_pane[s.pane] = s
end

assert(#sessions == 3, "three agents: " .. #sessions)
assert(by_pane["%0"].agent == pi and by_pane["%0"].pid == 101, "pi under a wrapper, counted once (the nearest process)")
assert(by_pane["%0"].tmux == "pi-main" and by_pane["%0"].cwd == "/repo", "tmux name and folder")
assert(by_pane["%0"].started == 1790000000, "started = the tmux session's creation time")
assert(by_pane["%1"].agent == claude and by_pane["%1"].pid == 200, "the pane's own process is the agent")
assert(not by_pane["%2"], "a shell with `nvim pi.lua` / `grep pi` is no agent")
assert(by_pane["%3"].pid == 401, "the shell line mentioning claude doesn't count, its claude child does")
assert(not by_pane["%4"], "a pane whose process is gone")

-- A custom pattern decides by itself
local aider = { name = "aider", cmd = { "aider" }, match = "python.*aider" }
local custom = snapshot.parse("%9\t500\tx\t1\t/r", "  500     1 /usr/bin/python3 -m aider --model x", { aider })
assert(#custom == 1 and custom[1].agent == aider, "match pattern")

-- No tmux output at all: nothing, no errors
assert(#snapshot.parse("", ps, agents) == 0, "no panes")

-- For real: an isolated tmux server with a stand-in agent (`sleep`)
if vim.fn.executable("tmux") == 1 then
	local dir = vim.fn.resolve(vim.fn.tempname())
	vim.fn.mkdir(dir, "p")
	vim.env.TMUX_TMPDIR = dir
	vim.system({ "tmux", "new-session", "-d", "-s", "fake-agent", "-c", dir, "sleep", "30" }):wait()
	local got
	snapshot.take({ { name = "sleep", cmd = { "sleep" } } }, function(list)
		got = list
	end)
	vim.wait(5000, function()
		return got ~= nil
	end, 20)
	vim.system({ "tmux", "kill-server" }):wait()
	assert(got and #got == 1, "found the running stand-in: " .. vim.inspect(got))
	assert(got[1].tmux == "fake-agent" and got[1].cwd == dir, "its tmux session and folder")
end

print("snapshot: ok")
