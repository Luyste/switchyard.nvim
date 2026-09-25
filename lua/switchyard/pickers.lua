local worktrunk = require("switchyard.worktrunk")
local projects = require("switchyard.projects")

local M = {}

local function format(wt)
	local marker = wt.current and "@ " or "  "
	local symbols = wt.symbols ~= "" and ("  " .. wt.symbols) or ""
	return marker .. wt.branch .. symbols .. "   " .. vim.fn.fnamemodify(wt.path, ":~")
end

local function switch_later(path)
	-- Let the picker close completely before touching windows
	vim.schedule(function()
		projects.switch(path)
	end)
end

local function create(cwd)
	vim.ui.input({ prompt = "New branch: " }, function(branch)
		if not branch or branch == "" then
			return
		end
		vim.api.nvim_echo({ { "switchyard: creating " .. branch .. " …" } }, false, {})
		worktrunk.create(cwd, branch, function(path, err)
			if not path then
				return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
			end
			projects.switch(path)
		end)
	end)
end

local function remove(cwd, wt, reopen)
	if wt.current then
		return vim.notify("switchyard: you're in this worktree. Switch away first.", vim.log.levels.WARN)
	end
	if wt.main then
		return vim.notify("switchyard: the main worktree can't be removed.", vim.log.levels.WARN)
	end
	if vim.fn.confirm("Remove worktree " .. wt.branch .. "?", "&Yes\n&No", 2) ~= 1 then
		return
	end
	worktrunk.remove(cwd, wt.branch, function(ok, err)
		if not ok then
			return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
		end
		vim.notify("switchyard: removed " .. wt.branch)
		reopen()
	end)
end

-- With fzf-lua: fuzzy search plus keys for new and remove
local function pick_with_fzf(worktrees, cwd)
	local keys = require("switchyard.config").options.keys.picker
	local lines, by_line = {}, {}
	for _, wt in ipairs(worktrees) do
		local line = format(wt)
		table.insert(lines, line)
		by_line[line] = wt
	end

	require("fzf-lua").fzf_exec(lines, {
		prompt = "Worktrees> ",
		fzf_opts = { ["--header"] = "enter: switch · alt-n: new · alt-d: remove" },
		actions = {
			["enter"] = function(selected)
				local wt = by_line[selected[1]]
				if wt then
					switch_later(wt.path)
				end
			end,
			[keys.new_worktree] = function()
				vim.schedule(function()
					create(cwd)
				end)
			end,
			[keys.remove_worktree] = function(selected)
				local wt = by_line[selected[1]]
				if wt then
					vim.schedule(function()
						remove(cwd, wt, M.worktrees)
					end)
				end
			end,
		},
	})
end

-- Without fzf-lua: a plain list, switching only
local function pick_with_select(worktrees)
	vim.ui.select(worktrees, { prompt = "Worktrees", format_item = format }, function(wt)
		if wt then
			switch_later(wt.path)
		end
	end)
end

function M.worktrees()
	local cwd = vim.fn.getcwd()
	worktrunk.list(cwd, function(worktrees, err)
		if not worktrees then
			return vim.notify("switchyard: " .. (err ~= "" and err or "wt list failed"), vim.log.levels.WARN)
		end
		if pcall(require, "fzf-lua") then
			pick_with_fzf(worktrees, cwd)
		else
			pick_with_select(worktrees)
		end
	end)
end

return M
