# switchyard.nvim — handoff context

This file brings you up to date on switchyard.nvim, a Neovim plugin I've been
designing and building step by step in a chat. Read it fully before changing
anything, then **inspect the actual code**: some items below are marked
"verify", because I'm not sure every suggested change was applied.

## How I want to work

- I'm learning Neovim plugin development while building this. Explain **what**
  you change and **why** (the Neovim/Lua concept behind it), briefly.
- Small steps, each testable. Tell me how to test each step in Neovide.
- Plain Lua, Neovim 0.12+, no plugin dependencies. (An fzf-lua yard was
  tried in Oct 2026 and reverted: I prefer switchyard's own windows; the
  fuzzy matching came over via `matchfuzzypos`.)
- When something breaks, find the root cause before patching.

## My setup

- macOS, **Neovide** as the editor (GPU Neovim GUI), Ghostty as terminal, zsh +
  Oh My Zsh. Neovim config in `~/.config/nvim` (Lua, `vim.pack` plugin manager,
  one file per plugin under `lua/plugins/`), managed in a bare dotfiles repo.
- Agents: **pi** (pi coding agent) at work, **Claude Code** at home.
- Git worktrees: plain `git worktree` (switchyard no longer uses worktrunk or
  pi-nvim; see "Agents through tmux" below).
- Agents run inside **tmux** sessions (one tmux server; `.tmux.conf` has
  `mouse on`, `window-size latest`, `escape-time 10`, `status off`).
- Plugin repo checkout: `~/personal/projects/switchyard.nvim/` (loaded via
  runtimepath from my config when present, else `vim.pack` from GitHub
  `Luyste/switchyard.nvim`). The repo was renamed from `switchyard`: that name
  (repo and folder) now belongs to a separate Rust program. Inside Neovim the
  plugin is still `switchyard` (`require("switchyard")`, `:Switchyard`).
- My config loads it in `~/.config/nvim/lua/plugins/switchyard.lua`:
  - `require("switchyard").setup({ projects = { pinned = { "~/.config/nvim" } } })`
    (my nvim config is in a bare dotfiles repo: no `.git` of its own)
  - A `User SwitchyardSwitched` autocmd that opens nvim-tree (inside
    `vim.schedule`) and `wincmd p`.
  - Keymaps via a helper `sy(fn)` that returns `function() require("switchyard")[fn]() end`
    (function form, so a missing name never breaks startup):
    `<D-y>` open_yard (n + t), `<D-j>` toggle_view
    (n + t), `<D-J>` focus_view (n + t: jump between viewer and editor),
    `<D-O>` open_external, `<D-H>` link_here, `<D-l>`/`<D-L>` prompt /
    prompt_line, `<D-D>` dispatch.
  - fzf-lua (`lua/plugins/picker.lua`): `<D-f>` = `fzf.global` (files, `$`
    buffers, `@`/`#` symbols), `<D-g>` live_grep, `<D-G>` grep_cword,
    `<D-CR>` resume. (`grep` as a `/` prefix in global fails: rg gets an
    empty argument.)
    No terminal-mode escape key: Cmd+Shift+J leaves the viewer (Cmd+Esc never
    reaches Neovim in Neovide anyway).
  - My statusline (`lua/config/statusline.lua`) is global (`laststatus=3`):
    a badge for what has focus (FILE / TREE / AGENT = buffer `switchyard://…` /
    YARD = filetype `switchyard` / TERM), repo · branch, file or viewed agent,
    and the linked agent via `pcall(require("switchyard").status)`.

## What switchyard is

**Agents running on worktrees, and an editor that follows them.**

- **Tracks** = git worktrees (`git worktree`, see worktrees.lua).
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
- **Arrival rules** (simplified Oct 2026; on `DirChanged global`, after a fresh
  snapshot): the editor goes with the agent of where it is.
  - agent(s) in the new folder → link it (several: the last USED one = linked
    or shown in the viewer, `sessions.viewed`; else most recently started;
    already linked to one there → keep) AND show it in the viewer
    (`view.sync(true)`, no focus), even if the viewer was closed;
  - no agent → unlink and close the viewer.
  - VimEnter: only the link, the viewer stays closed.
  - Starting an agent in the editor's folder links it and shows it (launch).
