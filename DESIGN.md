# LIB_RTS: design notes

Monday, November 17, 2026. Written by Claude (Opus 5.5) from
`iGame3D_2026_CLAUDE/Data/Wizards/RNDRTS/RNDRTS.fl` and
`iGame3D_2026_CLAUDE/Data/Scripts/Games/RTS_Functions/*.lua` + `RTS_Entities/*.lua`.

## 1. Was there an xTalk version already?

No. uDead (LIB_GAMES, `Vibecode3D_Play_uDead.livecodescript`) shares this system's rules: the
same behaviours, melee, guns and rising dead. But uDead is played in first person, with one click
sending the best-ranked zombie. Its code is written for uDead and can't be lifted out. LIB_RTS is
the commander's version on its own: a selection box, groups and orders. It doesn't need Vibecode3D.

## 2. How the original is built

```
RNDRTS.fl (FLTK wizard)  ->  writes Data/Levels/<B_H_G_C_Z_RTS>/load script.lua
                              (map mesh, objects at random spots, RTS_Init.lua, game_func = handle_RTS)
RTS_Init.lua             ->  loads 15 RTS_Functions files, 8 RTS_Entities files, sets up A*
handle_RTS (every frame) ->  senses (every 0.7 s) -> health -> each unit: handle_ai -> do_task
handle_ai                ->  event, else order, else behaviour   (each one sets the unit's TASK)
do_task                  ->  the task becomes an animation and a velocity
```

The key idea, kept as it was: **an order beats the behaviour, and an event beats the order.**
Your commands are orders. When an order is done, the unit goes back to its own behaviour, so an
armed civilian you sent somewhere goes back to hunting.

## 3. Where each part went

| Lua | What it does | LIB_RTS |
|---|---|---|
| RNDRTS.fl `randomizeit`, `AutoLevelName` | counts 1 to 20 each, the name `B_H_G_C_Z_RTS` | `RTS.NewGame` (empty counts = random), `RTS.LevelName` |
| RNDRTS.fl `createBuildings` | a house in a random block; 4 tries, each 3 in 4, to fence a side of its yard | `RTS.MakeMap` (a 4 x 4 cell house, one door, fences along the block edges with the corners open) |
| RNDRTS.fl `EntityLocations`, `setEntityPos` | spawn spots in the blocks left over (the last block skipped, as it was) | `RTS.MakeMap`, `RTS.TakeSpot` |
| RNDRTS.fl `createEntities`, `createEnemy` + the start objects | humans + masterchief, guns + gun1, cars, zombies | `RTS.MakeCast` (humans + 1, guns + 1) |
| RTS_Human.lua `HumansWithGuns` | each gun to a random human; a human's second gun stays on the ground | `RTS.MakeCast`, `RTS.GiveGun` |
| RTS_Gun.lua | pistol: 8 shots, 0.4 s +- 0.2 apart, refills 4 to 8 | gun entities: `shots`, `interval`, `deviation` |
| RTS_Zombie.lua | team 1, health 500 to 1000 | `RTS.MakeCast` |
| RTS_Attributes.lua `init_object` | every unit's starting values | `RTS.NewEntity` (same names and numbers) |
| RTS_Game.lua `handle_clicks` | ground = move in a ring, enemy = fight, car, house, gun; your unit = select; else a box | `RTS.ClickAt`, `RTS.OrderMove` (the same ring: 8 at 2 m, the next 8 at 4 m) |
| RTS_Utilities.lua `handle_selection_box` | box from where you pressed; Shift flips | `RTS.BoxBegin`, `RTS.BoxUpdate` |
| RTS_Game.lua keys Z / H / Space / Tab / P / B | team switch, next unit, unselect, debug list, bullet time | `RTS.SetTeam`, `RTS.TabThrough`, `RTS.UnselectAll`, `RTS.Tasks`, `RTS.BulletTime` |
| RTS_Orders.lua | fight (and the "aware" kind, which switches to a nearer enemy it senses), run to spot, run to car, run to house (refills guns), pick up gun, eat | `RTS.DoOrder`, `RTS.FightOrder` |
| RTS_Senses.lua | eyes: 10 m, 90 degrees, line of sight; ears: hearing distance (20 to 30 m) times noise; memory of what was seen | `RTS.Sense`, `RTS.Seen`, `RTS.SeenBefore` |
| RTS_AI.lua `sort_perceived_objects_by_priority` | seen +2, heard +1, live enemy +3, times (50 - distance) | `RTS.Sense` (same formula) |
| RTS_Behaviours.lua | default (wander; flee when close), stand and cry, gunned civilian, sniper, zombie hold, zombie rush, reanimate, drive | `RTS.Behave` (same names) |
| RTS_AI.lua `do_task` | walk 1.2 m/s, run 2 (the dead 1.8), shoot, melee 20 a blow every 0.9 s (an armed human kills with one), the first blow of a fight stuns half the time, eat | `RTS.DoTask`, `RTS.MoveToward`, `RTS.Shoot`, `RTS.Melee` |
| RTS_AI.lua `handle_health` + `handle_RTS` freeze | the dead fall, 3 s, then 6 s frozen, then get up (500 to 1000 health); the living who die join the dead; a gun drops; a head shot is final | `RTS.Health`, `RTS.Rising` |
| RTS_Utilities.lua `rts_update_living_and_dead_counts` | the status lines and the three endings | `RTS.Count`, `RTS.Status` |
| RTS_Vehicles.lua, `stepOutOfCar` | cars on a crossings grid, engine sounds | `RTS.EnterCar`, `RTS.Drive`, `RTS.StepOut` (much simpler: see 4) |
| RTS_astar.lua | A* for every walker | `RTS.Field` / `RTS.NextCell`: shared distance maps (see 4) |

