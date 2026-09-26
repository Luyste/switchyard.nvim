local M = {}

function M.run(cmd, opts, callback)
	opts = opts or {}
	local started, err = pcall(vim.system, cmd, { text = true, cwd = opts.cwd, stdin = opts.stdin }, function(res)
		vim.schedule(function()
			callback(res.code == 0, res.stdout or "", res.stderr or "")
		end)
	end)

	if not started then
		vim.schedule(function()
			callback(false, "", tostring(err))
		end)
	end
end

-- A progress message: not kept in :messages, and cut to the width that's left,
-- because a message that wraps makes Neovim wait for "Press ENTER"
function M.progress(text)
	vim.api.nvim_echo({ { vim.fn.strcharpart(text, 0, math.max(vim.v.echospace, 20)) } }, false, {})
end

return M
