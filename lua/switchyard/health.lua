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

	vim.health.start("switchyard: integrations")
	local integrations = require("switchyard.integrations")
	for _, name in ipairs(integrations.names) do
		if require("switchyard.config").options.integrations[name] == false then
			vim.health.info(name .. ": disabled")
		elseif integrations.active(name) then
			vim.health.ok(name .. ": active")
		else
			vim.health.info(name .. ": not installed (optional)")
		end
	end
end

return M
