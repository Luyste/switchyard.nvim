local M = {}

function M.run(cmd, opts, callback)
	opts = opts or {}
	local started, err = pcall(vim.system, cmd, { text = true, cwd = opts.cwd }, function(res)
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

return M
