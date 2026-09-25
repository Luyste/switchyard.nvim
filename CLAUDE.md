# switchyard.nvim — handoff context

This file brings you up to date on switchyard.nvim, a Neovim plugin I've been
designing and building step by step in a chat. Read it fully before changing
anything, then **inspect the actual code**: some items below are marked
"verify", because I'm not sure every suggested change was applied.

## How I want to work

- I'm learning Neovim plugin development while building this. Explain **what**
  you change and **why** (the Neovim/Lua concept behind it), briefly.
- Small steps, each testable. Tell me how to test each step in Neovide.
- Plain Lua, Neovim 0.12+, no plugin dependencies (fzf-lua is optional).
- When something breaks, find the root cause before patching.

## My setup

- macOS, **Neovide** as the editor (GPU Neovim GUI), Ghostty as terminal, zsh +
  Oh My Zsh. Neovim config in `~/.config/nvim` (Lua, `vim.pack` plugin manager,
  one file per plugin under `lua/plugins/`), managed in a bare dotfiles repo.
- Agents: **pi** (pi coding agent) at work, **Claude Code** at home.
- Git worktrees via **worktrunk** (`wt`). pi extensions in use: **pi-nvim**
  (socket bridge) and **pi-worktrunk** (lets pi move its session between
  worktrees).
- Agents run inside **tmux** sessions (one tmux server; `.tmux.conf` has
  `mouse on`, `window-size latest`, `escape-time 10`, `status off`).
- Plugin repo checkout: `~/personal/projects/switchyard/` (loaded via
  runtimepath from my config when present, else `vim.pack` from GitHub
  `Luyste/switchyard.nvim`).
- My config loads it in `~/.config/nvim/lua/plugins/switchyard.lua`:
  - `require("switchyard").setup({ projects_dirs = { "~/personal/projects/", "~/work/projects/" } })`
  - A `User SwitchyardSwitched` autocmd that opens nvim-tree (inside
    `vim.schedule`) and `wincmd p`.
  - Keymaps via a helper `sy(fn)` that returns `function() require("switchyard")[fn]() end`
    (function form, so a missing name never breaks startup):
    `<D-W>` pick_worktree, `<D-A>` pick_agent, `<D-N>` start_agent,
    `<D-Y>` open_yard (I also want Cmd+Shift+S for the yard), `<D-j>` toggle_view
    (n + t), `<D-S-j>` open_external, `t <D-r>` → `<C-\><C-n>` (Cmd+Esc never reaches Neovim in Neovide),
    `t <C-w>h/j/k/l/w/p` → `<C-\><C-n><C-w>…` for window moves from terminals.
  - My statusline (`lua/config/statusline.lua`) shows the linked agent via
    `pcall(require("switchyard").status)`, in both the file-tree and file
    statuslines.

## What switchyard is

**Agents running on worktrees, and an editor that follows them.**

- **Tracks** = git worktrees (managed through worktrunk, never raw git).
- **Trains** = agent sessions (pi / Claude Code), each living in a tmux session.
- **The yard** = one screen in Neovim to switch worktrees and manage agents.
- The editor is **linked** to one agent session; it sends prompts to it and
  **follows** it when that agent moves to another worktree.

## Conventions (decided, don't change without asking)

- **Switching is the primary action and must never be interrupted.** No prompts
  on switch.
- **Agents live in a worktree.** The agent leads, the editor follows: when the
  _linked_ agent moves worktree, the editor switches there. Switching the editor
  alone never moves an agent (that's "peeking").
- **Arrival rules** (on `VimEnter` / `DirChanged global`):
  - exactly one agent in the new folder → link to it silently;
  - no agent → **keep the current link** (config `empty_worktree = "keep"`;
    `"unlink"` and `"ask"` also exist). Keeping the link enables "peek into
    worktree C, copy a snippet, send it to the orchestrator in worktree A";
  - several agents → keep the current link.
- **Starting an agent in the editor's current folder links to it.** (Starting in
  another worktree from the yard should NOT link — pending, see launch.lua.)
- **Viewing ≠ linking.** The viewer can show any agent; the link decides where
  prompts go.
- **Plugin has no default global keymaps.** It exposes functions/commands; my
  config maps keys. Buffer-local keys inside plugin windows are fine and
  configurable via `config.keys`.
- **Async everywhere**: shell out via `util.run` (vim.system + vim.schedule).
  Only the health check may `:wait()`.
- **Messages**: progress → `nvim_echo(…, false, {})` (no history); results and
  errors → `vim.notify`. Anything that changes layout calls `vim.cmd("redraw")`
  before notifying (avoids "Press ENTER" prompts that break window changes).
