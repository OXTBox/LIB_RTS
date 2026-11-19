script "RTS_Demo"
######################################################################################
## RTS_Demo  (17 11 2026)
## A small demonstration of LIB_RTS: a random RNDRTS level seen from above.
## Open this file in the IDE (it builds its own cards). It loads RTS_Library.livecodescript
## from the same folder.
##
##   drag on the map          select your units in a box (Shift adds or takes away)
##   click a unit of yours    select just it (Shift: add / take away)
##   click with units chosen  the ground: go there in a ring; an enemy: attack it;
##                            a gun: pick it up; a house: go in (refills guns); a car: get in
##   double click             selected drivers get out of their cars
##   H / Z                    command the living / the dead (again: the next one, like Tab)
##   Tab                      the next unit      Space   select nobody
##   U                        the dead you command rush the nearest living
##   X                        hold: the selected drop their orders (the dead stand and look)
##   B                        slow time (x0.1) on and off
##   P                        every unit's task in the side panel
##   N                        a new random level (RNDRTS's Randomize)
##   Escape                   pause; while paused + and - set the game speed
##   ` or F2                  write a note for the AI (a line starting with / runs as xTalk)
##   ? or F1                  the About card
######################################################################################

constant kScale = 7                 -- pixels a metre
constant kMapL = 10
constant kMapT = 36

local sPaused, sTickMsg, sLastMs, sDragging, sDragX, sDragZ, sShowTasks
local sSeed, sCounts, sMsg, sMsgUntil, sNoteOpen

on openStack
   Demo.Start
end openStack

on Demo.Start
   local tLib
   set the defaultStack to the short name of me
   put the effective filename of me into tLib
   set the itemDelimiter to "/"
   put item 1 to -2 of tLib & "/RTS_Library.livecodescript" into tLib
   set the itemDelimiter to ","
   if there is not a stack "RTS_Library" then
      if there is a file tLib then
         start using stack tLib
      else
         answer "RTS_Library.livecodescript must sit next to this stack:" & cr & tLib
         exit Demo.Start
      end if
   else
      start using stack "RTS_Library"
   end if
   Demo.StopLoop
   if there is not a card "Play" of stack "RTS_Demo" then Demo.Build
   set the title of me to "FOR OWNER | RTS_Demo: drag to select, click to command, ? for help"
   dispatch "Users.TitleStack" with the short name of me, "RTS_Demo: drag to select, click to command, ? for help"   -- LIB_USERS words it, when in use
   go card "Play" of stack "RTS_Demo"
   Demo.NewLevel
   put false into sPaused
   put the milliseconds into sLastMs
   Demo.Loop
end Demo.Start

on Demo.NewLevel pCounts, pSeed
   if pCounts is empty then
      put random(20),random(20),random(20),random(20),random(20) into pCounts   -- randomizeit
   end if
   put pCounts into sCounts
   put RTS.NewGame(pSeed, pCounts) into sSeed
   Demo.DrawMap
   Demo.Say "level" && RTS.LevelName(pCounts) && "(seed" && sSeed & ")", 4
end Demo.NewLevel

######################################################################################
## Building the cards (a script-only stack keeps no controls, so it makes them on open)
######################################################################################

