-- Run from the addon root:  lua tests/quest-progress.test.lua
--
-- How much of the quest in front of you have you already dealt with? The panel
-- coloured each word by status but never said what the mix was, so a quest you
-- half know and one you know nothing of looked much the same until you read
-- them.
--
-- Two things here are easy to get subtly wrong and are what this pins down: the
-- three figures have to add to 100, and a word repeated nine times has to count
-- once.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.ProgressShares and Addon.FormatProgress, "Core.lua must provide both")

local function shares(known, learning, new)
  return Addon.ProgressShares({ known = known, learning = learning, new = new })
end

-- Nothing to score. A quest whose every word the player has ignored, or an
-- empty panel, must say so rather than divide by zero or claim 0%.
assert(shares(0, 0, 0) == nil, "with no countable words there is no percentage to give")
assert(Addon.FormatProgress({ known = 0, learning = 0, new = 0 }) == Addon.LABELS.progressNothing)
assert(Addon.FormatProgress(nil) == Addon.LABELS.progressNothing, "no counts at all is the same case")

-- The plain cases.
local s = shares(10, 0, 0)
assert(s.known == 100 and s.learning == 0 and s.new == 0, "all known is 100% known")
assert(s.total == 10, "the total is the words counted, not a percentage")
s = shares(5, 3, 2)
assert(s.known == 50 and s.learning == 30 and s.new == 20)

-- The one that catches naive rounding. An even three-way split floors to 33
-- each and loses a point; the line then reads 33/33/33 and a player who adds
-- them up finds 99. Whoever gets the spare point, the three must total 100.
for _, case in ipairs({ { 1, 1, 1 }, { 2, 2, 2 }, { 1, 1, 4 }, { 7, 7, 7 }, { 1, 2, 3 }, { 5, 5, 1 } }) do
  local r = shares(case[1], case[2], case[3])
  assert(r.known + r.learning + r.new == 100,
    ("%d/%d/%d should still add to 100, got %d+%d+%d")
      :format(case[1], case[2], case[3], r.known, r.learning, r.new))
end

-- A share can never exceed its honest value by more than the rounding.
s = shares(1, 0, 2)
assert(s.known == 33 and s.new == 67, "one in three known should read 33/67, got " .. s.known .. "/" .. s.new)

-- The line names all three states and carries the colour each is drawn in, so
-- the figure and the words it counts match on screen.
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
local text = Addon.FormatProgress({ known = 2, learning = 1, new = 1 })
assert(text:find("50%% known"), "the known share belongs in the line: " .. text)
assert(text:find("25%% learning"), "so does learning: " .. text)
assert(text:find("25%% new"), "and new: " .. text)
assert(text:find("4 words"), "and how many words that is out of: " .. text)
for _, status in ipairs({ "known", "learning", "new" }) do
  assert(text:find(Addon.ColorHex(status), 1, true),
    status .. " should be tinted the colour its words are drawn in")
end

-- The colour has to come from the same table the word buttons read, or the
-- figure and the words drift apart the first time a colour is retuned.
Addon.COLORS.known = { 0, 0, 0 }
assert(Addon.ColorHex("known") == "|cff000000", "ColorHex must read Addon.COLORS, not a copy of it")

-- And the panel itself has to count that way. A quest naming the same place
-- nine times is one word to learn; scoring it nine times would make a
-- repetitive quest look better known than a varied one.
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
Addon.COLORS.known = { 0.30, 0.88, 0.48 }   -- undo the tamper above

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()

GetQuestText = function() return "Zul Zul Zul Zul kennen lernen neu" end
GetObjectiveText = function() return "" end
QuestFrame:Show()
Addon.readCurrentQuest()

local meta = Addon.panel.meta:GetText()
assert(meta, "the panel should put the progress line in its meta row")
-- Four distinct words: Zul, kennen, lernen, neu. Not seven tokens.
assert(meta:find("4 words"), "a repeated word counts once, expected 4 words in: " .. meta)

print("quest-progress: ok")