## 4. What changed, and why

- **Paths:** uDead measured one A* search at about 120 ms in xTalk. Here a distance map over the
  48 x 48 grid serves everyone going the same way: one map toward each team, rebuilt every 0.7 s
  with the senses, and one map for each spot ordered, kept because walls never move. A unit with
  a clear line to its goal walks straight there.
- **The dead with no order:** UDG's `zombie_behaviour` followed the player's box, but an RTS has
  no player box. Here they wander slowly and attack the living they see or that come within 3 m.
  That's my choice.
- **Bullet damage** was in the C engine. I used uDead's numbers: 185 a hit, a 1 in 10 chance of a
  head shot, and the chance to hit drops 7% a metre.
- **Cars** drive straight along the paths at 6 m/s and run the dead down (400 damage on contact).
  The original's crossing-by-crossing driving, skids and flips are not ported.
- **Left out:** sound, particles, ragdolls, tracking lights, LOD, animation names, grenades, and
  kicking furniture. Snipers exist as a behaviour, but RNDRTS never made any.

## 5. Tested, and not

Headless with OXT-Beyond's runner (`python3 -I ~/projects/OXT-BEYOND/tests/oxt_headless.py tests/t_rts_*.txt`):
- The library passes on Beyond and on the 9.6.3 server. Tested: the map, the counts, the box,
  click selection, the move order, the team switch, and a rush of the dead.
- Three minutes of game time take about 1.5 s, and the worst step is 15 ms.
- The demo stack passes 20 checks on Beyond. Tested: it builds its three cards, draws the map and
  the units, the keys work (H, Z, U, N, Escape, +, `, ?), a note reaches a copy of the inbox, and
  a `/` command shows its value.

**Not tested:** anything on screen. The real mouse (drag, click, double click), how it looks,
the frame rate with drawing, and whether it is fun.

**Balance:** I noticed one thing but haven't tuned it. On the test level (5 houses, 7 humans, 5 guns,
6 dead), when the dead rush, the gunners win in three minutes.
