-- sidekick.nvim (folke/sidekick.nvim) as the viewer's terminal: its terminal
-- window (layout, size, keys and options from your sidekick setup) running
-- `tmux attach` to the agent's session. switchyard still finds, starts and
-- sends to agents itself; sidekick only draws the terminal.
local M = {}

function M.available()
	return pcall(require, "sidekick.cli.terminal")
end

-- A sidekick terminal attached to tmux session `name`, not started yet.
-- `tool`: the agent's name (sidekick's settings for that tool apply, if any).
-- Uses sidekick internals (sidekick.cli.terminal): checked by the health check.
function M.terminal(name, tool, cwd)
	require("sidekick.cli.session").setup() -- registers the terminal backend
	local Terminal = require("sidekick.cli.terminal")
	return Terminal.new({
		id = "switchyard " .. name,
		cwd = cwd,
		tool = require("sidekick.config").get_tool(tool):clone({ cmd = require("switchyard.tmux").attach_cmd(name) }),
	})
end

return M
