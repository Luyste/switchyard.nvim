# Shared settings, included by every demo tape (run from the switchyard repo root).
Set Shell "bash"
Set FontSize 16
Set Width 1280
Set Height 720
Set Padding 16
Set TypingSpeed 60ms
Set Theme "OneDark"
Env TMUX_TMPDIR "/tmp/switchyard-demo-tmux"
Env PS1 "$ "

# A fresh demo repo with two idle agents, then Neovim in it
Hide
Type "R=$PWD && demo/setup.sh >/dev/null && cd ~/personal/projects/switchyard-demo && sleep 6 && nvim -u $R/demo/init.lua parser.py"
Enter
Wait+Screen@30s /parse_line/
Sleep 1s
Ctrl+L
Sleep 0.5s
Show
Sleep 1s
