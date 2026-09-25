local M = {}

-- Adapters from the `agents` option whose program is installed
function M.active()
	local list = {}
	for _, name in ipairs(require("switchyard.config").options.agents) do
		local ok, adapter = pcall(require, "switchyard.adapters." .. name)
		-- An empty or unfinished adapter file returns `true` instead of a table: skip it
		if ok and type(adapter) == "table" and vim.fn.executable(adapter.cmd) == 1 then
			table.insert(list, adapter)
		end
	end
	return list
end

return M
