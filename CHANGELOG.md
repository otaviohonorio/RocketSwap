# Rocket Swap 0.31.0

- **A gear set missing an item no longer switches.** The game does not leave the empty slot alone
  — it keeps whatever you are wearing, so the swap "works" and you end up with the previous
  role's piece in a set built for another one, with nothing saying so. And a set with a missing
  piece can never report itself as in use, so the step never got its check mark.
- The preset is marked in red **before you click**, and the tooltip names the missing slots.
- The Load button becomes the action that helps: **Save set** when you are already wearing the
  rest of it, or **Equipment Manager**, which opens the game's own manager on the right tab.
  Same from chat with `/rs fix`.
