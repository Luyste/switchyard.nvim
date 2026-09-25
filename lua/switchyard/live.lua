-- Live reload: open files follow changes made outside Neovim (by an agent),
-- also while you're typing in a terminal, where 'autoread' never checks.
local M = {}

-- One watcher per folder that holds a loaded file: dir -> { handle, count }.
-- A folder watcher also sees files replaced by rename (how many tools save).
local folders = {}
-- The folder each watched buffer counts towards: buf -> dir
local buf_folder = {}
-- Paths changed since the last reload, and whether a reload is scheduled
local changed, pending = {}, false

-- Reload the loaded buffers whose file changed. Buffers with unsaved changes
-- are left alone: Neovim warns about those itself (W12) when you return.
local function reload()
	pending = false
	local paths = changed
	changed = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_loaded(buf)
			and paths[vim.api.nvim_buf_get_name(buf)]
			and not vim.bo[buf].modified
		then
			vim.cmd("checktime " .. buf)
		end
	end
end

local function watch(buf)
	if buf_folder[buf] or vim.bo[buf].buftype ~= "" then
		return
	end
	local name = vim.api.nvim_buf_get_name(buf)
	if name == "" then
		return
	end
	local dir = vim.fs.dirname(name)
	local folder = folders[dir]
	if not folder then
		local handle = vim.uv.new_fs_event()
		-- Runs in a fast context: only plain Lua here, the reload is deferred
		local ok = handle:start(dir, {}, function(err, filename)
			if err or not filename then
				return
			end
			changed[dir .. "/" .. filename] = true
			if not pending then
				pending = true
				vim.defer_fn(reload, 100) -- a burst of writes becomes one reload
			end
		end)
		if not ok then -- e.g. the folder doesn't exist (yet)
			handle:close()
			return
		end
		folder = { handle = handle, count = 0 }
		folders[dir] = folder
	end
	folder.count = folder.count + 1
	buf_folder[buf] = dir
end

local function unwatch(buf)
	local dir = buf_folder[buf]
	if not dir then
		return
	end
	buf_folder[buf] = nil
	local folder = folders[dir]
	folder.count = folder.count - 1
	if folder.count == 0 then
		folder.handle:stop()
		folder.handle:close()
		folders[dir] = nil
	end
end

function M.setup()
	local group = vim.api.nvim_create_augroup("switchyard_live", { clear = true })
	-- BufWritePost: a new file only exists (and can be watched) once saved
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
		group = group,
		callback = function(args)
			watch(args.buf)
		end,
	})
	vim.api.nvim_create_autocmd("BufUnload", {
		group = group,
		callback = function(args)
			unwatch(args.buf)
		end,
	})
	-- Renamed (:saveas, :file): watch the new folder instead
	vim.api.nvim_create_autocmd("BufFilePost", {
		group = group,
		callback = function(args)
			unwatch(args.buf)
			watch(args.buf)
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) then
			watch(buf)
		end
	end
end

-- How many folders are being watched (for tests)
function M.watched_count()
	return vim.tbl_count(folders)
end

return M
