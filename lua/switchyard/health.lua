local M = {}

-- Check that a program is installed, and show its version
local function check_program(name, version_args, advice)
	if vim.fn.executable(name) == 0 then
		vim.health.error(name .. " not found", advice)
		return
	end
	local res = vim.system(vim.list_extend({ name }, version_args), { text = true }):wait()
	local version = vim.trim(((res.stdout or "") .. (res.stderr or "")):match("[^\n]*") or "")
	vim.health.ok(("%s: %s"):format(name, version))
end

function M.check()
	vim.health.start("switchyard: programs")
	check_program("git", { "--version" }, "brew install git")
	check_program("tmux", { "-V" }, "brew install tmux")
	check_program("fzf", { "--version" }, "brew install fzf")

	vim.health.start("switchyard: plugins")
	if pcall(require, "fzf-lua") then
		vim.health.ok("fzf-lua: found (the yard)")
	else
		vim.health.error("fzf-lua not found: the yard needs it", "Install ibhagwan/fzf-lua")
	end

	vim.health.start("switchyard: options")
	local opts = require("switchyard.config").options

	local ok_view, view = pcall(require, "switchyard.view")
	if ok_view then
		local name, err = view.terminal_name()
		if name then
			vim.health.ok("external terminal: " .. name)
		else
			vim.health.warn("external terminal: " .. err, "Set `terminal` in setup()")
		end
	end



	vim.health.start("switchyard: agents")
	local running = {}
	for _, s in ipairs(require("switchyard.sessions").all()) do
		running[s.agent.name] = (running[s.agent.name] or 0) + 1
	end
	local any = false
	for _, agent in ipairs(require("switchyard.agents").configured()) do
		if vim.fn.executable(agent.cmd[1]) == 1 then
			any = true
			vim.health.ok(("%s: installed, %d running in tmux"):format(agent.name, running[agent.name] or 0))
		else
			vim.health.info(agent.name .. ": `" .. agent.cmd[1] .. "` not installed")
		end
	end
	if not any then
		vim.health.warn("none of the configured agents is installed", "Install one (pi, claude, codex) or add your own in `agents`")
	end
end

return M
