-- Live reload: open files follow changes made outside Neovim (by an agent),
-- also while you're typing in a terminal, where 'autoread' never checks.
local util = require("switchyard.util")

local M = {}

-- One watcher per folder that holds a loaded file: dir -> { handle, count }.
-- A folder watcher also sees files replaced by rename (how many tools save).
local folders = {}
-- The folder each watched buffer counts towards: buf -> dir
local buf_folder = {}
-- Paths changed since the last reload, and whether a reload is scheduled
local changed, pending = {}, false

-- Follow edits: the recursive watcher on the worktree, the changed paths
-- (relative, in order) waiting for the debounce, and the buffer text before
-- live reload replaced it (so the jump can find what changed)
local follow = { handle = nil, root = nil, queue = {}, scheduled = false }
local snapshots = {}

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
			if follow.handle then
				snapshots[vim.api.nvim_buf_get_name(buf)] = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			end
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
	-- Following edits moves along with the editor
	vim.api.nvim_create_autocmd("DirChanged", {
		group = group,
		pattern = "global",
		callback = function()
			if follow.handle then
				stop_following()
				start_following(vim.fn.getcwd())
			end
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

---------------------------------------------------------------------------
-- Follow edits: show the file the agent just changed in the editor window
---------------------------------------------------------------------------

-- The window for files: the current one if it's a normal file window, else the
-- first one (never the viewer, the file tree or a float)
local function editor_window()
	local function ok(win)
		local buf = vim.api.nvim_win_get_buf(win)
		return vim.api.nvim_win_get_config(win).relative == "" and vim.bo[buf].buftype == ""
	end
	local current = vim.api.nvim_get_current_win()
	if ok(current) then
		return current
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if ok(win) then
			return win
		end
	end
end

-- The first line that differs between two texts (lists of lines), or nil
local function first_change(old, new)
	local hunks = vim.diff(table.concat(old, "\n") .. "\n", table.concat(new, "\n") .. "\n", { result_type = "indices" })
	local hunk = hunks[1]
	if hunk then
		return math.max(hunk[3], 1) -- start in the new text (a pure deletion points at the line before)
	end
end

-- Show `path` in the editor window, cursor on the first changed line.
-- `old`: the text before the change, or nil (unknown: cursor stays at the top).
local function show(path, old)
	local new = vim.fn.readfile(path)
	local line = old and first_change(old, new)
	if old and not line then
		return -- nothing changed (e.g. you saved it yourself)
	end
	local win = editor_window()
	if not win or vim.bo[vim.api.nvim_win_get_buf(win)].modified then
		return -- never replace a buffer with unsaved changes
	end
	local buf = vim.fn.bufadd(path)
	if vim.bo[buf].modified then
		return
	end
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	vim.api.nvim_win_set_buf(win, buf) -- without entering the window: focus stays put
	vim.api.nvim_buf_call(buf, function()
		vim.cmd("checktime") -- the buffer may still hold the old text
	end)
	if line then
		vim.api.nvim_win_set_cursor(win, { math.min(line, vim.api.nvim_buf_line_count(buf)), 0 })
		vim.api.nvim_win_call(win, function()
			vim.cmd("normal! zz")
		end)
	end
end

-- The text of `path` before the latest change: live reload's snapshot, the
-- loaded buffer, or git's staged version. callback(lines or nil)
local function old_text(root, rel, callback)
	local path = root .. "/" .. rel
	if snapshots[path] then
		local lines = snapshots[path]
		snapshots[path] = nil
		return callback(lines)
	end
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.api.nvim_buf_get_name(buf) == path then
			return callback(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
		end
	end
	util.run({ "git", "show", ":./" .. rel }, { cwd = root }, function(ok, stdout)
		callback(ok and vim.split(stdout:gsub("\n$", ""), "\n") or nil)
	end)
end

-- After the debounce: drop gitignored and deleted files, show the latest one
local function process()
	follow.scheduled = false
	local root, queue = follow.root, follow.queue
	follow.queue = {}
	local files = vim.tbl_filter(function(rel)
		local stat = vim.uv.fs_stat(root .. "/" .. rel)
		return stat and stat.type == "file"
	end, queue)
	if #files == 0 then
		return
	end
	-- Exit code 1 means "nothing ignored", so read stdout whatever the result
	util.run({ "git", "check-ignore", "--stdin" }, { cwd = root, stdin = table.concat(files, "\n") .. "\n" }, function(_, stdout)
		if root ~= follow.root then
			return -- switched worktree or stopped meanwhile
		end
		local ignored = {}
		for rel in stdout:gmatch("[^\n]+") do
			ignored[rel] = true
		end
		for i = #files, 1, -1 do
			if not ignored[files[i]] then
				local rel = files[i]
				return old_text(root, rel, function(old)
					show(root .. "/" .. rel, old)
				end)
			end
		end
	end)
end

-- libuv can only watch a folder tree recursively on macOS and Windows
local function supported()
	return vim.fn.has("mac") == 1 or vim.fn.has("win32") == 1
end

local function stop_following()
	if follow.handle then
		follow.handle:stop()
		follow.handle:close()
	end
	follow.handle, follow.root, follow.queue, snapshots = nil, nil, {}, {}
end

local function start_following(root)
	local handle = vim.uv.new_fs_event()
	-- Runs in a fast context: only plain Lua here
	local ok = handle:start(root, { recursive = true }, function(err, rel)
		if err or not rel or rel == ".git" or rel:match("^%.git/") then
			return
		end
		table.insert(follow.queue, rel)
		if not follow.scheduled then
			follow.scheduled = true
			vim.defer_fn(process, 150)
		end
	end)
	if not ok then
		handle:close()
		return false
	end
	follow.handle, follow.root = handle, root
	return true
end

-- Turn following edits on or off (nil: toggle)
function M.follow_edits(on)
	if on == nil then
		on = follow.handle == nil
	end
	stop_following()
	if on then
		if not supported() then
			return vim.notify("switchyard: following edits needs macOS or Windows", vim.log.levels.WARN)
		end
		if not start_following(vim.fn.getcwd()) then
			return vim.notify("switchyard: can't watch " .. vim.fn.getcwd(), vim.log.levels.ERROR)
		end
	end
	vim.cmd("redrawstatus")
	vim.notify("switchyard: following edits " .. (on and "on" or "off"))
end

-- For statuslines: cheap, no I/O
function M.following_edits()
	return follow.handle ~= nil
end

M.follow_supported = supported

-- How many folders are being watched (for tests)
function M.watched_count()
	return vim.tbl_count(folders)
end

return M
