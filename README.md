# loadsagolf

A chill top-down slingshot mini-golf game for kids aged 4–10. Tablet-first, iOS + Android. Built with Godot 4.7.2.

Design: [`docs/DESIGN.md`](docs/DESIGN.md)

## Setup (Linux)

- Godot **4.7.2-stable**, plus its export templates (`~/.local/share/godot/export_templates/4.7.2.stable/`)
- Android SDK at `~/Android/Sdk` (from Android Studio). Godot uses Android Studio's bundled JDK (`/opt/android-studio/jbr`, set in Godot's editor settings).
- Python 3 with numpy + scipy (only needed to re-render sounds)
- For USB debugging on Arch: `sudo pacman -S android-udev`, then re-plug the tablet

## Commands

| | |
|---|---|
| Run on desktop (mouse acts as touch) | `godot` (or open the project in the editor and press F5) |
| Run on the tablet | `tools/deploy-android.sh` (add `--logs` to follow output) |
| Tests | `tests/run.sh` |
| Re-render sounds | `python3 tools/sfx/render.py [names…]`, then open `tools/sfx/out/index.html` to audition |
| Screenshot | `godot res://tools/screenshot.tscn -- --level=res://levels/w1_meadow/01.tscn --size=1280x800 --seconds=1.6 --out=/tmp/shot.png [--demo-aim \| --demo-win]` |
| Level report | `godot --headless -s tools/level_report.gd [-- res://levels/…tscn]` |

## Building a level

1. Duplicate `levels/_template.tscn` into the world's folder and give it a unique `id`.
2. Set `board_rect` on the Level node, place the Tee and Hole, and add Walls, Zones (sand or water) and Bumpers with **Add Child Node** (search "Wall", "Zone", "Bumper"). For a Wall, select it and click on the board to add points.
3. Press **F6** to play just that level. Warnings (⚠ on the Level node) flag anything wrong.
4. Add it to `levels/worlds.tres` to put it in the running order.
5. Check it can be finished, and roughly how hard it is: `godot --headless -s tools/level_report.gd -- res://levels/…/xx.tscn`

More in `docs/DESIGN.md` §5. `levels/_sandbox.tscn` has every mechanic, for testing.

## Playing (`scenes/game.tscn`)

Plays the worlds in order. The round buttons switch 1P/2P, toggle mute and restart the hole. The dev pills (debug builds only):

- **grab:** cycles the grab-while-moving variants (brake 80%, brake 50%, full stop, ramp, resting only)
- **leftover:** whether a shot adds to the ball's leftover speed or replaces it
- **next hole:** skip ahead
- **latency:** tap anywhere to play a sharp click and flash the screen. To measure touch-to-sound latency, record with a phone close to the tablet while tapping the screen firmly with a fingernail. In an audio editor, the gap between the tap and the click is the latency.

Feel constants live in `core/tuning.tres` / `core/tuning.gd`.

The look and sound follow our sibling app [picslide](https://github.com/networkburger/picslide). See `docs/DESIGN.md` §7–8.
