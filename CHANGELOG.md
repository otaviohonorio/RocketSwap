# Rocket Swap 0.38.1

- **Fixed a Lua error on every click of Load** in the addon's window (0.38.0). The switch
  itself went through; the error also kept the window from holding the transmog outfit back
  when the switch was refused before it began.
- **The preset rows keep up with the game.** A row could stay with "1 item missing", and Load
  off, for a gear set that had every piece: what it showed was read once, at an event. The
  missing-item warning, the Load button and the "in use" mark are now checked against the game
  while the window is open.
- **Fixed an endless loop in the wrong-gear warning.** When the game had an item's data but its
  tooltip was still loading, the warning asked for the item again and again until the game cut
  it off, with a stutter and a Lua error.
- **The macro limit is the game's: 30 per character.** The addon counted 18 and refused to make
  a preset's macro with room to spare.
