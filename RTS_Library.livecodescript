script "RTS_Library"
######################################################################################
## RTS_Library  (17 11 2026)
## The iGame3D 2008 real-time strategy system (Data/Scripts/Games/RTS_Functions/*.lua and the
## RNDRTS level maker, Data/Wizards/RNDRTS/RNDRTS.fl) as one xTalk library with no windows.
## The demo stack (RTS_Demo.livecodescript) draws it; any game can: `start using` this stack,
## call RTS.NewGame, then RTS.Step every frame and read RTS.Snapshot() to draw.
##
## The parts, each named after the Lua it comes from (DESIGN.md has the full map):
##   Map maker      RNDRTS.fl         blocks, buildings with fenced yards, spawn spots
##   Selection      RTS_Game/Utilities click, drag box, shift toggles, Tab, Z/H team switch
##   Orders         RTS_Orders        move (in a ring), attack, enter car, enter house, pick up gun
##   Senses         RTS_Senses        eyes (10 m, 90 degrees, line of sight), ears (noise)
##   Behaviours     RTS_Behaviours    what a unit does with no order: wander, flee, cry, shoot...
##   Tasks          RTS_AI do_task    the action of this step: walk, run, shoot, punch, eat...
##   Health         RTS_AI handle_health   death, the living turning, the dead getting up
##   Paths          (was RTS_astar)   shared distance maps on a 2 m grid instead of A* per unit
##
## World: metres, x to the right, z down the screen, the map from 0,0 to RTS.WorldSize().
## Teams: 0 the living, 1 the dead, 3 cars, 4 buildings (as in RTS_Teams.lua).
######################################################################################

constant kCell = 2           -- metres per path cell
constant kBlockCells = 8     -- a block is 8 x 8 cells (16 m); RNDRTS used 64 units
constant kBlocks = 6         -- 6 x 6 blocks, as RNDRTS's -160..160 step 64
constant kSenseEvery = 0.7   -- gSensesInterval
constant kSight = 10         -- gVisibleDistance
constant kReached = 0.6      -- gReachedTolerance

local sE, sIds, sNextId, sNow, sSpeed, sSenseAt
local sCols, sRows, sBlocked, sKindAt, sHouses, sSpots
local sFields, sFieldAt
local sTeamSelect, sStatus, sCountH, sCountZ, sShots, sLog
local sBoxBase, sLastClick, sTabAt

######################################################################################
## Game setup  (RNDRTS.fl: randomizeit, createBuildings, EntityLocations, createEntities)
######################################################################################

-- pCounts: buildings,humans,guns,cars,zombies (each 1..20, as the RNDRTS fields); empty = random
function RTS.NewGame pSeed, pCounts
   if pSeed is empty then put random(99999) into pSeed
   set the randomSeed to pSeed
   if pCounts is empty then
      put random(20),random(20),random(20),random(20),random(20) into pCounts
   end if
   put empty into sE
   put empty into sIds
   put 0 into sNextId
   put 0 into sNow
   put 1 into sSpeed
   put 0 into sSenseAt
   put empty into sFields
   put empty into sFieldAt
   put 0 into sTeamSelect
   put empty into sShots
   put empty into sLog
   put empty into sBoxBase
   put -1 into sLastClick
   put 0 into sTabAt
   RTS.MakeMap item 1 of pCounts
   RTS.MakeCast item 2 of pCounts, item 3 of pCounts, item 4 of pCounts, item 5 of pCounts
   RTS.Count
   return pSeed
end RTS.NewGame

-- RNDRTS's level name: B<b>_H<h>_G<g>_C<c>_Z<z>_RTS
function RTS.LevelName pCounts
   return "B" & item 1 of pCounts & "_H" & item 2 of pCounts & "_G" & item 3 of pCounts & \
         "_C" & item 4 of pCounts & "_Z" & item 5 of pCounts & "_RTS"
end RTS.LevelName

function RTS.WorldSize
   return kBlocks * kBlockCells * kCell
end RTS.WorldSize

on RTS.MakeMap pBuildings
   local tBlocks, tPick, tBX, tBZ, tC0, tR0, tC, tR, tSides, tSide, tTry, tDoor
   put kBlocks * kBlockCells into sCols
   put sCols into sRows
   put empty into sBlocked
   put empty into sKindAt
   put empty into sHouses
   -- housePos: every block
   repeat with tBZ = 0 to kBlocks - 1
      repeat with tBX = 0 to kBlocks - 1
         put tBX & "," & tBZ & cr after tBlocks
      end repeat
   end repeat
   delete last char of tBlocks
   repeat min(pBuildings, kBlocks * kBlocks - 1) times
      put random(the number of lines of tBlocks) into tPick
      put item 1 of line tPick of tBlocks into tBX
      put item 2 of line tPick of tBlocks into tBZ
      delete line tPick of tBlocks
      put tBX * kBlockCells into tC0
      put tBZ * kBlockCells into tR0
      -- the building: 4 x 4 cells in the middle of the block
      repeat with tR = tR0 + 2 to tR0 + 5
         repeat with tC = tC0 + 2 to tC0 + 5
            RTS.Block tC, tR, "building"
         end repeat
      end repeat
      -- its door: the middle of a random side, just outside
      put random(4) into tSide
      switch tSide
         case 1
            put tC0 + 3, tR0 + 1 into tDoor
            break
         case 2
            put tC0 + 6, tR0 + 3 into tDoor
            break
         case 3
            put tC0 + 4, tR0 + 6 into tDoor
            break
         default
            put tC0 + 1, tR0 + 4 into tDoor
      end switch
      put RTS.NewEntity("house", 4, (tC0 + 4) * kCell, (tR0 + 4) * kCell) into tPick
      put (item 1 of tDoor + 0.5) * kCell into sE[tPick]["doorX"]
      put (item 2 of tDoor + 0.5) * kCell into sE[tPick]["doorZ"]
      put 1000 into sE[tPick]["health"]
      put tPick & cr after sHouses
      -- HouseWallMap: four tries, each 3 in 4 to fence a side not yet fenced
      put "1,2,3,4" into tSides
      repeat 4 times
         if random(4) is 1 or tSides is empty then next repeat
         put random(the number of items of tSides) into tTry
         put item tTry of tSides into tSide
         delete item tTry of tSides
         repeat with tTry = 1 to kBlockCells - 2
            switch tSide
               case 1
                  RTS.Block tC0 + tTry, tR0, "fence"
                  break
               case 2
                  RTS.Block tC0 + kBlockCells - 1, tR0 + tTry, "fence"
                  break
               case 3
                  RTS.Block tC0 + tTry, tR0 + kBlockCells - 1, "fence"
                  break
               default
                  RTS.Block tC0, tR0 + tTry, "fence"
            end switch
         end repeat
      end repeat
   end repeat
   -- EntityLocations: free cells of the blocks left (RNDRTS skipped the last one too)
   put empty into sSpots
   delete last line of tBlocks
   repeat for each line tPick in tBlocks
      put (item 1 of tPick) * kBlockCells into tC0
      put (item 2 of tPick) * kBlockCells into tR0
      repeat with tR = tR0 + 1 to tR0 + kBlockCells - 2
         repeat with tC = tC0 + 1 to tC0 + kBlockCells - 2
            if sBlocked[tR * sCols + tC] is not true then put tR * sCols + tC & cr after sSpots
         end repeat
      end repeat
   end repeat
   delete last char of sSpots
end RTS.MakeMap

on RTS.Block pC, pR, pKind
   put true into sBlocked[pR * sCols + pC]
   put pKind into sKindAt[pR * sCols + pC]
end RTS.Block

-- setEntityPos: a random free spot, used up
function RTS.TakeSpot
   local tN, tCell
   if sSpots is empty then return random(RTS.WorldSize()), random(RTS.WorldSize())
   put random(the number of lines of sSpots) into tN
   put line tN of sSpots into tCell
   delete line tN of sSpots
   return ((tCell mod sCols) + 0.5) * kCell, ((tCell div sCols) + 0.5) * kCell
end RTS.TakeSpot

