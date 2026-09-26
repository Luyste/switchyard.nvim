local M = {}

function M.setup(opts)
	require("switchyard.config").setup(opts)
	require("switchyard.sessions").setup()
	if require("switchyard.config").options.live_reload then
		require("switchyard.live").setup()
	end
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

-- Show the file the agent just changed (on/off; nil toggles)
function M.follow_edits(on)
	require("switchyard.live").follow_edits(on)
end

-- For statuslines: is following edits on? Cheap, no I/O.
function M.following_edits()
	return package.loaded["switchyard.live"] ~= nil and require("switchyard.live").following_edits()
end

-- The prompt builder: write a prompt for the linked agent (the draft is kept)
function M.prompt()
	require("switchyard.prompt").open()
end

-- For statuslines: "DRAFT" while a prompt draft waits. Cheap, no I/O.
function M.draft_status()
	return package.loaded["switchyard.prompt"] and require("switchyard.prompt").draft_status() or ""
end

function M.link_here()
	require("switchyard.sessions").link_here()
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

-- Jump between the viewer and the editor (opens the viewer when hidden)
function M.focus_view()
	require("switchyard.view").focus()
end

function M.open_external()
	local s = require("switchyard.sessions").linked()
	if not s then
		return vim.notify("switchyard: no linked agent", vim.log.levels.WARN)
	end
	require("switchyard.view").external(s)
end

return M
