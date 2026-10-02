# switchyard.nvim — handoff context

This file brings you up to date on switchyard.nvim, a Neovim plugin I've been
designing and building step by step in a chat. Read it fully before changing
anything, then **inspect the actual code**.

## How I want to work

- I'm learning Neovim plugin development while building this. Explain **what**
  you change and **why** (the Neovim/Lua concept behind it), briefly.
- Small steps, each testable. Tell me how to test each step in Neovide.
- Plain Lua, Neovim 0.12+, no plugin dependencies.
- When something breaks, find the root cause before patching.

## My setup

- macOS, **Neovide** as the editor (GPU Neovim GUI), Ghostty as terminal, zsh +
  Oh My Zsh. Neovim config in `~/.config/nvim` (Lua, `vim.pack` plugin manager,
  one file per plugin under `lua/plugins/`), managed in a bare dotfiles repo.
- Agents: **pi** at work, **Claude Code** at home, run through
  **sidekick.nvim** (`lua/plugins/sidekick.lua`: tmux backend,
  `create = "terminal"`). tmux: one server, `status off`.
- Git worktrees: plain `git worktree`.
- Plugin repo checkout: `~/personal/projects/switchyard.nvim/` (loaded via
  runtimepath from my config when present, else `vim.pack` from GitHub
  `Luyste/switchyard.nvim`). Inside Neovim the plugin is `switchyard`
  (`require("switchyard")`, `:Switchyard`).
- My config loads it in `~/.config/nvim/lua/plugins/switchyard.lua`:
  `setup({})`, a `User SwitchyardSwitched` autocmd that opens nvim-tree (inside
  `vim.schedule`) and `wincmd p`, and keymaps via a helper `sy(fn)` (function
  form, so a missing name never breaks startup). `<D-Y>` = open_yard (I also
  want Cmd+Shift+S). The other old keymaps (toggle_view, focus_view,
  open_external, link_here, follow_edits) point at removed functions.
- My statusline (`lua/config/statusline.lua`, global, `laststatus=3`) shows a
  YARD badge for filetype `switchyard`; its `pcall(require("switchyard").status)`
  now finds nothing.

## What switchyard is (since the sidekick scope cut, Oct 2026)

**A worktree and folder switcher.** Agents are sidekick.nvim's job; switchyard
only moves the editor: between a repo's git worktrees, and between folders
(projects). Everything agent-related (tmux, agents, linking, viewer, prompt
builder, dispatch, live reload, follow edits) was removed; it's in git history
before the `feature/sidekick-scope` branch, and an unfinished "continue earlier
sessions" feature sits in `git stash` ("continue earlier sessions …").

## Conventions (decided, don't change without asking)

- **Switching must never be interrupted.** No prompts on switch. Unsaved
  changes → refuse with a message.
- **Switch = fresh editor in the new folder:** `botright new` + `only`, delete
  file buffers, stop LSP clients, `cd`, fire `User SwitchyardSwitched`.
  `User SwitchyardSwitching` fires before any window closes (integrations note
  what was open).
