# Rocket Swap 0.31.0

- **A gear set missing an item no longer switches.** The game does not leave the empty slot alone
  — it keeps whatever you are wearing, so the swap "works" and you end up with the previous
  role's piece in a set built for another one, with nothing saying so. And a set with a missing
  piece can never report itself as in use, so the step never got its check mark.
- The preset is now marked in red **before you click**, the tooltip names the missing slots and
  explains what would go wrong.
- `/rs fix` updates a broken set with what you are wearing — offered only when you are already
  wearing the whole set except the missing pieces, which is the only case where saving over it
  fixes rather than destroys.
