if vim.g.loaded_switchyard then
	return
end
vim.g.loaded_switchyard = true

-- :Switchyard opens the yard; :Switchyard <subcommand> runs one
local subcommands = {
	["follow-edits"] = function()
		require("switchyard").follow_edits()
	end,
}

vim.api.nvim_create_user_command("Switchyard", function(args)
	if args.args == "" then
		return require("switchyard").open_yard()
	end
	local run = subcommands[args.args]
	if not run then
		return vim.notify("switchyard: unknown subcommand " .. args.args, vim.log.levels.ERROR)
	end
	run()
end, {
	nargs = "?",
	desc = "Open the switchyard yard, or run a subcommand",
	complete = function()
		return vim.tbl_keys(subcommands)
	end,
})
