-- The yard: opening and closing, fuzzy filtering, projects, a plain folder.
-- Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/yard.lua
vim.opt.rtp:prepend(vim.fn.getcwd()) -- the test cds away: "." would point elsewhere
require("switchyard").setup({})
local yard = require("switchyard.yard")

local function floats()
	return #vim.tbl_filter(function(w)
		return vim.api.nvim_win_get_config(w).relative ~= ""
	end, vim.api.nvim_list_wins())
end

local editor = vim.api.nvim_get_current_win()
require("switchyard").open_yard() -- the public function, as mapped in a config
assert(yard.is_open() and floats() == 1, "opens one window")
yard.close()
assert(not yard.is_open() and floats() == 0, "closes its window")
assert(vim.api.nvim_get_current_win() == editor, "back in the window it was opened from")

yard.open()
yard.open() -- again while open: focuses it, no second window
assert(floats() == 1, "no second yard")
yard.close()

-- A repo with two worktrees, and two more folders
local root = vim.fn.resolve(vim.fn.tempname())
local function git(dir, ...)
	local res = vim.system(vim.list_extend({ "git", "-C", dir }, { ... }), { text = true }):wait()
	assert(res.code == 0, table.concat({ ... }, " ") .. ": " .. (res.stderr or ""))
end
for _, dir in ipairs({ "repo", "other", "notes" }) do
	vim.fn.mkdir(root .. "/" .. dir, "p")
end
git(root .. "/repo", "init", "-q", "-b", "main")
git(root .. "/repo", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init")
git(root .. "/repo", "worktree", "add", "-q", "-b", "feature/login-form", root .. "/repo.login")
git(root .. "/repo", "worktree", "add", "-q", "-b", "fix-tests", root .. "/repo.fix")
vim.cmd.cd(root .. "/repo")

-- No agents, no fd, no history here
require("switchyard.sessions").all = function()
	return {}
end
local projects = require("switchyard.projects")
projects.find = function(on_found, on_done)
	on_found(root .. "/other")
	on_done()
end
projects.recent = function()
	return {}
end
projects.cached = function()
	return {}
end
require("switchyard.config").options.projects.pinned = { root .. "/notes" }

local yard_win -- below
local function shown()
	return table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(yard_win()), 0, -1, false), "|")
end
yard_win = function()
	for _, w in ipairs(vim.api.nvim_list_wins()) do
		local config = vim.api.nvim_win_get_config(w)
		if config.relative ~= "" and config.height > 1 then
			return w
		end
	end
end
local function shows(pattern)
	assert(vim.wait(3000, function()
		return shown():find(pattern) ~= nil
	end, 20), "expected " .. pattern .. " in: " .. shown())
end
local function press(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "x", false)
end
-- Typing in the filter line (TextChangedI doesn't fire for fed keys)
local function filter(text)
	press("/" .. text)
	vim.api.nvim_exec_autocmds("TextChangedI", { buffer = vim.api.nvim_get_current_buf() })
end
local function count()
	local buf = vim.api.nvim_get_current_buf()
	local marks = vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })
	for _, m in ipairs(marks) do
		local virt = m[4].virt_text
		if virt and virt[1][1]:find("/") then
			return vim.trim(virt[1][1])
		end
	end
end

yard.open()
shows("feature/login%-form")
press("2") -- agents, then back with Tab Tab (agents → projects → worktrees)
shows("No agents running")
press("<Tab><Tab>")
shows("feature/login%-form")
-- Fuzzy: "flf" matches feature/login-form (letters in order), not fix-tests
filter("flf")
assert(count() == "1 / 3", tostring(count()))
assert(shown():find("login") and not shown():find("fix%-tests"), shown())
press("A<Esc>") -- fed keys leave insert mode: back in, then Esc clears the filter
shows("fix%-tests")

-- 3: projects (the current one, pinned, then what fd finds)
press("3")
shows("other")
assert(shown():find("@ repo") and shown():find("notes"), shown())
filter("oth")
assert(count() == "1 / 3", tostring(count()))
press("A<Esc>")
yard.close()

-- Outside git: the folder itself is the one worktree
vim.cmd.cd(root .. "/notes")
yard.open()
press("1") -- worktrees (the yard remembered projects)
shows("@ notes")
yard.close()

print("yard: ok")
