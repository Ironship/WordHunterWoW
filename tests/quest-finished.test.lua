-- Run from the addon root:  lua tests/quest-finished.test.lua
--
-- Hand a quest in and the panel came back on its own, showing the quest that
-- had just been handed in, a moment after the player had closed it.
--
-- QUEST_FINISHED hides the panel. But Blizzard redraws the quest pane while it
-- is tearing it down, that redraw fires the hook the addon listens on, and the
-- hook reaches readCurrentQuest through a zero-delay timer -- which lands after
-- the hide. The panel was then shown again by the addon's own code, with
-- nothing on screen for it to sit beside.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.createPanel and Addon.readCurrentQuest, "QuestPanel.lua must provide both")

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
local panel = Addon.panel
assert(panel, "createPanel should expose the panel")

-- Reading a quest at an NPC: the window is open, so the panel belongs on screen.
QuestFrame:Show()
panel:Hide()
Addon.readCurrentQuest()
assert(panel:IsShown(), "with the NPC's quest window open the panel should show")

-- Handing it in. QUEST_FINISHED closes the panel, and then the late redraw
-- arrives. This is the bug: it used to put the panel straight back.
QuestFrame:Hide()
panel:Hide()
Addon.readCurrentQuest()
assert(not panel:IsShown(),
  "with no quest window open the panel must stay closed after a hand-in")

-- The same while reading from the quest log, which is a different window.
QuestFrame:Hide()
QuestLogFrame = node()
QuestLogFrame:Show()
panel:Hide()
Addon.readCurrentQuest()
assert(panel:IsShown(), "reading from the quest log should still show the panel")
QuestLogFrame:Hide()

-- A panel the player opened by hand stays open and keeps updating: this guard
-- only ever declines to add, it never takes away.
panel:Show()
Addon.readCurrentQuest()
assert(panel:IsShown(), "a panel already on screen must not be closed by this")

print("quest-finished: ok")
