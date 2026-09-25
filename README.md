# Rocket Swap

Presets that tie **specialization + talents + gear + appearance** together, switched with one
click. For World of Warcraft: Midnight (12.x).

> 🇧🇷 [Leia em português](README-ptBR.md)

## Why it exists

Changing role in WoW is not one action, it is four — and they live in four different windows.
Anyone who alternates between tank and damage does this several times a session, in the right
order, without forgetting any of them. The addon stores the preset and performs all four.

## What it solves, and what is not obvious

**A swap is a chain, not a command.** Every step depends on the previous one and is confirmed by
a game event, never by reading state right after the call — the server takes its time, and
checking immediately reports failure on a swap that is already on its way.

**The appearance change is a protected API.** `ChangeToOutfit` returns success and does nothing
when called from addon code. Since patch 12.0.5 there is a secure `outfit` action, which is why
the appearance only changes through the **Load** button — it happens inside the click, before
everything else. The final step only verifies that it took effect.

**And that secure click was causing a second cast.** Because the appearance change *casts*, and
the game refuses to start a specialization change while another cast is in flight, the first
`SetSpecialization` was refused on every single swap that touched both. The addon read that as
"the game is busy" and retried four seconds later — so the player saw two cast bars with a dead
gap between them. The specialization step now waits for the in-flight cast to clear before
asking. Diagnosed from the addon's own diary, not from a guess.

**A gear set missing an item does not switch.** When a saved set asks for a piece you no longer
have, the game does not leave that slot empty — it **keeps whatever you are wearing**. So the swap
"works" and you walk away with the previous role's trinket in a set built for another role, with
nothing on screen saying so. On top of that, a set with a missing piece can never report itself as
in use, so the step never closes. Rocket Swap refuses the swap instead, marks the preset in red
before you click, names the missing slots, and The Load button goes dark — a button that
takes the click and then answers "it did not work" is worse than one that is plainly disabled —
and the red strip carries the action that helps: **Save set** when you are already wearing the
whole set except what went missing (the only case where saving over it fixes rather than
destroys), or **Equipment Manager**, which opens the game's own manager on the right tab. Same
from chat with `/rs fix`.

## How to use it

| Command | What it does |
|---|---|
| `/rs` | opens the window |
| `/rs load <name>` | loads a preset by name |
| `/rs list` | lists the presets |
| `/rs macro` | makes a macro for every named preset (in this character's macros) |
| `/rs gear` | shows what each slot is reading as |
| `/rs progress` | turns the floating progress panel on or off |
| `/rs log` | the diary of the last swaps (this is what answers "why didn't it switch?") |
| `/rs warn` | turns the wrong-gear warning on or off |
| `/rs ready` | turns the ready check summary on or off |
| `/rs queue` | turns the PvP queue pop summary on or off |

The minimap button opens the window; right-click lists your presets to pick one.

While a swap runs, a floating panel shows which steps the preset asks for, which one is running
and which have closed. The bar advances **per closed step**, never against a clock: the chain
cannot know how long the server will take, and a bar racing an invented estimate stalls halfway
and lies. When the swap finishes cleanly the panel turns green and says so for three seconds; if
a step failed it keeps the list on screen until you close it.

## Architecture

| File | Responsibility |
|---|---|
| `Core.lua` | lifecycle, SavedVariables, events |
| `Log.lua` | the diary in SavedVariables — read from outside the game when something goes wrong |
| `Data.lua` | the step chain and the game APIs; handles Secret Values |
| `UI.lua` | the window: list, editor and in-window progress |
| `Progress.lua` | the floating progress panel |
| `Gear.lua` | reading the equipment set and the wrong-gear warning |
| `Alert.lua` | the ready check and queue pop summaries |
| `Minimap.lua` | the minimap button |

`tests/harness.lua` runs the addon outside the game with LuaJIT, and `tests/sabotar.py` breaks
the code on purpose to confirm the tests catch it — counting `ok` lines is not an acceptance
criterion.

```
luajit tests/harness.lua
python tests/sabotar.py
```

## Support

These addons are free and always will be. If they save you time every session, there are two
ways to help, and both pay for the same thing — the hours that go into keeping them current
with each patch:

- **[Ko-fi](https://ko-fi.com/ottorocket)** — a one-off tip, any amount, **no account needed**.
- **[GitHub Sponsors](https://github.com/sponsors/otaviohonorio)** — recurring, if you'd rather.

Doing neither costs you nothing here. A good bug report is worth just as much.

## License

MIT — see `LICENSE`.