on Demo.Build
   local tG
   lock screen
   set the rect of me to 60, 60, 960, 760
   set the backgroundColor of me to "16,16,20"
   set the foregroundColor of me to "220,220,220"
   set the textFont of me to "Arial"
   set the textSize of me to 12
   set the name of card 1 of stack "RTS_Demo" to "Developer"
   -- card 1: Developer (the fall-back card of LIB_ALPHA rule 20)
   Demo.Label "DevText", "RTS_Demo: developer card. Play shows the demo; About says how it works.", 20, 20, 860, 40
   Demo.Button "Play", 20, 70, "Demo.GoPlay"
   Demo.Button "About", 130, 70, "Demo.GoAbout"
   -- the play card
   create card "Play"
   Demo.Label "Top", empty, kMapL, 8, kMapL + 672, 30
   set the textStyle of field "Top" to "bold"
   create graphic "Ground"
   set the style of graphic "Ground" to "rectangle"
   set the rect of graphic "Ground" to kMapL, kMapT, kMapL + RTS.WorldSize() * kScale, kMapT + RTS.WorldSize() * kScale
   set the filled of graphic "Ground" to true
   set the backgroundColor of graphic "Ground" to "34,38,34"
   set the foregroundColor of graphic "Ground" to "70,80,70"
   Demo.Poly "Fences", "120,90,60", true
   Demo.Poly "Buildings", "95,95,110", true
   Demo.Poly "Doors", "230,200,90", false
   Demo.Poly "HouseBlink", "255,60,60", false
   Demo.Poly "Cars", "70,120,220", true
   Demo.Poly "Guns", "250,230,60", true
   Demo.Poly "Down", "80,80,80", true
   Demo.Poly "Dead", "90,200,80", true
   Demo.Poly "Living", "235,235,235", true
   Demo.Poly "Armed", "255,150,40", true
   Demo.Poly "Facing", "20,20,20", false
   Demo.Poly "Rings", "80,255,120", false
   Demo.Poly "Blink", "255,60,60", false
   Demo.Poly "Markers", "80,255,120", false
   Demo.Poly "Shots", "255,255,150", false
   create graphic "Box"
   set the style of graphic "Box" to "rectangle"
   set the filled of graphic "Box" to false
   set the foregroundColor of graphic "Box" to "80,255,120"
   set the dashes of graphic "Box" to "4,3"
   set the visible of graphic "Box" to false
   Demo.Label "HUD", empty, kMapL + 682, kMapT, 890, 690
   set the textSize of field "HUD" to 11
   Demo.Label "Msg", empty, kMapL, kMapT + 674, kMapL + 672, kMapT + 694
   -- the note / command line, lower left at 8/10 down (LIB_ALPHA rules 19 and the game notes)
   create field "Note"
   set the rect of field "Note" to kMapL, kMapT + 530, kMapL + 500, kMapT + 552
   set the backgroundColor of field "Note" to "0,0,0"
   set the foregroundColor of field "Note" to "255,255,150"
   set the borderColor of field "Note" to "255,255,150"
   set the threeD of field "Note" to false
   set the visible of field "Note" to false
   -- the About card
   create card "About"
   Demo.Label "AboutText", empty, 20, 20, 880, 640
   set the textSize of field "AboutText" to 13
   set the text of field "AboutText" to Demo.AboutText()
   Demo.Button "Back to play", 20, 650, "Demo.GoPlay"
   unlock screen
end Demo.Build

on Demo.Label pName, pText, pL, pT, pR, pB
   create field pName
   set the rect of field pName to pL, pT, pR, pB
   set the lockText of field pName to true
   set the traversalOn of field pName to false
   set the opaque of field pName to false
   set the showBorder of field pName to false
   set the dontWrap of field pName to false
   set the text of field pName to pText
end Demo.Label

on Demo.Button pName, pL, pT, pHandler
   create button pName
   set the rect of button pName to pL, pT, pL + 100, pT + 26
   set the script of button pName to "on mouseUp" & cr & "   " & pHandler & cr & "end mouseUp"
end Demo.Button

on Demo.Poly pName, pColor, pFilled
   create graphic pName
   set the style of graphic pName to "polygon"
   set the filled of graphic pName to pFilled
   set the opaque of graphic pName to pFilled
   set the backgroundColor of graphic pName to pColor
   set the foregroundColor of graphic pName to pColor
   set the lineSize of graphic pName to 1
   set the antialiased of graphic pName to false
   set the points of graphic pName to empty
end Demo.Poly

function Demo.AboutText
   return the long date & cr & \
         "Stack: RTS_Demo   Title: FOR OWNER | RTS_Demo: drag to select, click to command, ? for help" & cr & cr & \
         "What it is for: to show LIB_RTS, the iGame3D 2008 real-time strategy system (the RNDRTS level maker and the RTS_Functions scripts) rebuilt in xTalk. A random level: houses with fenced yards, the living (white; orange with a gun), the dead (green), guns (yellow), cars (blue). Seen from above." & cr & cr & \
         "How to play it:" & cr & \
         "  - Drag on the map: select your units in a box. Shift adds or takes away." & cr & \
         "  - Click one of your units: select just it." & cr & \
         "  - With units selected, click: the ground = go there (in a ring); an enemy = attack;" & cr & \
         "    a gun = pick it up; a house = go in (refills guns); a car = get in. Double click = get out." & cr & \
         "  - H commands the living, Z the dead (press again for the next one; Tab too). Space: select nobody." & cr & \
         "  - U: the dead you command rush the nearest living. X: hold. B: slow time. P: every task." & cr & \
         "  - N: a new random level. Escape: pause (+ and - set the speed while paused)." & cr & cr & \
         "How to report: press ` (or F2), type a note, press Return. It goes to LIB_LLMIN/LIB_GAMES/GAME_NOTES.txt with the level name and the counts; Claude reads that file each session. Nothing watches it live. The first question is simply: was it fun? A line starting with / runs as xTalk instead (the command line)." & cr & cr & \
         "Press ? or F1 again, or click Back to play."
