local M = {}

-- list: the agents the viewer can show here, as { pid, name } (for the statusline tabs)
local viewer = { buf = nil, win = nil, name = nil, list = {} }

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end
local function valid_buf(buf)
	return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

-- The tmux session `session` runs in: callback(name), or a warning if it isn't in tmux
local function with_tmux_name(session, callback)
	local sessions = require("switchyard.sessions")
	local known = sessions.tmux_name(session)
	if known then
		return callback(known)
	end
	require("switchyard.tmux").session_of_pid(session.pid, function(name)
		if not name then
			return vim.notify(
				"switchyard: " .. sessions.describe(session) .. " isn't running in tmux",
				vim.log.levels.WARN
			)
		end
		callback(name)
	end)
end

-- One agent tab: the visible one highlighted, ● before the linked one
local function tab(name, visible, linked)
	local label = (linked and "● " or "") .. name:gsub("%%", "%%%%") -- % is special in a statusline
	return (visible and "%#SwitchyardSelection#" or "%#SwitchyardDim#") .. " " .. label .. " %*"
end

-- The viewer's own statusline: mode, agent tabs, hint. Runs on every redraw,
-- so it only reads cached values (viewer.list, linked_pid), never files.
function M.statusline()
	local focused = vim.api.nvim_get_current_win() == viewer.win
	local terminal = focused and vim.api.nvim_get_mode().mode == "t"
	local badge = terminal and "%#SwitchyardFilterBadge# TERMINAL %*" or "%#SwitchyardNormalBadge# NORMAL %*"
	local hint = terminal and "keys go to the agent" or "i type · q hide"

	local linked = require("switchyard.sessions").linked_pid()
	local tabs, listed = {}, false
	for _, agent in ipairs(viewer.list) do
		listed = listed or agent.name == viewer.name
		table.insert(tabs, tab(agent.name, agent.name == viewer.name, agent.pid == linked))
	end
	-- Shown from the yard, from another worktree: not in the list, still show it
	if not listed and viewer.name then
		table.insert(tabs, 1, tab(viewer.name, true, false))
	end

	return " " .. badge .. " " .. table.concat(tabs) .. "%=%#SwitchyardDim#" .. hint .. " %*"
end

-- The viewer window on the right: reuse it, or create it
local function open_window()
	if valid_win(viewer.win) then
		vim.api.nvim_set_current_win(viewer.win)
		return
	end
	vim.cmd("botright vsplit")
	viewer.win = vim.api.nvim_get_current_win()
	local width = require("switchyard.config").options.viewer.width
	vim.api.nvim_win_set_width(viewer.win, math.floor(vim.o.columns * width))
	vim.wo[viewer.win].winfixwidth = true
	vim.wo[viewer.win].number = false
	vim.wo[viewer.win].relativenumber = false
	vim.wo[viewer.win].signcolumn = "no"
	require("switchyard.ui").set_highlights()
end

-- Start a terminal attached to tmux session `name`, in the viewer window
local function attach(name)
	local old = viewer.buf
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(viewer.win, buf)
	vim.fn.jobstart(require("switchyard.tmux").attach_cmd(name), { term = true })
	pcall(vim.api.nvim_buf_set_name, buf, "switchyard://" .. name)
	viewer.buf, viewer.name = buf, name

	-- `q` in normal mode hides the viewer; entering it goes straight to typing
	vim.keymap.set("n", "q", M.hide, { buffer = buf, nowait = true, silent = true })
	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = buf,
		callback = function()
			vim.cmd.startinsert()
		end,
	})
	-- Switching terminal/normal mode doesn't redraw the statusline by itself
	vim.api.nvim_create_autocmd({ "TermEnter", "TermLeave" }, {
		buffer = buf,
		callback = function()
			vim.cmd.redrawstatus()
		end,
	})

	-- The agent's session ended: clean up instead of leaving a dead terminal
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		callback = function()
			vim.schedule(function()
				if viewer.buf == buf then
					if valid_win(viewer.win) then
						pcall(vim.api.nvim_win_close, viewer.win, true)
					end
					viewer.win, viewer.buf, viewer.name = nil, nil, nil
				end
				if valid_buf(buf) then
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
			end)
		end,
	})

	-- Showing another agent: drop the previous terminal (that only detaches it)
	if valid_buf(old) then
		pcall(vim.api.nvim_buf_delete, old, { force = true })
	end
end

-- Show tmux session `name` in the viewer split
local function show_name(name)
	open_window()
	if viewer.name == name and valid_buf(viewer.buf) then
		vim.api.nvim_win_set_buf(viewer.win, viewer.buf)
	else
		attach(name)
	end
	-- A local statusline only sticks to the buffer it was set with, so set it
	-- after the buffer is in place. %! re-evaluates it on every redraw.
	vim.wo[viewer.win].statusline = "%!v:lua.require'switchyard.view'.statusline()"
	vim.cmd.startinsert()
end

-- The agents the viewer can show here: the linked one first, then the others
-- in this worktree, only those running in tmux. Stores them in viewer.list.
-- callback(list of { pid, name }, linked session or nil)
local function viewable(callback)
	local sessions = require("switchyard.sessions")
	local linked = sessions.linked()
	local candidates = linked and { linked } or {}
	for _, s in ipairs(sessions.in_folder(vim.fn.getcwd())) do
		if not linked or s.pid ~= linked.pid then
			table.insert(candidates, s)
		end
	end
	local pids = vim.tbl_map(function(s)
		return s.pid
	end, candidates)
	require("switchyard.tmux").sessions_for_pids(pids, function(names)
		viewer.list = {}
		for _, s in ipairs(candidates) do
			if names[s.pid] then
				table.insert(viewer.list, { pid = s.pid, name = names[s.pid] })
			end
		end
		callback(viewer.list, linked)
	end)
