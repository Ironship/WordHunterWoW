-- Run from the addon root:  lua tests/compat.test.lua
--
-- Compat.lua was written without a Classic client to try it on, so this test
-- stands in for one. It builds a fake Retail API and a fake Classic API and
-- checks that the same calls come out right on both -- in particular the two
-- differences that would silently corrupt what the panel shows:
--
--   * Retail's GetQuestLogQuestText takes a log index. Classic's takes nothing
--     and reads whatever entry is selected, so Classic has to select the entry
--     and put the player's selection back afterwards.
--   * The season decides Era vs SoD, and it must never be guessed. A client
--     that cannot name its season has to come out as Era.

local Addon = { }
WordHunterWoW_Addon = Addon
dofile("Compat.lua")
local Compat = Addon.Compat
assert(Compat, "Compat.lua did not attach itself to the addon table")

local function clearApi()
  for _, name in ipairs({
    "WOW_PROJECT_ID", "WOW_PROJECT_MAINLINE", "C_Seasons", "Enum", "C_QuestLog",
    "GetQuestLogQuestText", "GetQuestLogIndexByID", "GetQuestLogTitle",
    "GetQuestLogSelection", "SelectQuestLogEntry", "QuestFrame", "QuestLogFrame",
    "QuestMapFrame", "WorldMapFrame",
  }) do _G[name] = nil end
end

-- Which game are we on -------------------------------------------------------

clearApi()
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
assert(Compat.Refresh() == "retail", "mainline should be retail")
assert(Compat.IsRetail() and not Compat.IsClassic())

clearApi()
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
assert(Compat.Refresh() == "classic", "classic project with no season API is Era")
assert(Compat.IsClassic() and not Compat.IsSeasonOfDiscovery())

-- The season is read by name out of the enum, never written down as a number.
clearApi()
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
C_Seasons = { GetActiveSeason = function() return 2 end }
assert(Compat.Refresh() == "sod", "active season matching the enum is SoD")

-- A season we cannot name is Era, not SoD: Era text on SoD is incomplete, but
-- SoD text on Era would be text from a game the player is not in.
C_Seasons = { GetActiveSeason = function() return 99 end }
assert(Compat.Refresh() == "classic", "an unrecognised season must fall back to Era")

Enum = nil
C_Seasons = { GetActiveSeason = function() return 2 end }
assert(Compat.Refresh() == "classic", "no enum to name the season means Era")

C_Seasons = { GetActiveSeason = function() error("not available") end }
assert(Compat.Refresh() == "classic", "a season API that throws must not take the addon with it")

-- Reading the quest text -----------------------------------------------------

-- Retail: the index is an argument, and nothing touches the selection.
clearApi()
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
Compat.Refresh()
local retailAskedFor
C_QuestLog = { GetLogIndexForQuestID = function(id) return id == 40 and 7 or nil end }
GetQuestLogQuestText = function(index) retailAskedFor = index; return "offer", "objectives" end
SelectQuestLogEntry = function() error("Retail must not move the quest log selection") end
local description, objectives = Compat.QuestLogText(Compat.QuestLogIndexForID(40))
assert(retailAskedFor == 7, "Retail should pass the log index, got " .. tostring(retailAskedFor))
assert(description == "offer" and objectives == "objectives")

-- Classic: no argument, so the entry has to be selected first -- and the
-- player's own selection restored, or their quest log jumps under them.
clearApi()
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Compat.Refresh()
local selection, selectionLog = 3, {}
GetQuestLogSelection = function() return selection end
SelectQuestLogEntry = function(index) selection = index; selectionLog[#selectionLog + 1] = index end
GetQuestLogIndexByID = function(id) return id == 40 and 7 or nil end
GetQuestLogQuestText = function(index)
  assert(index == nil, "Classic's GetQuestLogQuestText takes no argument")
  return "text for entry " .. selection, "objectives for entry " .. selection
end
description, objectives = Compat.QuestLogText(Compat.QuestLogIndexForID(40))
assert(description == "text for entry 7", "Classic read the wrong entry: " .. description)
assert(objectives == "objectives for entry 7")
assert(#selectionLog == 2 and selectionLog[1] == 7 and selectionLog[2] == 3,
  "Classic must select the entry and put the previous selection back, got " ..
  table.concat(selectionLog, ","))
assert(selection == 3, "the player's selection was left moved")

-- Already on the entry we want: do not touch the selection at all.
selection, selectionLog = 7, {}
Compat.QuestLogText(7)
assert(#selectionLog == 0, "re-selecting the entry already selected is needless UI churn")

-- Finding the quest id from a log index --------------------------------------

-- Classic returns the id somewhere among GetQuestLogTitle's results and the
-- position has moved between builds, so the id is the number that maps back to
-- the index we started from. The quest's level must not be mistaken for it.
clearApi()
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Compat.Refresh()
GetQuestLogIndexByID = function(id) return id == 8342 and 4 or nil end
GetQuestLogTitle = function(index)
  if index ~= 4 then return nil end
  return "Wanted: Hogger", 11, nil, false, false, false, nil, 8342
end
assert(Compat.QuestIDForLogIndex(4) == 8342,
  "expected the id that maps back to index 4, got " .. tostring(Compat.QuestIDForLogIndex(4)))
assert(Compat.TitleForQuestID(8342) == "Wanted: Hogger")

-- Hooks ----------------------------------------------------------------------

clearApi()
local hookedNames = {}
hooksecurefunc = function(name) hookedNames[#hookedNames + 1] = name end
QuestInfo_ShowDescriptionText = function() end
QuestLog_SetSelection = function() end
-- QuestMapFrame_ShowQuestDetails and QuestLog_UpdateQuestDetails are absent,
-- and hooking a name that does not exist is an error, not a no-op.
assert(Compat.HookQuestUi(function() end) == 2, "should hook exactly the two that exist")
assert(#hookedNames == 2)
assert(Compat.HookQuestUi(function() end) == 0, "hooking twice would fire the handler twice")
assert(#hookedNames == 2)

-- Frames ---------------------------------------------------------------------

clearApi()
local function fakeFrame(isShown) return { IsShown = function() return isShown end } end
assert(Compat.QuestLogFrame() == nil, "no quest log open")
assert(not Compat.NpcQuestFrameShown())
QuestLogFrame = fakeFrame(true)
assert(Compat.QuestLogFrame() == QuestLogFrame, "Classic's own quest log window")
QuestLogFrame = fakeFrame(false)
QuestMapFrame = fakeFrame(true)
assert(Compat.QuestLogFrame() == QuestMapFrame, "Retail's map quest log")
QuestFrame = fakeFrame(true)
assert(Compat.NpcQuestFrameShown())

-- A frame that is not a frame must not throw. Blizzard UI pieces are
-- load-on-demand and a global can exist as something else entirely.
QuestLogFrame, QuestMapFrame, WorldMapFrame, QuestFrame = "not a frame", nil, nil, nil
assert(Compat.QuestLogFrame() == nil)
assert(not Compat.NpcQuestFrameShown())

print("compat: ok")
