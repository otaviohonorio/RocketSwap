# Rocket Swap 0.38.0

**Every preset gets its own macro, ready on your action bar.** Save a preset with a name and the
addon creates a macro with the same name and the preset's icon — in this character's macros, not
the general ones — and puts it on the first empty slot of a visible action bar. One click (or a
key binding on that slot) loads the whole preset: specialization, talents, equipment **and the
transmog outfit**.

- **Drag a preset to your action bar**: drag its card from the list, like a spell from the
  spellbook, and drop it on the slot you want.
- The chat tells you where the macro went ("Action Bar 3, button 4"). If no visible bar has an empty slot, drag it from
  `/macro` (the character tab).
- Renaming the preset renames its macro (macro names stop at 16 letters); deleting the preset
  deletes its macro. A macro you delete yourself is not made again, unless you type `/rs macro`.
- `/rs macro` makes the macros for presets you saved before this version.
- In combat nothing changes: the macro is made when the fight ends.

**All or nothing.** Before a preset switches, every step it needs is checked with the game —
specialization (including its cooldown, and standing still, since moving cuts the cast), talents,
the equipment set (missing or locked items, a deleted set) and the appearance (its cooldown, a
style event, a deleted outfit). If anything would fail, **nothing is changed** and you are told
why, with the time left when the game lets it be read — in red in the middle of the screen, in
chat and in the window. No more half switches such as "loaded, except the appearance".

- A click in combat no longer queues the switch for after the fight: it is refused, with a warning.
- A preset with an appearance only switches through a click on it (the window or its macro).
- A character has 18 macro slots; when they are full, the chat says so and the preset keeps
  working from the window.