on RTS.MakeCast pHumans, pGuns, pCars, pZombies
   local tId, tAt, tHumans, tGuns, tH
   -- the start objects of RNDRTS (masterchief and gun1) plus the counts asked for
   repeat pHumans + 1 times
      put RTS.TakeSpot() into tAt
      put RTS.NewEntity("human", 0, item 1 of tAt, item 2 of tAt) into tId
      put tId & cr after tHumans
   end repeat
   repeat pGuns + 1 times
      put RTS.TakeSpot() into tAt
      put RTS.NewEntity("gun", 2, item 1 of tAt, item 2 of tAt) into tId
      put 8 into sE[tId]["shots"]          -- RTS_Gun.lua: pistol, 8 shots, refills 4..8
      put 0.4 into sE[tId]["interval"]
      put 0.4 into sE[tId]["deviation"]
      put tId & cr after tGuns
   end repeat
   repeat pCars times
      put RTS.TakeSpot() into tAt
      put RTS.NewEntity("car", 3, item 1 of tAt, item 2 of tAt) into tId
      put -10 into sE[tId]["health"]       -- gets health when a driver comes
   end repeat
   repeat pZombies times
      put RTS.TakeSpot() into tAt
      put RTS.NewEntity("zombie", 1, item 1 of tAt, item 2 of tAt) into tId
      put 500 + random(501) - 1 into sE[tId]["health"]
      put "zombie" into sE[tId]["behaviour"]
   end repeat
   -- HumansWithGuns: each gun to a random human; a second gun for the same human stays on the ground
   repeat for each line tId in tGuns
      put line random(the number of lines of tHumans) of tHumans into tH
      if sE[tH]["gun"] is empty then RTS.GiveGun tH, tId
   end repeat
end RTS.MakeCast

-- init_object (RTS_Attributes.lua)
function RTS.NewEntity pKind, pTeam, pX, pZ
   local tId, tA
   add 1 to sNextId
   put sNextId into tId
   put pKind into tA["kind"]
   put pTeam into tA["team"]
   put pX into tA["x"]
   put pZ into tA["z"]
   put 0 into tA["fx"]
   put 1 into tA["fz"]
   put (pKind is "human" or pKind is "zombie") into tA["alive"]
   put 100 into tA["health"]
   put 3 into tA["deathCount"]
   put "default" into tA["behaviour"]
   put 3 into tA["scareDist"]
   put 1.0 into tA["meleeDist"]
   put 6 into tA["farDist"]
   put 0.9 into tA["meleeInterval"]
   put 0.5 into tA["meleeDelay"]
   put 0 into tA["nextMelee"]
   put 0 into tA["nextShot"]
   put 0 into tA["noise"]
   put 19 + random(11) into tA["hearing"]
   put true into tA["mayRush"]
   put true into tA["mayStun"]
   put 0 into tA["stunAgainAt"]
   put false into tA["selected"]
   put false into tA["headshot"]
   put "idle" into tA["task"]
   put tA into sE[tId]
   put tId & cr after sIds
   return tId
end RTS.NewEntity

on RTS.GiveGun pId, pGun
   put pGun into sE[pId]["gun"]
   put pId into sE[pGun]["carrier"]
   put "gunned" into sE[pId]["behaviour"]
end RTS.GiveGun

######################################################################################
## Reading the game (for drawing and tests)
######################################################################################

-- one line an entity: id,kind,team,x,z,fx,fz,alive,selected,state,armed,blink
function RTS.Snapshot
   local tOut, tId, tState
   repeat for each line tId in sIds
      if sE[tId]["kind"] is "house" then next repeat
      if sE[tId]["kind"] is "gun" and sE[tId]["carrier"] is not empty then next repeat
      if sE[tId]["kind"] is "human" or sE[tId]["kind"] is "zombie" then
         if sE[tId]["vehicle"] is not empty then next repeat     -- inside a car
      end if
      put sE[tId]["task"] into tState
      if sE[tId]["frozen"] is true or (sE[tId]["kind"] is not "gun" and sE[tId]["kind"] is not "car" and sE[tId]["alive"] is not true) then put "down" into tState
      put tId,sE[tId]["kind"],sE[tId]["team"],sE[tId]["x"],sE[tId]["z"],sE[tId]["fx"],sE[tId]["fz"], \
            sE[tId]["alive"],sE[tId]["selected"],tState,(sE[tId]["gun"] is not empty), \
            (sE[tId]["blinkUntil"] + 0 > sNow) & cr after tOut
   end repeat
   delete last char of tOut
   return tOut
end RTS.Snapshot

-- blocked cells: x,z (metres, top left),size,kind  (kind building or fence)
function RTS.MapCells
   local tOut, tN
   repeat for each key tN in sBlocked
      put (tN mod sCols) * kCell, (tN div sCols) * kCell, kCell, sKindAt[tN] & cr after tOut
   end repeat
   delete last char of tOut
   return tOut
end RTS.MapCells

-- houses: id,centre x,z,door x,z
function RTS.Houses
   local tOut, tId
   repeat for each line tId in sHouses
      put tId,sE[tId]["x"],sE[tId]["z"],sE[tId]["doorX"],sE[tId]["doorZ"] & cr after tOut
   end repeat
   delete last char of tOut
   return tOut
end RTS.Houses

-- where the selected units are going: x1,z1,x2,z2,kind (move or attack): the unit markers
function RTS.Markers
   local tOut, tId, tT
   repeat for each line tId in sIds
      if sE[tId]["selected"] is not true or sE[tId]["orderKind"] is empty then next repeat
      put sE[tId]["orderTarget"] into tT
      if tT is not empty then
         put sE[tId]["x"],sE[tId]["z"],sE[tT]["x"],sE[tT]["z"],"attack" & cr after tOut
      else
         put sE[tId]["x"],sE[tId]["z"],sE[tId]["orderX"],sE[tId]["orderZ"],"move" & cr after tOut
      end if
   end repeat
   delete last char of tOut
   return tOut
end RTS.Markers

-- shots of the last 0.15 s: x1,z1,x2,z2
function RTS.Shots
   local tOut, tL
   repeat for each line tL in sShots
      if item 5 of tL > sNow - 0.15 then put item 1 to 4 of tL & cr after tOut
   end repeat
   delete last char of tOut
   put tOut into sShots
   return tOut
end RTS.Shots

function RTS.Status
   return sStatus
end RTS.Status

function RTS.Counts
   return sCountH, sCountZ
end RTS.Counts

function RTS.Get pId, pKey
   return sE[pId][pKey]
end RTS.Get

function RTS.Ids
   return sIds
end RTS.Ids

function RTS.Now
   return sNow
end RTS.Now

function RTS.Selected
   local tOut, tId
   repeat for each line tId in sIds
      if sE[tId]["selected"] is true then put tId & cr after tOut
   end repeat
   delete last char of tOut
   return tOut
end RTS.Selected

function RTS.TeamSelect
   return sTeamSelect
end RTS.TeamSelect

-- the living who carry a gun
function RTS.ArmedIds
   local tOut, tId
   repeat for each line tId in sIds
      if sE[tId]["gun"] is not empty and sE[tId]["alive"] is true then put tId & cr after tOut
   end repeat
   delete last char of tOut
   return tOut
end RTS.ArmedIds

-- the key P of the original: the task of everyone (task_to_string)
function RTS.Tasks
   local tOut, tId
   repeat for each line tId in sIds
      if sE[tId]["kind"] is "human" or sE[tId]["kind"] is "zombie" then
         put tId && sE[tId]["kind"] && "team" && sE[tId]["team"] & ":" && sE[tId]["task"] && \
               sE[tId]["taskObj"] && "(" & sE[tId]["behaviour"] & ")" & cr after tOut
      end if
   end repeat
   delete last char of tOut
   return tOut
end RTS.Tasks

######################################################################################
## Time  (RTS_Keyboard.lua: bulletTimeKey, stopTimeKey)
######################################################################################

on RTS.SetSpeed pSpeed
   put max(0.0001, pSpeed) into sSpeed
end RTS.SetSpeed

function RTS.Speed
   return sSpeed
end RTS.Speed

-- B: 1 <-> 0.1
on RTS.BulletTime
   if sSpeed is 1 then
      put 0.1 into sSpeed
   else
      put 1 into sSpeed
   end if
end RTS.BulletTime

######################################################################################
## Selection and commands  (RTS_Game.lua handle_clicks, RTS_Utilities.lua selection box)
######################################################################################

on RTS.SetTeam pTeam
   if pTeam is not sTeamSelect then
      put pTeam into sTeamSelect
      RTS.UnselectAll
   end if
end RTS.SetTeam