end Demo.AboutText

on Demo.GoPlay
   go card "Play" of stack "RTS_Demo"
   put the milliseconds into sLastMs
end Demo.GoPlay

on Demo.GoAbout
   go card "About" of stack "RTS_Demo"
end Demo.GoAbout

######################################################################################
## The loop. Escape pauses it (LIB_ALPHA rule 18)
######################################################################################

on Demo.Loop
   local tNow
   put the milliseconds into tNow
   if not sPaused and the short name of this card of stack "RTS_Demo" is "Play" then
      RTS.Step (tNow - sLastMs) / 1000
      Demo.Draw
   else if the short name of this card of stack "RTS_Demo" is "Play" then
      Demo.ShowHUD
   end if
   put tNow into sLastMs
   send "Demo.Loop" to me in 33 milliseconds
   put the result into sTickMsg
end Demo.Loop

on Demo.StopLoop
   local tLine
   repeat for each line tLine in the pendingMessages
      if item 3 of tLine is "Demo.Loop" then cancel item 1 of tLine
   end repeat
end Demo.StopLoop

on closeStackRequest
   Demo.StopLoop
   set the destroyStack of me to true
   close stack (the mainStack of me)
end closeStackRequest

on closeStack
   Demo.StopLoop
   pass closeStack
end closeStack

######################################################################################
## Drawing
######################################################################################

function Demo.PX pX
   return kMapL + round(pX * kScale)
end Demo.PX

function Demo.PZ pZ
   return kMapT + round(pZ * kScale)
end Demo.PZ

function Demo.Square pX, pZ, pHalf
   local tX, tZ
   put Demo.PX(pX) into tX
   put Demo.PZ(pZ) into tZ
   return tX - pHalf & "," & tZ - pHalf & cr & tX + pHalf & "," & tZ - pHalf & cr & \
         tX + pHalf & "," & tZ + pHalf & cr & tX - pHalf & "," & tZ + pHalf & cr & \
         tX - pHalf & "," & tZ - pHalf & cr & cr
end Demo.Square

function Demo.Diamond pX, pZ, pR
   local tX, tZ
   put Demo.PX(pX) into tX
   put Demo.PZ(pZ) into tZ
   return tX & "," & tZ - pR & cr & tX + pR & "," & tZ & cr & tX & "," & tZ + pR & cr & \
         tX - pR & "," & tZ & cr & tX & "," & tZ - pR & cr & cr
end Demo.Diamond

-- the map: once a level
on Demo.DrawMap
   local tCell, tB, tF, tHalf, tD, tH
   lock screen
   repeat for each line tCell in RTS.MapCells()
      put item 3 of tCell * kScale / 2 into tHalf
      if item 4 of tCell is "building" then
         put Demo.Square(item 1 of tCell + item 3 of tCell / 2, item 2 of tCell + item 3 of tCell / 2, tHalf) after tB
      else
         put Demo.Square(item 1 of tCell + item 3 of tCell / 2, item 2 of tCell + item 3 of tCell / 2, tHalf - 2) after tF
      end if
   end repeat
   repeat for each line tH in RTS.Houses()
      put Demo.Diamond(item 4 of tH, item 5 of tH, 4) after tD
   end repeat
   set the points of graphic "Buildings" of card "Play" of stack "RTS_Demo" to tB
   set the points of graphic "Fences" of card "Play" of stack "RTS_Demo" to tF
   set the points of graphic "Doors" of card "Play" of stack "RTS_Demo" to tD
   unlock screen
end Demo.DrawMap

