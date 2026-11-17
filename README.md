# LIB_RTS

The iGame3D 2008 real-time strategy system, rebuilt in xTalk: click, drag a box to select,
command. It covers the RNDRTS random level maker and the RTS_Functions scripts that it and uDeadGame
ran on. It's one library with no windows, plus a small demonstration stack.

| File | What it is |
|---|---|
| `RTS_Library.livecodescript` | the system: map maker, selection, orders, senses, behaviours, tasks, health, paths. No windows, no IDE |
| `RTS_Demo.livecodescript` | the demonstration: a random level seen from above, drawn with polygon graphics |
| `DESIGN.md` | which Lua became which handler, what was kept, changed or left out |
| `tests/t_rts_library.txt`, `tests/t_rts_demo.txt` | headless tests (OXT-Beyond's runner) |

## Try it

Open `RTS_Demo.livecodescript` in OXT-Beyond or the IDE. It builds its own cards and loads the
library from the same folder.

- **Drag** on the map to select your units in a box. **Shift** adds to the selection or takes away from it.
- **Click** one of your units to select just that unit.
- With units selected, **click** a target:
  - the ground: they go there, spread in a ring;
  - an enemy: they attack it;
  - a gun: they pick it up;
  - a house: they go in, which refills guns;
  - a car: they get in. **Double click** makes the selected drivers get out.
- **H** commands the living and **Z** the dead. Pressing the same key again selects the next unit, as **Tab** does. **Space** selects nobody.
- **U** makes the dead rush the nearest living. **X** makes the selected units hold. **B** slows time. **P** lists every unit's task.
- **N** makes a new random level. **Escape** pauses; while paused, **+** and **-** set the game speed.
- **`** or **F2** opens a note for the AI, saved to `LIB_LLMIN/LIB_GAMES/GAME_NOTES.txt`. A line that starts with `/` runs as xTalk instead.
- **?** or **F1** shows the About card.

On screen: the living are white, or orange when carrying a gun. The dead are green, bodies grey,
guns yellow and cars blue. Houses are grey blocks with a yellow door mark, and the brown lines
are yard fences.

## Use it in a game

```
start using stack "<path>/RTS_Library.livecodescript"
put RTS.NewGame(tSeed, "buildings,humans,guns,cars,zombies") into tSeed   -- empty = random, as RNDRTS
-- every frame:
RTS.Step tSeconds
repeat for each line tL in RTS.Snapshot()   -- id,kind,team,x,z,fx,fz,alive,selected,state,armed,blink
-- mouse: RTS.ClickAt(x, z, shift, double) -> "box" | "select" | "move" | "attack" | "gun" | "house" | "car"
--        on "box": RTS.BoxBegin, then RTS.BoxUpdate x1,z1,x2,z2,shift while dragging
```

Positions are in metres, on a 96 m map (6 x 6 blocks of 16 m), in 2 m path cells.
