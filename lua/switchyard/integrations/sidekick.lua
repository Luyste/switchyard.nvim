-- sidekick.nvim (folke/sidekick.nvim) runs the agents. A switch closes every
-- window (`only`), sidekick's agent window too: when it was open, bring it
-- back with the agent of the new folder, if one runs there.
local M = {}

function M.available()
	return pcall(require, "sidekick.cli")
end

-- Is sidekick's agent window open? (checked by filetype, no sidekick internals)
local function window_open()
	return vim.iter(vim.api.nvim_list_wins()):any(function(win)
		return vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "sidekick_terminal"
	end)
end

-- An agent runs in the editor's folder (sidekick finds them in tmux/zellij)
local function agent_here()
	local ok, state = pcall(require, "sidekick.cli.state")
	return ok and #state.get({ cwd = true, started = true }) > 0
end

function M.setup()
	local was_open = false
	local group = vim.api.nvim_create_augroup("switchyard_sidekick", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "SwitchyardSwitching",
		callback = function()
			was_open = window_open()
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "SwitchyardSwitched",
		callback = function()
			if not was_open then
				return
			end
			-- After the user's own SwitchyardSwitched handlers (a file tree)
			vim.schedule(function()
				if agent_here() then
					require("sidekick.cli").show({ filter = { cwd = true, started = true }, focus = false })
				end
			end)
		end,
	})
end

return M