- **Enter vs Shift+Enter in the yard (switching):**
  - Enter = **switch**: the editor goes there and the arrival rules apply.
  - Shift+Enter = **peek** (worktrees, projects, plain folders): the editor goes
    there but the link AND the viewer stay as they were (`keep_link_for(dir)`
    records whether the viewer was open; `on_arrival` brings it back). The link stays
    on the current agent, whatever the worktree contains (statusline shows
    `agent (in <other worktree>)`). Used to grab context from B and send it to
    agent A (with the prompt builder's cross-worktree paths).
- **Three yard views, one meaning per key:** 1 worktrees, 2 agents, 3
  projects (`keys.yard.view_*`; the title shows them as tabs; Tab cycles;
  `yard.view` = first; rows have no numbers / 1-9 picks any more). Keys act on what the current view shows
  (`n` = new worktree / new agent, `D` = remove worktree / stop agent).
  Enter on an agent = "go to" (switch + link); Shift+Enter = link only. `/`
  filters fuzzily (`vim.fn.matchfuzzypos`, best score first, matched letters
  highlighted; projects match on the folder name only).
- **Prompt builder = chat convention:** Enter sends, Shift+Enter is a new line.
- **Dispatch** (fire-and-forget): describe a task → new worktree + agent started
  there with the task as its first message. The editor does NOT switch and the
  link does NOT change; the new worktree + working agent simply appear in the yard.
- **Starting an agent in the editor's current folder links to it.** Starting in
  another worktree does not link (just a message).
- **Viewing ≠ linking.** The viewer can show any agent; the link decides where
  prompts go.
- **Agents through tmux:** switchyard knows agents only as CLI programs in tmux
  panes. Finding: snapshot of `tmux list-panes -a` + `ps` (snapshot.lua), the
  first configured agent walking down each pane's process tree. Sending:
  bracketed paste + Enter into the pane. Following: the pane's
  `pane_current_path` (the agent's real working directory). No agent
  extensions (pi-nvim is gone), no sockets, no registries.
- **Dependencies:** hard dependencies are PROGRAMS only (git, tmux, fd, the
  agents; reported by the health check). switchyard never requires another
  Neovim plugin. Every plugin integration is optional (`pcall(require, …)`),
  lives in `lua/switchyard/integrations/`, has a no-dependency fallback or is
  simply not offered, and is reported by the health check. Pluggable features
  follow the `terminal` pattern: `"auto" | <name> | function(...)`.
- **Projects view:** projects only (no worktrees of other repos): the
  current project, `projects.pinned`, projects with agents, recent ones
  (`stdpath("state")/switchyard/recent.json`), the cached last scan
  (`projects.json`), then `fd` over `projects.roots` minus
  `projects.exclude` (junk: Library, node_modules, .cache, .Trash, nvim's
  pack dir, .oh-my-zsh, .claude/plugins). Enter = switch to its main
  worktree. `&` and `*` stay about the current repo (outside git: the folder
  itself is the one "worktree", so agents can be started there).
- **Window style:** titles and key hints never go in the border (Neovide
  draws them over the border line). Title = the float's winbar
  (`ui.title(win, chunks)`), hints = a virtual line below the last line
  (`ui.hints(buf, text)`); both add a line to the window's height.
- **Questions in switchyard's own style:** choices via `menu.open`, text via
  `menu.input` (a small float below the yard when opened from it; ⏎ confirm,
  Esc cancels, clicking elsewhere cancels). Never `vim.ui.select` /
  `vim.ui.input` (those end up at the bottom of the screen).
- **Plugin has no default global keymaps.** It exposes functions/commands; my
  config maps keys. Buffer-local keys inside plugin windows are fine and
  configurable via `config.keys`.
- **Async everywhere**: shell out via `util.run` (vim.system + vim.schedule).
  Only the health check may `:wait()`.
- **Messages**: progress → `nvim_echo(…, false, {})` (no history); results and
  errors → `vim.notify`. Anything that changes layout calls `vim.cmd("redraw")`
  before notifying (avoids "Press ENTER" prompts that break window changes).
- **Callbacks from menus that touch windows are `vim.schedule`d.**
- Terminal-agnostic, OS-agnostic where possible (repo will be public).

## Module map (as designed; verify against code)

```
plugin/switchyard.lua        :Switchyard → open the yard; :Switchyard <folder> → switch there
lua/switchyard/
  init.lua                   setup(opts) → config, sessions, live; public API:
                             switch, prompt, dispatch,
                             prompt_line, draft_status, link_here, status, open_yard,
                             toggle_view, focus_view, open_external
  config.lua                 defaults + setup (no unknown-option warning yet; lists replaced
                             not merged)
  health.lua                 :checkhealth switchyard — programs (git, tmux), external
                             terminal, follow edits, agents (installed, running)
  util.lua                   run(cmd, {cwd, stdin}, cb(ok, stdout, stderr)) — async;
                             progress(text) (echo cut to v:echospace)
  worktrees.lua              plain git: parse(porcelain), list(cwd, cb) →
                             {branch, path, current, main, symbols ("*" = uncommitted)};
                             create(cwd, branch, cb(path)) → "<repo>.<branch>" next to the
                             main worktree: existing/remote branch = `git worktree add
                             <path> <branch>`, new = `-b <branch> <path> <default branch>`,
                             already checked out = its path; remove(cwd, wt, cb) =
                             `git worktree remove` + `git branch -d` (merged only)
  projects.lua               switch(dir): refuse on unsaved, tabonly/only/enew, delete
                             file buffers (buftype==""), stop LSP clients, cd, redraw,
                             notify, fire User SwitchyardSwitched {from,to};
  tmux.lua                   list, free_name, new(name, cwd, cmd, cb(pane_id)),
                             paste(pane, text, cb) (bracketed), submit(pane, text, cb)
                             (paste + 50 ms + Enter), rename, kill, attach_cmd
  agents.lua                 agent tables {name, cmd, continue?, history?, task?, fork?, match?};
                             presets pi / claude / codex (pi fork = --fork <newest
                             ~/.pi/agent/sessions file>, claude fork = --resume <id from
                             ~/.claude/sessions/<pid>.json> --fork-session; the fork note
                             is the copy's first message); history(cwd, running) = earlier
                             sessions {time, title, cmd} newest first, running ones left
                             out (pi: ~/.pi/agent/sessions files, title = first prompt,
                             `pi --session <file>`; claude: ~/.claude/projects/<path with
                             non-alphanumerics as ->/<id>.jsonl, title = last custom/AI
                             title or last prompt read from the file's tail, `claude
                             --resume <id>`); configured(), installed(),
                             task_cmd(agent, task)
  snapshot.lua               parse(panes, ps, agents) → sessions {agent, pid, pane, tmux,
                             cwd, started}; take(agents, cb) runs tmux + ps side by side
  sessions.lua               cache of the last snapshot: all, in_folder, linked,
                             linked_pid, link(session, quiet), status, name (= tmux),
                             describe, send (waits until the tmux session is 4 s old,
                             then tmux.submit); update(list) (fires
                             SwitchyardSessionsChanged only on a change, refreshes the
                             link, follows a MOVED linked agent: `seen_cwd`/`follow_to`,
                             retried on BufWritePost); refresh(cb) (one snapshot at a
                             time); arrival rules on VimEnter/DirChanged after a fresh
                             snapshot; 2 s timer
  actions.lua                confirm(title, yes_label, fn) (menu, "No" first),
                             with_agent(cb) (asks when several are installed),
                             continue_agent(cwd) (menu of earlier sessions of every
                             installed agent, 9 newest, age on the right; agents without
                             history offer their `continue` command),
                             create_worktree(cwd, on_done(path)), remove_worktree(cwd,
                             wt, on_done, agents) (refuses current/main),
                             stop_agent(session, on_done) (tmux kill-session)
  launch.lua                 start(agent, cmd, label, cwd?, cb)/new/fork —
                             tmux.new gives the pane; wait until an agent runs in THAT
                             pane (refresh every 500 ms, 30 s), then link only if it runs
                             where the editor is (checked then), else "started <name>"
  ui.lua                     shared highlights (linked to standard groups, default=true)
                             + hide/show cursor (guicursor → blended hl), one shared save;
                             badge text color picked by WCAG contrast (Normal fg vs bg)
  menu.lua                   yard-style small menu (numbered items, key/danger, 1-9);
                             used for every choice; menu.input for text
  live.lua                   live reload: one fs_event per folder of loaded file buffers
                             (refcounted), debounced checktime, skips modified buffers
  yard.lua                   the yard: three views (worktrees, agents, projects), Tab
                             cycles; fuzzy `/` filter (`filtered(rows, texts_of)` +
                             `match` = matchfuzzypos); projects: `load_projects()` once
                             per open (current, pinned, recent, cached, then fd via
                             projects.find, redrawn every 100 ms as results come);
                             `worktree_list()` = git's or `plain_folder()` outside git.
                             close() returns to the window it was opened from
  projects.lua               (also) root(dir) (a linked worktree's `.git` file gives
                             the main repo), remember/recent, cached, find(on_found,
                             on_done) = fd --hidden --no-ignore -t d --prune -g .git
                             (streamed, cached)
  view.lua                   the viewer (split + statusline with agent tabs, cycle,
                             external terminal)
tests/*.lua                  nvim --headless -u NONE --cmd "set rtp+=." -l tests/<name>.lua
                             (live: live reload; arrival: arrival rules + peek (fake viewer);
                             history: earlier sessions from a fake home;
                             launch: linking after a start; yard: open/close, fuzzy
                             filter, projects view (fd faked), plain folder;
                             view: showing/hiding, also as the last window)
```

## Status

### Done and working

- Health check, config, git worktrees list/create/remove, project + worktree
  switching (with the nvim-tree User event in my config).
- Agents through tmux (pi, Claude Code, codex presets; own agents in config):
  found, started, forked, sent to and followed without agent extensions.
- Linking, arrival rules, following (move-only), tmux names in statusline.
- Launching agents in tmux (new/continue/fork) from `start_agent`.
- **Continue earlier sessions** (`c` in the worktrees view): a menu of the
  worktree's earlier sessions (all installed agents, newest first, running ones
  left out), so agents can be stopped (`D`) to free memory and resumed later.
- **Yard, Oct 2026:** fuzzy `/` filter, a projects view (see Conventions),
  the folder itself as the one worktree outside git. (An fzf-lua version of
  the yard and the menus was built and reverted, see git history of
  feature/fzf-yard.)
- **Compact yard** (replaced part 1): one float sized to its content (width
  50..90, height ≤ 60% of lines), centered, opens in normal mode. Two views,
  Tab toggles, remembered while Neovim runs (`yard.view` = first view):
  - worktrees (current repo): number, `@`, branch, `*` (uncommitted), agents on the
    right (`● <linked agent's tmux name> +n` in green / `● n`). Title is
    `switchyard · <view>` in both views (no repo name);
  - agents (this repo only: one project per yard): number, `●` + tmux name,
    branch on the right; linked first, then by worktree. Agents whose folder is
    gone (kept after "remove worktree") show as "removed worktree".
  - Keys (`keys.yard`): Enter (worktree: switch · agent: go to = switch + link),
    Shift+Enter (worktree: peek · agent: link only, yard stays), `1`–`9` = Enter
    on row n, j/k and Ctrl-N/P, Tab, `/` filter (a 1-line float above the list
    only while filtering; Enter acts, Esc clears and removes it), Ctrl-R
    refresh, `q`/Esc close. Footer hints per view.
  - One action list per view in yard.lua (`actions`: key name in `keys.yard`,
    label, run(row), danger, any_row). Keymaps, the `.` menu (the row's
    actions) and `?` (all keys of the view) are built from it: a new action
    shows up everywhere. `a`/`c` ask which agent only when several are
    installed. menu.lua returns focus to the window it was opened from.
    Menus opened from a float sit below it (above when there's no room);
    worktree choices end with "new worktree…".
  - No "move" action: linking only changes where the editor's prompts go;
    moving an agent = `f` fork into a worktree (or "new worktree…") + optionally
    `D` on the original. A real move isn't generic (pi-worktrunk has a
    `worktrunk` tool but no switch command; Claude Code's plugin only has
    `/wt-switch-create`; pi-nvim delivers socket messages as user messages, not
    slash commands). Claude Code's own `EnterWorktree` does move its process:
    that's followed through tmux.
  - Kept: highlights, selection per view by row key, cursor hidden + column
    locked, closes when focus goes to a normal window, returns to the origin
    window, redraws on SwitchyardSessionsChanged / VimResized.
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
- **Follow edits**: removed (Oct 2026). `link_here()` (Cmd+Shift+H) links an
  agent here after a peek.
- **Peek**: Shift+Enter in the yard (`keys.yard.alt_activate`) switches but keeps the
  link (and the viewer): `sessions.keep_link_for(dir)` is a one-time hold that `on_arrival`
  consumes; cleared again when the switch is blocked.
- **Switching from any window**: `projects.switch` starts from a fresh window
  (`botright new` + `only`), so switching while focus is in the tree, the viewer
  or a float no longer eats the tree window.
- Checked: `tmux.new` cds inside the shell line; `menu.lua` used by
  `launch.pick` and the viewer's choice; `ui.lua` used by yard.lua; config has
  `viewer.width`, `terminal`, `live_reload`, `projects`.

- **Viewer terminal options from sidekick.nvim** (Oct 2026): the viewer split
  glitched sometimes. sidekick.nvim was tried as the viewer and then dropped
  (only switchyard should be installed); its terminal window settings were
  copied into view.lua (`terminal_options`, applied after the terminal buffer
  is in the window; `start_typing` = leftcol 0 + startinsert; TermClose keeps
  the window when attaching failed within 3 s). Attribution:
  `licenses/sidekick.nvim.txt` + README. PR #2 (scope cut to a worktree
  switcher) was merged and then reverted; its folders view + `:Switchyard
  <folder>` live in branch `feature/sidekick-scope`.

