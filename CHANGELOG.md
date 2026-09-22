# Rocket Swap 0.30.2

- **Fixed the double cast when loading a preset.** Changing the appearance casts a spell, and the
  game refuses to start a specialization change while another cast is in flight — so the first
  attempt was always refused and the addon retried four seconds later. You saw two cast bars with
  a dead gap between them. The specialization step now waits for the cast to clear before asking,
  which also removes those four seconds from every swap.
- **New floating progress panel.** It appears on its own when a swap starts, so you can see what
  is happening without keeping the window open: which steps the preset asks for, which one is
  running, and which have closed. The bar advances per finished step, never against a clock.
- When everything finishes cleanly the panel turns green and says so for three seconds. If a step
  failed it keeps the list on screen until you close it.
- Turn the panel off with `/rs progress`.
