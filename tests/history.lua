-- Earlier sessions of a folder (for `c` in the yard), read from a fake home.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/history.lua
local home = vim.fn.tempname()
vim.env.HOME = home
vim.fn.mkdir(home .. "/repo.feat", "p")
local cwd = vim.uv.fs_realpath(home .. "/repo.feat")
local presets = require("switchyard.agents").presets

local function write(path, lines, time)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(vim.tbl_map(vim.json.encode, lines), path)
	vim.uv.fs_utime(path, time, time)
end

-- Claude Code: titles near the end; a session without one is left out
local claude = home .. "/.claude/projects/" .. cwd:gsub("[^%w]", "-") .. "/"
write(claude .. "old.jsonl", { { type = "user" }, { type = "ai-title", aiTitle = "Old work" } }, 1000)
write(claude .. "new.jsonl", {
	{ type = "ai-title", aiTitle = "AI title" },
	{ type = "custom-title", customTitle = "My name" },
}, 2000)
write(claude .. "empty.jsonl", { { type = "user" } }, 3000)
local list = presets.claude.history(cwd, {})
assert(#list == 2, "claude: " .. #list)
assert(list[1].title == "My name" and list[1].cmd[3] == "new", vim.inspect(list[1]))
assert(list[2].title == "Old work", vim.inspect(list[2]))

-- pi: the first prompt is the title; running sessions (the newest) are left out
local pi = home .. "/.pi/agent/sessions/--" .. cwd:gsub("^/", ""):gsub("[/:]", "-") .. "--/"
local function prompt(text)
	return { type = "message", message = { role = "user", content = { { type = "text", text = text } } } }
end
write(pi .. "a.jsonl", { { type = "session" }, prompt("first task") }, 1000)
write(pi .. "b.jsonl", { { type = "session" }, prompt("live task") }, 2000)
list = presets.pi.history(cwd, { {} })
assert(#list == 1 and list[1].title == "first task", vim.inspect(list))
assert(list[1].cmd[2] == "--session" and list[1].cmd[3] == pi .. "a.jsonl")

print("history: ok")
