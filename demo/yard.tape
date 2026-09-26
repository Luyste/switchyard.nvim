# The yard: worktrees, agents, actions, filter, switching.
Output "demo/media/yard.gif"
Source "demo/common.tape"

# Open the yard: this repo's worktrees, the linked agent marked
Type " y"
Sleep 2.5s
# The agents view, and back
Tab
Sleep 2.5s
Tab
Sleep 1s
# What can I do with this worktree?
Type "."
Sleep 3s
Escape
Sleep 1s
# Filter, then switch: the link moves to the agent there (see the statusline)
Type "/"
Sleep 0.5s
Type "parser"
Sleep 1.5s
Enter
Sleep 2s
Type ":e parser.py"
Enter
Sleep 2s
Type " y"
Sleep 3.5s
Type "q"
Sleep 1s
