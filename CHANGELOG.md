# Rocket Swap 0.35.2

**A gear set missing an item no longer switches.** When a saved set asks for a piece you no
longer have, the game does not leave that slot empty — it keeps whatever you are wearing. The
swap "works" and you walk away with the previous role's piece in a set built for another one,
with nothing saying so. And such a set can never report itself as in use, so the step never got
its check mark.

- The preset is marked in red **before you click**, and the tooltip names the missing slots.
- Load is disabled for it, and the red strip carries the fix: **Save set** when you are already
  wearing the rest of it, or **Equipment Manager**, which opens the game's own manager on the
  right tab. Same from chat with `/rs fix`.

**The preset list is now a card.** Each field gets its own labelled line — Specialization,
Talents, Gear, Appearance — instead of one run-on line with dots between values. The name gets
the first line to itself, the icon sits beside the fields, and the card is only as tall as the
fields that preset actually defines. The window is sized so three full presets fit without
scrolling.

**The wrong-gear warning is now one switch per content: PvE and PvP.** They used to share a
single switch, so anyone who runs Mythic+ every night and PvP now and then had to choose one
setting for both. If you had it turned off, it stays off for both. The checkboxes are laid out
in two columns to match, and `/rs warn pve` / `/rs warn pvp` toggle them from chat.

**Smaller things**

- Every label for the queue-pop summary now says **PvP queue**, because that is all it watches:
  battlegrounds and arenas. The dungeon and raid finders are a different system and never
  triggered it — the old wording did not say so.
- The Brazilian Portuguese labels now say "Ready Check", which is what players actually call it.
