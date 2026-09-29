# Rocket Swap 0.38.1

- **Fixed a Lua error on every click of Load** in the addon's window (0.38.0). The switch
  itself went through; the error also kept the window from holding the transmog outfit back
  when the switch was refused before it began.
- **The preset rows keep up with the game.** A row could stay with "1 item missing", and Load
  off, for a gear set that had every piece: what it showed was read once, at an event. The
  missing-item warning, the Load button and the "in use" mark are now checked against the game
  while the window is open.