- **Callbacks from pickers/menus that touch windows are `vim.schedule`d.**
- Terminal-agnostic, OS-agnostic where possible (repo will be public).

## Module map (as designed; verify against code)

```
plugin/switchyard.lua        :Switchyard → open the yard (guarded by vim.g.loaded_switchyard)
lua/switchyard/
  init.lua                   setup(opts) → config.setup + sessions.setup; public API:
                             switch, open_yard, pick_worktree, pick_project, pick_agent,
                             start_agent, status, toggle_view, open_external
                             (planned: next_agent, prev_agent)
  config.lua                 defaults + setup (unknown-option warning; lists replaced
                             not merged; projects_dirs string→list, expanded)
  health.lua                 :checkhealth switchyard — programs (git, wt, tmux),
                             projects_dirs, external terminal, agents/adapters
  util.lua                   run(cmd, {cwd}, cb(ok, stdout, stderr)) — async, pcall'd
  worktrunk.lua              list(cwd, cb) via `wt list --format=json` (luanil),
                             normalized to {branch, path, current, main, symbols};
                             create(cwd, branch, cb) via `wt switch --create --no-cd --yes`;
                             remove(cwd, branch, cb) via `wt remove --yes`
  projects.lua               switch(dir): refuse on unsaved, tabonly/only/enew, delete
                             file buffers (buftype==""), stop LSP clients, cd, redraw,
                             notify, fire User SwitchyardSwitched {from,to};
                             list(cb): repos (.git dirs only) in projects_dirs via find
  pickers.lua                worktrees/projects pickers (fzf-lua direct if installed,
                             else vim.ui.select). To be REPLACED by the yard.
  tmux.lua                   list, free_name, new(name, cwd, cmd, cb), kill,
                             sessions_for_pids (walks the process tree up to a pane),
                             session_of_pid, attach_cmd. Targets use "=name".
  adapters/init.lua          active(): adapters from opts.agents that are tables and installed
  adapters/pi.lua            name/cmd/hint/watch_dir, new_cmd, continue_cmd,
                             fork_cmd(session) (pi --fork <latest session file in
                             ~/.pi/agent/sessions/--<path>--/>), sessions() (from
                             /tmp/pi-nvim-sockets/*.info; newest per pid; alive check;
                             socket = info.socket or file minus ".info"), send(session,
                             msg, cb) over the unix socket ({"type":"prompt"})
  adapters/claude.lua        EMPTY placeholder (must stay skipped: type check)
  sessions.lua               all, in_folder, linked (fresh), link(session, quiet),
                             status (cached), linked_pid (planned), describe, pick,
                             resolve_tmux (public; caches tmux names; fires
                             User SwitchyardSessionsChanged), tmux_name, arrival rules,
                             follow (only on actual MOVE of linked agent; pending retry
                             on BufWritePost), fs_event watch on adapter.watch_dir
                             (debounced 300 ms, fires SwitchyardSessionsChanged)
  launch.lua                 start/new/continue/fork/pick — agents start in tmux, wait
                             for registration (poll 500 ms, 30 s), then link
  ui.lua                     shared highlights (linked to standard groups, default=true)
                             + hide/show cursor (guicursor → blended hl), one shared save
  yard.lua                   the yard (part 1 done, see below)
  view.lua                   the viewer (split + external terminal)
```

## Status

### Done and working

- Health check, config, worktrunk list/create/remove, project + worktree
  switching (with the nvim-tree User event in my config).
- pi adapter (incl. older pi-nvim manifests without `socket`), sending works.
- tmux module incl. process-tree walk (needed because pi isn't a direct child
  of the pane shell).
- Linking, arrival rules, following (move-only), tmux names in statusline.
- Launching agents in tmux (new/continue/fork) from `start_agent`.
- **Yard part 1**: two modes.
  - Filter mode (opens here): 3 floats (input line with inline `›` virt text and
    `n / m` count, list, detail only in normal mode). Typing filters
    (substring, case-insensitive, match highlighted; worktree shown if branch or
    any agent matches, auto-expanded when only an agent matches). Ctrl-N/P move,
    Enter switches worktree / links agent, Tab expands, Esc → normal mode.
  - Normal mode: wide two-pane layout (tree left, detail panel right, detail
    lists actions + keys from `config.keys.yard`). j/k and Ctrl-N/P move freely,
    `o`/Tab expand, Enter, `i`/`/` back to filter, `q`/Esc close.
  - Full-row selection (cursorline → `SwitchyardSelection` = PmenuSel), cursor
    hidden and locked to column 0, title/footer in borders with mode badge,
    selection kept across redraws by row key (path or `pid:<n>`), closes when
    focus goes to a normal (non-floating) window, redraws on
    `SwitchyardSessionsChanged` / `VimResized`.
