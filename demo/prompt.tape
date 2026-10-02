# The viewer and the prompt builder: code as context, sent to the agent.
Output "demo/media/prompt.gif"
Source "demo/common.tape"

# The linked agent's terminal next to the code
Type " v"
Sleep 2.5s
Ctrl+]
Sleep 1s
# Select parse_line and ask about it
Type "4GV2j"
Sleep 1s
Type " p"
Sleep 1.5s
Type "What happens here when a line has no '=' sign? One sentence."
Sleep 1.5s
Enter
Sleep 3s
# (the local model takes a while: skip the wait)
Hide
Wait+Screen@180s /ValueError|unpack|raise/
Sleep 3s
Show
Sleep 5s
