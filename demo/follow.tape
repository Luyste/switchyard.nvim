# Live reload and following edits: the editor shows what the agent changes.
Output "demo/media/follow.gif"
Source "demo/common.tape"

# Follow edits on, look at app.py, agent in the split
Type " f"
Sleep 1.5s
Type ":e app.py"
Enter
Sleep 1s
Type " v"
Sleep 2s
Ctrl+]
Sleep 1s
Type " p"
Sleep 1s
Type "In parser.py, make parse_line raise a ValueError with a clear message when a line has no '='."
Sleep 1.5s
Enter
Sleep 3s
# (skip the model's thinking time)
Hide
Wait+Screen@300s /raise ValueError\(/
Sleep 2s
Show
# parser.py opened by itself, on the changed line
Sleep 6s
