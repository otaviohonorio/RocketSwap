# Rocket Swap 0.37.0

**Right-clicking the minimap button no longer changes your specialization.** It now opens a menu
listing your presets, and nothing happens until you pick one.

It used to load your last preset immediately. A right-click on a minimap icon is expected to open
a menu — that is what every other addon does, including the other Rocket addons — so a click made
in that expectation was silently swapping spec, talents and gear. Thank you to the player who
reported it with a video; it was not reproducible on the author's own characters, because every
preset there has an appearance saved, and presets with an appearance already opened the window
instead of swapping.

Also in this version:

- The shortcut no longer closes the window when it is already open.
- `/rs load <name>` is unchanged, and remains the way to switch from a macro or keybind.
