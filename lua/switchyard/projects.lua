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
	M.remember(dir)

	-- Tell the user's config, so it can open a file tree etc.
	vim.api.nvim_exec_autocmds("User", {
		pattern = "SwitchyardSwitched",
		data = { from = from, to = dir },
	})

	-- `only` closed the viewer: the arrival rules (on DirChanged) bring it back
	-- with the agent of this folder, or leave it closed
	return true
end

---------------------------------------------------------------------------
-- Finding projects: git repos under the roots, pinned folders, recent ones
---------------------------------------------------------------------------

local function state_file(name)
	return vim.fn.stdpath("state") .. "/switchyard/" .. name
end

local function read_list(name)
	local ok, list = pcall(function()
		return vim.json.decode(table.concat(vim.fn.readfile(state_file(name)), ""))
	end)
	return ok and type(list) == "table" and list or {}
end

local function write_list(name, list)
	vim.fn.mkdir(vim.fn.fnamemodify(state_file(name), ":h"), "p")
	vim.fn.writefile({ vim.json.encode(list) }, state_file(name))
end

-- The project a folder belongs to: a linked worktree's main repo (its `.git`
-- file says "gitdir: <repo>/.git/worktrees/<name>"), else the folder itself
function M.root(dir)
	local ok, lines = pcall(vim.fn.readfile, dir .. "/.git", "", 1)
	local gitdir = ok and lines[1] and lines[1]:match("^gitdir: (.+)/%.git/worktrees/[^/]+$")
	return gitdir or dir
end

-- Remember a project the editor went to (newest first, at most 50)
function M.remember(dir)
	local root = M.root(dir)
	local list = vim.tbl_filter(function(p)
		return p ~= root
	end, read_list("recent.json"))
	table.insert(list, 1, root)
	write_list("recent.json", vim.list_slice(list, 1, 50))
end

function M.recent()
	return read_list("recent.json")
end

-- The projects found last time (shown at once while fd looks again)
function M.cached()
	return read_list("projects.json")
end

-- Look for git repos under the configured roots with fd: on_found(path) per
-- repo as fd finds it, on_done() at the end (the result is cached)
function M.find(on_found, on_done)
	local opts = require("switchyard.config").options.projects
	local cmd = { "fd", "--hidden", "--no-ignore", "--type", "d", "--prune", "--glob", ".git" }
	for _, root in ipairs(opts.roots) do
		table.insert(cmd, vim.fn.expand(root))
	end
	for _, pattern in ipairs(opts.exclude) do
		vim.list_extend(cmd, { "--exclude", pattern })
	end
	local found, rest = {}, ""
	local function take(text)
		rest = rest .. text
		while true do
			local line, after = rest:match("^([^\n]*)\n(.*)$")
			if not line then
				return
			end
			rest = after
			local path = line:gsub("/%.git/?$", "")
			if path ~= "" then
				table.insert(found, path)
				on_found(path)
			end
		end
	end
	local ok = pcall(vim.system, cmd, {
		text = true,
		stdout = function(_, data)
			if data then
				vim.schedule(function()
					take(data)
				end)
			end
		end,
	}, function()
		vim.schedule(function()
			write_list("projects.json", found)
			on_done()
		end)
	end)
	if not ok then
		vim.notify("switchyard: fd not found (needed to find projects)", vim.log.levels.WARN)
		on_done()
	end
end

return M
