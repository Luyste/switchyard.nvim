local M = {}

function M.setup(opts)
	require("switchyard.config").setup(opts)
	require("switchyard.sessions").setup()
end

function M.switch(dir)
	require("switchyard.projects").switch(dir)
end

function M.pick_worktree()
	require("switchyard.pickers").worktrees()
end

function M.pick_agent()
	require("switchyard.sessions").pick()
end

function M.status()
	return require("switchyard.sessions").status()
end

function M.start_agent()
	require("switchyard.launch").pick()
end

function M.open_yard()
	require("switchyard.yard").open()
end

function M.toggle_view()
	require("switchyard.view").toggle()
end

function M.next_agent()
	require("switchyard.view").cycle(1)
end

function M.prev_agent()
	require("switchyard.view").cycle(-1)
end

function M.open_external()
	local s = require("switchyard.sessions").linked()
	if not s then
		return vim.notify("switchyard: no linked agent", vim.log.levels.WARN)
	end
	require("switchyard.view").external(s)
end

return M
