-- Run from the addon root:  lua tests/quest-log-button.test.lua
--
-- The panel opened itself whenever the player looked at a quest. At a quest
-- giver that is the point; from the quest log it was the fault. On a live realm
-- the log is a pane of the world map, and the panel is FULLSCREEN_DIALOG at
-- frame level 20 with SetToplevel -- so a click meant to read a quest's
-- objectives, or to abandon it, dropped the panel over the row it was aimed at
-- and the quest could not be reached again until the panel was closed.
--
-- From the log the panel now waits for the button hung on the log itself. The
-- quest giver's window is untouched, which is the half of this that must not
-- break: it is what the addon is mostly used for.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

-- The log's own text, which the stub does not model: without it every read by
-- log id comes back empty and readCurrentQuest gives up before it ever reaches
-- the decision this file is about, so every assertion below would pass on air.
GetQuestLogQuestText = function()
  return "Ein Bote wartet am Tor.", "Sprecht mit dem Boten."
end
QuestMapFrame_GetDetailQuestID = function() return 184 end

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
local panel = Addon.panel

-- The default is the new behaviour. A player who has never opened the settings
-- is the one the fault was reported from.
assert(Addon.GetQuestLogAutoOpen() == false,
  "out of the box the quest log must not open the panel")

-- Before the quest log exists at all, which is every login: Retail builds the
-- map's quest log in Blizzard_WorldMap and Classic keeps its own in
-- Blizzard_QuestLog, both load-on-demand. Nothing to hang the button on is a
-- reason to come back later, not an error and not a button hung on nothing.
local mapFrame = QuestMapFrame
QuestMapFrame = nil
assert(Addon.QuestLogButtonHost() == nil, "no quest log yet means no host")
assert(Addon.AttachQuestLogButton() == nil, "and no button until there is one")
QuestMapFrame = mapFrame

-- Retail hangs the button on the map's quest details pane, which is on screen
-- exactly while a quest is being read there.
assert(Addon.QuestLogButtonHost() == QuestMapFrame.DetailsFrame,
  "on Retail the button belongs on the quest details pane")

-- hookQuestUi is called at every moment the log could have arrived, so that is
-- where the button has to be put up.
Addon.hookQuestUi()
local button = Addon.questLogButton
assert(button, "hookQuestUi should have put the button on the quest log")
assert(button:GetText() == Addon.LABELS.questLogButton, "the button should be labelled")
assert(Addon.AttachQuestLogButton() == button, "attaching again must not build a second button")

-- Reading a quest in the log. -------------------------------------------------
QuestFrame:Hide()
QuestMapFrame:Show()
panel:Hide()
Addon.readCurrentQuest(184)
assert(not panel:IsShown(), "the quest log must not open the panel by itself")
-- Read all the same: the panel is only being kept off the screen, and pressing
-- the button must not have to go and fetch anything.
assert(Addon.lastQuest and Addon.lastQuest.id == 184, "the quest should still have been read")
assert(Addon.lastQuest.text:find("Bote", 1, true),
  "the text should come from the log: " .. tostring(Addon.lastQuest.text))

-- Pressing the button. --------------------------------------------------------
local click = button:GetScript("OnClick")
assert(click, "the button does nothing without an OnClick")
click(button)
assert(panel:IsShown(), "the button must open the panel")
assert(Addon.lastQuest.id == 184, "on the quest the log has selected")

-- And again: the complaint was a panel in the way, so the same press has to be
-- able to send it away.
click(button)
assert(not panel:IsShown(), "a second press must close the panel again")

-- The quest giver, which must go on working exactly as it did. ----------------
QuestMapFrame:Hide()
QuestFrame:Show()
panel:Hide()
Addon.readCurrentQuest()
assert(panel:IsShown(), "a quest giver's window must still open the panel by itself")
assert(Addon.lastQuest.text:find("Wolfsfleisch", 1, true),
  "and on the NPC's text, not the log's: " .. tostring(Addon.lastQuest.text))

-- The setting puts the old behaviour back. ------------------------------------
QuestFrame:Hide()
QuestMapFrame:Show()
panel:Hide()
Addon.SetQuestLogAutoOpen(true)
Addon.readCurrentQuest(184)
assert(panel:IsShown(), "with the setting on the quest log opens the panel again")
Addon.SetQuestLogAutoOpen(false)

-- A panel already on screen keeps following the log. Only the opening changed;
-- clicking through quests with the panel up has to keep working, or the button
-- would have to be pressed once per quest.
panel:Show()
Addon.readCurrentQuest(184)
assert(panel:IsShown(), "the new rule only ever declines to open, it never closes")

-- The log holds nothing but a quest's opening text. This used to inherit
-- whichever passage the last conversation left behind -- GOSSIP_CLOSED clears
-- none -- so browsing the log after a chat labelled every quest gossip, which
-- put the "no English for this part of a quest" caveat over text that was the
-- opening text all along.
Addon.lastPassage = "gossip"
Addon.readCurrentQuest(184)
assert(Addon.lastQuest.passage == "offer",
  "a quest read out of the log is its offer, got " .. tostring(Addon.lastQuest.passage))
Addon.lastPassage = nil

-- Classic Era, where the quest log is a window of its own. Checked through the
-- host chooser rather than by attaching a second time, because the button is
-- built once per session and which frame it chose cannot be read back off it
-- afterwards.
--
-- The flavour is switched rather than the frames hidden, because that is what
-- the chooser asks: it settles the parent once and never rehomes the button, so
-- picking by whichever global happens to be lying about would strand it on a
-- window that never opens.
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Addon.Compat.Refresh()
QuestLogFrame = node()
assert(Addon.QuestLogButtonHost() == QuestLogFrame,
  "on Classic Era the button belongs on the quest log window")
-- Retail's map frame is still standing here and must not tempt it.
assert(QuestMapFrame ~= nil and Addon.QuestLogButtonHost() ~= QuestMapFrame.DetailsFrame,
  "Classic must not take Retail's details pane")

-- And Classic before its own load-on-demand quest log has arrived.
QuestLogFrame = nil
assert(Addon.QuestLogButtonHost() == nil, "no quest log yet means no host")

WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = nil, nil
Addon.Compat.Refresh()
assert(Addon.QuestLogButtonHost() == QuestMapFrame.DetailsFrame, "back on Retail")

-- And it is drawn above the panel it opens.
--
-- The panel is FULLSCREEN_DIALOG at level 20 and opens right beside the quest
-- log; the log lives in the world map, which sits lower, so the button hung off
-- the map went under the panel and showed as a red sliver two letters wide.
-- This is the one control whose job is to toggle that panel, so it is the one
-- that has to stay reachable while the panel is up.
assert(button:GetFrameStrata() == Addon.panel:GetFrameStrata(),
  "the button is in a different strata from the panel, so its level decides nothing"
  .. " -- button " .. tostring(button:GetFrameStrata())
  .. ", panel " .. tostring(Addon.panel:GetFrameStrata()))
assert(button:GetFrameLevel() > Addon.panel:GetFrameLevel(),
  "the button draws at level " .. button:GetFrameLevel()
  .. ", under the panel at " .. Addon.panel:GetFrameLevel())
print("  and stays visible over the panel it opens")
print("quest-log-button: ok")
