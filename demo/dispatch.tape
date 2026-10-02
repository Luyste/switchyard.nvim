# Dispatch: a task for a new agent in a new worktree, without leaving your work.
Output "demo/media/dispatch.gif"
Source "demo/common.tape"

Type " d"
Sleep 1.5s
Type "Add a dark theme option to settings.conf"
Sleep 1.5s
Enter
# Branch name suggested from the task
Sleep 2.5s
Enter
Sleep 2s
# The new worktree and its agent show up in the yard
Hide
Wait+Screen@60s /started/
Show
Sleep 2s
Type " y"
Sleep 3s
Tab
Sleep 3s
Type "q"
Sleep 1s
