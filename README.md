# switchyard.nvim

**Switch worktrees and folders without leaving Neovim.**

switchyard is a small Neovim plugin that moves your editor between git
worktrees and project folders. One floating window, the yard, lists the
worktrees of your repo and the folders around it; Enter moves the editor
there, closing the old folder's files and language servers.

It pairs with [sidekick.nvim](https://github.com/folke/sidekick.nvim): run an
agent per worktree with sidekick, switch with switchyard, and sidekick's agent
window follows to the agent of the folder you arrive in.

## Requirements

- **Neovim 0.12+**
- **git**
- Optional: [sidekick.nvim](https://github.com/folke/sidekick.nvim)

Run `:checkhealth switchyard` to see what's found.

## Installation

With the built-in plugin manager (`vim.pack`, Neovim 0.12):

```lua
vim.pack.add({ "https://github.com/Luyste/switchyard.nvim" })
require("switchyard").setup({})
```

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "Luyste/switchyard.nvim",
  opts = {},
}
```

## Keymaps

switchyard sets **no global keymaps**. Map the yard yourself:

```lua
vim.keymap.set("n", "<leader>y", function()
  require("switchyard").open_yard()
end, { desc = "switchyard: the yard" })
```

## The yard

Two views; Tab switches between them.

- **worktrees**: the repo's worktrees. `@` marks the one the editor is in,
  `*` one with uncommitted changes.
- **folders**: the folders around the repo. Repos are marked `git`; plain
  folders end in `/`. Worktree folders are left out (they're listed under
  their repo). Move around like a file tree: `l` looks inside a folder (a repo
  shows its worktrees), `h` goes up.

| Key | Worktrees | Folders |
| --- | --- | --- |
| `Enter` | switch to the worktree | switch to the folder |
| `l` | | look inside (a repo: its worktrees) |
| `h` | the folders around the repo | one folder up |
| `n` | new worktree | |
| `D` | remove worktree (not the current or main one) | |
| `y` | copy the path | copy the path |
| `1`–`9` | switch to row n | switch to row n |
| `/` | filter | filter |
| `.` / `?` | the row's actions / every key | |
| `Tab`, `Ctrl-R`, `q`/`Esc` | other view, refresh, close | |

A new worktree for branch `b` goes next to the main one, as `<repo>.<b>`: an
existing (or remote) branch is checked out, a new one branches off the default
branch. Removing a worktree also deletes its branch when it's merged.

Switching never asks questions: with unsaved changes it refuses, otherwise it
closes every window and file buffer, stops the language servers and `cd`s.
`:Switchyard <folder>` (with folder completion) switches without the yard.

## sidekick.nvim

When sidekick's agent window was open, it comes back after a switch, showing
the agent that runs in the new folder (if one does). Turn it off with
`integrations = { sidekick = false }`.

## Configuration

The defaults:

```lua
require("switchyard").setup({
  yard = {
    view = "worktrees", -- the view the yard opens in: "worktrees" or "folders"
  },
  integrations = {
    sidekick = true, -- used when installed
  },
  keys = {
    yard = { -- inside the yard
      activate = "<CR>", enter = "l", up = "h", toggle_view = "<Tab>",
      filter = "/", refresh = "<C-r>", close = "q", actions = ".", help = "?",
      new = "n", remove = "D", copy_path = "y",
    },
  },
})
```

## Commands and events

- `:Switchyard` opens the yard; `:Switchyard <folder>` switches to a folder.
- `User SwitchyardSwitching` fires before a switch closes the windows,
  `User SwitchyardSwitched` after it (`data = { from, to }` for both). For
  example, reopen a file tree:

  ```lua
  vim.api.nvim_create_autocmd("User", {
    pattern = "SwitchyardSwitched",
    callback = function()
      require("nvim-tree.api").tree.open()
      vim.cmd.wincmd("p")
    end,
  })
  ```

## Development

Tests run headless: `for t in tests/*.lua; do nvim --headless -u NONE --cmd "set rtp+=." -l $t; done`.

## License

[MIT](LICENSE)
