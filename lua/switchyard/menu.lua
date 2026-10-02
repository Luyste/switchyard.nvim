-- Small questions, in fzf-lua like the yard: a choice from a list
-- (`open`), or one line of text (`input`). Type to filter or edit, Enter
-- confirms, Esc cancels. Focus goes back where it was, typing again when you
-- were typing (the prompt builder).
local M = {}

local function color(hl, text)
	return (require("fzf-lua.utils").ansi_from_hl(hl, text))
end

-- Remember the window (and insert mode) to return to; returns that return
local function remember()
	local from = vim.api.nvim_get_current_win()
	local typing = vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
	vim.cmd.stopinsert()
	return function()
		if vim.api.nvim_win_is_valid(from) then
			vim.api.nvim_set_current_win(from)
			if typing then
				vim.cmd("startinsert!")
			end
		end
	end
end

-- A small fzf-lua window for `count` lines, without preview or border title
-- (Neovide draws over border titles). `done(value)` runs once: with the
-- action's value, or nil when closed without one.
local function show(lines, opts, on_enter, done)
	require("switchyard.ui").set_highlights()
	local back = remember()
	local finished = false
	local function finish(value)
		if finished then
			return
		end
		finished = true
		back()
		done(value)
	end
	local width = 20
	for _, l in ipairs(lines) do
		width = math.max(width, vim.fn.strdisplaywidth((l:gsub("\27%[[%d;]*m", ""):gsub("\t.*$", ""))) + 6)
	end
	require("fzf-lua").fzf_exec(lines, {
		prompt = opts.title .. "❯ ",
		query = opts.default,
		no_hide = true, -- a question is answered or gone, never kept for resume
		previewer = false,
		fzf_opts = vim.tbl_extend("force", {
			["--delimiter"] = "\t",
			["--with-nth"] = "1",
			["--no-multi"] = true,
			["--no-sort"] = true, -- keep the list's order while filtering
		}, opts.fzf_opts or {}),
		actions = {
			enter = function(selected, o)
				local value = on_enter(selected, o)
				vim.schedule(function()
					finish(value)
				end)
			end,
		},
		winopts = {
			title = false,
			height = #lines + 3, -- + prompt, separator and border
			width = math.min(math.max(width, #opts.title + 30), vim.o.columns - 4),
			row = 0.35,
			preview = { hidden = true },
			-- Runs before an action: wait a moment to tell a cancel from a choice
			on_close = function()
				vim.schedule(function()
					vim.schedule(function()
						finish(nil)
					end)
				end)
			end,
		},
	})
end

-- Choose from a list.
-- opts.title: the prompt
-- opts.items: list of { label, action, key? (shown dim after it), danger? }
-- opts.on_cancel: optional, called when closed without choosing
function M.open(opts)
	local lines = {}
	for i, item in ipairs(opts.items) do
		local label = item.danger and color("SwitchyardDanger", item.label) or item.label
		local key = item.key and ("  " .. color("SwitchyardDim", item.key)) or ""
		lines[i] = label .. key .. "\t" .. i
	end
	show(lines, { title = opts.title }, function(selected)
		return tonumber((selected[1] or ""):match("\t(%d+)$"))
	end, function(index)
		local item = index and opts.items[index]
		if item then
			item.action()
		elseif opts.on_cancel then
			opts.on_cancel()
		end
	end)
end

-- Ask for one line of text: the search line is the input (fzf doesn't filter
-- here). opts.title, opts.default. callback(text), or callback(nil) when
-- cancelled.
function M.input(opts, callback)
	show({ color("SwitchyardDim", "⏎ confirm  esc cancel") }, {
		title = opts.title,
		default = opts.default,
		fzf_opts = { ["--disabled"] = true },
	}, function(_, o)
		return vim.trim(o.last_query or "")
	end, callback)
end

return M
