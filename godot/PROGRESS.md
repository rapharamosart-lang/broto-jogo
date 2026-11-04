# Broto — Godot 4.7 port

Source of truth for gameplay numbers and level data is still the web version (`inside-game/index.html` + `level.json`).
The Godot project mirrors it: `data/level.json` is loaded at runtime.

## How to run
```
godot --path godot/                       # editor/game (unpack broto-godot.zip.b64 first, see below)
godot --headless --path . -- --quit=4 --bot=right,run          # smoke test, prints state + position
xvfb-run godot --path . -- --x=36 --bot=right,run --botjump=.3 --shot=/tmp/a.png --frames=80
godot --headless --path . --export-release Web export/web/index.html
```
Test flags (after `--`): `--x --y` spawn, `--bot=right,run`, `--botjump=t1,t2`, `--botdash=t`, `--botdown=t`,
`--shot=path --frames=N`, `--quit=N`, `--probe`, `--touch`,
`--botatk=t1,t2` `--botup=t` `--botfocus=t0-t1` `--fresh` `--save=user://x.json` `--savetest` `--xp=N` `--buy=a,b` `--tree[=id]` `--god` `--hp=N` `--soul=N`.

Full project (assets, data, screenshots): `broto-godot.zip.b64` → `base64 -d broto-godot.zip.b64 > broto-godot.zip && unzip broto-godot.zip`.

## Phase 1 — foundation ✅ (this commit)
- [x] Project, Godot 4.7.2; Forward+ desktop / Mobile / Compatibility (web)
- [x] Rig exported from Blender (`tools/export_rig.py` → `assets/char/broto.glb`, 26 actions), AnimationTree (Transition + TimeScale)
- [x] Player CharacterBody3D locked to z=0: coyote .10s, jump buffer .13s, variable jump (cut .45), fall ×1.35, dash (12.5 / .17s, 1 air dash)
- [x] Wooden-puppet secondary motion (lean, squash, clack, turn springs)
- [x] Swimming ported from web `swimStep`: buoyancy spring, dive, surface, jump out, climb out, swim dash
- [x] Ropes (pendulum, grab/swing/climb/jump off) and auto-climb (step up / mantle, probe raycasts)
- [x] Pushable crates/barrels (RigidBody, z locked)
- [x] Level loader from level.json: terrain (vertex colours) + collision strip, walls, solids, beams, water, trunks, props by layer
- [x] Watercolor shader (wash, blooms, granulation; NO outlines, NO VHS), water shader (fresnel + waves, SSR reflection on Forward+)
- [x] Bright saturated lighting, crisp sun shadows, fog, side camera with lookahead
- [x] Leaf guide (basic follow/wait)
- [x] Input: keyboard, gamepad, touch buttons
- [x] Headless import + run with no script errors; rendered screenshots (xvfb/llvmpipe); Web export (nothreads) runs in Chromium

Known gaps: only the surface route is built (caves skipped); camera framing near ropes/trees in the foreground layer needs tuning;
leaf canopy colours read a bit cyan vs web; puppet tone is a flat warm white (web has no materials either); SSR not available on web.

## Phase 2 — combat & progression ✅
- [x] HK-style nail (`scripts/combat.gd`): 4-dir slash (up / down in air / side), pogo on down-hit (resets air dash + double jump), recoil, hit-stop (time_scale .05), i-frames with blink, knockback, focus heal (hold F/H/LB, 33 soul), soul gain
- [x] Enemies (`scripts/enemy.gd`): walker / charger / hopper / flyer / shooter / chaser / swimmer archetypes for every web type, warm telegraph glow + shake, beetles block frontal hits, projectiles, bosses flagged in save
- [x] Drops (soul shards, hearts), XP pop-ups; XP curve + levels to 50 (`scripts/progress.gd`, autoload `Prog`), +1 point per level
- [x] Skill tree UI (`scripts/ui/tree.gd`, Tab/N/Back): 3 branches with web names/costs/requirements, respec; passive effects wired: força, ritmo, alcance, carga, quique, eco, pulo duplo, controle no ar, investida (+air dash), mãos de corda, vento, pés leves, máscara, alma, foco, espinhos, resina
- [x] HUD (`scripts/ui/hud.gd`): soul vessel, focus arc, masks, XP bar, level, messages
- [x] Save/load JSON in `user://broto_save.json` (xp, points, tree, flags, bench position, hp); benches heal + save (press up); death → last bench
- [x] Caves: all room interiors (floors, ceilings, walls, ledges), doors/levers/benches with locks, underground water, omni lights, glowing crystals + fungi, light shafts, fireflies, zone lighting (fog/ambient change, sun fades)
- [x] Phase-1 gaps: foreground occluder fade, camera lookahead, low lake framing when swimming, leaf greens, wood-grain shader on the puppet
- [x] Tests (headless): side hits on beetle/plant, pogo kill (beetle → +10 XP), plant kill (+12 XP), buy (requirements respected), save→reset→load round trip, door `d_gruta_s` → Gruta (y −60); Web export runs in Chromium
- Not done / unverified: powers (Lança, Impacto, Raízes, Casca, Enxame) are listed but not implemented; `need` item doors stay locked (no items yet); boss fights only smoke-tested; balance untuned.

## Phase 3 — world
- Powers, items/keys, map, NPCs, keepsakes/story, day/night cycle, audio (music + SFX).