- **Viewer**: Cmd+J toggles a right split (`botright vsplit`, width
  `config.viewer.width`) with a terminal running `tmux attach -t =name`; reused
  window; hidden buffer kept; `q` hides; BufEnter → startinsert; TermClose →
  cleanup. Toggle rules: viewer open → hide; else linked agent if in tmux; else
  agents in this worktree that run in tmux (one → show, several → choose,
  none → warn). External terminal: `config.terminal = "auto" | name | function(cmd)`,
  built-ins ghostty/kitty/wezterm/alacritty/terminal.app (macOS `open -na`).

### Verify (suggested, may not be applied)

- `tmux.new` should `cd <cwd> &&` inside the shell line (after rc files), then
  the agent command, then `; exec $SHELL`.
- `menu.lua` (yard-style small menu: title, numbered items, optional key/danger,
  Enter/1-9 choose, Esc/q cancel, cursor hidden, does NOT close on focus loss).
  Should replace every remaining `vim.ui.select`: `launch.pick`, the viewer's
  "which agent" choice, `ask_about_link`.
- `ui.lua` in use by yard.lua (no local copies of highlight/cursor helpers left).
- Config keys: `keys.yard` should contain activate `<CR>`, toggle `o`, filter `i`,
  close `q`, refresh `<C-r>`, new_worktree `%`, remove `D`, new_agent `n`,
  continue_agent `c`, fork_agent `f`, copy_path `y`, view `v`, external `g`,
  send `s`, move `m`, spin_off `F`, rename `r`. Also `viewer.width = 0.45`,
  `terminal = "auto"`, `empty_worktree = "keep"`.

### Next steps (in this order)

1. **Viewer statusline** (window-local `statusline =
"%!v:lua.require'switchyard.view'.statusline()"`, redraw on
   `TermEnter/TermLeave`):
   - mode badge: TERMINAL (blue, `SwitchyardFilterBadge`) / NORMAL (green,
     `SwitchyardNormalBadge`), hint on the right;
   - **agent tabs**: all agents the viewer can show for this worktree (linked
     first), the visible one highlighted, `●` before the linked one (use a new
     cheap `sessions.linked_pid()` from the cache, never file reads in a
     statusline).
