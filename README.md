# Stickman Dojo (prototype)

A 3D martial arts combat prototype built around **defence**: parrying, dodging, ducking and hopping.
You fight a training dummy that throws telegraphed strings of high, low and unblockable attacks.
The feel takes inspiration from close-quarters "read and react" brawlers: tight parry timing, a structure
(posture) meter, and counters that only land once you've opened the enemy up.

Everything is made from primitive shapes and procedural animation, so there are no external assets. Every joint
is driven by a damped spring, with a walk/strafe cycle, lean, a fighter's bounce and hit recoil layered on top.
There is no hit-freeze and no hit-stun: the game never pauses on impact, and getting hit never takes control away
from you (you get knocked back a little instead).

## How to run

1. Install **Godot 4.3 or newer** (standard build, not .NET): https://godotengine.org/download
2. Open Godot, click **Import**, and select `project.godot` in this folder.
3. Press **F5** (or the ▶ Play button at the top right).

Plug in a controller before or after launching. Xbox, PlayStation and most generic pads work.

## Controls

| Action | Controller (Xbox / PlayStation) | Keyboard / mouse |
|---|---|---|
| Move / strafe around the dummy | Left stick (or D-pad) | WASD |
| **Flick dodge** (any direction) | Flick the right stick: left/right = sidestep, down = backstep, up = slip in | Tap an arrow key |
| **Block** (hold) | LB / L1 (or LT / L2) | K or right mouse |
| **Parry** | Tap block right as the hit lands | Same |
| Dodge button (uses left-stick direction) | RB / R1 (or RT / R2) | Shift or L (+ WASD) |
| **Duck** (hold) | B / Circle | C or Ctrl |
| **Hop** | A / Cross | Space |
| Counter strike | X / Square | J or left mouse |
| Reset | Start / Options | R |
| Slow-motion training (50%) | Back / View / Share | T |

## How the fight works

The dummy's attacking limb glows while it winds up, then **flashes bright just before impact**. That flash is your cue.

| Telegraph | Attack | Answers |
|---|---|---|
| Yellow, `HIGH` | High punch | Duck, dodge, parry, or block |
| Blue, `LOW` | Low sweep | Hop, dodge, parry, or block |
| Red, `UNBLOCKABLE` | High or low, can't be blocked or parried | Duck it (high), hop it (low), or dodge |

- **Parry**: press block within 0.16 s of impact. Mashing doesn't work: re-pressing within 0.35 s won't open a new window.
  Parries fill the dummy's structure. Parrying the last hit of a string staggers it.
- **Block**: safe, but each blocked hit fills *your* structure. When it's full your guard breaks: you're shoved back
  and can't block for 0.8 s, but you can still move and dodge.
- **Perfect avoid**: dodge, duck or hop within about 0.22 s of impact. The dummy's string is cancelled and it's open for a counter.
- **Counter**: strikes are guarded unless the dummy is open (after a perfect avoid or a final parry). Counters fill its structure.
- **Structure break**: fill the dummy's structure bar to knock it down for free hits. It gets a little faster each time.
- Strings are 1 to 3 attacks long, and follow-ups come faster than openers.

## Code layout

| File | What it does |
|---|---|
| `scripts/main.gd` | Builds the dojo, camera, HUD, hitstop and camera shake |
| `scripts/player.gd` | Player state machine and all defensive timing (tuning constants at the top) |
| `scripts/dummy.gd` | Training dummy AI, attack strings and telegraphs |
| `scripts/stickman.gd` | Primitive-shape stickman, spring-driven joints, walk cycle and secondary motion |
| `scripts/poses.gd` | Pose library (joint positions) |
| `scripts/input_setup.gd` | Gamepad and keyboard bindings |
| `tests/bot_test.gd` | Headless bot that plays the game and prints stats |

Most of the feel lives in the constants at the top of `player.gd` and `dummy.gd` (`PARRY_WINDOW`, `PERFECT_WINDOW`,
`DODGE_IFRAMES`, windup times). Tweak those first.

## Headless smoke test

```
godot --headless --path . --fixed-fps 60 -s tests/bot_test.gd -- perfect
```

Modes: `perfect` (reacts to every telegraph), `hold_block`, `dodge`, `flick` (right-stick flicks), `walk`, `idle`. Each plays 60 seconds and prints the stats.
