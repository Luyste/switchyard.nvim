if vim.g.loaded_switchyard then
	return
end
vim.g.loaded_switchyard = true

-- :Switchyard opens the yard; :Switchyard <folder> switches to a folder
vim.api.nvim_create_user_command("Switchyard", function(args)
	if args.args == "" then
		return require("switchyard").open_yard()
	end
	require("switchyard").switch(vim.fn.expand(args.args))
end, {
	nargs = "?",
	complete = "dir",
	desc = "Open the switchyard yard, or switch to a folder",
})