-- everything that moves: one graphic a colour, many shapes in each
on Demo.Draw
   local tLine, tLiving, tArmed, tDead, tDown, tGuns, tCars, tRings, tFacing, tBlink, tMarks, tShot, tX, tZ, tH, tHB
   repeat for each line tLine in RTS.Snapshot()
      put item 4 of tLine into tX
      put item 5 of tLine into tZ
      switch item 2 of tLine
         case "gun"
            put Demo.Square(tX, tZ, 2) after tGuns
            break
         case "car"
            put Demo.Square(tX, tZ, 7) after tCars
            break
         default
            if item 10 of tLine is "down" then
               put Demo.Square(tX, tZ, 3) after tDown
            else if item 3 of tLine is 1 then
               put Demo.Diamond(tX, tZ, 5) after tDead
            else if item 11 of tLine is true then
               put Demo.Diamond(tX, tZ, 5) after tArmed
            else
               put Demo.Diamond(tX, tZ, 5) after tLiving
            end if
            if item 10 of tLine is not "down" then
               put Demo.PX(tX) & "," & Demo.PZ(tZ) & cr & Demo.PX(tX + item 6 of tLine * 0.9) & "," & Demo.PZ(tZ + item 7 of tLine * 0.9) & cr & cr after tFacing
            end if
      end switch
      if item 9 of tLine is true then put Demo.Diamond(tX, tZ, 9) after tRings
      if item 12 of tLine is true then put Demo.Diamond(tX, tZ, 11) after tBlink
   end repeat
   repeat for each line tLine in RTS.Markers()
      put Demo.PX(item 1 of tLine) & "," & Demo.PZ(item 2 of tLine) & cr & Demo.PX(item 3 of tLine) & "," & Demo.PZ(item 4 of tLine) & cr & cr after tMarks
      if item 5 of tLine is "move" then put Demo.Diamond(item 3 of tLine, item 4 of tLine, 3) after tMarks
   end repeat
   repeat for each line tLine in RTS.Shots()
      put Demo.PX(item 1 of tLine) & "," & Demo.PZ(item 2 of tLine) & cr & Demo.PX(item 3 of tLine) & "," & Demo.PZ(item 4 of tLine) & cr & cr after tShot
   end repeat
   repeat for each line tH in RTS.Houses()
      if RTS.Get(item 1 of tH, "blinkUntil") + 0 > RTS.Now() then put Demo.Square(item 2 of tH, item 3 of tH, 4 * kScale) after tHB
   end repeat
   lock screen
   set the points of graphic "Living" of stack "RTS_Demo" to tLiving
   set the points of graphic "Armed" of stack "RTS_Demo" to tArmed
   set the points of graphic "Dead" of stack "RTS_Demo" to tDead
   set the points of graphic "Down" of stack "RTS_Demo" to tDown
   set the points of graphic "Guns" of stack "RTS_Demo" to tGuns
   set the points of graphic "Cars" of stack "RTS_Demo" to tCars
   set the points of graphic "Rings" of stack "RTS_Demo" to tRings
   set the points of graphic "Facing" of stack "RTS_Demo" to tFacing
   set the points of graphic "Blink" of stack "RTS_Demo" to tBlink
   set the points of graphic "HouseBlink" of stack "RTS_Demo" to tHB
   set the points of graphic "Markers" of stack "RTS_Demo" to tMarks
   set the points of graphic "Shots" of stack "RTS_Demo" to tShot
   Demo.ShowHUD
   unlock screen
end Demo.Draw

on Demo.ShowHUD
   local tT, tTeam
   if RTS.TeamSelect() is 1 then
      put "THE DEAD (Z)" into tTeam
   else
      put "THE LIVING (H)" into tTeam
   end if
   put "You command:" && tTeam & cr & "Selected:" && the number of lines of RTS.Selected() & cr & cr & RTS.Status() & cr & cr after tT
   if sPaused then
      put "PAUSED  (Escape resumes)" & cr & "Game speed x" & RTS.Speed() & "  (+ / -)" & cr & cr after tT
   else if RTS.Speed() is not 1 then
      put "Slow time x" & RTS.Speed() & "  (B)" & cr & cr after tT
   end if
   if sShowTasks then
      put "Tasks (P hides):" & cr & RTS.Tasks() after tT
   else
      put "Lately:" & cr & line -8 to -1 of RTS.Log() & cr & cr & \
            "Drag: select   Click: command" & cr & "H living  Z dead  Tab next" & cr & \
            "U rush  X hold  B slow  P tasks" & cr & "N new level  Esc pause" & cr & "` note   ? about" after tT
   end if
   if field "HUD" of stack "RTS_Demo" is not tT then set the text of field "HUD" of stack "RTS_Demo" to tT
   set the text of field "Top" of stack "RTS_Demo" to "RNDRTS level" && RTS.LevelName(sCounts) & "   seed" && sSeed
   if the milliseconds > sMsgUntil then put empty into sMsg
   if field "Msg" of stack "RTS_Demo" is not sMsg then set the text of field "Msg" of stack "RTS_Demo" to sMsg
