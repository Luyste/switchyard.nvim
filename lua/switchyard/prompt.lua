-- The prompt builder: a small floating input for writing a prompt to an agent.
-- The draft lives in one hidden buffer, so it survives closing; the window
-- disappears as soon as focus goes elsewhere.
local ui = require("switchyard.ui")

local M = {}

local MAX_HEIGHT = 8

local state = { buf = nil, win = nil }

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

-- The draft buffer, created once
local function draft_buf()
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		return state.buf
	end
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].bufhidden = "hide" -- keep the draft while no window shows it
	vim.bo[buf].filetype = "markdown"
	state.buf = buf
	return buf
end

local function draft_text()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return ""
	end
	return vim.trim(table.concat(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false), "\n"))
end

-- Where prompts go: the linked agent
local function target()
	return require("switchyard.sessions").linked()
end

local function title()
	local sessions = require("switchyard.sessions")
	local s = target()
	if not s then
		return { { " → no linked agent (link one in the yard) ", "SwitchyardDanger" } }
	end
	local parts = { { " → ", "SwitchyardDim" }, { (sessions.tmux_name(s) or s.adapter.name) .. " ", "SwitchyardLinked" } }
	if s.cwd ~= vim.fn.getcwd() then
		table.insert(parts, { "(in " .. vim.fn.fnamemodify(s.cwd, ":t") .. ") ", "SwitchyardDim" })
	end
	return parts
end

-- Size and place the window: as wide as fits, as high as the text (wrapped),
-- up to MAX_HEIGHT; low in the middle of the screen
local function layout()
	if not valid_win(state.win) then
		return
	end
	local width = math.min(80, vim.o.columns - 6)
	local height = 0
	for _, line in ipairs(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
	end
	height = math.max(1, math.min(height, MAX_HEIGHT))
	vim.api.nvim_win_set_config(state.win, {
		relative = "editor",
		width = width,
		height = height,
		row = math.max(1, math.floor(vim.o.lines * 0.7) - height),
		col = math.floor((vim.o.columns - width) / 2),
		title = title(),
		title_pos = "left",
	})
end

function M.close()
	if valid_win(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	state.win = nil
	vim.cmd.stopinsert()
	vim.cmd("redrawstatus") -- the DRAFT marker
end

-- Send the draft to the target; cleared once it's sent
function M.send()
	local text = draft_text()
	local s = target()
	if text == "" then
		return
	end
	if not s then
		return vim.notify("switchyard: no linked agent. Link one in the yard first.", vim.log.levels.WARN)
	end
	local name = require("switchyard.sessions").tmux_name(s) or s.adapter.name
	s.adapter.send(s, text, function(ok, err)
		if not ok then
			return vim.notify("switchyard: couldn't send to " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
		end
		vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
		M.close()
		vim.cmd("redraw")
		vim.notify("switchyard: sent to " .. name)
	end)
end

local function set_keymaps(buf)
	local function map(modes, key, fn)
		vim.keymap.set(modes, key, fn, { buffer = buf, nowait = true, silent = true })
	end
	-- Chat convention: Enter sends, Shift+Enter (or Ctrl-J) is a new line
	map({ "i", "n" }, "<CR>", M.send)
	map("i", "<S-CR>", "<CR>")
	map("i", "<C-j>", "<CR>")
	-- Esc in insert mode is plain Vim (to normal mode); in normal mode it closes
	map("n", "<Esc>", M.close)
	map("n", "q", M.close)
	map("n", "<C-x>", function()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
	end)
end

-- Open the builder (or focus it), typing right away
function M.open()
	if valid_win(state.win) then
		vim.api.nvim_set_current_win(state.win)
		return vim.cmd("startinsert!")
	end
	ui.set_highlights()
	local buf = draft_buf()
	local fresh = not vim.b[buf].switchyard_mapped
	state.win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = 1,
		col = 1,
		width = 40,
		height = 1,
		style = "minimal",
		border = "rounded",
		footer = { { " ⏎ send  ⇧⏎ new line  esc normal  q close ", "SwitchyardDim" } },
		footer_pos = "left",
	})
	vim.wo[state.win].wrap = true
	vim.wo[state.win].linebreak = true
	layout()

	if fresh then
		vim.b[buf].switchyard_mapped = true
		set_keymaps(buf)
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = layout })
		-- Gone as soon as focus goes elsewhere; the draft stays
		vim.api.nvim_create_autocmd("WinLeave", {
			buffer = buf,
			callback = function()
				vim.schedule(function()
					if valid_win(state.win) and vim.api.nvim_get_current_win() ~= state.win then
						M.close()
					end
				end)
			end,
		})
	end
	local last = vim.api.nvim_buf_line_count(buf)
	vim.api.nvim_win_set_cursor(state.win, { last, #vim.api.nvim_buf_get_lines(buf, last - 1, last, false)[1] })
	vim.cmd("startinsert!") -- typing on at the end of the draft
end

-- For statuslines: "DRAFT" while a draft waits and the builder is hidden. No I/O.
function M.draft_status()
	if valid_win(state.win) or draft_text() == "" then
		return ""
	end
	return "DRAFT"
end

return M
