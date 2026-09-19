# Mark Zero

Fly a powered armour suit over New York. Controller only, desktop only.

A rebuild of the browser version (three.js) in **Godot 4.6**, decided 2026-09-19. What came
across: the five armours and the flight model, which is the only part of the old project
worth keeping and the part that took the longest to get right. Everything else — world, UI,
menus — is new, because the game moved from a grey test plate to New York.

## Running it

Open `game/` in Godot 4.6 and press Play. **The first open takes a minute**: Godot imports
the six suit models, and scene import is an editor job — `godot --headless --import` skips
it silently, so the models only appear once the editor has been opened at least once.

Needs a controller. There is no keyboard fallback and that is deliberate: designing for one
device means the flight model can assume analog input everywhere, and the throttle can be a
trigger rather than an on/off key.

## Controls

| | |
|---|---|
| Left stick | move / slide |
| Right stick | turn the whole body |
| R2 / L2 | thrust / retro burn — both analog |
| R1 | repulsor |
| L1 | boost |
| ✕ / ○ | up / down |
| □ | interact |
| △ | put the armour on or take it off |
| L3 / R3 | hover lock / faceplate |
| OPTIONS | pause |

## Checks

```
godot --headless --path game --script res://tools/test_flight.gd
godot --headless --path game --script res://tools/test_world.gd
```

The flight tests assert the numbers measured in the browser build — 150 m/s to a stop in
0.85 s, a 70 m/s fall arrested in 0.48 s — so a change that alters how the suit flies fails
loudly instead of quietly.