end Demo.ShowHUD

on Demo.Say pText, pSeconds
   if pSeconds is empty then put 2 into pSeconds
   put pText into sMsg
   put the milliseconds + pSeconds * 1000 into sMsgUntil
   if there is a field "Msg" of card "Play" of stack "RTS_Demo" then set the text of field "Msg" of card "Play" of stack "RTS_Demo" to pText
end Demo.Say

######################################################################################
## The mouse  (handle_clicks / handle_selection_box of RTS_Game.lua)
######################################################################################

function Demo.OnMap pX, pY
   return pX >= kMapL and pY >= kMapT and pX < kMapL + RTS.WorldSize() * kScale and pY < kMapT + RTS.WorldSize() * kScale
end Demo.OnMap

on mouseDown pButton
   Demo.Press false
   pass mouseDown
end mouseDown

on mouseDoubleDown pButton
   Demo.Press true
   pass mouseDoubleDown
end mouseDoubleDown

on Demo.Press pDouble
   local tX, tZ, tWhat
   if the short name of this card of stack "RTS_Demo" is not "Play" or sPaused or sNoteOpen then exit Demo.Press
   if not Demo.OnMap(the mouseH, the mouseV) then exit Demo.Press
   put (the mouseH - kMapL) / kScale into tX
   put (the mouseV - kMapT) / kScale into tZ
   put RTS.ClickAt(tX, tZ, the shiftKey is down, pDouble) into tWhat
   if tWhat is "box" then
      if the shiftKey is not down then RTS.UnselectAll
      RTS.BoxBegin
      put true into sDragging
      put tX into sDragX
      put tZ into sDragZ
      set the rect of graphic "Box" of stack "RTS_Demo" to the mouseH, the mouseV, the mouseH + 1, the mouseV + 1
      set the visible of graphic "Box" of stack "RTS_Demo" to true
   else if tWhat is not "select" then
      Demo.Say tWhat, 1
   end if
end Demo.Press

on mouseMove pX, pY
   local tX, tZ
   if sDragging is not true then pass mouseMove
   put max(0, min(RTS.WorldSize(), (pX - kMapL) / kScale)) into tX
   put max(0, min(RTS.WorldSize(), (pY - kMapT) / kScale)) into tZ
   RTS.BoxUpdate sDragX, sDragZ, tX, tZ, the shiftKey is down
   set the rect of graphic "Box" of stack "RTS_Demo" to Demo.PX(min(sDragX, tX)), Demo.PZ(min(sDragZ, tZ)), Demo.PX(max(sDragX, tX)) + 1, Demo.PZ(max(sDragZ, tZ)) + 1
end mouseMove

on mouseUp
   Demo.EndDrag
   pass mouseUp
end mouseUp

on mouseRelease
   Demo.EndDrag
   pass mouseRelease
end mouseRelease

on Demo.EndDrag
   if sDragging is not true then exit Demo.EndDrag
   put false into sDragging
   set the visible of graphic "Box" of stack "RTS_Demo" to false
end Demo.EndDrag

######################################################################################
## Keys  (RTS_Game.lua and RTS_Keyboard.lua)
######################################################################################

on rawKeyDown pKey
   if sNoteOpen then
      if pKey is 65307 or pKey is 65471 then
         Demo.CloseNote
         exit rawKeyDown
      end if
      pass rawKeyDown
   end if
   if pKey is 96 or pKey is 65471 then
      Demo.OpenNote
      exit rawKeyDown
   end if
   if pKey is 65470 then
      Demo.ToggleAbout
      exit rawKeyDown
   end if
   if pKey is 65307 then
      put not sPaused into sPaused
      exit rawKeyDown
   end if
   pass rawKeyDown
end rawKeyDown

on tabKey
   if sNoteOpen then pass tabKey
   if the short name of this card of stack "RTS_Demo" is "Play" then get RTS.TabThrough()
