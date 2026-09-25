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
	check_program("wt", { "--version" }, "brew install worktrunk && wt config shell install")
	check_program("tmux", { "-V" }, "brew install tmux")

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

	for _, dir in ipairs(opts.projects_dirs) do
		if vim.fn.isdirectory(dir) == 1 then
			vim.health.ok("projects dir: " .. dir)
		else
			vim.health.warn("projects dir doesn't exist: " .. dir, "Fix or remove it in projects_dirs in setup()")
		end
	end

	vim.health.start("switchyard: agents")
	for _, name in ipairs(opts.agents) do
		local ok, adapter = pcall(require, "switchyard.adapters." .. name)
		if not ok or type(adapter) ~= "table" then
			vim.health.info(name .. ": no adapter yet")
		elseif vim.fn.executable(adapter.cmd) == 0 then
			vim.health.warn(name .. ": " .. adapter.cmd .. " not installed")
		else
			local count = #adapter.sessions()
			vim.health.ok(("%s: installed, %d running session(s)"):format(name, count))
			if count == 0 and adapter.hint then
				vim.health.info(adapter.hint)
			end
		end
	end
end

return M