- **The yard** = one float, two views, Tab toggles:
  - worktrees: the worktrees of `state.repo` (the editor's folder at open).
  - folders: the folders of `state.dir` (at open: the folder around the repo).
    `l` = look inside (repo → its worktrees view), `h` = up (worktrees view →
    folders around the repo). Dot folders and linked worktrees (`.git` is a
    file) are hidden; repos marked `git`.
  - Title: `switchyard · <view>`, plus the location only when it's not the
    editor's own repo (folders: the path; worktrees of another repo: its name).
- **Dependencies:** hard dependencies are programs only (git). Every plugin
  integration is optional, lives in `lua/switchyard/integrations/<name>.lua`
  (`available()`, `setup()`), is listed in `integrations.names`, can be turned
  off with `config.integrations.<name> = false`, and is reported by the health
  check. Integrations use the plugin's public API or plain Neovim facts
  (filetypes) where possible.
- **Window style:** titles and key hints never go in the border (Neovide
  draws them over the border line). Title = the float's winbar
  (`ui.title(win, chunks)`), hints = a virtual line below the last line
  (`ui.hints(buf, text)`).
- **Questions in switchyard's own style:** choices via `menu.open`, text via
  `menu.input`. Never `vim.ui.select` / `vim.ui.input`.
- **Plugin has no default global keymaps.** Buffer-local keys inside plugin
  windows are fine and configurable via `config.keys`.
- **Async everywhere**: shell out via `util.run` (vim.system + vim.schedule).
  Only the health check may `:wait()`. Reading a folder (`vim.fs.dir`) is fine
  synchronously.
- **Messages**: progress → `util.progress` (no history); results and errors →
  `vim.notify`. `redraw` before notifying in layout-changing code.
- **Callbacks from menus that touch windows are `vim.schedule`d.**
- Terminal-agnostic, OS-agnostic where possible (repo is public).

## Module map

```
plugin/switchyard.lua        :Switchyard → yard; :Switchyard <folder> → switch (dir completion)
lua/switchyard/
  init.lua                   setup(opts), switch(dir), open_yard()
  config.lua                 defaults (yard.view, integrations, keys.yard) + setup
  health.lua                 git; integrations (active / not installed / disabled)
  util.lua                   run(cmd, {cwd, stdin}, cb(ok, stdout, stderr)); progress(text)
  worktrees.lua              parse(porcelain), list(cwd, cb), create(cwd, branch, cb),
                             remove(cwd, wt, cb) (+ `git branch -d`, merged only)
  projects.lua               switch(dir): refuse on unsaved, SwitchyardSwitching, tabonly +
                             botright new + only, delete file buffers, stop LSP, cd,
                             notify, SwitchyardSwitched {from, to}
  actions.lua                confirm, create_worktree(cwd, on_done), remove_worktree(cwd,
                             wt, on_done) (refuses current/main)
  ui.lua                     highlights (linked, default=true), hide/show cursor,
                             title(win, chunks), hints(buf, text)
  menu.lua                   yard-style menu (numbered, key/danger, 1-9); menu.input
  yard.lua                   the yard (worktrees + folders views, filter, `.`/`?` menus
                             built from one `actions` table per view)
  integrations/init.lua      names, active(name), setup()
  integrations/sidekick.lua  remembers on SwitchyardSwitching whether a window with
                             filetype `sidekick_terminal` was open; after the switch
                             (scheduled) shows sidekick's agent for the new cwd via
                             `require("sidekick.cli").show({ filter = { cwd = true,
                             started = true }, focus = false })` when
                             `sidekick.cli.state.get` finds one
tests/*.lua                  nvim --headless -u NONE --cmd "set rtp+=." -l tests/<name>.lua
                             (menu, worktrees, yard: open/close + folders navigation in a
                             temp repo)
```

## Status

Done: worktrees view (switch, new, remove, copy path, filter), folders view
(switch, look inside, up), `:Switchyard <folder>`, sidekick integration
(untested against a real sidekick agent window).

Next / ideas:
- Test the sidekick hand-over in Neovide with agents in two worktrees.
- Choosing the base branch for a new worktree.
- Worktree rows could show the diff size vs the default branch.
- `config.setup` has no unknown-option warning.
- Re-record the README GIF (the old demos were removed with the agent code).

## Gotchas we already hit (don't reintroduce)

- A module without `return M` makes `require` return `true` ("attempt to index a
  boolean value").
- `vim.system` / luv callbacks run in a fast context → `vim.schedule` before
  touching the API.
- Two quick `vim.notify` messages → "Press ENTER" prompt → window changes (like
  opening nvim-tree) get lost. `redraw` before notifying in layout-changing code.
- `vim.ui.select`-style callbacks fire before the picker closes → schedule.
- JSON null → use `vim.json.decode(s, { luanil = { object = true, array = true } })`.
- `bufhidden = "hide"` for buffers whose windows open/close repeatedly;
  delete them explicitly on close.
- Measure display width with `vim.fn.strdisplaywidth`, not `#` (bytes).
- The statusline must never do I/O: use cached values.
- A message longer than the message line makes Neovim stop at "Press ENTER"
  and swallow the next key: progress goes through `util.progress` (cut to
  `v:echospace`), notifications stay short.
- A pending redraw (e.g. the yard closing) wipes a message shown right before
  it: `redraw` before `vim.notify` in switch paths.
- `:only` closes every other window (file tree, sidekick's agent window):
  whoever needs one back reopens it after `SwitchyardSwitched`.
- A `local function f` is only visible BELOW its definition; above it, `f`
  silently means the global `f` (nil) and fails only when that code runs. Check
  for accidental globals before committing:
  `for f in lua/switchyard/*.lua lua/switchyard/integrations/*.lua; do luajit -bl "$f" | grep -oE 'GGET.*"[a-z_]+"' ; done`
  (only vim, require, package and Lua builtins may show up).
- `ipairs({ a, b })` stops at the first nil: iterate optional values with
  `pairs` over named keys.