### Open (small)

- `config.setup` has no unknown-option warning yet.

### Next steps (in this order)

1. **Yard part 2 — actions per view** (done: worktrees `n` `D` `a` `c` `f` `y`;
   agents `v` `g` `n` `f` `r` `D`; no `m`, see "No move action"; no `p`: one
   project per yard, for another repo you step out of the plugin;
   `N`/`F` come with dispatch, `s` with the prompt builder) (row under cursor is the subject;
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
   | `r`                             | —                                        | rename tmux session (update the name cache)                                           |
   | `y`                             | copy path                                | —                                                                                     |
   | Tab                             | agents view                              | worktrees view                                                                        |
   | `1`–`9`, `/`, `?`, `.`, `q`/Esc | same in both                             | same in both                                                                          |
   - With several agents installed, ask which one (menu); with one, use it.
   - Later: agent state (working / waiting); Claude Code has it in
     ~/.claude/sessions/<pid>.json (`status`), pi has no generic source; was: pi-worktrunk's `wt list`
     markers; lock marker for locked worktrees.
2. **Dispatch** — done as the prompt builder's target (see step 3). Original notes:

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

3. **Prompt builder** — part 1 done (prompt.lua: one float, target in the
   title, grows with wrapped text up to 8 lines, Enter sends / Shift+Enter or
   Ctrl-J new line, Esc = normal mode, q/Esc in normal = close, Ctrl-X clear;
   draft = one hidden buffer that survives closing; the window **disappears on
   focus loss**, my statusline shows DRAFT via `draft_status()`; Cmd+L opens).
   Part 2 done: contexts (Visual Cmd+L via `prompt()` in visual mode, Cmd+Shift+L
   `prompt_line()` = line + diagnostics; snapshot of the lines at add time; a
   non-focusable list above the input, one line per context; ranges highlighted
   (Visual) while open; Ctrl-F = the file it was opened from, as a path
   (`File: <path>`, the agent reads it); Ctrl-D = menu to remove one, Ctrl-X clears all; sent as
   `From <path>:<a>-<b>:` + fenced code (+ `- SEVERITY: message`), paths
   relative to the target's folder when inside it, else absolute). DRAFT n in
   the statusline. The builder stays open when a switchyard menu takes focus.
   Part 3 done: Ctrl-T = menu of this repo's agents, the prompt goes there
   (link unchanged; back to the linked agent after sending); yard `s` =
   `prompt.open_for(session)`; title `→ name (linked) (in <wt>)`, target looked
   up on open/choose only (not per keystroke); Ctrl-O hand-over =
   `tmux.paste` (load-buffer from stdin + paste-buffer -p, no Enter) into the
   agent's input, then the viewer shows it. Cross-worktree paths are absolute
   (no "(worktree <branch>)" suffix yet).
   Part 4 done: dispatch = the builder's "new worktree + agent" target
   (Ctrl-T item, yard `N` in both views, public `dispatch()` also in visual
   mode, Cmd+Shift+D). Enter asks for the branch (suggested: slug of the first
   line), creates it with git (base: the default branch), starts the
   agent there via `agents.task_cmd(agent, task)` (`cmd` + task); no link,
   no switch. Not done: choosing the base (current worktree instead of default).
   Spin-off = `f` in the agents view → "new worktree…".
   as the "new worktree" target (`N`, `dispatch()`). Original design notes:
   (compact, chat-style; NOT via the yard). Inspired by
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

4. (Done differently: every agent goes through tmux, see "Agents through
   tmux"; the separate branch feature/claude-adapter is superseded.)
    hand-over already works for any agent in tmux.
5. README, docs, fuzzy matching, polish.

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
  boolean value").
- `vim.system` / luv callbacks run in a fast context → `vim.schedule` before
  touching the API.
- Two quick `vim.notify` messages → "Press ENTER" prompt → window changes (like
  opening nvim-tree) get lost. `redraw` before notifying in layout-changing code.
- fzf-lua / `vim.ui.select` callbacks fire before the picker closes → schedule.
- JSON null → use `vim.json.decode(s, { luanil = { object = true, array = true } })`.
- An agent's program isn't always the pane's process: pi via volta is
  `node …/bin/pi` with a child `pi`; switchyard starts agents through a shell
  line that mentions the agent. Match the program (or interpreter + script),
  never any word on the command line (`grep pi` isn't pi); take the first match
  walking DOWN from the pane.
- Claude Code names its process after its version (`2.1.283`): tmux's
  `pane_current_command` is useless for matching; use `ps` command lines.
- An agent's process exists before its screen takes input: text pasted right
  after the start is lost. `sessions.send` waits until the session is 4 s old.
- While an agent shows a question (permission, Claude's folder trust), a sent
  Enter answers it (Claude's trust question defaults to "No, exit"): never send
  on start; fork notes and dispatched tasks go in the start command instead.
- In zsh, `=name` on the command line expands to a program path; quote tmux
  targets when testing in a shell (switchyard itself passes args without a shell).
- `bufhidden = "hide"` for buffers whose windows open/close repeatedly;
  delete them explicitly on close.
- Measure display width with `vim.fn.strdisplaywidth`, not `#` (bytes).
- The statusline must never do I/O: use cached values.
- A message longer than the message line makes Neovim stop at "Press ENTER"
  and swallow the next key: progress goes through `util.progress` (cut to
  `v:echospace`), notifications stay short (no long tmux names or paths).
- A pending redraw (e.g. the yard closing, insert mode ending) wipes a message
  shown right before it: `redraw` before `vim.notify` in switch paths.
- `:only` also closes the viewer: whoever switches must bring it back.
- A split inherits the editor window's local options (number, signcolumn,
  `scrolloff = 19` from my config, cursorline): a terminal needs its own
  (`view.lua` `terminal_options`), set after its buffer is in the window.
- The last window can't be hidden or closed (E444): `view.hide()` swaps in an
  empty buffer when the viewer is the only window left.
- A `local function f` is only visible BELOW its definition; above it, `f`
  silently means the global `f` (nil) and fails only when that code runs
  (hit twice: live.setup, prompt's add_file). Put setup() last, or declare
  `local f` early. Check for accidental globals before committing:
  `for f in lua/switchyard/*.lua; do luajit -bl "$f" | grep -oE 'GGET.*"[a-z_]+"' ; done`
  (only vim, require, package and Lua builtins may show up).
- `ipairs({ a, b })` stops at the first nil: iterate optional values with
  `pairs` over named keys (the yard's close left its window open this way).
- `follow()` must react to a _move_ of the linked agent (compare with the cached
  cwd), not to "agent is elsewhere", or it hijacks the editor after "keep link".