on RTS.UnselectAll
   local tId
   repeat for each line tId in sIds
      put false into sE[tId]["selected"]
   end repeat
end RTS.UnselectAll

function RTS.SomethingSelected
   local tId
   repeat for each line tId in sIds
      if sE[tId]["selected"] is true then return true
   end repeat
   return false
end RTS.SomethingSelected

-- Z / H pressed again, or Tab: the next unit of the team you command
function RTS.TabThrough
   local tStart, tN, tCount, tId
   put the number of lines of sIds into tCount
   put sTabAt into tStart
   repeat with tN = 1 to tCount
      put line ((tStart + tN - 1) mod tCount) + 1 of sIds into tId
      if sE[tId]["alive"] is true and sE[tId]["team"] is sTeamSelect and sE[tId]["kind"] is not "car" then
         RTS.UnselectAll
         put true into sE[tId]["selected"]
         put ((tStart + tN - 1) mod tCount) + 1 into sTabAt
         return tId
      end if
   end repeat
   return empty
end RTS.TabThrough

-- what is at a point: id or empty (units first, then guns, cars, houses)
function RTS.HitAt pX, pZ
   local tId, tBest, tBestD, tD, tR, tKind, tCell
   put empty into tBest
   put 999 into tBestD
   repeat for each line tId in sIds
      put sE[tId]["kind"] into tKind
      if tKind is "house" then next repeat
      if tKind is "gun" and sE[tId]["carrier"] is not empty then next repeat
      if sE[tId]["vehicle"] is not empty then next repeat
      if tKind is "car" then
         put 1.4 into tR
      else
         put 0.8 into tR
      end if
      put sqrt((sE[tId]["x"] - pX) ^ 2 + (sE[tId]["z"] - pZ) ^ 2) into tD
      if tD > tR then next repeat
      if tKind is "gun" then add 0.5 to tD        -- a person standing on a gun wins
      if tD < tBestD then
         put tD into tBestD
         put tId into tBest
      end if
   end repeat
   if tBest is not empty then return tBest
   put RTS.CellAt(pX, pZ) into tCell
   if sKindAt[tCell] is "building" then return RTS.HouseAt(pX, pZ)
   return empty
end RTS.HitAt

function RTS.HouseAt pX, pZ
   local tId
   repeat for each line tId in sHouses
      if abs(sE[tId]["x"] - pX) <= 4 * kCell / 2 + 0.1 and abs(sE[tId]["z"] - pZ) <= 4 * kCell / 2 + 0.1 then return tId
   end repeat
   return empty
end RTS.HouseAt

-- a mouse-down on the map. Returns "box" when the caller should start a selection box
-- (call RTS.BoxBegin then RTS.BoxUpdate while dragging), else what was done.
function RTS.ClickAt pX, pZ, pShift, pDouble
   local tHit, tSel, tId, tTeam
   -- double click: selected drivers step out of their cars
   if pDouble is true then
      repeat for each line tId in RTS.Selected()
         if sE[tId]["vehicle"] is not empty then RTS.StepOut tId
      end repeat
      put -1 into sLastClick
   end if
   put RTS.HitAt(pX, pZ) into tHit
   put RTS.Selected() into tSel
   -- nothing hit (the ground)
   if tHit is empty then
      if tSel is empty then return "box"
      RTS.OrderMove tSel, pX, pZ
      return "move"
   end if
   put sE[tHit]["team"] into tTeam
   -- your own unit: select it (Shift adds or takes away)
   if tTeam is sTeamSelect and sE[tHit]["alive"] is true then
      if pShift is not true then RTS.UnselectAll
      if pShift is true then
         put not (sE[tHit]["selected"] is true) into sE[tHit]["selected"]
      else
         put true into sE[tHit]["selected"]
      end if
      return "select"
   end if
   if tSel is empty then return "box"
   -- an enemy: attack it
   if tTeam is 1 - sTeamSelect and sE[tHit]["alive"] is true then
      repeat for each line tId in tSel
         RTS.SetOrder tId, "fight", tHit
      end repeat
      put sNow + 1 into sE[tHit]["blinkUntil"]
      return "attack"
   end if
   switch sE[tHit]["kind"]
      case "car"
         repeat for each line tId in tSel
            if sE[tId]["team"] is 1 then
               RTS.SetOrder tId, "walkTo", empty, sE[tHit]["x"], sE[tHit]["z"]
            else
               RTS.SetOrder tId, "toCar", tHit
            end if
         end repeat
         put sNow + 1 into sE[tHit]["blinkUntil"]
         return "car"
      case "house"
         repeat for each line tId in tSel
            RTS.SetOrder tId, "toHouse", tHit, sE[tHit]["doorX"], sE[tHit]["doorZ"]
         end repeat
         put sNow + 1 into sE[tHit]["blinkUntil"]
         return "house"
      case "gun"
         repeat for each line tId in tSel
            RTS.SetOrder tId, "pickup", tHit
         end repeat
         put sNow + 1 into sE[tHit]["blinkUntil"]
         return "gun"
   end switch
   return "box"
end RTS.ClickAt

-- the ring the original spread a group in: 8 on a 2 m ring, the next 8 on a 4 m ring...
on RTS.OrderMove pIds, pX, pZ
   local tId, tDist, tDeg, tX, tZ, tAt
   put 1 into tDist
   put 0 into tDeg
   put pX into tX
   put pZ into tZ
   repeat for each line tId in pIds
      put RTS.FreePoint(tX, tZ) into tAt
      RTS.SetOrder tId, "runTo", empty, item 1 of tAt, item 2 of tAt
      put pX + cos(tDeg) * trunc(tDist) * 2 into tX
      put pZ + sin(tDeg) * trunc(tDist) * 2 into tZ
      add 0.125 to tDist
      add 0.25 * pi to tDeg
   end repeat
end RTS.OrderMove

-- a free point near pX,pZ (inside the map, not in a wall)
function RTS.FreePoint pX, pZ
   local tCell
   put max(0.5, min(RTS.WorldSize() - 0.5, pX)) into pX
   put max(0.5, min(RTS.WorldSize() - 0.5, pZ)) into pZ
   put RTS.CellAt(pX, pZ) into tCell
   if sBlocked[tCell] is not true then return pX, pZ
   put RTS.FreeNear(tCell) into tCell
   return ((tCell mod sCols) + 0.5) * kCell, ((tCell div sCols) + 0.5) * kCell
end RTS.FreePoint

on RTS.BoxBegin
   local tId
   put empty into sBoxBase
   repeat for each line tId in sIds
      put sE[tId]["selected"] into sBoxBase[tId]
   end repeat
end RTS.BoxBegin

-- handle_selection_box: units of your team inside the box; Shift flips them
on RTS.BoxUpdate pX1, pZ1, pX2, pZ2, pShift
   local tId, tL, tR, tT, tB, tIn
   put min(pX1, pX2) into tL
   put max(pX1, pX2) into tR
   put min(pZ1, pZ2) into tT
   put max(pZ1, pZ2) into tB
   repeat for each line tId in sIds
      put (sBoxBase[tId] is true) into sE[tId]["selected"]
      if sE[tId]["team"] is not sTeamSelect or sE[tId]["alive"] is not true then next repeat
      if sE[tId]["vehicle"] is not empty then
         put sE[sE[tId]["vehicle"]]["x"] into tIn
         put (tIn >= tL and tIn <= tR and sE[sE[tId]["vehicle"]]["z"] >= tT and sE[sE[tId]["vehicle"]]["z"] <= tB) into tIn
      else
         put (sE[tId]["x"] >= tL and sE[tId]["x"] <= tR and sE[tId]["z"] >= tT and sE[tId]["z"] <= tB) into tIn
      end if
      if tIn then
         if pShift is true then
            put not (sBoxBase[tId] is true) into sE[tId]["selected"]
         else
            put true into sE[tId]["selected"]
         end if
      end if
   end repeat
end RTS.BoxUpdate

