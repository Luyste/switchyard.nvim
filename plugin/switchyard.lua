if vim.g.loaded_switchyard then
	return
end
vim.g.loaded_switchyard = true

vim.api.nvim_create_user_command("Switchyard", function()
	require("switchyard").open_yard()
end, { desc = "Open the switchyard yard" })