end tabKey

on keyDown pKey
   if sNoteOpen then pass keyDown
   if pKey is "?" or pKey is "/" then
      Demo.ToggleAbout
      exit keyDown
   end if
   if the short name of this card of stack "RTS_Demo" is not "Play" then pass keyDown
   switch toLower(pKey)
      case "h"
         if RTS.TeamSelect() is 0 then
            get RTS.TabThrough()
         else
            RTS.SetTeam 0
            Demo.Say "you command the living", 2
         end if
         break
      case "z"
         if RTS.TeamSelect() is 1 then
            get RTS.TabThrough()
         else
            RTS.SetTeam 1
            Demo.Say "you command the dead", 2
         end if
         break
      case " "
         RTS.UnselectAll
         break
      case "b"
         RTS.BulletTime
         break
      case "p"
         put not (sShowTasks is true) into sShowTasks
         break
      case "u"
         if RTS.TeamSelect() is 1 then
            RTS.Rush
            Demo.Say "the dead rush", 2
         else
            Demo.Say "U is for the dead: press Z first", 2
         end if
         break
      case "x"
         RTS.Hold
         Demo.Say "hold", 1
         break
      case "n"
         Demo.NewLevel
         break
      case "+"
      case "="
         if sPaused then RTS.SetSpeed min(4, RTS.Speed() * 2)
         break
      case "-"
         if sPaused then RTS.SetSpeed max(0.125, RTS.Speed() / 2)
         break
      default
         pass keyDown
   end switch
end keyDown

on Demo.ToggleAbout
   if the short name of this card of stack "RTS_Demo" is "About" then
      Demo.GoPlay
   else
      Demo.GoAbout
   end if
end Demo.ToggleAbout

######################################################################################
## The note box: a TELL for the AI, or a / command line
######################################################################################

on Demo.OpenNote
   if the short name of this card of stack "RTS_Demo" is not "Play" then exit Demo.OpenNote
   put true into sNoteOpen
   put true into sPaused
   set the lockText of field "Note" of stack "RTS_Demo" to false
   put empty into field "Note" of stack "RTS_Demo"
   set the visible of field "Note" of stack "RTS_Demo" to true
   focus on field "Note" of stack "RTS_Demo"
   Demo.Say "note: type and press Return (Escape closes; /xTalk runs it)", 30
end Demo.OpenNote

on Demo.CloseNote
   put false into sNoteOpen
   put false into sPaused
   set the visible of field "Note" of stack "RTS_Demo" to false
   focus on nothing
   Demo.Say empty, 0
end Demo.CloseNote

on returnInField
   if the short name of the target is "Note" then
      Demo.SaveNote
   else
      pass returnInField
   end if
end returnInField

on enterInField
   if the short name of the target is "Note" then
      Demo.SaveNote
   else
      pass enterInField
   end if
end enterInField

on Demo.SaveNote
   local tText, tFile, tLine, tResult
   put field "Note" of stack "RTS_Demo" into tText
   Demo.CloseNote
   if tText is empty then exit Demo.SaveNote
   if char 1 of tText is "/" then
      try
         -- an expression shows its value; anything else runs as a statement
         put value(char 2 to -1 of tText) into tResult
      catch tErr
         try
            do char 2 to -1 of tText
            put the result into tResult
         catch tErr2
            put "error:" && line 1 of tErr2 into tResult
         end try
      end try
      Demo.Say "/" & char 2 to -1 of tText && "->" && tResult, 6
      exit Demo.SaveNote
   end if
   put the effective filename of me into tFile
   set the itemDelimiter to "/"
   put item 1 to -3 of tFile & "/LIB_LLMIN/LIB_GAMES/GAME_NOTES.txt" into tFile
   set the itemDelimiter to ","
   put the short date && the long time && "|" && "RTS_Demo" && "|" && RTS.LevelName(sCounts) && "seed" && sSeed && \
         "living,dead" && RTS.Counts() && "|" && tText & lf into tLine
   if there is a folder (char 1 to -15 of tFile) then
      put textEncode(tLine, "UTF-8") after url ("binfile:" & tFile)
      Demo.Say "note saved for the AI", 3
   else
      Demo.Say "no LIB_LLMIN folder found; note not saved", 4
   end if
end Demo.SaveNote
