# loadsagolf — Design Doc

Status: draft v0.8 · 2026-11-26 (M0 scaffold built; picslide style applied; M2 level pipeline built). Decisions so far are logged in §11.

## 1. Pitch

A top-down 2D mini-golf game for kids aged 4–10. You pull back and let go, like a slingshot. Holes are small and fit on one screen. You can't fail: no stroke limit, no game over, no timer. It's a toy that feels good to poke. The look is cute and minimal. Sound carries most of the feel: no music, mostly silence, and a punchy sound for every action.

Later levels aren't harder. They're **more varied**: each world adds one new toy (bumpers, sand, slopes, windmills, teleporters…).

## 2. Constraints

| Constraint | What it means |
|---|---|
| Tablets first, iOS + Android | Touch only, landscape, big hit targets. Aspect ratios run from 4:3 (iPad) to 16:10 (most Android tablets). |
| Develop on Linux + Android | The toolchain must build and deploy to Android from Linux. iOS builds need macOS and Xcode. We can borrow a Mac only for an hour or two at a time, so iOS builds must run on a cloud Mac (see §3). |
| Modest hardware | The dev device is a Samsung Galaxy Tab S10 FE+ (from memory: 13.1", 2880×1800, 16:10, mid-range Exynos chip; confirm when it's free). It must run at a steady 60 fps. Many kids' tablets are weaker (Amazon Fire, old iPads), so before release we also test on a genuinely cheap tablet. Its high resolution makes fill-rate the main cost: keep overdraw and full-screen effects low. |
| Ages 4–10 | Many players can't read yet, so the game itself uses no text. Fingers are imprecise, and kids often rest a second finger or palm on the screen. |
| Sound-led | Sound must be low-latency (the release "thwack" has to land on the release). We need many voices at once, plus control of pitch and volume per event. |
| Small levels, many of them | We need a quick way to build levels and test them right away. |
| Kids' app store rules | Apple Kids Category and Google Families policy: no third-party analytics or ads, a parental gate in front of any link or settings screen, no data collection. Simplest to have **no network code at all**. |

## 3. Tech stack

### Options considered

| | Godot 4 | Web (TS + Pixi/Canvas + Capacitor) | Defold | Flutter + Flame | Unity |
|---|---|---|---|---|---|
| Linux dev + Android deploy | ✅ one-click deploy | ✅ | ✅ | ✅ | ⚠️ heavy |
| iOS | Needs a Mac or CI | Needs a Mac or CI | Its build server can bundle iOS | Needs a Mac or CI | Needs a Mac or CI |
| Level editor | ✅ **built-in scene editor** | ❌ build our own | ⚠️ basic | ❌ build our own | ✅ |
| Audio latency | Good (native) | ⚠️ Android WebView audio latency varies a lot | Good | ⚠️ depends on plugin | Good |
| 2D tools (tilemaps, tweens, particles) | ✅ | ⚠️ assemble from libraries | ✅ | ⚠️ | ✅ |
| Cost / licence | Free, MIT | Free | Free | Free | Fees / licence risk |
| Binary size | ~30–40 MB | small | ~5 MB | ~15 MB | large |

### Decision: **Godot 4 (pinned: 4.7.2-stable) + GDScript, Compatibility renderer**

- **The level editor comes free.** A level is a Godot scene: a tilemap for the ground plus objects dragged in from a palette (tee, hole, walls, bumpers…). `@tool` scripts make objects preview and validate inside the editor, and F6 plays the open level right away. Building our own editor is the biggest cost of the web option, so this tips the decision.
- **Native audio** with buses, effects (compressor and limiter on master), per-voice pitch and volume control, and `AudioStreamRandomizer` for variation.
- **Compatibility (OpenGL ES 3) renderer**: the widest device support and lightest load for simple 2D.
- Small dev loop: edit on Linux, run on desktop with mouse-as-touch, deploy to a USB Android tablet with one click.
- GDScript is fast to write and is enough for a game this size. We can drop to C++ (GDExtension) if we ever need to, though that's unlikely.

**Runner-up:** the web stack is fine if a custom in-browser editor appeals. Two problems decide it: we'd hand-build the editor, and Android WebView audio latency is the thing we'd fight hardest, while sound is our #1 feel priority.

**iOS plan.** We only borrow a Mac now and then, so builds run in CI and the Mac handles one-off tasks:
- **CI (GitHub Actions macOS runner, or Codemagic):** export from Godot headless → `xcodebuild` → sign with fastlane and an App Store Connect API key → upload to **TestFlight**. Runs on demand or on tag.
- **Testing:** install from TestFlight on an iPad. No Mac involved.
- **Borrowed-Mac sessions (rare, short):** one-time Apple Developer setup if the web portal can't cover it, and fixing any Xcode-specific build problem CI can't explain. Keep a checklist so each session is short and well used.
- Get one iOS build through CI and onto TestFlight by M1 or M2. Then iOS-only surprises (audio session, safe areas, the 4:3 layout) show up early, not at launch.
- Nothing in the design is Android-only.

### Supporting tools
- **Testing:** a tiny headless runner (`tests/run.sh`; no plugin dependency) for the ball sim and input logic. It also fails on any GDScript error. Level validation joins it in M2. `tools/screenshot.tscn` renders any scene offscreen at a given screen size for visual checks.
- **Art:** SVG sources, imported at 2× density. Flat shapes keep files small and sharp at any resolution.
- **Sound:** every sound is **synthesized by scripts kept in the repo** (Python + numpy/scipy, rendered to WAV). See §7. Short SFX as WAV (no decode latency).
- **Version control:** git, with Git LFS only if audio or art files get large.

## 4. Core gameplay

### Controls (slingshot)
1. **Touch anywhere** on the screen to start aiming. You don't have to hit the ball, which helps little fingers a lot. The ball's position is the anchor.
2. **Drag back.** The shot goes the *opposite* way to the drag. Power depends on drag length, with a dead zone so small drags do nothing, a gentle curve, and a cap at maximum power. The ball squashes and a rubber-band line stretches back from it.
3. **Let go to shoot.**
4. **Cancel:** drag back to within the dead zone and let go. Nothing happens.
- Only the first touch counts. Other touches are ignored, so a resting palm does nothing. (Two-player mode works differently: see below.)
- **Grab the ball at any time, even while it's moving.** The same rule applies in 1P and 2P. Grabbing **instantly cuts the ball's speed by 80%**. A slow ball practically stops. A fast one keeps drifting at 20% speed while you aim, with friction still slowing it.
  - **The fast-grab penalty:** the aim anchor moves with the drifting ball, and when you let go the shot is **added to** whatever speed the ball still has. A grabbed fast ball is harder to aim and its shot gets skewed. A slow ball is basically a clean shot.
  - The aim guide predicts from the ball's current position *and* its leftover speed, so it stays honest even while the ball drifts.
  - If a held ball drifts into water, the grab is dropped: splash, back to its last resting spot.
  - Grabbing sounds like a quick brake squeak, louder the more speed it removed.
  - ⚗️ **Experiment, not settled.** The 80% brake is an idea to test (M0/M1). Alternatives to compare on the tablet: a full stop on grab, a different brake %, a brake that grows over the hold, and grab only once the ball has stopped. Put the brake % and the "add vs replace leftover speed" rule in one tuning resource so we can switch between them without changing code.
- A ball left alone still settles quickly when slow (a speed threshold plus extra damping), so nothing creeps forever.
- **Aim guide:** a dotted line in the shot direction. Early worlds show the path up to the first bounce, which helps a lot for ages 4–6. Later worlds show a shorter line. It never gets taken away completely.

### No-fail rules
- No stroke limit, no timer, no lives.
- **Water / off-course:** a cute splash, then the ball pops back to its last resting spot. No penalty is shown.
- **Stuck detection:** if the ball has been taken many times without getting closer, the hole gently "calls" (wiggle + sound). After more tries, an optional helper arrow appears. We never auto-complete the hole, so kids still get to finish it themselves.
- **Strokes:** counted internally for tuning but **never shown as a score.** No par, no "bogey". Every hole-in gets the full celebration.
- **Collectibles (optional):** 1–3 stars or gems per level, reachable with fun trick shots. They give replay value for older kids, and younger ones can ignore them.

### Ball physics
We write a small custom simulation (`BallSim`) instead of using Godot's physics bodies. It's pure GDScript with its own simple geometry: wall segments (thick lines), circular bumpers, surface zones and the hole. In M2, tilemap walls get converted to segments when a level loads. This gives:
- predictable, tunable feel (restitution, friction, stop threshold), with no physics-engine jitter
- an aim guide that runs the same code as the real shot, so the preview matches what happens
- easy per-surface behaviour (friction and sound) from a tilemap lookup at the ball's position.

Hole capture: if the ball passes over the hole slower than a capture speed, it's pulled in. If it's faster, it rattles over the rim and gets deflected a little. The capture speed should be generous.

**Build for several balls from the start.** v1 is single-player, but the simulation steps a *list* of balls and handles ball–ball collisions (circle–circle, near-elastic, equal mass). Then two-player mode needs no physics rewrite. A shared `BallSim` steps every ball each tick; each `Ball` node only draws its state and plays its sounds.

### Two-player "chaos" mode (post-v1, designed for now)
Two balls share the screen, and both kids play **at the same time**: no turns. Anyone can flick **any** resting ball, including the other player's. Knocking your sibling's ball into the sand is part of the fun.

- **Input:** touch-anywhere is off. A touch only grabs a ball if it starts within a **grab radius** of that ball (start at ~64 logical px ≈ 15 mm on the S10 FE+; tune in playtests). If both balls are in range, the nearest one is grabbed. Touches that don't grab a ball do nothing, which also takes care of resting palms.
- **Multi-touch:** each touch holds at most one ball, and each ball is held by at most one touch. Both kids can aim at once. If the second kid tries to grab a ball that's already held, nothing happens (later: a small "taken" wobble and sound).
- **Grabbing:** the same grab-any-time rule as 1P (see Controls), on *either* ball. The grab radius is measured from where the ball is when the finger lands, so catching a fast ball takes some skill.
- **Collisions:** ball–ball hits are near-elastic with a big satisfying "clack" (and a squash on both balls). The aim guide stops where it would first touch the other ball, so the preview never lies.
- **Telling the balls apart:** two strongly contrasting colours that colour-blind players can also tell apart (e.g. orange and blue), plus a pattern on one ball (a stripe) so colour isn't the only cue. Each ball's sounds are tuned slightly differently (e.g. a few semitones apart), so kids can hear whose ball hit what.
- **Hazards:** a ball that goes in the water returns to *its own* last resting spot, even if the other player knocked it in.
- **Sinking:** a sunk ball stays in the hole and can't be knocked out or grabbed.
- **Winner:** the **first ball in wins the hole**: a crown pops onto the hole flag in that ball's colour, with a winner fanfare. The winner is the *ball*, not whoever flicked it, so sinking your sibling's ball by accident counts for them. That's part of the chaos.
  - The second ball can still be played in for a smaller, friendly celebration. A skip button (big icon) jumps to the next hole for kids who don't want to finish.
  - **Match:** crowns add up over the world's holes, shown as crowns stacked in each colour (no numbers or text). The ball with the most crowns gets the big end-of-world celebration. A tie means both get it.
  - In 2P the no-fail idea still applies to the game (no lives, no timer, no stroke limit). Losing a hole only means the other colour got a crown.
- **Levels:** the same levels as single-player. Each Tee has **two spawn points** from day one, so no level needs editing later.

## 5. Level design

### Size and screen
- **Every level fits on one screen.** No camera panning, so kids always see the ball, the hole and the whole puzzle.
- Design area: **1024×768 logical px (4:3 safe area)**, using Godot's `canvas_items` stretch with `expand` aspect. Wider screens show extra decorative edge (grass, flowers), never gameplay.
- Grid: 32 px tiles (32×24 cells). Objects snap to the grid by default but can be placed freely.
- Ball ~24 px diameter, hole ~40 px: hole-ins come easily.

### Level anatomy (one `.tscn` per level)
```
Level (Node2D, core/level/level.gd)  # id, board_rect, aim_guide_bounces; draws the board
├── Tee      (tee.gd)     # 1P start; 2P starts ± spread_2p along spread_dir
├── Hole     (hole.gd)    # cup + flag (flag drawn above balls)
├── Wall…    (wall.gd, a Line2D)  # raised white rail; edit points with the Line2D handles
├── Zone…    (zone.gd)    # sand or water patch: size, corner_radius; centred on the node
└── Bumper…  (bumper.gd)  # radius
```
- **The board** is a rounded white-bordered rectangle (`board_rect`, inside the 1024×768 safe area). Its border is the outer wall. Small boards suit early holes, and the game centres whatever size the level uses.
- **Walls are `Line2D`s, not tiles.** Godot's point handles make them fast to draw, they look like picslide's rounded rails, and they map 1:1 onto the sim's segment geometry. Tile-painted walls (the original plan) would look blocky.
- **Every node draws itself in the editor exactly as in game** (`@tool`), so what you see while editing is the level.
- The sim is built from the nodes when a level loads (`Level.build_sim()`). Nodes are found anywhere under the root, so grouping them under plain `Node2D`s is fine.
- New mechanics (windmills, slopes, teleporters…) become new node types in `core/level/` plus a few lines in `build_sim()`.

### Editor workflow
1. Duplicate `levels/_template.tscn` into the world's folder and set a unique `id`.
2. Set `board_rect`, then move the Tee and Hole. Add walls, zones and bumpers with **Add Child Node** (search "Wall", "Zone" or "Bumper": the script classes are listed there), or copy one from another level. For a wall, select it and click on the board to add points.
3. **F6** plays just this level, over and over. The dev "next hole" pill skips ahead.
4. **Warnings show live in the scene tree** (the ⚠ on the Level node). The checks:
   - an id is set
   - exactly one Tee and one Hole
   - the board is inside the safe area
   - the tee, both 2P spots and the hole are on grass, clear of walls and bumpers, and on the fairway
   - nothing sits under the 4:3 button corner (shown red in the editor)
   - no rotated or scaled zones or walls
   - the tee isn't right next to the hole
5. Add the level to `levels/worlds.tres` (an inspector-editable list of worlds and their holes). The play order lives there, not in file names.
6. Run `godot --headless -s tools/level_report.gd [level.tscn]`. It brute-forces 432 shots from the tee, plus second shots from wherever those stop, and reports the fewest shots found (1, 2, 3+), the hole-in-one rate and the splash rate. Use it to check every hole can be finished and to sense-check difficulty. `tests/run.sh` validates every level automatically.

`levels/_sandbox.tscn` is the old M0 test hole (sand, water, bumper, walls). It's kept for testing mechanics and isn't in any world.

Later (stretch goal): an in-game "sandbox" where kids place a few pieces themselves, built from the same node types.

## 6. Progression

Each world brings in **one new idea**, plays with it for ~6–8 holes, then mixes it with earlier ones. The holes stay roughly as hard as before. They just get more interesting.

### v1 scope: 2 worlds × 4 holes = 8 holes

| World | Theme | Holes | New thing |
|---|---|---|---|
| 1 Meadow ✅ built | green, flowers | 1. Straight shot · 2. Corner (bank off a wall) · 3. Zig-zag corridor · 4. First bumpers | Aim and shoot, walls, bank shots, bumpers (springy, loud) |
| 2 Beach | sand, sea | 1. Sand patch · 2. Water to cross · 3. Sand + water together · 4. Mix of everything so far | Sand (slows the ball), water (gentle splash-and-return) |

These 8 holes test every core system: the slingshot, walls, a prefab mechanic (bumpers), surface types (different friction and roll sounds), the no-fail hazard return, world unlocking and the celebration.

### Later worlds (post-v1, not committed)
| World | Theme | New thing |
|---|---|---|
| Hills | rolling green | Slopes (shown with arrows), dips that funnel the ball toward the hole |
| Ice | snow, penguins | Low-friction ice, boost pads |
| Workshop | wood, gears | Moving things: windmills, rotating gates, sliding blocks, buttons that open doors |
| Magic | night, stars | Teleporters, pipes, a gravity well |

The architecture should make each of these "one new prefab plus a few tiles". We won't build any of them in v1.

- Worlds unlock in order. Finishing all of a world's levels unlocks the next one, and since you can't fail, progress never stalls. All levels you've unlocked stay replayable.
- Level select is a map with big level bubbles, no text.
- Save data is local only: a small JSON file in `user://` (unlocked levels, collectibles).

## 7. Sound design (the main focus)

> **Style guide: our sibling app [picslide](https://github.com/networkburger/picslide)** (`src/audio.ts`, `src/haptics.ts`). loadsagolf uses the same sound vocabulary and key so the two apps feel like one family:
> - **Voices:** soft sine and triangle `tone()`s with exponential pitch glides (rising = pick up or good, falling = cancel or let go). A three-partial `marimba()` for anything musical. Swept band-pass `noiseBurst()`s for whooshes and puffs. Woody "thocks" (a triangle gliding down plus a short noise burst) for impacts.
> - **Room:** one shared noise-tail reverb (1.8 s, cubic decay) with a different send level per sound: dry for impacts, wetter for musical sounds, very wet for sparkles.
> - **Key:** G major pentatonic (`noteHz(step)`, G4 = step 0). Anything that repeats climbs the scale: power notches, bumper hits in one shot.
> - **Win:** a marimba run panned left to right, a held chord, then random high sparkles (picslide `win()`).
> - **Haptics:** the same patterns (tap 8 ms, lift 12, drop 18, correct 20-40-30, win 30-60-30-60-80).
> - **Gentle by default:** no distortion. A compressor on master (threshold −14 dB, ratio 4 in picslide, ours is similar). A persisted mute button.
>
> picslide synthesizes live with Web Audio. We render the same graphs **offline to stereo WAVs with the reverb baked in** (`tools/sfx/synth.py` mirrors picslide's `tone` / `noiseBurst` / `marimba` / `route` API). The reverb uses the browser's convolver normalization, and the output gets +6 dB to stand in for the compressor's make-up gain. Balance between sounds is the same as picslide's.

### Principles
1. **Silence is the default.** No music, no constant ambience bed, **no continuous rolling sound**: a noise-based rolling loop was tried and removed after the first playtest ("a long crashing sound… doesn't fit the theme"). The ball is heard through its impacts. In some worlds, a rare soft one-shot (a bird chirp, a wave) at most every ~20 s.
2. **Every action gets a sound,** and the sound follows the physics. Volume and pitch come from impact speed, drag power and ball speed. Hit harder, hear louder.
3. **Variation always.** Every one-shot gets ±4–8 % random pitch and picks from 3–5 recorded variants, so it never sounds machine-gunned.
4. **Punchy, short, dry.** Sharp attacks and short tails. A compressor and limiter on the master bus keep loud moments from clipping on tablet speakers. Tablet speakers have almost no bass, so the character must sit in the mids (~300 Hz–4 kHz). Check every sound on a real tablet's speakers, not on headphones.
5. **Rising sequences reward.** Repeated events climb a musical scale (e.g. the 1st, 2nd and 3rd bumper hits in one shot go up a pentatonic step each, and the same for collectibles). This gives a musical feel without any music.
6. **Celebrate big, then go quiet.** The hole-in is the loudest, longest moment: a ~1.5 s sting plus confetti. Then back to silence.

### Event list (first pass)
| Event | Sound | Driven by |
|---|---|---|
| Grab ball | picslide `lift()`: rising glide | — |
| Pull back | a `tick` at each of 8 power notches, climbing the pentatonic scale (and stepping back down if you ease off) | notch = power × 8 |
| Cancel | picslide `cancel()`: falling glide | — |
| Release / hit | woody thock in 3 power layers; mid and hard add a rising whoosh, hard adds a sub thump | shot power picks the layer and volume |
| Wall hit | picslide `drop()` thock | impact normal-speed → volume, slight pitch |
| Bumper | upward spring glide + marimba note, plus a sparkle and a wobble | climbs the pentatonic scale with each bumper hit in one shot |
| Enter sand | soft "pff" puff | entry speed |
| Water | "plop" + bubbles, then a "pop" when the ball comes back | — |
| Slope / boost pad | "whoosh" | — |
| Ball–ball hit (2P) | big wooden "CLACK" | impact speed → volume; pitch per ball |
| Grab moving ball | brake "skrrt" | speed removed → volume and length |
| Hole winner (2P) | crown "ta-da" in the ball's pitch | — |
| Near hole / rim rattle | quick "rattle" | — |
| **Hole-in** | deep thock "plunk" → picslide `win()` jingle; hole flash, sparkles, board wobble, confetti cannons | biggest moment |
| Collectible / 2nd ball in | picslide `correct()` marimba + grace notes | climbs a step per collectible in the level |
| Teleport | "bwoop" in, "bwip" out | — |
| Tap decor | each critter or object has its own silly sound (frog croak, flower "pomf") | rewards poking around |
| UI | soft taps / pops for every button | — |

### Implementation
- **Buses:** `Master` (compressor → limiter) ← `SFX`, `Loops`, `UI`. A mute button (persisted, like picslide's) plus the device volume.
- **iOS audio session:** Playback, mixing with other audio, like picslide (`audioSession.type = "playback"`). Sounds play even with the silent switch on, and a parent's music keeps playing.
- `Sfx` autoload: `Sfx.play(&"wall", volume, pitch, pos)`. It runs a pool of `AudioStreamPlayer2D` voices. Each event has a cap on how many voices it can **start** within 150 ms, so reverb tails don't count, plus a short cooldown to prevent flamming.
- Sound events are defined in a single resource table (event → streams, base volume, pitch range, voice cap), so we can tune sounds without changing code.
- Light stereo panning by screen position (small, ±0.3): it helps on tablets held in landscape.
- **Haptics:** a short vibration on hit, hole-in and bumper where the device supports it (Android phones and some tablets; iPads have no haptic motor). Always optional, never required to understand what happened.
- **Spike early:** measure touch-release → audible latency on the Samsung tablet in week 1. Budget Samsung tablets have a history of high audio latency, so this matters. If it's bad, adjust Godot's audio output latency setting or the Android audio driver.

### Synthesis pipeline
All sounds are synthesized offline by scripts in the repo, not hand-made in a DAW. A sound is then a short recipe we can tweak and re-render, so tuning a sound is a code change.

```
tools/sfx/
  synth.py          # building blocks: oscillators (sine/tri/square/saw/FM), noise,
                    # envelopes + pitch sweeps, filters (LP/HP/BP), drive, seamless loops
  recipes/          # one module per family; each has SOUNDS = {name: (fn, variants)}
    shots.py        # click, pip, tick, hit_soft/mid/hard, fwoop, skrrt, button
    impacts.py      # wall, boing, clack, rattle
    surfaces.py     # pff, plop, pop
    rewards.py      # plunk, jingle, ding
  render.py         # → audio/sfx/<name>_<nn>.wav (and <name>_loop.wav), seeded + reproducible;
                    #   also writes tools/sfx/out/index.html to audition everything
```
- **Variants come from seeds.** Each recipe renders 3–5 variants with small random changes (pitch, decay, noise colour), so one-shots never repeat exactly.
- **Loops:** `render.py` and `Sfx.loop_player()` still support seamless `*_loop` sounds, but nothing uses them now (see principle 1).
- **Musical events** (bumper climb, power notches, collectible dings, hole-in jingle) use G major pentatonic, and the game pitches samples up the scale with `Sfx.step_ratio(step)`. Pitched musical sounds never get the per-ball pitch offset in 2P, which would take them out of key. Ball B's musical sounds start 2 steps higher instead.
- Render as 44.1 kHz 16-bit **stereo** WAV, tails trimmed at −50 dB. No per-sound normalization: the levels in the recipes *are* the mix. `render.py` also writes a contact-sheet HTML page so you can audition every sound in a browser.
- Run `render.py` by hand. The rendered WAVs are committed, so the game build doesn't need Python.
- **Listen on the tablet.** Desktop speakers flatter synth sounds. Every sound gets checked on the Samsung's speakers.

## 8. Visual style

> **Style guide: picslide** (`src/style.css`, `src/fx.ts`). Shared palette in `core/palette.gd`.
> - **Table:** cream `#fff4e6` background with four soft pastel corner blobs and a faint ink dot grid (`core/backdrop.gd`).
> - **Ink:** plum `#4a2c3a` for icons. Every shadow is ink at low alpha, never black.
> - **Sticker look:** things sit on the table like toys. Thick **white borders**, a **solid offset shadow** (0, 5–8 px) plus a soft blurred one, big round corners. The course is a white-bordered board, and walls are raised white rails. Sunken things (sand, water, the hole) show a darker rim at the top instead.
> - **Accents:** coral, pink, teal, yellow, purple and blue from picslide. Fairway greens `#7bd96a` / `#4fbf55`.
> - **Motion:** overshoot easing (`TRANS_BACK`). The board **pops in** (scale 0.4, −8° → 1) and does a **joy** wobble on a win. Things **nudge** periodically (the flag), and buttons press to 0.9 and bounce back.
> - **Particles:** `core/fx.gd` is a port of `fx.ts`: 8-point star **sparkles** for small wins (bumper, splash return, hole-in), and **confetti** cannons from both bottom corners plus a gentle rain for the big win.
> - **Buttons:** round white 56–60 px icon buttons with ink icons (`core/ui/icon_button.gd`). Like picslide's game bar, they sit in a **column in the side margin on wide screens** and a row in the corner on 4:3. **Levels must keep the top corners clear** for that 4:3 case.

- Flat shapes, soft rounded corners, a warm limited palette per world. Little or no texture.
- Movement does the "cute" work: squash and stretch on the ball, bumpers that wobble, a flag that waves, critters that blink and hop. Animations use tweens with ease-out-back.
- **The ball is a plain white ball** (coral and striped blue in 2P) with a solid offset shadow, a soft ink rim and a shine. Aiming shows a picslide-style power ring that fills coral → pink, with 8 notch pips. Its character comes from how it moves and sounds: it squashes on wall hits, stretches when pulled back, and does a little hop and wobble when it settles.
- Particles: grass flecks on hit, sand puffs, water rings, confetti on hole-in. Keep particle counts low for weak GPUs.
- UI: icons only (home, restart, map). Big buttons (≥ 88 logical px), placed in the corners so they're hard to tap by accident while aiming.

## 9. Architecture

```
project.godot                # main scene: scenes/game.tscn
autoload/
  sfx.gd                     # pooled, event-driven audio; pentatonic step_ratio(); persisted mute
  haptics.gd                 # picslide vibration patterns
  game.gd                    # running order (worlds.tres), current world/hole, F6 solo play
core/
  ball_sim.gd                # steps all balls: integration, walls, ball–ball, surfaces (pure, testable)
  shot_input.gd              # touches → gestures → shots; grab target: "anywhere" (1P) or "within radius" (2P)
  tuning.gd / tuning.tres    # feel constants: power curve, brake %, add-vs-replace, grab radius, friction…
  ball_view.gd               # one ball: drawing, squash & stretch
  palette.gd, backdrop.gd, fx.gd   # picslide look: colours, table background, sparkles + confetti
  ui/icon_button.gd          # picslide round icon button
  level/                     # level.gd (root, validator, build_sim), wall, zone, bumper, tee, hole,
                             # world.gd + world_list.gd (running order)
scenes/game.tscn             # plays levels: input, sound, haptics, fx, HUD, hole-to-hole transitions
levels/
  _template.tscn, _sandbox.tscn
  w1_meadow/01–04.tscn
  worlds.tres
audio/sfx/                   # rendered WAVs (committed)
tools/
  sfx/                       # synthesis scripts (see §7)
  level_report.gd            # brute-force "can this hole be finished, in how many shots?"
  deploy-android.sh          # export + install + launch on the tablet
  screenshot.tscn            # offscreen render: -- --scene=… --level=… --size=… --seconds=… [--demo-aim|--demo-win]
tests/
  run.sh, run_tests.gd       # headless: sim, input, every level validates, worlds list
```

- Mechanics talk to the ball through a small interface (`apply_impulse`, `teleport_to`, `set_surface_override`), not by reaching into its internals.
- **Shared logic for real shots and the aim guide:** `BallSim` has no scene dependencies, so the aim guide can copy the current state and run it forward.
- `shot_input` tracks gestures by touch index from the start (one active gesture in 1P), so multi-touch 2P is a policy change, not a rewrite.
- Fixed 60 Hz physics tick, with rendering interpolated between ticks for smoothness on 90/120 Hz screens.

## 10. Milestones

| # | Goal | Done when |
|---|---|---|
| M0 | **Spikes** (2–3 days) | Godot project runs on the Samsung tablet. Slingshot gesture feels good. Grab-while-moving variants can be switched and compared. Tap-to-sound latency measured and acceptable. `synth.py` renders a first "thwack" we like. |
| M1 | **Vertical slice** | Meadow hole 1 complete: tee, walls, hole, aim guide, synthesized sounds for every event in it, celebration. Feels good with a real kid. |
| M2 | **Pipeline + iOS** | ✅ Level template, validator, `worlds.tres`, level report. ✅ All 4 Meadow holes. ⏳ CI builds the Android APK and an iOS build that reaches TestFlight. |
| M3 | **World 2 + progression** | Sand, water and hazard return. All 4 Beach holes. Level-select map, save/unlock, roll loop per surface. |
| M4 | **Polish + ship prep** | Final art and sound pass, decor critters, collectibles, parental gate, app icons. Tested on a real iPad via TestFlight. Store listings (Kids / Families). |

**Playtest with kids from M1 onward.** A 5-year-old's behaviour will reshape the controls faster than any amount of thinking will.

## 11. Decisions log

| Question | Answer (2026-11-25) | Effect on the design |
|---|---|---|
| Mac access? | Borrowed now and then, 1–2 h at a time | iOS builds run on a cloud Mac and go to TestFlight; the Mac is only for one-off setup (§3) |
| Dev device? | Samsung Galaxy Tab S10 FE+ | It sets the performance and audio-latency bar; 16:10 is the main aspect ratio, 4:3 safe area kept for iPad. Also test on a cheap tablet before release |
| Ball? | Plain ball | No face; its character comes from movement and sound (§8) |
| Sounds? | Synthesized | Python synthesis scripts in the repo (§7) |
| Scope? | 2 worlds × 4 holes for v1 | Meadow + Beach (§6); later worlds are a backlog |
| Name? (2026-11-26) | **loadsagolf**: lower case, one word, final | App ID / bundle ID **`com.networkburger.loadsagolf`** (Android and iOS) |
| 2-player? (2026-11-26) | Both balls on screen at once; anyone can flick either ball; stricter touch rules | Post-v1, but v1's physics and input are built for several balls (§4) |
| 2P winner? | Yes | The first ball in gets the crown; crowns add up over the world (§4) |
| Grab moving ball? | Yes, any time, in **both 1P and 2P**. The 80% brake is an experiment | The brake rule lives in `tuning.tres`; compare variants in M0/M1 (§4) |

## 12. Open questions

None blocking. Open experiments are marked ⚗️ in the doc (currently just the grab brake rule).
