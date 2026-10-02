-- The prompt builder: a small floating input for writing a prompt to an agent,
-- plus "contexts": code selections (and diagnostics) that go along with it.
-- The draft (text + contexts) survives closing; the window disappears as soon
-- as focus goes elsewhere.
local ui = require("switchyard.ui")

local M = {}

local MAX_HEIGHT = 8
local ns = vim.api.nvim_create_namespace("switchyard_prompt")

local state = {
	buf = nil, -- the draft text (a hidden buffer)
	win = nil, -- the input window
	header = nil, -- the context list above it (only when there are contexts)
	header_buf = nil,
	-- { path, first, last, filetype, lines, diagnostics, source_buf },
	-- or a whole file: { path, whole = true, source_buf }
	contexts = {},
	origin_buf = nil, -- the buffer the builder was opened from (Ctrl-F adds it)
	target = nil, -- a chosen agent for this prompt (Ctrl-T, the yard's `s`); nil = the linked one
	dispatch = false, -- the target is a new worktree with a new agent (dispatch)
	shown = nil, -- the target as the title shows it (looked up on open/choose, not per keystroke)
}

local layout -- defined below; declared here so the context functions can call it

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

-- Where this prompt goes: the chosen agent while it runs, else the linked one
local function target()
	local chosen = state.target
	if chosen then
		for _, s in ipairs(require("switchyard.sessions").all()) do
			if s.pid == chosen.pid then
				return s
			end
		end
		state.target = nil -- it ended
	end
	return require("switchyard.sessions").linked()
end

local function title()
	local head = { " prompt ", "SwitchyardHeading" }
	if state.dispatch then
		return { head, { "→ ", "SwitchyardDim" }, { "new worktree + agent ", "SwitchyardHeading" }, { "(dispatch) ", "SwitchyardDim" } }
	end
	local s = state.shown
	if not s then
		return { head, { "→ no linked agent (link one in the yard, or ^T) ", "SwitchyardDanger" } }
	end
	local linked = s.pid == require("switchyard.sessions").linked_pid()
	local parts = {
		head,
		{ "→ ", "SwitchyardDim" },
		{ require("switchyard.sessions").name(s) .. " ", linked and "SwitchyardLinked" or "SwitchyardAgent" },
		{ linked and "(linked) " or "", "SwitchyardDim" },
	}
	if s.cwd ~= vim.fn.getcwd() then
		table.insert(parts, { "(in " .. vim.fn.fnamemodify(s.cwd, ":t") .. ") ", "SwitchyardDim" })
	end
	return parts
end

---------------------------------------------------------------------------
-- Contexts
---------------------------------------------------------------------------

-- `path` as the agent should read it: relative to its folder when it's in
-- there, otherwise absolute (never relative to the wrong checkout)
local function path_for(path, s)
	local root = s and s.cwd
	if root and path:sub(1, #root + 1) == root .. "/" then
		return path:sub(#root + 2)
	end
	return path
end

-- One header line: `file.go:12-14 (3 lines)` / `file.go:40 + 2 diagnostics`
local function describe(c)
	if c.whole then
		return path_for(c.path, state.shown) .. " (whole file)"
	end
	local range = c.first == c.last and tostring(c.first) or (c.first .. "-" .. c.last)
	local name = path_for(c.path, state.shown)
	local extra = #c.diagnostics > 0 and (" + " .. #c.diagnostics .. " diagnostic" .. (#c.diagnostics > 1 and "s" or ""))
		or (" (" .. (c.last - c.first + 1) .. " lines)")
	return name .. ":" .. range .. extra
end

local function add(buf, first, last, diagnostics)
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" then
		return vim.notify("switchyard: save the file first, so the agent can find it", vim.log.levels.WARN)
	end
	table.insert(state.contexts, {
		path = path,
		first = first,
		last = last,
		filetype = vim.bo[buf].filetype,
		lines = vim.api.nvim_buf_get_lines(buf, first - 1, last, false), -- as you saw it now
		diagnostics = diagnostics or {},
		source_buf = buf,
	})
end

-- Visual mode: add the selected lines
function M.add_selection()
	local a, b = vim.fn.line("v"), vim.fn.line(".")
	add(vim.api.nvim_get_current_buf(), math.min(a, b), math.max(a, b))
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
end

-- Normal mode: add the current line with its diagnostics
function M.add_line()
	local buf, line = vim.api.nvim_get_current_buf(), vim.fn.line(".")
	local diagnostics = vim.tbl_map(function(d)
		return { severity = vim.diagnostic.severity[d.severity], message = d.message }
	end, vim.diagnostic.get(buf, { lnum = line - 1 }))
	add(buf, line, line, diagnostics)
end

-- Ctrl-F: the whole file the builder was opened from (once)
local function add_file()
	local buf = state.origin_buf
	if not (buf and vim.api.nvim_buf_is_valid(buf)) or vim.bo[buf].buftype ~= "" then
		return vim.notify("switchyard: no file to add", vim.log.levels.WARN)
	end
	local path = vim.api.nvim_buf_get_name(buf)
	if path == "" then
		return vim.notify("switchyard: save the file first, so the agent can find it", vim.log.levels.WARN)
	end
	for _, c in ipairs(state.contexts) do
		if c.whole and c.path == path then
			return
		end
	end
	table.insert(state.contexts, { path = path, whole = true, source_buf = buf })
	layout()
end

-- While the builder is open, the context ranges light up in their buffers
local function highlight(on)
	for _, c in ipairs(state.contexts) do
		if vim.api.nvim_buf_is_valid(c.source_buf) then
			vim.api.nvim_buf_clear_namespace(c.source_buf, ns, 0, -1)
		end
	end
	if not on then
		return
	end
	for _, c in ipairs(state.contexts) do
		if not c.whole and vim.api.nvim_buf_is_valid(c.source_buf) then
			local count = vim.api.nvim_buf_line_count(c.source_buf)
			if c.first <= count then
				vim.api.nvim_buf_set_extmark(c.source_buf, ns, c.first - 1, 0, {
					end_row = math.min(c.last, count),
					hl_group = "Visual",
					hl_eol = true,
				})
			end
		end
	end
end

-- The message: the prompt first, then each context with its code
local function message(s)
	local out = { draft_text() }
	for _, c in ipairs(state.contexts) do
		table.insert(out, "")
		if c.whole then
			-- The agent reads the file itself: the path is enough
			table.insert(out, "File: " .. path_for(c.path, s))
			goto continue
		end
		local range = c.first == c.last and tostring(c.first) or (c.first .. "-" .. c.last)
		table.insert(out, ("From %s:%s:"):format(path_for(c.path, s), range))
		table.insert(out, "```" .. c.filetype)
		vim.list_extend(out, c.lines)
		table.insert(out, "```")
		for _, d in ipairs(c.diagnostics) do
			table.insert(out, ("- %s: %s"):format(d.severity, d.message))
		end
		::continue::
	end
	return vim.trim(table.concat(out, "\n"))
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------

-- Size and place the windows: the input as high as its text (wrapped), up to
-- MAX_HEIGHT, low in the middle of the screen; the context list right above it
layout = function()
	if not valid_win(state.win) then
		return
	end
	local width = math.min(80, vim.o.columns - 6)
	local height = 0
	for _, line in ipairs(vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)) do
		height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
	end
	height = math.max(1, math.min(height, MAX_HEIGHT))
	local row = math.max(1, math.floor(vim.o.lines * 0.7) - height)
	local col = math.floor((vim.o.columns - width) / 2)

	local has_header = #state.contexts > 0
	vim.api.nvim_win_set_config(state.win, {
		relative = "editor",
		width = width,
		height = height + 1 + (has_header and 0 or 1), -- + hints (+ title when there's no list)
		row = row,
		col = col,
	})
	-- The target goes on top: of the context list when there is one
	if has_header then
		vim.wo[state.win].winbar = ""
	else
		ui.title(state.win, title())
	end
	ui.hints(state.buf, " ⏎ send  ⇧⏎ new line  ^O hand over  ^T target  ^F file  ^D remove")

	if not has_header then
		if valid_win(state.header) then
			vim.api.nvim_win_close(state.header, true)
		end
		state.header = nil
		return
	end
	if not (state.header_buf and vim.api.nvim_buf_is_valid(state.header_buf)) then
		state.header_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.header_buf].bufhidden = "hide"
	end
	local lines = vim.tbl_map(function(c)
		return " " .. describe(c)
	end, state.contexts)
	vim.api.nvim_buf_set_lines(state.header_buf, 0, -1, false, lines)
	local header_height = math.min(#lines, 6) + 1 -- + the title line
	local config = {
		relative = "editor",
		width = width,
		height = header_height,
		row = math.max(0, row - header_height - 2),
		col = col,
	}
	if valid_win(state.header) then
		vim.api.nvim_win_set_config(state.header, config)
	else
		state.header = vim.api.nvim_open_win(
			state.header_buf,
			false,
			vim.tbl_extend("force", config, { style = "minimal", border = "rounded", focusable = false })
		)
		vim.wo[state.header].winhighlight = "Normal:SwitchyardDim"
	end
	ui.title(state.header, title())
end

function M.close()
	for _, win in pairs({ input = state.win, header = state.header }) do
		if valid_win(win) then
			vim.api.nvim_win_close(win, true)
		end
	end
	state.win, state.header = nil, nil
	highlight(false)
	vim.cmd.stopinsert()
	vim.cmd("redrawstatus") -- the DRAFT marker
end

local function clear()
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {})
	highlight(false)
	state.contexts = {}
	layout()
	vim.cmd("redrawstatus") -- the DRAFT marker
end

-- A branch name from the task's first line: "Add dark mode!" -> "add-dark-mode"
function M.slug(text)
	local first = (text:match("[^\n]+") or ""):lower()
	local slug = first:gsub("[^%w]+", "-"):gsub("^%-+", ""):sub(1, 40):gsub("%-+$", "")
	return slug
end

-- Dispatch: create a worktree, start an agent there with the prompt as its
-- task. The editor and the link stay where they are.
local function dispatch()
	local text = draft_text()
	if text == "" then
		return vim.notify("switchyard: write the task first", vim.log.levels.WARN)
	end
	local cwd = vim.fn.getcwd()
	M.close()
	require("switchyard.menu").input({ title = "dispatch: branch for the task", default = M.slug(text) }, function(branch)
		if not branch or branch == "" then
			return M.open() -- back to the draft
		end
		require("switchyard.actions").with_agent(function(agent)
			local agents = require("switchyard.agents")
			if not agents.task_cmd(agent, "") then
				return vim.notify("switchyard: " .. agent.name .. " can't start with a task", vim.log.levels.WARN)
			end
			require("switchyard.util").progress("switchyard: creating " .. branch .. " …")
			require("switchyard.worktrees").create(cwd, branch, function(path, err)
				if not path then
					return vim.notify("switchyard: " .. err, vim.log.levels.ERROR)
				end
				-- Contexts come from this worktree: absolute paths for the new one
				local task = message({ cwd = path })
				require("switchyard.launch").start(agent, agents.task_cmd(agent, task), "task on " .. branch, path)
				clear()
				state.dispatch = false
			end)
		end)
	end)
end

-- Send the draft to the target; cleared once it's sent
function M.send()
	if state.dispatch then
		return dispatch()
	end
	local s = target()
	if draft_text() == "" and #state.contexts == 0 then
		return
	end
	if not s then
		return vim.notify("switchyard: no linked agent. Link one in the yard first.", vim.log.levels.WARN)
	end
	local name = require("switchyard.sessions").name(s)
	require("switchyard.sessions").send(s, message(s), function(ok, err)
		if not ok then
			return vim.notify("switchyard: couldn't send to " .. name .. ": " .. tostring(err), vim.log.levels.ERROR)
		end
		clear()
		state.target = nil -- the next prompt goes to the linked agent again
		M.close()
		vim.cmd("redraw")
		vim.notify("switchyard: sent to " .. name)
	end)
end

-- Ctrl-D: choose a context to drop
local function remove_context()
	if #state.contexts == 0 then
		return
	end
	require("switchyard.menu").open({
		title = "remove which context?",
		items = vim.tbl_map(function(c)
			return {
				label = describe(c),
				action = function()
					highlight(false)
					state.contexts = vim.tbl_filter(function(other)
						return other ~= c
					end, state.contexts)
					highlight(true)
					layout()
				end,
			}
		end, state.contexts),
	})
end

-- Ctrl-T: send this prompt to another agent of this repo (the link stays)
local function choose_target()
	local sessions = require("switchyard.sessions")
	require("switchyard.worktrees").list(vim.fn.getcwd(), function(worktrees)
		local branch_of = {}
		for _, wt in ipairs(worktrees or {}) do
			branch_of[wt.path] = wt.branch
		end
		local agents = vim.tbl_filter(function(s)
			return branch_of[s.cwd] ~= nil
		end, sessions.all())
		local items = vim.tbl_map(function(s)
			return {
				label = require("switchyard.sessions").name(s) .. " · " .. branch_of[s.cwd],
				key = s.pid == sessions.linked_pid() and "linked" or nil,
				action = function()
					state.target, state.shown, state.dispatch = s, s, false
					layout()
				end,
			}
		end, agents)
		table.insert(items, {
			label = "new worktree + agent (dispatch)",
			action = function()
				state.dispatch = true
				layout()
			end,
		})
		require("switchyard.menu").open({ title = "send this prompt to", items = items })
	end)
end

-- Ctrl-O: hand the prompt over: paste it into the agent's own input,
-- without sending, and show the agent so you can finish it there
local function hand_over()
	if state.dispatch then
		return vim.notify("switchyard: a dispatch has no agent yet to hand over to", vim.log.levels.WARN)
	end
	local s = target()
	if draft_text() == "" and #state.contexts == 0 then
		return
	end
	if not s then
		return vim.notify("switchyard: no target agent", vim.log.levels.WARN)
	end
	require("switchyard.tmux").paste(s.pane, message(s), function(ok, err)
		if not ok then
			return vim.notify("switchyard: tmux: " .. tostring(err), vim.log.levels.ERROR)
		end
		clear()
		state.target = nil
		M.close()
		require("switchyard.view").show(s)
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
	map({ "i", "n" }, "<C-d>", remove_context)
	map({ "i", "n" }, "<C-f>", add_file)
	map({ "i", "n" }, "<C-t>", choose_target)
	map({ "i", "n" }, "<C-o>", hand_over)
	map("n", "<C-x>", clear)
end

-- Open the builder (or focus it), typing right away
function M.open()
	local current = vim.api.nvim_get_current_buf()
	if current ~= state.buf then
		state.origin_buf = current
	end
	state.shown = target()
	if valid_win(state.win) then
		layout()
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
	})
	vim.wo[state.win].wrap = true
	vim.wo[state.win].linebreak = true
	layout()
	highlight(true)

	if fresh then
		vim.b[buf].switchyard_mapped = true
		set_keymaps(buf)
		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = layout })
		-- Gone as soon as focus goes elsewhere (a menu on top of it doesn't count)
		vim.api.nvim_create_autocmd("WinLeave", {
			buffer = buf,
			callback = function()
				vim.schedule(function()
					local current = vim.api.nvim_get_current_win()
					local to_menu = vim.bo[vim.api.nvim_win_get_buf(current)].filetype == "switchyard"
					if valid_win(state.win) and current ~= state.win and not to_menu then
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

-- Open the builder aimed at `session` for this prompt (the link stays)
function M.open_for(session)
	state.target, state.dispatch = session, false
	M.open()
end

-- Open the builder for a dispatch: the prompt becomes a new agent's task
function M.open_dispatch()
	state.dispatch = true
	M.open()
end

-- For statuslines: "DRAFT" (+ number of contexts) while a draft waits and the
-- builder is hidden. No I/O.
function M.draft_status()
	if valid_win(state.win) or (draft_text() == "" and #state.contexts == 0) then
		return ""
	end
	return #state.contexts > 0 and ("DRAFT " .. #state.contexts) or "DRAFT"
end

return M
