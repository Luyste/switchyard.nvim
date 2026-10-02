local M = {}

function M.setup(opts)
	require("switchyard.config").setup(opts)
	require("switchyard.integrations").setup()
end

-- Move the editor to `dir` (closes the old folder's files). True when it moved.
function M.switch(dir)
	return require("switchyard.projects").switch(dir)
end

function M.open_yard()
	require("switchyard.yard").open()
end

return M
