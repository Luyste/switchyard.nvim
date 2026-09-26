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
    (n + t), `<D-J>` focus_view (n + t: jump between viewer and editor),
    `<D-O>` open_external, `<D-H>` link_here, `<D-F>` follow_edits (n + t).
    No terminal-mode escape key: Cmd+Shift+J leaves the viewer (Cmd+Esc never
    reaches Neovim in Neovide anyway).
  - My statusline (`lua/config/statusline.lua`) is global (`laststatus=3`):
    a badge for what has focus (FILE / TREE / AGENT = buffer `switchyard://…` /
    YARD = filetype `switchyard` / TERM), repo · branch, file or viewed agent,
    and the linked agent via `pcall(require("switchyard").status)`.

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
  - several agents → keep the link if it's already one of them; otherwise link
    the one the viewer showed last, else the most recently started (no prompt:
    Enter moves the link along, Shift+Enter/peek keeps it).
  - Arriving after a switch with the viewer open: the viewer comes back, showing
    the linked agent (`view.sync(true)`), without taking focus.
- **Enter vs Shift+Enter in the yard (worktree switching):**
  - Enter = **switch**: the editor goes to the worktree and the arrival rules
    apply (one agent there → the link moves to it).
  - Shift+Enter = **peek**: the editor goes to the worktree but the link stays
    on the current agent, whatever the worktree contains (statusline shows
    `agent (in <other worktree>)`). Used to grab context from B and send it to
    agent A (with the prompt builder's cross-worktree paths).
- **Two yard views, one meaning per key:** keys act on what the current view
  shows (`n` = new worktree / new agent, `D` = remove worktree / stop agent).
  Enter in the agents view = "go to" (switch + link); Shift+Enter = link only.
- **Prompt builder = chat convention:** Enter sends, Shift+Enter is a new line.
- **Dispatch** (fire-and-forget): describe a task → new worktree + agent started
  there with the task as its first message. The editor does NOT switch and the
  link does NOT change; the new worktree + working agent simply appear in the yard.
- **Starting an agent in the editor's current folder links to it.** Starting in
  another worktree does not link (just a message).
- **Viewing ≠ linking.** The viewer can show any agent; the link decides where
  prompts go.
- **Dependencies:** hard dependencies are PROGRAMS only (git, wt, tmux, the
  agents; reported by the health check). switchyard never requires another
  Neovim plugin. Every plugin integration is optional (`pcall(require, …)`),
  lives in `lua/switchyard/integrations/`, has a no-dependency fallback or is
  simply not offered, and is reported by the health check. Pluggable features
  follow the `terminal` pattern: `"auto" | <name> | function(...)`.
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
                             status (cached), linked_pid (cached), describe, pick,
                             resolve_tmux (public; caches tmux names; fires
                             User SwitchyardSessionsChanged), tmux_name, arrival rules,
                             follow (only on actual MOVE of linked agent: compares with
                             `seen_cwd`; blocked move kept in `follow_to`, retried on
                             BufWritePost), fs_event watch on adapter.watch_dir
                             (debounced 300 ms, fires SwitchyardSessionsChanged)
  launch.lua                 start(adapter, cmd, label, cwd?, cb)/new/continue/fork/pick —
                             agents start in tmux in `cwd` (default editor cwd), wait for
                             registration (poll 500 ms, 30 s), then link only if the agent
                             runs where the editor is (checked then), else "started <name>"
  ui.lua                     shared highlights (linked to standard groups, default=true)
                             + hide/show cursor (guicursor → blended hl), one shared save;
                             badge text color picked by WCAG contrast (Normal fg vs bg)
  menu.lua                   yard-style small menu (numbered items, key/danger, 1-9)
  live.lua                   live reload: one fs_event per folder of loaded file buffers
                             (refcounted), debounced checktime, skips modified buffers;
                             follow edits (recursive watcher, see Status)
  yard.lua                   the yard (part 1 done, see below); close() returns to
                             the window it was opened from
  view.lua                   the viewer (split + statusline with agent tabs, cycle,
                             external terminal)
tests/*.lua                  nvim --headless -u NONE --cmd "set rtp+=." -l tests/<name>.lua
                             (live: live reload + follow edits; arrival: arrival rules + peek;
                             launch: linking after a start)
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
  window; hidden buffer kept; BufEnter → startinsert; TermClose →
  cleanup. Toggle rules: viewer open → hide; else linked agent if in tmux; else
  agents in this worktree that run in tmux (one → show, several → choose,
  none → warn). External terminal: `config.terminal = "auto" | name | function(cmd)`,
  built-ins ghostty/kitty/wezterm/alacritty/terminal.app (macOS `open -na`).
  - Own **winbar** (works with my global statusline, `laststatus=3`; set AFTER
    the terminal buffer is in the window: window-local options only stick to the
    buffer they were set with): agent tabs (`viewable()` → cached `viewer.list`,
    linked first, `●` = linked, refreshed on SwitchyardSessionsChanged /
    DirChanged); a NORMAL badge only as a warning when the focused viewer is
    not in terminal mode.
  - The viewer is only for typing to the agent: no buffer-local keys, no
    cycling (removed). Choosing which agent to see happens in the yard.
    `focus_view()` jumps between viewer and editor (stopinsert + previous window).
- **Badge contrast**: text color = the theme's light or dark color, whichever
  contrasts more with the badge background.
- **Live reload** (`live_reload = true`): open files follow the agent's edits,
  also while in terminal mode. Folder watchers (see live.lua) also catch
  rename-replace saves.
- **Follow edits** (`follow_edits(on?)`, `following_edits()`, `:Switchyard
  follow-edits`, mapped Cmd+Shift+F; FOLLOW badge in my statusline): recursive
  fs_event on the worktree (macOS/Windows only), `.git/` dropped, 150 ms debounce,
  one `git check-ignore --stdin`, latest file shown in the editor window without
  focus; cursor on the first changed line via `vim.diff` against live reload's
  snapshot / the loaded buffer / `git show :./path`. Never replaces a modified
  buffer. Moves along on DirChanged. `link_here()` (Cmd+Shift+H) links an agent
  here after a peek.
- **Peek**: Shift+Enter in the yard (`keys.yard.peek`) switches but keeps the
  link: `sessions.keep_link_for(dir)` is a one-time hold that `on_arrival`
  consumes; cleared again when the switch is blocked.
- **Switching from any window**: `projects.switch` starts from a fresh window
  (`botright new` + `only`), so switching while focus is in the tree, the viewer
  or a float no longer eats the tree window.
- Checked: `tmux.new` cds inside the shell line; `menu.lua` used by
  `launch.pick` and the viewer's choice; `ui.lua` used by yard.lua; config has
  `viewer.width`, `terminal`, `empty_worktree`, `live_reload`.

### Open (small)

- `ask_about_link` and `sessions.pick` still use `vim.ui.select` → menu.lua.
- `config.setup` has no unknown-option warning yet.
- `keys.yard` will be redefined by the two-view yard (see the key table in the
  yard part 2 step); add `yard.view = "worktrees"`.

### Next steps (in this order)

1. **actions.lua** (shared by pickers/yard): create_worktree(cwd, on_done)
   via vim.ui.input, remove_worktree(cwd, wt, on_done) (refuse current/main,
   confirm), stop_agent(session, on_done) (tmux kill-session, confirm).
   Confirmations via menu.lua.
2. **Compact yard refactor, two views** (do BEFORE yard part 2; replaces
   part 1's layout):
   - ONE floating window, sized to content: width = longest row, clamped
     ~50..90 cols; height = number of rows, capped (~60% of lines). Centered.
     Title `switchyard · <repo> · worktrees` / `switchyard · agents` in the top
     border, key hints in the bottom border.
   - **Two views, Tab toggles**, remembered for the next open (`yard.view`
     default "worktrees"):
     - **Worktrees view** (current repo): one row per worktree, number, `@`,
       branch, status symbols, agent summary on the right (`● linked`, `● 2`).
       **No expand/collapse** (agents are managed in the agents view).
     - **Agents view** (all repos): flat list of agent sessions: number, tmux
       name, worktree/branch (+ repo when not the current one), state; sorted
       waiting → working → idle (state from pi-worktrunk markers; until then,
       sort linked first, then by worktree). Replaces "agents elsewhere".
   - Opens in **normal mode** with the current worktree / linked agent selected.
     `j`/`k` (and Ctrl-N/P) move, `1`–`9` act as Enter on the Nth row, `q`/Esc close.
   - Footer hints adapt to the view, most-used keys only, truncated to width.
     `?` = overlay with all keys. `.` = action menu for the row (menu.lua).
   - `/` = filter: a 1-line input float appears attached above the yard only
     while filtering; typing narrows the list; Enter acts; Esc clears the filter
     and removes the input line. Filtering is a temporary state, not a mode.
   - Keep: row building, highlights, selection-by-key, auto-close on focus loss,
     SwitchyardSessionsChanged redraws. Remove: the filter/normal layouts, the
     detail window, the mode badge, expand/collapse.
   - Iterate on size in real use; aim for "as small as possible".
3. **Yard part 2 — actions per view** (row under cursor is the subject;
   destructive actions confirm; every key configurable in `keys.yard`):
   | Key                             | Worktrees view                           | Agents view                                                                           |
   | ------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------- |
   | Enter                           | switch (arrival rules: link moves along) | **go to**: switch to its worktree + link                                              |
   | Shift+Enter                     | peek (keep link)                         | link only, stay where you are                                                         |
   | `n`                             | new worktree                             | new agent (menu: worktree, current preselected; last item "new worktree…" = dispatch) |
   | `N`                             | dispatch (new worktree + agent + task)   | dispatch                                                                              |
   | `D`                             | remove worktree                          | stop agent (tmux kill-session)                                                        |
   | `a`                             | start agent in this worktree             | —                                                                                     |
   | `c`                             | continue last agent session here         | —                                                                                     |
   | `f`                             | fork the linked agent into this worktree | fork this agent (menu: which worktree)                                                |
   | `F`                             | —                                        | spin off: new worktree + fork this agent into it                                      |
   | `v` / `g`                       | —                                        | view in split / external terminal                                                     |
   | `s`                             | —                                        | prompt builder aimed at this agent                                                    |
   | `m`                             | —                                        | move: pick worktree, ask the agent to switch via the worktrunk tool                   |
   | `r`                             | —                                        | rename tmux session (update the name cache)                                           |
   | `y`                             | copy path                                | —                                                                                     |
   | `p`                             | projects (switch repo)                   | projects                                                                              |
   | Tab                             | agents view                              | worktrees view                                                                        |
   | `1`–`9`, `/`, `?`, `.`, `q`/Esc | same in both                             | same in both                                                                          |
   - With several adapters installed, ask which one (menu); with one, use it.
   - Later: agent state (working / waiting) from pi-worktrunk's `wt list`
     markers; lock marker for locked worktrees.
4. **Dispatch** (after yard part 2; shares code with spin-off):

- Adapter gets `task_cmd(prompt)`: pi → `{ "pi", prompt }` (pi takes
  positional messages: `pi [options] [--] [@files...] [messages...]`),
  claude → `{ "claude", prompt }` (interactive session with an opening prompt).
- UI: a yard-style floating Markdown buffer for the task (multi-line). Branch
  name suggested from the first line (slug, e.g. `feature/add-dark-mode`),
  editable before confirming. Base = default branch; one key toggles "branch
  off the current worktree" → `wt switch --create <b> --base=@ --no-cd --yes`.
- Flow: create worktree (worktrunk.create, extend with optional base) →
  `launch.start(adapter, adapter.task_cmd(prompt), label, new_path)` (not the
  editor's cwd → no link, no switch) → yard refreshes via
  SwitchyardSessionsChanged (+ `refresh()` for the new worktree).
- Visual-mode dispatch includes the selection as context with ABSOLUTE path +
  `(worktree <branch>)` (cross-worktree rule).
- Keys: yard `N` (`keys.yard.dispatch = "N"`), public `dispatch()` for a
  global key (I'll map Cmd+Shift+D in n + x mode).
- Spin-off (`F`) = same flow but `fork_cmd(source)` instead of `task_cmd`.

5. **Prompt builder** (compact, chat-style; NOT via the yard). Inspired by
    pi-nvim's dialog (two stacked bubbles, growing input, selection highlighted in
    the source) but with a persistent draft and multiple contexts:

- **Layout:** two attached floats, accent border.
  - Header (not focusable): target line `→ <tmux name> (linked)` / `(in <wt>)`,
    then ONE LINE PER CONTEXT: `internal/router/router.go:12-14 (3 lines)`,
    `router_test.go:40 + 2 diagnostics`. The code itself is not shown.
  - Input: starts 1 line, grows with content (wrap-aware) up to ~8 lines,
    then scrolls. Plain text prompt.
- While open, every context range is highlighted (Visual) in its source buffer.
- **Keys (chat convention):** insert mode Enter = **send**, Shift+Enter = new
  line (configurable: some terminals can't distinguish Shift+Enter; offer
  `<C-j>` as an alternative newline key). Esc in insert = normal mode
  (Vim-standard); `q`/Esc in normal = close, **keeping the draft**. Ctrl-O =
  hand over (paste into the agent's own input via tmux, no submit, open
  viewer), Ctrl-T = change target (menu), Ctrl-F = add a file path, `dd` on a
  header line (or Ctrl-X in normal) = remove that context / clear all,
  `e` = expand the whole draft into a Markdown buffer for editing the code.
- **Draft:** survives closing and focus loss; cleared after send/hand-over.
  Visual Cmd+L adds the selection (file, range, filetype, text) and opens;
  normal Cmd+L opens; Cmd+Shift+L adds the current line + its diagnostics.
- **Message assembly at send time:** prompt text first, then each context as
  `From <path>:<a>-<b>:` + fenced code block with filetype (diagnostics as a
  list). Paths relative to the target agent's worktree when it's the same
  worktree; otherwise ABSOLUTE + `(worktree <branch>)`.
- Fork note (currently a separate first message from launch.fork) could move
  in front of the first real prompt.

6. Retire `pickers.lua` (yard filter mode replaces the worktree picker; `p`
   in the yard replaces the project picker) and the old keymaps. It calls
   fzf-lua directly, which breaks the dependency rule until then.
7. Claude Code adapter: external sessions via claudecode.nvim (IDE protocol);
    hand-over already works for any agent in tmux.
8. README, docs, fuzzy matching, polish.

Dropped: a review/diff viewer inside switchyard (a normal git diff plugin covers
it). Worktree rows may still show the diff size vs the default branch later
(`default_branch.diff.added/deleted` in the wt list JSON).

## Design references

- Yard mockups (OUTDATED layout: two modes + detail panel; superseded by the
  compact yard step. Still useful for colors/badges/row content. 6 artboards: filter mode, filter + expanded, normal mode with a
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
- A pending redraw (e.g. the yard closing, insert mode ending) wipes a message
  shown right before it: `redraw` before `vim.notify` in switch paths.
- `:only` also closes the viewer: whoever switches must bring it back.
- `follow()` must react to a _move_ of the linked agent (compare with the cached
  cwd), not to "agent is elsewhere", or it hijacks the editor after "keep link".
