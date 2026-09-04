-- Run from the addon root:  lua tests/quest-passages.test.lua
--
-- The clickable column used to keep showing the offer whenever GetQuestText
-- returned anything, which in the live client it always does — even while the
-- NPC is on the progress or hand-in line. Objectives were concatenated for the
-- offer, but gossip never reached the panel at all.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
QuestFrame:Show()

GetQuestID = function() return 40 end
GetTitleText = function() return "Der Auftrag" end
GetQuestText = function() return "Ein Hippogryph wurde gesehen." end
GetObjectiveText = function() return "Besichtigt die Ruinen." end
GetProgressText = function() return "Habt Ihr die Ruinen schon besichtigt?" end
GetRewardText = function() return "Gut gemacht." end

Addon.lastPassage = nil
Addon.readCurrentQuest()
assert(Addon.lastQuest.passage == "offer", "default is the offer, got " .. tostring(Addon.lastQuest.passage))
assert(Addon.lastQuest.text:find("Hippogryph", 1, true), "offer keeps the description")
assert(Addon.lastQuest.text:find("Besichtigt", 1, true),
  "objectives must be clickable on the offer: " .. Addon.lastQuest.text)

Addon.lastPassage = "progress"
Addon.readCurrentQuest()
assert(Addon.lastQuest.passage == "progress")
assert(Addon.lastQuest.text:find("besichtigt", 1, true),
  "progress must show the progress line even when the offer is still available: " .. Addon.lastQuest.text)
assert(not Addon.lastQuest.text:find("Hippogryph", 1, true),
  "the offer must not stay on screen during progress")

Addon.lastPassage = "reward"
Addon.readCurrentQuest()
assert(Addon.lastQuest.passage == "reward")
assert(Addon.lastQuest.text:find("Gut gemacht", 1, true),
  "hand-in must show the reward line: " .. Addon.lastQuest.text)

GetGossipText = function() return "Ah, da seid Ihr ja. Die Ruinen warten." end
Addon.readGossip()
assert(Addon.lastQuest.passage == "gossip")
assert(Addon.lastQuest.text:find("Ruinen", 1, true),
  "gossip must become clickable words: " .. Addon.lastQuest.text)
assert(Addon.panel:IsShown(), "gossip should open the panel")

print("quest-passages: ok")
