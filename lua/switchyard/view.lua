local M = {}

-- list: the agents the viewer can show here, as { pid, name } (for the winbar tabs)
local viewer = { buf = nil, win = nil, name = nil, list = {} }

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end
local function valid_buf(buf)
	return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

-- One agent tab: the visible one highlighted, ● before the linked one
local function tab(name, visible, linked)
	local label = (linked and "● " or "") .. name:gsub("%%", "%%%%") -- % is special in a winbar
	return (visible and "%#SwitchyardSelection#" or "%#SwitchyardDim#") .. " " .. label .. " %*"
end

-- The viewer's winbar (a bar on top of the window; unlike a local statusline it
-- also works with a global statusline): agent tabs and a hint. Runs on every
-- redraw, so it only reads cached values (viewer.list, linked_pid), never files.
-- Typing to the agent is the normal state; NORMAL only shows as a warning that
-- keys don't reach the agent.
function M.winbar()
	local focused = vim.api.nvim_get_current_win() == viewer.win
	local normal = focused and vim.api.nvim_get_mode().mode ~= "t"
	local badge = normal and "%#SwitchyardNormalBadge# NORMAL %* " or ""
	local hint = normal and "i type" or ""

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

	return " " .. badge .. table.concat(tabs) .. "%=%#SwitchyardDim#" .. hint .. " %*"
end

-- Window options for a terminal running a full-screen program (tmux), from
-- sidekick.nvim's terminal window (folke/sidekick.nvim,
-- lua/sidekick/cli/terminal.lua, Apache-2.0, see licenses/sidekick.nvim.txt).
-- Columns on the left break the terminal's reflow; wrapping and horizontal
-- scrolling shift what you see. Added here: scrolloff = 0 (a large global
-- value makes the view jump in normal mode).
local terminal_options = {
	colorcolumn = "",
	cursorcolumn = false,
	cursorline = false,
	fillchars = "eob: ",
	list = false,
	number = false,
	relativenumber = false,
	scrolloff = 0,
	sidescrolloff = 0,
	signcolumn = "no",
	statuscolumn = "",
	foldcolumn = "0",
	spell = false,
	wrap = false,
	winfixwidth = true,
}

