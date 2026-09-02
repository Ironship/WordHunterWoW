-- Run from the addon root:  lua tests/english-passage.test.lua
--
-- Which English passage the panel shows, and when it admits it has none.
--
-- Blizzard's quest API publishes a quest's opening text and nothing else. It
-- does not publish the line an NPC speaks while the quest is in progress, nor
-- the one spoken at hand-in. So the panel used to show the opening text at
-- every passage and print a red caveat saying it was the wrong one -- accurate,
-- but the reader still could not read what was in front of them.
--
-- The shipped records now carry those two lines where they are known. Where
-- they are, the panel must show the passage the player is actually reading and
-- drop the caveat. Where they are not, the caveat has to stay: showing the
-- opening text as if it were the hand-in is the one outcome worse than saying
-- nothing.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

WordHunterWoW_QuestEN = {
  [1] = {
    title = "Sharptalon's Claw",
    description = "The mighty hippogryph Sharptalon has been slain.",
    objectives = "Bring Sharptalon's Claw to Senani Thunderheart.",
    progress = "What have you there, adventurer? Could it be....?",
    completion = "You have slain the beast? I owe you a great debt.",
  },
  -- The same shape without the two lines: this is what most records still look
  -- like, and every Classic record.
  [2] = {
    title = "Old Bounty",
    description = "Gnolls have been seen along the borders of Elwynn Forest.",
    objectives = "Bring twelve paws to the guard.",
  },
}

Addon.createPanel()
local panel = Addon.panel
QuestFrame:Show()

local CAVEAT = "Blizzard publishes no English text"

-- Drive the real path: the addon works out the passage from which of Blizzard's
-- text functions answers, so the test sets those rather than the field it wants.
local function render(questId, passage)
  GetQuestID = function() return questId end
  if passage == "offer" then
    GetQuestText = function() return "Der Hippogryph wurde getoetet." end
    GetProgressText = function() return "" end
    GetRewardText = function() return "" end
  elseif passage == "progress" then
    GetQuestText = function() return "" end
    GetProgressText = function() return "Was habt Ihr denn da?" end
    GetRewardText = function() return "" end
  else
    GetQuestText = function() return "" end
    GetProgressText = function() return "" end
    GetRewardText = function() return "Ihr habt das Biest erlegt?" end
  end
  GetObjectiveText = function() return "" end
  panel.renderedQuestKey = nil
  CAPTURE_TEXT = {}
  Addon.readCurrentQuest()
  local seen = table.concat(CAPTURE_TEXT, " ")
  CAPTURE_TEXT = nil
  assert(Addon.lastQuest and Addon.lastQuest.passage == passage,
    "the test failed to reach the " .. passage .. " passage, got "
    .. tostring(Addon.lastQuest and Addon.lastQuest.passage))
  return seen
end

-- The offer is unchanged: opening text, no caveat, as it always was.
local offer = render(1, "offer")
assert(offer:find("hippogryph", 1, true),
  "the offer should show the opening text, got: " .. offer:sub(1, 140))
assert(not offer:find(CAVEAT, 1, true), "an offer was never owed a caveat")

-- In progress: show the progress line, not the opening text.
local progress = render(1, "progress")
assert(progress:find("Could", 1, true),
  "the progress passage should show the progress line, got: " .. progress:sub(1, 140))
assert(not progress:find("hippogryph", 1, true),
  "the opening text must not be shown in its place")
assert(not progress:find(CAVEAT, 1, true),
  "nothing is missing here, so nothing should be apologised for")

-- Hand-in: show the hand-in line.
local reward = render(1, "reward")
assert(reward:find("debt", 1, true),
  "the hand-in passage should show the hand-in line, got: " .. reward:sub(1, 140))
assert(not reward:find(CAVEAT, 1, true), "nothing is missing here either")

-- A record that has neither still has to say so, and still falls back to the
-- opening text rather than showing an empty pane.
local missing = render(2, "reward")
assert(missing:find("Gnolls", 1, true), "the fallback is still the opening text")
assert(missing:find(CAVEAT, 1, true),
  "a record without the hand-in line must keep the caveat, got: " .. missing:sub(1, 180))

print("english-passage: ok")
