-- The Claude Code adapter, against a fake ~/.claude/sessions.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/claude.lua
local home = vim.fn.resolve(vim.fn.tempname())
vim.fn.mkdir(home .. "/.claude/sessions", "p")
vim.env.HOME = home -- before the adapter reads ~
local claude = require("switchyard.adapters.claude")

local me = vim.fn.getpid() -- a pid that is surely running
local function write(name, info)
	vim.fn.writefile({ vim.json.encode(info) }, home .. "/.claude/sessions/" .. name)
end
write(me .. ".json", {
	pid = me,
	sessionId = "abc-123",
	cwd = "/work/repo",
	startedAt = 1790491155326,
	kind = "interactive",
	status = "busy",
})
write("1.json", { pid = 999999, sessionId = "gone", cwd = "/x", kind = "interactive" }) -- not running
write("2.json", { pid = me, sessionId = "print", cwd = "/y", kind = "print" }) -- a `claude -p` run
vim.fn.writefile({ "not json" }, home .. "/.claude/sessions/3.json")
vim.fn.writefile({ "secret" }, home .. "/.claude/sessions/" .. me .. ".abc.key") -- ignored

local list = claude.sessions()
assert(#list == 1, "only the running interactive session: " .. #list)
local s = list[1]
assert(s.pid == me and s.cwd == "/work/repo" and s.session_id == "abc-123", "fields")
assert(s.status == "busy", "status")
assert(s.started == "2026-09-27T06:39:15", "startedAt as ISO: " .. s.started)
assert(s.adapter == claude, "adapter")

assert(vim.deep_equal(claude.fork_cmd(s), { "claude", "--resume", "abc-123", "--fork-session" }), "fork")
assert(vim.deep_equal(claude.task_cmd("do it"), { "claude", "do it" }), "task")
assert(claude.watch_dir == home .. "/.claude/sessions", "watch dir")

print("claude: ok")
