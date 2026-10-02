-- Optional plugins. Each integration is a module here with `available()` and
-- `setup()`; it's used when enabled in `config.integrations` and installed.
local M = {}

M.names = { "sidekick" }

-- Enabled in the config and installed
function M.active(name)
	return require("switchyard.config").options.integrations[name] ~= false
		and require("switchyard.integrations." .. name).available()
end

function M.setup()
	for _, name in ipairs(M.names) do
		if M.active(name) then
			require("switchyard.integrations." .. name).setup()
		end
	end
end

return M