2. **Cycling agents in the viewer**: refactor toggle's candidate logic into
   `viewable(cb)` (stores `viewer.list`), add `view.cycle(delta)` with wraparound,
   buffer-local `]a`/`[a` in the viewer, public `next_agent`/`prev_agent`
   (I'll map Cmd+] / Cmd+[ in n+t mode). Cycling doesn't change the link.
3. **Badge contrast**: badges use theme colors as background; choose the text
   color by luminance (dark text on light backgrounds, light on dark). NORMAL
   and LINKED are currently unreadable with my theme (mawkler/onedark).
4. **Seeing the agent's edits live** (new module, e.g. `live.lua`):
   - **Live reload**: problem today: `autoread` only checks on focus/buffer/
     CursorHold events, none of which fire while I'm in terminal mode in the
     viewer, so open files stay stale while the agent edits them. Watch the file
     of every loaded normal buffer with `vim.uv.new_fs_event` (start on
     BufReadPost/BufNewFile, stop on BufDelete/BufWipeout, restart after a
     rename/replace since editors and agents often write via rename); on change,
     debounce ~100 ms and `vim.cmd("checktime " .. buf)` inside `vim.schedule`.
     Never touch buffers with unsaved changes (Neovim's own W12 warning stays).
     Config: `live_reload = true`. Gitsigns then shows the changed hunks.
   - **Follow edits** (toggle, off by default; public `follow_edits(bool?)` and
     `:Switchyard follow-edits`): watch the current worktree recursively
     (`fs_event` with `recursive = true`, works on macOS; on Linux fall back to
     watching loaded buffers + polling or skip), ignore `.git`, `node_modules`,
     build dirs and gitignored files (check with `git check-ignore` in batch or
     cache `git ls-files`). When a file changes, open it in the main editor window
     (not the viewer, not the tree) and jump to the first changed hunk (gitsigns
     `nav_hunk("first")` if available, else leave the cursor). Debounce, and don't
     steal focus from the viewer: change the editor window's buffer without
     entering it. Show "following edits" in my statusline via a cheap cached
     `require("switchyard").following_edits()`.
5. **launch.lua**: `start(adapter, cmd, label, cwd, callback)` — default cwd =
   editor cwd; only link when cwd == getcwd, otherwise notify "started <name>";
   `new(adapter, cwd)`, `continue(adapter, cwd)`, `fork(source, cwd)`.
6. **actions.lua** (shared by pickers/yard): create_worktree(cwd, on_done)
   via vim.ui.input, remove_worktree(cwd, wt, on_done) (refuse current/main,
   confirm), stop_agent(session, on_done) (tmux kill-session, confirm).
7. **Yard part 2 — normal-mode actions** (row under cursor is the subject;
   destructive actions confirm; keys from config):
   - worktree row: Enter switch, `o` expand, `%` new worktree (refresh, don't
     switch), `D` remove, `n` new agent here, `c` continue here, `f` fork the
     linked agent into this worktree, `y` copy path;
   - agent row: Enter link, `v` view in split, `g` external terminal, `s` open
     prompt builder aimed at this agent, `m` move (pick worktree → send the agent
     a message asking it to switch via the worktrunk tool; editor follows if
     linked), `F` spin off (new worktree + fork this agent into it),
     `r` rename tmux session (update the name cache), `D` stop;
   - everywhere: `p` projects inside the yard, `.` action menu for the row
     (menu.lua with keys shown), `?` help, Ctrl-R refresh.
   - With several adapters installed, ask which one (menu); with one, use it.
   - Later: show agent state (working / waiting for you) from pi-worktrunk's
     `wt list` markers; lock marker for locked worktrees.
8. **Prompt builder** (Markdown floating window, NOT via the yard):
   - A **draft** that survives closing. Visual Cmd+L: add the selection as
     `path:start-end` + fenced code block (filetype) and open the builder;
     normal Cmd+L: open the builder; Cmd+Shift+L: add current line + its
     diagnostics.
   - Inside: Ctrl-S send (adapter.send), Ctrl-O **hand over** (paste into the
     agent's own input via `tmux load-buffer` + `paste-buffer -p`, no submit,
     open viewer), Ctrl-T change target (menu), Ctrl-F insert a file path,
     `q` close keeping the draft, Ctrl-X clear. Draft cleared after sending.
   - Title shows the target: `→ <tmux name> (linked)` and `(in <worktree>)` when
     the agent lives elsewhere; no link → ask for a target.
   - **Cross-worktree paths**: if the target agent's cwd isn't the snippet's
     worktree, use absolute paths + "(worktree <branch>)", never paths relative
     to the wrong checkout.
   - Fork note (currently sent as a separate first message by launch.fork)
     could move in front of the first real prompt.
9. Retire `pickers.lua` (yard filter mode replaces the worktree picker; `p`
   in the yard replaces the project picker) and the old keymaps.
10. Claude Code adapter: external sessions via claudecode.nvim (IDE protocol);
    hand-over already works for any agent in tmux.
11. README, docs, fuzzy matching, polish.

## Design references

- Yard mockups (6 artboards: filter mode, filter + expanded, normal mode with a
  worktree selected, with an agent selected, `.` action menu, prompt builder):
  https://claude.ai/artifact/RyPyrsqwLEGBmypLWLQYcg
- Workflow doc (conventions, setup overview):
  https://claude.ai/code/artifact/6047621e-fbd9-44b2-900d-6e0c960d9264

## Gotchas we already hit (don't reintroduce)

- A module without `return M` makes `require` return `true` ("attempt to index a
  boolean value"). Empty adapter files too → always check `type(adapter) == "table"`.
- `vim.system` / luv callbacks run in a fast context → `vim.schedule` before
  touching the API.
- Two quick `vim.notify` messages → "Press ENTER" prompt → window changes (like
  opening nvim-tree) get lost. `redraw` before notifying in layout-changing code.
- fzf-lua / `vim.ui.select` callbacks fire before the picker closes → schedule.
- JSON null → use `vim.json.decode(s, { luanil = { object = true, array = true } })`.
- Older pi-nvim `.info` files have no `socket` field.
- pi's process is not always a direct child of the tmux pane → walk the tree.
- In zsh, `=name` on the command line expands to a program path; quote tmux
  targets when testing in a shell (switchyard itself passes args without a shell).
- `bufhidden = "hide"` for buffers whose windows open/close repeatedly;
  delete them explicitly on close.
- Measure display width with `vim.fn.strdisplaywidth`, not `#` (bytes).
- The statusline must never do I/O: use cached values.
- `follow()` must react to a _move_ of the linked agent (compare with the cached
  cwd), not to "agent is elsewhere", or it hijacks the editor after "keep link".
