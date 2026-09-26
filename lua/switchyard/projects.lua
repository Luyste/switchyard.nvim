local M = {}

-- Listed file buffers with unsaved changes
local function unsaved_buffers()
	local found = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buflisted and vim.bo[buf].modified then
			table.insert(found, buf)
		end
	end
	return found
end

-- Move this editor to `dir`, closing the previous folder's files.
-- Returns true when it switched (or was already there), false when blocked.
function M.switch(dir)
	dir = vim.fn.fnamemodify(dir, ":p"):gsub("/$", "")
	local from = vim.fn.getcwd()
	if dir == from then
		return true
	end

	-- redraw first: a pending screen update (the yard closing) would wipe the message
	if vim.fn.isdirectory(dir) == 0 then
		vim.cmd("redraw")
		vim.notify("switchyard: folder doesn't exist: " .. dir, vim.log.levels.ERROR)
		return false
	end

	local unsaved = unsaved_buffers()
	if #unsaved > 0 then
		vim.cmd("redraw")
		vim.notify(
			("switchyard: unsaved changes in %s. Save first."):format(vim.fn.bufname(unsaved[1])),
			vim.log.levels.WARN
		)
		return false
	end

	local viewer_open = require("switchyard.view").is_open()

	-- Back to a single window with an empty buffer. A fresh window, because the
	-- current one may be a file tree, a terminal or a float: `only` + `enew`
	-- there would keep that window and replace its buffer.
	vim.cmd("silent! tabonly")
	vim.cmd("botright new")
	vim.cmd("silent! only")

	-- Close the old folder's files (terminals and other special buffers stay)
	local keep = vim.api.nvim_get_current_buf()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= keep and vim.bo[buf].buflisted and vim.bo[buf].buftype == "" then
			vim.api.nvim_buf_delete(buf, {})
		end
	end

	-- Language servers for the old folder aren't needed anymore
	for _, client in ipairs(vim.lsp.get_clients()) do
		client:stop()
	end

	vim.cmd.cd(dir)
	vim.notify("switchyard: " .. vim.fn.fnamemodify(dir, ":~"))

	-- Tell the user's config, so it can open a file tree etc.
	vim.api.nvim_exec_autocmds("User", {
		pattern = "SwitchyardSwitched",
		data = { from = from, to = dir },
	})

	-- `only` closed the viewer: bring it back once the arrival rules have run
	-- (they're scheduled from DirChanged, so this runs after them)
	if viewer_open then
		vim.schedule(function()
			require("switchyard.view").sync(true)
		end)
	end
	return true
end

return M
