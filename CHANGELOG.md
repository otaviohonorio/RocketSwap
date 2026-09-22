# Rocket Swap 0.32.0

- **The preset list is now a card.** Each field gets its own labelled line — Specialization,
  Talents, Gear, Appearance — instead of one run-on line with dots between values. The card is
  only as tall as the fields the preset actually defines, and the window is wider to fit it.
- **A gear set missing an item no longer switches.** The game does not leave the empty slot alone
  — it keeps whatever you are wearing, so the swap "works" and you end up with the previous
  role's piece in a set built for another one. And such a set can never report itself as in use,
  so the step never got its check mark.
- The Load button is disabled for those presets, and a red strip on the card says what is missing
  and offers the fix: **Save set** when you are already wearing the rest of it, or **Equipment
  Manager**, which opens the game's own manager on the right tab. Same from chat with `/rs fix`.
