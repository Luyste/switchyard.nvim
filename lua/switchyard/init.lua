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

-- The prompt builder: write a prompt for the linked agent (the draft is kept).
-- In visual mode the selected lines are added as context first.
function M.prompt()
	local prompt = require("switchyard.prompt")
	if vim.fn.mode():match("^[vV\22]") then
		prompt.add_selection()
	end
	prompt.open()
end

-- Dispatch: write a task for a new agent in a new worktree (in visual mode the
-- selection comes along as context). The editor and the link stay put.
function M.dispatch()
	local prompt = require("switchyard.prompt")
	if vim.fn.mode():match("^[vV\22]") then
		prompt.add_selection()
	end
	prompt.open_dispatch()
end

-- Add the current line and its diagnostics to the prompt, and open it
function M.prompt_line()
	local prompt = require("switchyard.prompt")
	prompt.add_line()
	prompt.open()
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