-- Start typing in the viewer, scrolled fully to the left (sidekick's focus())
local function start_typing()
	vim.fn.winrestview({ leftcol = 0 })
	vim.cmd.startinsert()
end

-- Lines the tabline takes at the top, and the statusline + command line at the bottom
local function editor_edges()
	local tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
	return tabline and 1 or 0, vim.o.cmdheight + (vim.o.laststatus > 0 and 1 or 0)
end

-- layout = "float": the viewer floats on the right, over the editor, full
-- height. zindex 40: below the yard (50) and the menus (100).
local function float_config()
	local top, bottom = editor_edges()
	local width = math.floor(vim.o.columns * require("switchyard.config").options.viewer.width)
	return {
		relative = "editor",
		anchor = "NE",
		row = top,
		col = vim.o.columns,
		width = math.max(width - 2, 20), -- the border takes a column on each side
		height = math.max(vim.o.lines - top - bottom - 2, 5),
		border = "rounded",
		zindex = 40,
	}
end

-- The viewer window on the right: reuse it, or create it. Returns the
-- placeholder buffer a new float starts with (to delete once the terminal is in).
local function open_window()
	if valid_win(viewer.win) then
		vim.api.nvim_set_current_win(viewer.win)
		return
	end
	local options = require("switchyard.config").options.viewer
	local placeholder
	if options.layout == "float" then
		-- A float needs a buffer from the start; attach() puts the terminal in
		placeholder = not valid_buf(viewer.buf) and vim.api.nvim_create_buf(false, true) or nil
		viewer.win = vim.api.nvim_open_win(placeholder or viewer.buf, true, float_config())
	else
		vim.cmd("botright vsplit")
		viewer.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_width(viewer.win, math.floor(vim.o.columns * options.width))
	end
	require("switchyard.ui").set_highlights()
	return placeholder
end

-- Start a terminal attached to tmux session `name`, in the viewer window
local function attach(name)
	local old = viewer.buf
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(viewer.win, buf)
	vim.fn.jobstart(require("switchyard.tmux").attach_cmd(name), { term = true })
	local started = vim.uv.hrtime()
	pcall(vim.api.nvim_buf_set_name, buf, "switchyard://" .. name)
	viewer.buf, viewer.name = buf, name

	-- Scrolling is tmux's job (its own history, mouse on). Neovim keeps no
	-- scrollback of its own, and the wheel in normal mode goes back to typing
	-- and on to tmux, instead of scrolling Neovim's copy of the screen.
	vim.bo[buf].scrollback = 1
	for _, key in ipairs({ "<ScrollWheelUp>", "<ScrollWheelDown>" }) do
		vim.keymap.set("n", key, function()
			vim.cmd.startinsert()
			vim.api.nvim_feedkeys(vim.keycode(key), "n", false)
		end, { buffer = buf })
	end

	-- Entering the viewer goes straight to typing
	vim.api.nvim_create_autocmd("BufEnter", {
		buffer = buf,
		callback = start_typing,
	})
	-- Switching terminal/normal mode doesn't redraw the winbar by itself
	vim.api.nvim_create_autocmd({ "TermEnter", "TermLeave" }, {
		buffer = buf,
		callback = function()
			vim.cmd.redrawstatus()
		end,
	})

	-- The agent's session ended: clean up instead of leaving a dead terminal.
	-- Unless attaching failed right away: keep the error readable (sidekick).
	vim.api.nvim_create_autocmd("TermClose", {
		buffer = buf,
		callback = function()
			if vim.v.event.status ~= 0 and (vim.uv.hrtime() - started) / 1e6 < 3000 then
				return
			end
			vim.schedule(function()
				if viewer.buf == buf then
					if valid_win(viewer.win) then
						pcall(vim.api.nvim_win_close, viewer.win, true)
					end
					viewer.win, viewer.buf, viewer.name = nil, nil, nil
					M.update_bar()
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

-- A tmux session was renamed: the terminal stays attached, only the name changes
function M.renamed(old, new)
	if viewer.name == old then
		viewer.name = new
	end
end

function M.is_open()
	return valid_win(viewer.win)
end

-- Show `agent` ({ name, pid }) in the viewer. focus = false: keep the
-- cursor where it is (for updates the user didn't ask for).
local function show_name(agent, focus)
	local from = vim.api.nvim_get_current_win()
	local placeholder = open_window()
	if viewer.name == agent.name and valid_buf(viewer.buf) then
		vim.api.nvim_win_set_buf(viewer.win, viewer.buf)
	else
		attach(agent.name)
	end
	if placeholder then
		vim.api.nvim_buf_delete(placeholder, { force = true })
	end
	require("switchyard.sessions").viewed(agent.pid)
	-- Window-local options set here only stick to the buffer in the window at that
	-- moment, so set them after the buffer is in place. %! re-evaluates on every redraw.
	for option, value in pairs(terminal_options) do
		vim.api.nvim_set_option_value(option, value, { win = viewer.win, scope = "local" })
	end
	vim.wo[viewer.win].winbar = "%!v:lua.require'switchyard.view'.winbar()"
	-- NormalFloat:Normal: a floating viewer has the editor's background, like the split
	vim.wo[viewer.win].winhighlight = "WinBar:StatusLine,WinBarNC:StatusLineNC,NormalFloat:Normal"
	M.update_bar()
	if focus == false then
		vim.api.nvim_set_current_win(from)
	else
		start_typing()
	end
end

-- The agents the viewer can show here: the linked one first, then the others
-- in this worktree. Stores them in viewer.list (for the tabs).
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
	viewer.list = vim.tbl_map(function(s)
		return { pid = s.pid, name = s.tmux }
	end, candidates)
	callback(viewer.list, linked)
end

-- Update the tabs while the viewer is open
local function refresh()
	if valid_win(viewer.win) then
		viewable(function()
			vim.cmd.redrawstatus()
		end)
	end
end

-- Show the linked agent without taking focus. Only while
-- the viewer is open, or with `reopen` (a worktree switch closed the viewer).
function M.sync(reopen)
	if not reopen and not valid_win(viewer.win) then
		return
	end
	viewable(function(list, linked)
		local target
		if list[1] and linked and list[1].pid == linked.pid then
			target = list[1]
		elseif reopen and list[1] then
			-- The linked agent isn't viewable: the one shown before, if still here
			target = list[1]
			for _, agent in ipairs(list) do
				if agent.name == viewer.name then
					target = agent
				end
			end
		end
		if target and (target.name ~= viewer.name or not valid_win(viewer.win)) then
			show_name(target, false)
		else
			vim.cmd.redrawstatus()
		end
	end)
end

vim.api.nvim_create_autocmd("User", { pattern = "SwitchyardSessionsChanged", callback = refresh })
vim.api.nvim_create_autocmd("User", {
	pattern = "SwitchyardLinkChanged",
	callback = function()
		M.sync(false)
	end,
})
vim.api.nvim_create_autocmd("DirChanged", { pattern = "global", callback = refresh })
-- A floating viewer keeps its place and size when the editor is resized
vim.api.nvim_create_autocmd("VimResized", {
	callback = function()
		if valid_win(viewer.win) and vim.api.nvim_win_get_config(viewer.win).relative ~= "" then
			vim.api.nvim_win_set_config(viewer.win, float_config())
		end
		M.update_bar()
	end,
})
-- The bar: every snapshot (the state moves on) and every link change
vim.api.nvim_create_autocmd("User", {
	pattern = { "SwitchyardSessionsUpdated", "SwitchyardLinkChanged" },
	callback = function()
		M.update_bar()
	end,
})

-- Show `session` in the viewer
function M.show(session)
	show_name({ name = session.tmux, pid = session.pid })
	refresh()
end

function M.hide()
	if not valid_win(viewer.win) then
		return
	end
	local others = vim.tbl_filter(function(win)
		return win ~= viewer.win and vim.api.nvim_win_get_config(win).relative == ""
	end, vim.api.nvim_tabpage_list_wins(0))
	if #others == 0 then
		-- The last window can't be hidden (E444): turn it into an empty editor
		-- window instead. The agent's terminal stays loaded in the background.
		vim.cmd.stopinsert()
		vim.api.nvim_win_set_buf(viewer.win, vim.api.nvim_create_buf(true, false))
	else
		vim.api.nvim_win_hide(viewer.win)
	end
	viewer.win = nil
	M.update_bar()
end

-- Jump between the viewer and the editor, in terminal and normal mode.
-- In the viewer: back to the window you came from. Elsewhere: into the viewer
-- (typing right away), opening it first when it's hidden.
function M.focus()
	local current = vim.api.nvim_get_current_win()
	if current == viewer.win then
		vim.cmd.stopinsert() -- also ends terminal mode; a window change alone doesn't always
		local previous = vim.fn.win_getid(vim.fn.winnr("#"))
		if previous ~= 0 and previous ~= viewer.win then
			return vim.api.nvim_set_current_win(previous)
		end
		return vim.cmd("wincmd p")
	end
	if not valid_win(viewer.win) then
		return M.toggle()
	end
	vim.api.nvim_set_current_win(viewer.win)
	start_typing()
end

-- Cmd+J: hide the viewer, or show the linked agent (or one from this worktree)
function M.toggle()
	if valid_win(viewer.win) then
		return M.hide()
	end

	viewable(function(list, linked)
		if #list == 0 then
			return vim.notify("switchyard: no agent here. Start one from the yard.", vim.log.levels.WARN)
		end
		-- The linked agent comes first
		if linked or #list == 1 then
			return show_name(list[1])
		end

		require("switchyard.menu").open({
			title = "show which agent?",
			items = vim.tbl_map(function(agent)
				return {
					label = agent.name,
					action = function()
						show_name(agent)
					end,
				}
			end, list),
		})
	end)
end

---------------------------------------------------------------------------
-- The bar (viewer.bar): the linked agent and its state while the viewer is closed
---------------------------------------------------------------------------

local bar = { buf = nil, win = nil }
local bar_ns = vim.api.nvim_create_namespace("switchyard_bar")

-- Show, update or remove the bar: a one-line float in the bottom-right
-- corner, `● name  working`. Clicking it opens the viewer.
function M.update_bar()
	local sessions = require("switchyard.sessions")
	local linked = sessions.linked()
	if not require("switchyard.config").options.viewer.bar or valid_win(viewer.win) or not linked then
		if valid_win(bar.win) then
			vim.api.nvim_win_close(bar.win, true)
		end
		bar.win = nil
		return
	end

	local name = sessions.name(linked)
	if vim.fn.strchars(name) > 30 then
		name = vim.fn.strcharpart(name, 0, 29) .. "…"
	end
	local state = sessions.state(linked)
	local text = " ● " .. name .. "  " .. state .. " "
	if not valid_buf(bar.buf) then
		bar.buf = vim.api.nvim_create_buf(false, true)
		-- focusable = false keeps the bar out of <C-w>w; mouse = true still lets a
		-- click enter it: go back and open the viewer
		vim.api.nvim_create_autocmd("BufEnter", {
			buffer = bar.buf,
			callback = function()
				vim.schedule(function()
					vim.cmd("wincmd p")
					if not valid_win(viewer.win) then
						M.toggle()
					end
				end)
			end,
		})
	end
	vim.api.nvim_buf_set_lines(bar.buf, 0, -1, false, { text })
	vim.api.nvim_buf_clear_namespace(bar.buf, bar_ns, 0, -1)
	vim.api.nvim_buf_set_extmark(bar.buf, bar_ns, 0, 1, {
		end_col = 1 + #"●",
		hl_group = state == "working" and "SwitchyardLinked" or "SwitchyardDim",
	})

	local _, bottom = editor_edges()
	local config = {
		relative = "editor",
		anchor = "SE",
		row = vim.o.lines - bottom, -- just above the statusline
		col = vim.o.columns,
		width = vim.fn.strdisplaywidth(text),
		height = 1,
		style = "minimal",
		focusable = false,
		mouse = true,
		zindex = 40,
	}
	if valid_win(bar.win) then
		vim.api.nvim_win_set_config(bar.win, config)
	else
		require("switchyard.ui").set_highlights()
		bar.win = vim.api.nvim_open_win(bar.buf, false, config)
		vim.wo[bar.win].winhighlight = "NormalFloat:StatusLine"
	end
end

-------------------------------------------------------------------------
-- External terminals
---------------------------------------------------------------------------

local is_mac = vim.fn.has("mac") == 1

local function mac_app(name)
	return is_mac and vim.fn.isdirectory("/Applications/" .. name .. ".app") == 1
end

-- Terminals that open a window running a command: their macOS app (started
-- with `open -na App.app --args ...`) or program, and the arguments before the
-- command. Terminal.app is scripted with osascript instead.
local terminals = {
	ghostty = { app = "Ghostty", bin = "ghostty", app_args = { "--quit-after-last-window-closed=true", "-e" }, args = { "-e" } },
	kitty = { app = "kitty", bin = "kitty", app_args = {}, args = { "--detach" } },
	wezterm = { app = "WezTerm", bin = "wezterm", app_args = { "start", "--" }, args = { "start", "--" } },
	alacritty = { app = "Alacritty", bin = "alacritty", app_args = { "-e" }, args = { "-e" } },
}

local auto_order = { "ghostty", "kitty", "wezterm", "alacritty", "terminal.app" }

local function available(name)
	if name == "terminal.app" then
		return is_mac
	end
	local t = terminals[name]
	return mac_app(t.app) or vim.fn.executable(t.bin) == 1
end

-- The command that opens terminal `name` running `cmd`
local function command(name, cmd)
	if name == "terminal.app" then
		local line = table.concat(vim.tbl_map(vim.fn.shellescape, cmd), " ")
		return {
			"osascript",
			"-e",
			('tell application "Terminal" to do script %q'):format(line),
			"-e",
			'tell application "Terminal" to activate',
		}
	end
	local t = terminals[name]
	if mac_app(t.app) then
		return vim.list_extend({ "open", "-na", t.app .. ".app", "--args", unpack(t.app_args) }, cmd)
	end
	return vim.list_extend({ t.bin, unpack(t.args) }, cmd)
end

-- The terminal to use: its name, or nil and an error message
function M.terminal_name()
	local choice = require("switchyard.config").options.terminal
	if type(choice) == "function" then
		return "custom"
	end
	if choice ~= "auto" then
		if terminals[choice] or choice == "terminal.app" then
			return choice
		end
		return nil, "unknown terminal '" .. tostring(choice) .. "'"
	end
	for _, name in ipairs(auto_order) do
		if available(name) then
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
	return command(name, cmd)
end

-- Open `session` in a new external terminal window
function M.external(session)
	local attach = { vim.fn.exepath("tmux"), "attach-session", "-t", "=" .. session.tmux }
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
end
return M