-- U: the dead you command rush the nearest living (uDead's R); the living: hold where they are
on RTS.Rush
   local tId
   repeat for each line tId in RTS.TeamIds(sTeamSelect)
      if sTeamSelect is 1 then
         put "zombie_rush" into sE[tId]["behaviour"]
         RTS.ClearOrder tId
      end if
   end repeat
end RTS.Rush

-- X: hold. The dead stand and look (zombie_hold_behaviour); the living drop their orders
on RTS.Hold
   local tId
   repeat for each line tId in RTS.Selected()
      RTS.ClearOrder tId
      if sE[tId]["team"] is 1 then put "zombie_hold" into sE[tId]["behaviour"]
   end repeat
end RTS.Hold

function RTS.TeamIds pTeam
   local tOut, tId
   repeat for each line tId in sIds
      if sE[tId]["team"] is pTeam and sE[tId]["alive"] is true then put tId & cr after tOut
   end repeat
   delete last char of tOut
   return tOut
end RTS.TeamIds

######################################################################################
## Orders  (RTS_Orders.lua). An order beats the behaviour until it is done.
######################################################################################

on RTS.SetOrder pId, pKind, pTarget, pX, pZ
   put pKind into sE[pId]["orderKind"]
   put pTarget into sE[pId]["orderTarget"]
   put pX into sE[pId]["orderX"]
   put pZ into sE[pId]["orderZ"]
   if pKind is "fight" and sE[pId]["team"] is 1 then put "zombie" into sE[pId]["behaviour"]
end RTS.SetOrder

on RTS.ClearOrder pId
   put empty into sE[pId]["orderKind"]
   put empty into sE[pId]["orderTarget"]
   put empty into sE[pId]["orderX"]
   put empty into sE[pId]["orderZ"]
end RTS.ClearOrder

on RTS.DoOrder pId
   local tT, tD
   put sE[pId]["orderTarget"] into tT
   switch sE[pId]["orderKind"]
      case "runTo"
      case "walkTo"
         if RTS.DistTo(pId, sE[pId]["orderX"], sE[pId]["orderZ"]) < kReached then
            RTS.ClearOrder pId
            RTS.SetTask pId, "idle"
            exit RTS.DoOrder
         end if
         if sE[pId]["orderKind"] is "walkTo" or (sE[pId]["team"] is 1 and sE[pId]["mayRush"] is not true) then
            RTS.SetTask pId, "walkToSpot", empty, sE[pId]["orderX"], sE[pId]["orderZ"]
         else
            RTS.SetTask pId, "runToSpot", empty, sE[pId]["orderX"], sE[pId]["orderZ"]
         end if
         break
      case "fight"
         RTS.FightOrder pId, tT, false
         break
      case "fightAware"
         RTS.FightOrder pId, tT, true
         break
      case "toCar"
         if sE[tT]["driver"] is not empty and sE[tT]["driver"] is not pId then
            RTS.ClearOrder pId
            exit RTS.DoOrder
         end if
         if RTS.Dist(pId, tT) < 2.0 then
            RTS.EnterCar pId, tT
            RTS.ClearOrder pId
         else
            RTS.SetTask pId, "runTo", tT
         end if
         break
      case "toHouse"
         if RTS.DistTo(pId, sE[pId]["orderX"], sE[pId]["orderZ"]) < kReached + 0.4 then
            -- run_to_house: a house refills the gun
            if sE[pId]["gun"] is not empty then
               add 3 + random(5) to sE[sE[pId]["gun"]]["shots"]
               put "gunned" into sE[pId]["behaviour"]
               RTS.Say "refilled a gun at a house"
            end if
            RTS.ClearOrder pId
            RTS.SetTask pId, "idle"
         else
            RTS.SetTask pId, "runToSpot", empty, sE[pId]["orderX"], sE[pId]["orderZ"]
         end if
         break
      case "pickup"
         if sE[tT]["carrier"] is not empty then
            RTS.ClearOrder pId
            exit RTS.DoOrder
         end if
         if RTS.Dist(pId, tT) < kReached + 0.3 then
            if sE[pId]["gun"] is empty and sE[pId]["team"] is 0 then
               RTS.GiveGun pId, tT
               put 8 into sE[tT]["shots"]
               RTS.Say "picked up a gun"
            end if
            RTS.ClearOrder pId
            RTS.SetTask pId, "idle"
         else
            RTS.SetTask pId, "runTo", tT
         end if
         break
      case "eat"
         -- eat_dead_human: until the body gets up, or six seconds
         if sE[tT]["alive"] is true or sNow > sE[pId]["orderUntil"] then
            RTS.ClearOrder pId
            RTS.SetTask pId, "idle"
         else
            RTS.SetTask pId, "eat", tT
         end if
         break
      default
         RTS.ClearOrder pId
   end switch
end RTS.DoOrder

-- fight_enemy_order and fight_enemy_order_aware
on RTS.FightOrder pId, pT, pAware
   local tD, tEmpty, tNew
   if pAware then
      put line 1 of sE[pId]["sensedIds"] into tNew
      if tNew is not empty and tNew is not pT and sE[tNew]["alive"] is true and sE[tNew]["team"] is 1 - sE[pId]["team"] then
         put tNew into pT
         put pT into sE[pId]["orderTarget"]
      end if
   end if
   if pT is empty or pT is pId or sE[pT]["alive"] is not true or sE[pT]["team"] is sE[pId]["team"] then
      RTS.ClearOrder pId
      RTS.SetTask pId, "idle"
      exit RTS.FightOrder
   end if
   put RTS.Dist(pId, pT) into tD
   if tD < sE[pId]["meleeDist"] then
      RTS.SetTask pId, "melee", pT
   else
      put (sE[pId]["gun"] is empty) into tEmpty
      if not tEmpty then put (sE[sE[pId]["gun"]]["shots"] <= 0) into tEmpty
      if tD > sE[pId]["farDist"] or tEmpty or not RTS.Clear(sE[pId]["x"], sE[pId]["z"], sE[pT]["x"], sE[pT]["z"]) then
         RTS.SetTask pId, "runTo", pT
         put 7 into sE[pId]["farDist"]
      else
         if sE[pId]["task"] is not "shoot" then put sNow + sE[sE[pId]["gun"]]["interval"] into sE[pId]["nextShot"]
         RTS.SetTask pId, "shoot", pT
         put 10 into sE[pId]["farDist"]
      end if
   end if
   if sE[pId]["task"] is "runTo" and sE[pId]["team"] is 1 and sE[pId]["mayRush"] is not true then
      RTS.SetTask pId, "goto", pT
   end if
end RTS.FightOrder

-- run_to_vehicle reached the car
on RTS.EnterCar pId, pCar
   put pCar into sE[pId]["vehicle"]
   put pId into sE[pCar]["driver"]
   put 10000 into sE[pCar]["health"]
   put "drive" into sE[pId]["behaviour"]
   RTS.Say "got into a car"
end RTS.EnterCar

-- stepOutOfCar (double click)
on RTS.StepOut pId
   local tCar, tAt
   put sE[pId]["vehicle"] into tCar
   if tCar is empty then exit RTS.StepOut
   put empty into sE[tCar]["driver"]
   put -10 into sE[tCar]["health"]
   put empty into sE[pId]["vehicle"]
   put RTS.FreePoint(sE[tCar]["x"] + 1.5, sE[tCar]["z"]) into tAt
   put item 1 of tAt into sE[pId]["x"]
   put item 2 of tAt into sE[pId]["z"]
   if sE[pId]["gun"] is not empty then
      put "gunned" into sE[pId]["behaviour"]
   else
      put "default" into sE[pId]["behaviour"]
   end if
   RTS.ClearOrder pId
end RTS.StepOut

######################################################################################
## The step  (RTS_Game.lua handle_RTS)
######################################################################################

on RTS.Step pDT
   local tDT, tId, tSense
   put min(pDT, 0.1) * sSpeed into tDT
   add tDT to sNow
   put false into tSense
   if sNow >= sSenseAt then
      put sNow + kSenseEvery into sSenseAt
      put true into tSense
      -- the maps toward each team go stale with the senses; maps toward spots keep (walls never move)
      delete variable sFields["T0"]
      delete variable sFields["T1"]
      if the number of lines of the keys of sFields > 40 then put empty into sFields
   end if
   repeat for each line tId in sIds
      if sE[tId]["kind"] is "human" or sE[tId]["kind"] is "zombie" or sE[tId]["kind"] is "car" then RTS.Health tId
   end repeat
   repeat for each line tId in sIds
      if sE[tId]["kind"] is not "human" and sE[tId]["kind"] is not "zombie" then next repeat
      if sE[tId]["alive"] is true then
         if tSense then RTS.Sense tId
         RTS.Think tId
         RTS.DoTask tId, tDT
      else
         RTS.Rising tId
      end if
      put max(0, sE[tId]["noise"] - tDT) into sE[tId]["noise"]
   end repeat
   RTS.Separate
   if tSense then RTS.Count
end RTS.Step

-- the freeze after death, then the dead get up (handle_RTS freezeTime / freeze)
on RTS.Rising pId
   if sE[pId]["freezeAt"] is empty then exit RTS.Rising
   if sNow < sE[pId]["freezeAt"] then exit RTS.Rising
   if sE[pId]["frozen"] is not true then
      put true into sE[pId]["frozen"]
      put sNow + 6 into sE[pId]["freezeAt"]
      exit RTS.Rising
   end if
   if sE[pId]["team"] is 1 and sE[pId]["headshot"] is not true and sE[pId]["deathCount"] > 0 then
      put false into sE[pId]["frozen"]
      put empty into sE[pId]["freezeAt"]
      put true into sE[pId]["alive"]
      put 500 + random(501) - 1 into sE[pId]["health"]
      put "reanimate" into sE[pId]["behaviour"]
      put sNow + 0.5 into sE[pId]["reanimateUntil"]
      put "zombie" into sE[pId]["kind"]
      put empty into sE[pId]["mind"]
      put empty into sE[pId]["sensedIds"]
      RTS.Say "a body gets up"
   else
      put empty into sE[pId]["freezeAt"]        -- stays down for good
   end if
end RTS.Rising

-- handle_health
on RTS.Health pId
   local tGun, tCar, tDriver
   if sE[pId]["kind"] is "car" then
      put sE[pId]["driver"] into tDriver
      if sE[pId]["health"] <= 0 and tDriver is not empty then
         put -10 into sE[tDriver]["health"]       -- the driver falls out, dead
         RTS.StepOut tDriver
      end if
      exit RTS.Health
   end if
   if sE[pId]["health"] > 0 or sE[pId]["alive"] is not true then exit RTS.Health
   subtract 1 from sE[pId]["deathCount"]
   if sE[pId]["headshot"] is true then put 0 into sE[pId]["deathCount"]
   put sE[pId]["vehicle"] into tCar
   if tCar is not empty then RTS.StepOut pId
   put false into sE[pId]["alive"]
   put sNow + 3 into sE[pId]["freezeAt"]
   put false into sE[pId]["frozen"]
   RTS.ClearOrder pId
   put false into sE[pId]["selected"]
   put empty into sE[pId]["event"]
   RTS.SetTask pId, "idle"
   put sE[pId]["gun"] into tGun
   if tGun is not empty then
      -- the gun drops where the body falls
      put empty into sE[tGun]["carrier"]
      put sE[pId]["x"] + 0.6 into sE[tGun]["x"]
      put sE[pId]["z"] into sE[tGun]["z"]
      put empty into sE[pId]["gun"]
   end if
   if sE[pId]["team"] is 1 then put false into sE[pId]["mayRush"]
   if sE[pId]["team"] is 0 then
      put 1 into sE[pId]["team"]               -- the living who die join the dead
      put "zombie" into sE[pId]["behaviour"]
      put 0.5 into sE[pId]["meleeDelay"]
   end if
   RTS.Count
end RTS.Health

-- rts_update_living_and_dead_counts
on RTS.Count
   local tId, tH, tZ, tRush, tFollow, tHold, tEat, tOrders
   put 0 into tH
   put 0 into tZ
   put 0 into tRush
   put 0 into tFollow
   put 0 into tHold
   put 0 into tEat
   put 0 into tOrders
   repeat for each line tId in sIds
      if sE[tId]["kind"] is not "human" and sE[tId]["kind"] is not "zombie" then next repeat
      if sE[tId]["team"] is 0 and sE[tId]["alive"] is true then add 1 to tH
      if sE[tId]["team"] is 1 and sE[tId]["deathCount"] > 0 then
         add 1 to tZ
         if sE[tId]["alive"] is not true then next repeat
         if sE[tId]["task"] is "eat" then
            add 1 to tEat
         else if sE[tId]["orderKind"] is not empty then
            add 1 to tOrders
         else if sE[tId]["behaviour"] is "zombie_rush" then
            add 1 to tRush
         else if sE[tId]["behaviour"] is "zombie_hold" then
            add 1 to tHold
         else
            add 1 to tFollow
         end if
      end if
   end repeat
   put tH into sCountH
   put tZ into sCountZ
   if tH > 0 and tZ > 0 then
      put tH && "living" & cr & tZ && "dead" & cr & cr & tRush && "rushing" & cr & tFollow && "roaming" & cr & \
            tHold && "holding position" & cr & tOrders && "in action" & cr & tEat && "eating" & cr & \
            (tZ - tRush - tFollow - tHold - tOrders - tEat) && "down" into sStatus
   else if tH is 0 and tZ > 0 then
      put "All Living Devoured!!" into sStatus
   else if tH is 0 and tZ is 0 then
      put "Everybody Is Dead!!" into sStatus
   else
      put "All Zombies Destroyed!!!" into sStatus
   end if
end RTS.Count

-- what happened lately, newest last (the demo shows it)
on RTS.Say pText
   put round(sNow, 1) && pText & cr after sLog
   if the number of lines of sLog > 20 then delete line 1 of sLog
end RTS.Say

function RTS.Log
   return sLog
end RTS.Log

######################################################################################
## Senses  (RTS_Senses.lua, sort_perceived_objects_by_priority in RTS_AI.lua)
######################################################################################

on RTS.Sense pId
   local tId, tD, tDX, tDZ, tSeen, tHeard, tPrio, tList, tMind, tOther, tSeenNow, tSensed
   put sE[pId]["mind"] into tMind
   repeat for each line tId in sIds
      if tId is pId then next repeat
      if sE[tId]["kind"] is not "human" and sE[tId]["kind"] is not "zombie" and sE[tId]["kind"] is not "car" and sE[tId]["kind"] is not "house" then next repeat
      if sE[tId]["vehicle"] is not empty then next repeat
      put RTS.Dist(pId, tId) into tD
      put false into tSeen
      put false into tHeard
      if tD < kSight and sE[tId]["kind"] is not "house" then
         -- eyes: within 90 degrees of where it faces, and nothing in between
         put sE[tId]["x"] - sE[pId]["x"] into tDX
         put sE[tId]["z"] - sE[pId]["z"] into tDZ
         if tD < 0.01 or (tDX * sE[pId]["fx"] + tDZ * sE[pId]["fz"]) / tD >= 0.707 then
            put RTS.Clear(sE[pId]["x"], sE[pId]["z"], sE[tId]["x"], sE[tId]["z"]) into tSeen
         end if
      end if
      -- ears: noise carries hearing distance times loudness
      if tD <= sE[pId]["hearing"] * sE[tId]["noise"] then put true into tHeard
      if sE[tId]["kind"] is "house" and tD < kSight then put true into tHeard      -- houses are known nearby
      if tSeen then put true into tMind[tId]
      -- forget_corpses: the dead-for-good drop out of mind
      if sE[tId]["alive"] is not true and sE[tId]["kind"] is not "car" and sE[tId]["kind"] is not "house" then
         delete variable tMind[tId]
         next repeat
      end if
      if not (tSeen or tHeard or tMind[tId] is true) then next repeat
      put 0 into tPrio
      if tSeen then add 2 to tPrio
      if tHeard then add 1 to tPrio
      if sE[tId]["team"] is 1 - sE[pId]["team"] and sE[tId]["alive"] is true then add 3 to tPrio
      put trunc(tPrio * max(50 - tD, 1)) into tPrio
      put tPrio & "," & tId & "," & tSeen & cr after tList
   end repeat
   put tMind into sE[pId]["mind"]
   sort lines of tList descending numeric by item 1 of each
   put empty into tSeenNow
   put empty into tSensed
   repeat for each line tOther in tList
      put item 2 of tOther & cr after tSensed
      if item 3 of tOther is true then put true into tSeenNow[item 2 of tOther]
   end repeat
   delete last char of tSensed
   put tSensed into sE[pId]["sensedIds"]
   put tSeenNow into sE[pId]["seenNow"]
end RTS.Sense

function RTS.Seen pId, pOther
   return sE[pId]["seenNow"][pOther] is true
end RTS.Seen

function RTS.SeenBefore pId, pOther
   return sE[pId]["mind"][pOther] is true
end RTS.SeenBefore

######################################################################################
## Thinking: event, else order, else behaviour  (handle_order_and_behaviour)
######################################################################################

on RTS.Think pId
   put sE[pId]["task"] into sE[pId]["lastTask"]
   if sE[pId]["mayStun"] is not true and sNow > sE[pId]["stunAgainAt"] then put true into sE[pId]["mayStun"]
   if sE[pId]["event"] is not empty then
      if sNow < sE[pId]["eventUntil"] then
         RTS.SetTask pId, sE[pId]["event"], sE[pId]["eventTarget"]
         exit RTS.Think
      end if
      put empty into sE[pId]["event"]
   end if
   if sE[pId]["orderKind"] is not empty then
      RTS.DoOrder pId
      exit RTS.Think
   end if
   RTS.Behave pId
end RTS.Think

on RTS.SetTask pId, pTask, pObj, pX, pZ
   put pTask into sE[pId]["task"]
   put pObj into sE[pId]["taskObj"]
   put pX into sE[pId]["taskX"]
   put pZ into sE[pId]["taskZ"]
end RTS.SetTask

on RTS.Event pId, pEvent, pSeconds, pTarget
   put pEvent into sE[pId]["event"]
   put sNow + pSeconds into sE[pId]["eventUntil"]
   put pTarget into sE[pId]["eventTarget"]
end RTS.Event

-- the first one it senses, if that is an enemy that is up
function RTS.Threat pId
   local tT
   put line 1 of sE[pId]["sensedIds"] into tT
   if tT is empty then return empty
   if sE[tT]["team"] is not 1 - sE[pId]["team"] or sE[tT]["alive"] is not true then return empty
   return tT
end RTS.Threat

on RTS.Behave pId
   local tT, tD
   put RTS.Threat(pId) into tT
   switch sE[pId]["behaviour"]
      case "default"
         -- always run away from enemies close by; otherwise wander
         if tT is not empty and RTS.Dist(pId, tT) < sE[pId]["scareDist"] then
            put 6 into sE[pId]["scareDist"]
            RTS.Flee pId, tT
         else
            put 3 into sE[pId]["scareDist"]
            RTS.Wander pId, 1
         end if
         break
      case "cry"
         -- stand_and_cry: five seconds, then back to what it did
         RTS.SetTask pId, "cry", tT
         if sNow > sE[pId]["cryUntil"] then put sE[pId]["oldBehaviour"] into sE[pId]["behaviour"]
         break
      case "gunned"
         -- gunned_civilian_behaviour: shoot what it sees, chase what it saw, else seek and destroy
         if tT is not empty and RTS.Seen(pId, tT) then
            if sE[pId]["task"] is not "shoot" then put sNow + sE[sE[pId]["gun"]]["interval"] into sE[pId]["nextShot"]
            if sE[sE[pId]["gun"]]["shots"] > 0 then
               RTS.SetTask pId, "shoot", tT
            else
               RTS.SetOrder pId, "fight", tT
            end if
         else if tT is not empty and RTS.SeenBefore(pId, tT) then
            RTS.SetTask pId, "runTo", tT
         else
            RTS.SeekAndDestroy pId
         end if
         break
      case "sniper"
         if tT is not empty and RTS.Seen(pId, tT) then
            RTS.SetTask pId, "shoot", tT
         else
            RTS.SetTask pId, "idle"
         end if
         break
      case "zombie"
         -- in the RTS the dead with no order roam slowly and go for the living they see
         -- (UDG's zombie_behaviour followed the player's box; there is no player box here)
         if tT is not empty and (RTS.Seen(pId, tT) or RTS.Dist(pId, tT) < 3) then
            RTS.SetOrder pId, "fightAware", tT
         else
            RTS.Wander pId, 0.5
         end if
         break
      case "zombie_hold"
         if tT is not empty then
            RTS.SetTask pId, "lookAt", tT
         else
            RTS.SetTask pId, "idle"
         end if
         break
      case "zombie_rush"
         -- zombie_rush_behaviour: the nearest living, wherever they are
         put RTS.Nearest(pId, 1 - sE[pId]["team"]) into tT
         if tT is empty then
            put "zombie" into sE[pId]["behaviour"]
            RTS.SetTask pId, "idle"
         else
            RTS.SetOrder pId, "fightAware", tT
            put "zombie_rush" into sE[pId]["behaviour"]
         end if
         break
      case "reanimate"
         RTS.SetTask pId, "reanimate"
         if sNow > sE[pId]["reanimateUntil"] then put "zombie" into sE[pId]["behaviour"]
         break
      case "drive"
         RTS.SetTask pId, "drive", sE[pId]["vehicle"]
         break
      default
         RTS.SetTask pId, "idle"
   end switch
end RTS.Behave

-- seekAndDestroy: run along the map toward the nearest enemy
on RTS.SeekAndDestroy pId
   local tT
   put RTS.Nearest(pId, 1 - sE[pId]["team"]) into tT
   if tT is empty then
      RTS.SetTask pId, "idle"
   else
      RTS.SetTask pId, "runTo", tT
   end if
end RTS.SeekAndDestroy

-- randomWalking: a spot within 8 m it can see, a new one when there
on RTS.Wander pId, pPace
   local tA, tX, tZ, tTry
   if sE[pId]["wanderX"] is empty or RTS.DistTo(pId, sE[pId]["wanderX"], sE[pId]["wanderZ"]) < kReached or sNow > sE[pId]["wanderUntil"] then
      repeat 6 times
         put random(628) / 100 into tA
         put sE[pId]["x"] + cos(tA) * (2 + random(6)) into tX
         put sE[pId]["z"] + sin(tA) * (2 + random(6)) into tZ
         if tX > 1 and tZ > 1 and tX < RTS.WorldSize() - 1 and tZ < RTS.WorldSize() - 1 then
            if RTS.Clear(sE[pId]["x"], sE[pId]["z"], tX, tZ) then exit repeat
         end if
         put empty into tX
      end repeat
      put tX into sE[pId]["wanderX"]
      put tZ into sE[pId]["wanderZ"]
      put sNow + 6 + random(6) into sE[pId]["wanderUntil"]
   end if
   if sE[pId]["wanderX"] is empty then
      RTS.SetTask pId, "idle"
   else
      RTS.SetTask pId, "walkToSpot", empty, sE[pId]["wanderX"], sE[pId]["wanderZ"]
      put pPace into sE[pId]["pace"]
   end if
end RTS.Wander

-- flee_to_safe_place / standard_flee: run away; with nowhere to go, stand and cry
on RTS.Flee pId, pFrom
   local tBest, tBestD, tA, tX, tZ, tD
   put -1 into tBestD
   repeat with tA = 0 to 7
      put sE[pId]["x"] + cos(tA * pi / 4) * 3 into tX
      put sE[pId]["z"] + sin(tA * pi / 4) * 3 into tZ
      if tX < 0.5 or tZ < 0.5 or tX > RTS.WorldSize() - 0.5 or tZ > RTS.WorldSize() - 0.5 then next repeat
      if not RTS.Clear(sE[pId]["x"], sE[pId]["z"], tX, tZ) then next repeat
      put sqrt((tX - sE[pFrom]["x"]) ^ 2 + (tZ - sE[pFrom]["z"]) ^ 2) into tD
      if tD > tBestD then
         put tD into tBestD
         put tX, tZ into tBest
      end if
   end repeat
   if tBest is empty or tBestD < RTS.Dist(pId, pFrom) then
      put sE[pId]["behaviour"] into sE[pId]["oldBehaviour"]
      put "cry" into sE[pId]["behaviour"]
      put sNow + 5 into sE[pId]["cryUntil"]
      RTS.SetTask pId, "cry", pFrom
      exit RTS.Flee
   end if
   RTS.SetTask pId, "runOff", pFrom, item 1 of tBest, item 2 of tBest
end RTS.Flee

######################################################################################
## Tasks  (do_task in RTS_AI.lua): the action of this step
######################################################################################

on RTS.DoTask pId, pDT
   local tT, tSpeed, tCar
   put sE[pId]["taskObj"] into tT
   -- in a car: the car does the moving, the driver goes with it
   put sE[pId]["vehicle"] into tCar
   if tCar is not empty then
      RTS.Drive pId, tCar, pDT
      exit RTS.DoTask
   end if
   if sE[pId]["team"] is 1 then
      put 1.8 into tSpeed
   else
      put 2.0 into tSpeed
   end if
   switch sE[pId]["task"]
      case "walkToSpot"
         if sE[pId]["pace"] is empty then put 1 into sE[pId]["pace"]
         RTS.MoveToward pId, sE[pId]["taskX"], sE[pId]["taskZ"], 1.2 * sE[pId]["pace"], pDT
         put empty into sE[pId]["pace"]
         break
      case "runToSpot"
         RTS.MoveToward pId, sE[pId]["taskX"], sE[pId]["taskZ"], tSpeed, pDT
         break
      case "runOff"
         RTS.MoveToward pId, sE[pId]["taskX"], sE[pId]["taskZ"], tSpeed, pDT
         break
      case "runTo"
         if tT is not empty then RTS.MoveToward pId, sE[tT]["x"], sE[tT]["z"], tSpeed, pDT, tT
         break
      case "goto"
         if tT is not empty then RTS.MoveToward pId, sE[tT]["x"], sE[tT]["z"], 1.2, pDT, tT
         break
      case "shoot"
         RTS.Face pId, sE[tT]["x"], sE[tT]["z"]
         RTS.Shoot pId, tT
         break
      case "melee"
         RTS.Face pId, sE[tT]["x"], sE[tT]["z"]
         RTS.Melee pId, tT
         break
      case "lookAt"
      case "cry"
      case "eat"
         if tT is not empty then RTS.Face pId, sE[tT]["x"], sE[tT]["z"]
         break
   end switch
end RTS.DoTask

-- walk or run toward a point: straight when nothing is in the way, else down a distance map
on RTS.MoveToward pId, pX, pZ, pSpeed, pDT, pTarget
   local tX, tZ, tDX, tDZ, tD, tStep, tNext, tKey
   put sE[pId]["x"] into tX
   put sE[pId]["z"] into tZ
   if not RTS.Clear(tX, tZ, pX, pZ) then
      if pTarget is not empty and sE[pTarget]["kind"] is not "car" and sE[pTarget]["kind"] is not "gun" then
         put "T" & sE[pTarget]["team"] into tKey      -- the map toward that whole team
      else
         put "G" & RTS.CellAt(pX, pZ) into tKey       -- the map toward that spot
      end if
      put RTS.NextCell(tKey, RTS.CellAt(tX, tZ), pX, pZ) into tNext
      if tNext is not empty then
         put ((tNext mod sCols) + 0.5) * kCell into pX
         put ((tNext div sCols) + 0.5) * kCell into pZ
      end if
   end if
   put pX - tX into tDX
   put pZ - tZ into tDZ
   put sqrt(tDX ^ 2 + tDZ ^ 2) into tD
   if tD < 0.001 then exit RTS.MoveToward
   put tDX / tD into tDX
   put tDZ / tD into tDZ
   put tDX into sE[pId]["fx"]
   put tDZ into sE[pId]["fz"]
   put min(tD, pSpeed * pDT) into tStep
   RTS.Slide pId, tX + tDX * tStep, tZ + tDZ * tStep
end RTS.MoveToward

-- move there, or slide along the wall in the way
on RTS.Slide pId, pX, pZ
   if not RTS.Solid(pX, pZ) then
      put pX into sE[pId]["x"]
      put pZ into sE[pId]["z"]
   else if not RTS.Solid(pX, sE[pId]["z"]) then
      put pX into sE[pId]["x"]
   else if not RTS.Solid(sE[pId]["x"], pZ) then
      put pZ into sE[pId]["z"]
   end if
end RTS.Slide

on RTS.Face pId, pX, pZ
   local tDX, tDZ, tD
   put pX - sE[pId]["x"] into tDX
   put pZ - sE[pId]["z"] into tDZ
   put sqrt(tDX ^ 2 + tDZ ^ 2) into tD
   if tD < 0.001 then exit RTS.Face
   put tDX / tD into sE[pId]["fx"]
   put tDZ / tD into sE[pId]["fz"]
end RTS.Face

-- object_action_shootat. Bullet damage lived in the C engine; these numbers are uDead's
on RTS.Shoot pId, pT
   local tGun, tD, tHit
   put sE[pId]["gun"] into tGun
   if tGun is empty or pT is empty then exit RTS.Shoot
   put 1 into sE[pId]["noise"]                    -- shots can be heard
   if sNow < sE[pId]["nextShot"] then exit RTS.Shoot
   put sNow + sE[tGun]["interval"] - sE[tGun]["deviation"] * 0.5 + random(100) / 100 * sE[tGun]["deviation"] into sE[pId]["nextShot"]
   put RTS.Dist(pId, pT) into tD
   put random(100) <= max(15, 100 - tD * 7) into tHit
   put sE[pId]["x"], sE[pId]["z"], sE[pT]["x"] + (random(9) - 5) / 10, sE[pT]["z"] + (random(9) - 5) / 10, sNow & cr after sShots
   if tHit then
      if random(10) is 1 then
         put true into sE[pT]["headshot"]
         subtract 10000 from sE[pT]["health"]
      else
         subtract 185 from sE[pT]["health"]
      end if
      -- remember who shot me
      put true into sE[pT]["mind"][pId]
   end if
   subtract 1 from sE[tGun]["shots"]
   if sE[tGun]["shots"] <= 0 then
      put 8 into sE[tGun]["shots"]                 -- recharge, after three seconds of reloading
      RTS.Event pId, "reload", 3, pT
   end if
end RTS.Shoot

-- object_action_melee
on RTS.Melee pId, pT
   local tDmg
   if pT is empty or sE[pT]["alive"] is not true then exit RTS.Melee
   put 20 into tDmg
   if sE[pId]["gun"] is not empty then put 10000 into tDmg     -- a gun butt ends it
   -- the living: half the time the first blow of a fight stuns instead of hurting
   if sE[pId]["team"] is 0 and sE[pId]["mayStun"] is true then
      if random(2) is 1 then
         put 0 into tDmg
         RTS.Event pId, "kick", 0.9, pT
         RTS.Event pT, "stunned", 0.9, pId
         if sE[pId]["gun"] is empty then RTS.ClearOrder pId     -- better run!
      end if
      put false into sE[pId]["mayStun"]
      put sNow + 3 into sE[pId]["stunAgainAt"]
   end if
   if sE[pId]["lastTask"] is not "melee" then
      put sNow + sE[pId]["meleeDelay"] into sE[pId]["nextMelee"]
   end if
   if sNow > sE[pId]["nextMelee"] then
      put max(sE[pId]["meleeDelay"], 0.5) into sE[pId]["meleeDelay"]
      subtract tDmg from sE[pT]["health"]
      put sNow + sE[pId]["meleeInterval"] into sE[pId]["nextMelee"]
      if sE[pT]["health"] <= 0 then
         if sE[pId]["team"] is 0 then
            put true into sE[pId]["mayStun"]
            RTS.ClearOrder pId
         else
            -- the dead won: eat
            RTS.SetOrder pId, "eat", pT
            put sNow + 6 into sE[pId]["orderUntil"]
            RTS.Say "someone was caught"
         end if
      else
         -- remember fights: the one hit must fight back now
         if sE[pT]["orderKind"] is empty or sE[pT]["orderKind"] is "runTo" or sE[pT]["orderKind"] is "walkTo" then
            RTS.SetOrder pT, "fight", pId
         end if
         put true into sE[pT]["mind"][pId]
      end if
   end if
end RTS.Melee

-- a driven car: toward the driver's order spot, else stand; it runs the dead down
on RTS.Drive pId, pCar, pDT
   local tX, tZ, tId
   if sE[pId]["orderKind"] is "runTo" or sE[pId]["orderKind"] is "walkTo" or sE[pId]["orderKind"] is "toHouse" then
      put sE[pId]["x"] into tX
      put sE[pId]["z"] into tZ
      put sE[pCar]["x"] into sE[pId]["x"]
      put sE[pCar]["z"] into sE[pId]["z"]
      RTS.MoveToward pId, sE[pId]["orderX"], sE[pId]["orderZ"], 6, pDT
      put sE[pId]["x"] into sE[pCar]["x"]
      put sE[pId]["z"] into sE[pCar]["z"]
      put sE[pId]["fx"] into sE[pCar]["fx"]
      put sE[pId]["fz"] into sE[pCar]["fz"]
      if RTS.DistTo(pId, sE[pId]["orderX"], sE[pId]["orderZ"]) < 1.5 then RTS.ClearOrder pId
      put 0.6 into sE[pCar]["noise"]
      repeat for each line tId in sIds
         if sE[tId]["team"] is 1 and sE[tId]["alive"] is true and RTS.Dist(pCar, tId) < 1.6 then
            subtract 400 from sE[tId]["health"]
         end if
      end repeat
   end if
   put sE[pCar]["x"] into sE[pId]["x"]
   put sE[pCar]["z"] into sE[pId]["z"]
   RTS.SetTask pId, "drive", pCar
end RTS.Drive

-- keep bodies from standing in each other
on RTS.Separate
   local tA, tB, tList, tDX, tDZ, tD, tPush, tN, tM, tCount
   repeat for each line tA in sIds
      if sE[tA]["alive"] is true and sE[tA]["vehicle"] is empty and (sE[tA]["kind"] is "human" or sE[tA]["kind"] is "zombie") then
         add 1 to tCount
         put tA into tList[tCount]
      end if
   end repeat
   repeat with tN = 1 to tCount - 1
      put tList[tN] into tA
      repeat with tM = tN + 1 to tCount
         put tList[tM] into tB
         put sE[tB]["x"] - sE[tA]["x"] into tDX
         if abs(tDX) > 0.6 then next repeat
         put sE[tB]["z"] - sE[tA]["z"] into tDZ
         if abs(tDZ) > 0.6 then next repeat
         put sqrt(tDX ^ 2 + tDZ ^ 2) into tD
         if tD >= 0.6 then next repeat
         if tD < 0.01 then
            put 0.01 into tDX
            put 0.01 into tD
         end if
         put (0.6 - tD) / 2 into tPush
         RTS.Slide tA, sE[tA]["x"] - tDX / tD * tPush, sE[tA]["z"] - tDZ / tD * tPush
         RTS.Slide tB, sE[tB]["x"] + tDX / tD * tPush, sE[tB]["z"] + tDZ / tD * tPush
      end repeat
   end repeat
end RTS.Separate

######################################################################################
## Space and paths  (replaces RTS_astar.lua: one distance map serves many walkers)
######################################################################################

function RTS.CellAt pX, pZ
   local tC, tR
   put max(0, min(sCols - 1, trunc(pX / kCell))) into tC
   put max(0, min(sRows - 1, trunc(pZ / kCell))) into tR
   return tR * sCols + tC
end RTS.CellAt

function RTS.Solid pX, pZ
   if pX < 0.2 or pZ < 0.2 or pX > RTS.WorldSize() - 0.2 or pZ > RTS.WorldSize() - 0.2 then return true
   return sBlocked[RTS.CellAt(pX, pZ)] is true
end RTS.Solid

-- nothing solid on the line (a look every half metre)
function RTS.Clear pX1, pZ1, pX2, pZ2
   local tD, tN, tK
   put sqrt((pX2 - pX1) ^ 2 + (pZ2 - pZ1) ^ 2) into tD
   put trunc(tD / 0.5) into tN
   repeat with tK = 1 to tN
      if sBlocked[RTS.CellAt(pX1 + (pX2 - pX1) * tK / (tN + 1), pZ1 + (pZ2 - pZ1) * tK / (tN + 1))] is true then return false
   end repeat
   return true
end RTS.Clear

function RTS.FreeNear pCell
   local tC, tR, tRing, tDC, tDR, tN
   put pCell mod sCols into tC
   put pCell div sCols into tR
   repeat with tRing = 1 to 6
      repeat with tDR = -tRing to tRing
         repeat with tDC = -tRing to tRing
            if tC + tDC < 0 or tC + tDC >= sCols or tR + tDR < 0 or tR + tDR >= sRows then next repeat
            put (tR + tDR) * sCols + tC + tDC into tN
            if sBlocked[tN] is not true then return tN
         end repeat
      end repeat
   end repeat
   return pCell
end RTS.FreeNear

-- a distance map: steps from every cell to the nearest seed cell (4 ways, walls block)
function RTS.Field pSeeds
   local tD, tQ, tHead, tTail, tN, tC, tV, tNb
   put 0 into tTail
   repeat for each line tN in pSeeds
      if tN is empty then next repeat
      if sBlocked[tN] is true then put RTS.FreeNear(tN) into tN
      if tD[tN] is not empty then next repeat
      put 0 into tD[tN]
      add 1 to tTail
      put tN into tQ[tTail]
   end repeat
   put 1 into tHead
   repeat while tHead <= tTail
      put tQ[tHead] into tN
      add 1 to tHead
      put tD[tN] + 1 into tV
      put tN mod sCols into tC
      if tC > 0 then
         put tN - 1 into tNb
         if tD[tNb] is empty and sBlocked[tNb] is not true then
            put tV into tD[tNb]
            add 1 to tTail
            put tNb into tQ[tTail]
         end if
      end if
      if tC < sCols - 1 then
         put tN + 1 into tNb
         if tD[tNb] is empty and sBlocked[tNb] is not true then
            put tV into tD[tNb]
            add 1 to tTail
            put tNb into tQ[tTail]
         end if
      end if
      if tN >= sCols then
         put tN - sCols into tNb
         if tD[tNb] is empty and sBlocked[tNb] is not true then
            put tV into tD[tNb]
            add 1 to tTail
            put tNb into tQ[tTail]
         end if
      end if
      if tN < sCols * (sRows - 1) then
         put tN + sCols into tNb
         if tD[tNb] is empty and sBlocked[tNb] is not true then
            put tV into tD[tNb]
            add 1 to tTail
            put tNb into tQ[tTail]
         end if
      end if
   end repeat
   return tD
end RTS.Field

-- the next cell to step to from pCell along map pKey ("T0"/"T1" a team, "G<cell>" a spot)
function RTS.NextCell pKey, pCell, pX, pZ
   local tD, tSeeds, tId, tTeam, tBest, tBestV, tC, tR, tDC, tDR, tN, tOK
   if sFields[pKey] is empty then
      if char 1 of pKey is "T" then
         put char 2 to -1 of pKey into tTeam
         repeat for each line tId in sIds
            if sE[tId]["team"] is tTeam and sE[tId]["alive"] is true then put RTS.CellAt(sE[tId]["x"], sE[tId]["z"]) & cr after tSeeds
         end repeat
      else
         put char 2 to -1 of pKey into tSeeds
      end if
      put RTS.Field(tSeeds) into sFields[pKey]
   end if
   put sFields[pKey] into tD
   put tD[pCell] into tBestV
   if tBestV is empty then return empty
   put empty into tBest
   put pCell mod sCols into tC
   put pCell div sCols into tR
   repeat with tDR = -1 to 1
      repeat with tDC = -1 to 1
         if tDR is 0 and tDC is 0 then next repeat
         if tC + tDC < 0 or tC + tDC >= sCols or tR + tDR < 0 or tR + tDR >= sRows then next repeat
         put (tR + tDR) * sCols + tC + tDC into tN
         if tD[tN] is empty then next repeat
         -- no cutting a corner past a wall
         put true into tOK
         if tDR is not 0 and tDC is not 0 then
            if sBlocked[tR * sCols + tC + tDC] is true or sBlocked[(tR + tDR) * sCols + tC] is true then put false into tOK
         end if
         if tOK and tD[tN] < tBestV then
            put tD[tN] into tBestV
            put tN into tBest
         end if
      end repeat
   end repeat
   return tBest
end RTS.NextCell

function RTS.Dist pA, pB
   return sqrt((sE[pA]["x"] - sE[pB]["x"]) ^ 2 + (sE[pA]["z"] - sE[pB]["z"]) ^ 2)
end RTS.Dist

function RTS.DistTo pA, pX, pZ
   return sqrt((sE[pA]["x"] - pX) ^ 2 + (sE[pA]["z"] - pZ) ^ 2)
end RTS.DistTo

-- getNearestEnemy (pass the enemy team)
function RTS.Nearest pId, pTeam
   local tBest, tBestD, tId, tD
   put 99999 into tBestD
   repeat for each line tId in sIds
      if sE[tId]["team"] is not pTeam or sE[tId]["alive"] is not true then next repeat
      if sE[tId]["vehicle"] is not empty then next repeat
      put RTS.Dist(pId, tId) into tD
      if tD < tBestD then
         put tD into tBestD
         put tId into tBest
      end if
   end repeat
   return tBest
end RTS.Nearest
