# Agent skills

Claude Code loads every folder here as a project skill. They were picked for this game: a
Godot 4 3D stickman fighting prototype built around parrying and dodging, played on a
controller.

## Source and license

Copied unmodified from
[gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
at commit `c6ca6c41c839b68319ffc08430b99ab768debc32`. Licensed under the Apache License 2.0;
see `LICENSE` and `NOTICE` in this folder.

## What is here

| Skill | Why it is here |
|-------|----------------|
| `godot-gdscript` | GDScript typing, annotations and a headless compile check. |
| `godot-nodes-scenes` | Scene tree and instancing; ships the `check_godot_project.py` linter the other Godot skills call. |
| `godot-3d-essentials` | Camera, lights, `WorldEnvironment`, tonemapping and materials: the main fix when a 3D scene looks flat or washed out. |
| `godot-animation` | `AnimationPlayer`, `AnimationTree`, tweens and particles for attack, parry and dodge poses. |
| `godot-physics` | `CharacterBody3D`, hitbox and hurtbox areas, raycasts. |
| `godot-shaders` | Spatial shaders for outlines, hit flashes and a stylized look. |
| `godot-signals-groups` | Signals for hit, parry and dodge events that feedback hooks into. |
| `godot-resources` | Moves data such as attack timings and parry windows into `.tres` files. |
| `godot-audio` | Hit, parry and whoosh sounds and audio buses. |
| `godot-gdscript-headless-testing` | Headless tests, matching `tests/bot_test.gd`. |
| `game-feel` | Screen shake, flash, squash and stretch, knockback, hit-stop. |
| `camera-systems` | Third-person combat camera framing and smoothing. |
| `input-systems` | Input buffering, controller deadzones and rebinding, which parry and dodge timing depend on. |
| `game-ai` | Enemy state machines and attack telegraphs for the training dummy and future opponents. |
| `create-game-assets` | Art direction brief and asset pipeline, for when the look gets a proper pass. |

## Notes for this project

- The skills target Godot 4.7. This project declares 4.3 with the Compatibility renderer in
  `project.godot`; keep code to the 4.3 API unless the project is upgraded. Compatibility has
  no SSAO, SDFGI, SSR or volumetric fog.
- Hit-stop and hit-stun were removed from the prototype on purpose. The `game-feel` skill
  recommends hit-stop; do not add it back without asking.
- Skill helper scripts (`*.py`, `*.gd` under `scripts/` and `assets/`) only read project files.
  `create-game-assets` needs Pillow for its scripts.