end

-- Update the tabs while the viewer is open
local function refresh()
	if valid_win(viewer.win) then
		viewable(function()
			vim.cmd.redrawstatus()
		end)
	end
end

vim.api.nvim_create_autocmd("User", { pattern = "SwitchyardSessionsChanged", callback = refresh })
vim.api.nvim_create_autocmd("DirChanged", { pattern = "global", callback = refresh })

-- Show `session` in the viewer split
function M.show(session)
	with_tmux_name(session, function(name)
		show_name(name)
		refresh()
	end)
end

function M.hide()
	if valid_win(viewer.win) then
		vim.api.nvim_win_hide(viewer.win)
		viewer.win = nil
	end
end

-- Cmd+J: hide the viewer, or show the linked agent (or one from this worktree)
function M.toggle()
	if valid_win(viewer.win) then
		return M.hide()
	end

	viewable(function(list, linked)
		if #list == 0 then
			return vim.notify("switchyard: no agent here runs in tmux. Start one from the yard.", vim.log.levels.WARN)
		end
		-- The linked agent comes first when it runs in tmux
		local linked_shown = linked and list[1].pid == linked.pid
		if linked and not linked_shown then
			vim.notify("switchyard: the linked agent isn't in tmux, showing another one here")
		end
		if linked_shown or #list == 1 then
			return show_name(list[1].name)
		end

		require("switchyard.menu").open({
			title = "show which agent?",
			items = vim.tbl_map(function(agent)
				return {
					label = agent.name,
					action = function()
						show_name(agent.name)
					end,
				}
			end, list),
		})
	end)
end

-------------------------------------------------------------------------
-- External terminals
---------------------------------------------------------------------------

local is_mac = vim.fn.has("mac") == 1

local function mac_app(name)
	return is_mac and vim.fn.isdirectory("/Applications/" .. name .. ".app") == 1
end

-- `open -na App.app --args ...` starts a new instance of a macOS app with arguments
local function mac_open(app, args)
	return vim.list_extend({ "open", "-na", app .. ".app", "--args" }, args)
end

local terminals = {
	ghostty = {
		available = function()
			return mac_app("Ghostty") or vim.fn.executable("ghostty") == 1
		end,
		command = function(cmd)
			if mac_app("Ghostty") then
				return mac_open("Ghostty", vim.list_extend({ "--quit-after-last-window-closed=true", "-e" }, cmd))
			end
			return vim.list_extend({ "ghostty", "-e" }, cmd)
		end,
	},
	kitty = {
		available = function()
			return mac_app("kitty") or vim.fn.executable("kitty") == 1
		end,
		command = function(cmd)
			if mac_app("kitty") then
				return mac_open("kitty", cmd)
			end
			return vim.list_extend({ "kitty", "--detach" }, cmd)
		end,
	},
	wezterm = {
		available = function()
			return mac_app("WezTerm") or vim.fn.executable("wezterm") == 1
		end,
		command = function(cmd)
			if mac_app("WezTerm") then
				return mac_open("WezTerm", vim.list_extend({ "start", "--" }, cmd))
			end
			return vim.list_extend({ "wezterm", "start", "--" }, cmd)
		end,
	},
	alacritty = {
		available = function()
			return mac_app("Alacritty") or vim.fn.executable("alacritty") == 1
		end,
		command = function(cmd)
			if mac_app("Alacritty") then
				return mac_open("Alacritty", vim.list_extend({ "-e" }, cmd))
			end
			return vim.list_extend({ "alacritty", "-e" }, cmd)
		end,
	},
	["terminal.app"] = {
		available = function()
			return is_mac
		end,
		command = function(cmd)
			local line = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
			return {
				"osascript",
				"-e",
				('tell application "Terminal" to do script %q'):format(line),
				"-e",
				'tell application "Terminal" to activate',
			}
		end,
	},
}

local auto_order = { "ghostty", "kitty", "wezterm", "alacritty", "terminal.app" }

-- The terminal to use: its name, or nil and an error message
function M.terminal_name()
	local choice = require("switchyard.config").options.terminal
	if type(choice) == "function" then
		return "custom"
	end
	if choice ~= "auto" then
		if terminals[choice] then
			return choice
		end
		return nil, "unknown terminal '" .. tostring(choice) .. "'"
	end
	for _, name in ipairs(auto_order) do
		if terminals[name].available() then
			return name
		end
	end
	return nil, "no supported terminal found"
end

-- The full command that opens a terminal window running `cmd`
local function terminal_command(cmd)
	local choice = require("switchyard.config").options.terminal
	if type(choice) == "function" then
		return choice(cmd)
	end
	local name, err = M.terminal_name()
	if not name then
		return nil, err
	end
	return terminals[name].command(cmd)
end

-- Open `session` in a new external terminal window
function M.external(session)
	with_tmux_name(session, function(name)
		local attach = { vim.fn.exepath("tmux"), "attach-session", "-t", "=" .. name }
		local cmd, err = terminal_command(attach)
		if not cmd then
			return vim.notify("switchyard: " .. err .. ". Set `terminal` in setup().", vim.log.levels.WARN)
		end
		vim.system(cmd, {}, function(res)
			if res.code ~= 0 then
				vim.schedule(function()
					vim.notify("switchyard: couldn't open a terminal: " .. (res.stderr or ""), vim.log.levels.ERROR)
				end)
			end
		end)
	end)
end
return M
