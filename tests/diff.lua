-- Choosing how to show a worktree's changes. Run: nvim --headless -u NONE --cmd "set rtp+=." -l tests/diff.lua
local config = require("switchyard.config")
local actions = require("switchyard.actions")

-- Without codediff: nothing on "auto"
config.setup({})
assert(actions.diff_viewer() == nil, "no viewer without codediff")

-- Your own function always wins
local seen
config.setup({
	diff = function(worktree)
		seen = worktree
	end,
})
actions.diff_viewer()({ path = "/w", branch = "b", base = "main" })
assert(seen.path == "/w" and seen.base == "main", "custom function called")

-- With codediff installed: :CodeDiff --repo <worktree> <base>
package.preload["codediff"] = function()
	return {}
end
local ran
vim.cmd = setmetatable({}, {
	__call = function(_, cmd)
		ran = cmd
	end,
})
config.setup({})
actions.diff_viewer()({ path = "/w", branch = "b", base = "develop" })
assert(ran.cmd == "CodeDiff" and vim.deep_equal(ran.args, { "--repo", "/w", "develop" }), "codediff command")

-- Turned off
config.setup({ diff = false })
assert(actions.diff_viewer() == nil, "off")

print("diff: ok")
