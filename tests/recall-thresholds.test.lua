-- Run from the addon root:  lua tests/recall-thresholds.test.lua
--
-- The two counts a reader can set: how many ratings before a word is called
-- difficult, and how many quests before the editor offers Ready for Known.
--
-- Both were written into the code as 5. Five is right for somebody who meets a
-- word a handful of times a month and wrong for somebody reading a zone an
-- evening, who reaches five ratings before they have looked at the word twice
-- and gets a difficult list full of words they never struggled with.
--
-- Tested through the thing that reads the setting rather than through the
-- getter: a getter returning 20 proves nothing if IsDifficult still compares
-- against a local. Each assertion below is run once in a state where it should
-- hold and once in a state where it should not.

local node = dofile("tests/wowstub.lua")

UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_SetText = function(frame, text) frame.shownText = text end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function() end
UIDropDownMenu_Initialize = function(frame, initializer) initializer(frame, 1) end

dofile("Core.lua")
dofile("Compat.lua")
dofile("Recall.lua")
dofile("UICommon.lua")
dofile("Editor.lua")
dofile("Harvest.lua")
dofile("QuestPanel.lua")
dofile("Settings.lua")
local Addon = WordHunterWoW_Addon

local now = 1700000000
time = function() return now end

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
WordHunterWoWCorpus = { version = 1, byLocale = {} }

-- --- defaults ---------------------------------------------------------------
assert(Addon.GetDifficultMinRatings() == 5, "difficult starts at five")
assert(Addon.GetReadyAfter() == 5, "ready starts at five")

-- --- what a hand-edited profile can put there -------------------------------
-- A saved variable is a file the player can open. Every caller uses these as a
-- comparison threshold, so a string or a negative number has to come back as a
-- usable count and not reach the comparison.
WordHunterWoWDB.settings.difficultMinRatings = "twenty"
assert(Addon.GetDifficultMinRatings() == 5, "nonsense falls back to the default")
WordHunterWoWDB.settings.difficultMinRatings = -4
assert(Addon.GetDifficultMinRatings() == Addon.RECALL_DIFFICULT_MIN, "below the floor clamps up")
WordHunterWoWDB.settings.difficultMinRatings = 9999
assert(Addon.GetDifficultMinRatings() == Addon.RECALL_DIFFICULT_MAX, "above the ceiling clamps down")
WordHunterWoWDB.settings.difficultMinRatings = 20.4
assert(Addon.GetDifficultMinRatings() == 20, "a fraction rounds to a whole count")
WordHunterWoWDB.settings.difficultMinRatings = nil

-- The setter clamps on the way in too, so the stored file never holds a value
-- the getter has to repair on every read.
Addon.SetDifficultMinRatings(9999)
assert(WordHunterWoWDB.settings.difficultMinRatings == Addon.RECALL_DIFFICULT_MAX,
  "the setter stores the clamped value, not the one it was given")
Addon.SetDifficultMinRatings(5)

-- --- the setting actually governs IsDifficult -------------------------------
local words = Addon.GetWordsTable()
words.hund = { word = "Hund", status = "learning", translation = "dog",
  statusChangedAt = now - 3 * 86400 }
for i = 1, 5 do Addon.RecordRating("hund", 1, now + i) end
local row = Addon.GetRecallRow("hund")

assert(Addon.IsDifficult(row), "five low ratings is difficult at a threshold of five")
assert(Addon.CountDifficult() == 1, "and the word is in the list")

Addon.SetDifficultMinRatings(20)
assert(not Addon.IsDifficult(row), "the same five ratings is not difficult at twenty")
assert(Addon.CountDifficult() == 0, "and the list is empty")

for i = 6, 20 do Addon.RecordRating("hund", 1, now + i) end
assert(Addon.IsDifficult(row), "twenty low ratings reaches the raised threshold")

-- Raising the bar past what a word can ever reach is a real setting, not an
-- error: RATINGS_KEPT trims the stored list to twenty, and ratingCount has to
-- keep counting past it or the top of the range would be unreachable.
assert((row.ratingCount or 0) == 20, "ratingCount counts every rating")
assert(#row.ratings <= 20, "while the stored list stays trimmed")
Addon.SetDifficultMinRatings(5)

-- --- the setting governs Ready for Known ------------------------------------
-- Driven through the editor, because the comparison lives there. Both halves
-- of the condition are checked: the count, and the fourteen days that are not
-- settable and must still hold.
Addon.createEditor()
local editor = Addon.editor
assert(editor and editor.history, "the editor has no history line")

-- Through openEditor, which is what a click reaches: the function that decides
-- whether to append the label is a local in Editor.lua and has no other door.
local function readyShown(encounters, learningDaysAgo)
  words.hund = {
    word = "Hund", status = "learning", translation = "dog",
    firstSeenAt = now - 400 * 86400, lastSeenAt = now,
    encounterCount = encounters,
    statusChangedAt = now - learningDaysAgo * 86400,
  }
  Addon.openEditor("Hund", "Der Hund bellt.", 1, "Q")
  return (editor.history:GetText() or ""):find(Addon.LABELS.readyForKnown, 1, true) ~= nil
end

Addon.SetReadyAfter(5)
assert(readyShown(5, 30), "five quests and a month learning offers Known")
assert(not readyShown(4, 30), "four does not")

Addon.SetReadyAfter(25)
assert(not readyShown(5, 30), "five stops offering it once the setting is twenty-five")
assert(readyShown(25, 30), "twenty-five does")
assert(not readyShown(25, 3), "but never before fourteen days, which is not settable")
Addon.SetReadyAfter(5)

-- --- the sliders on the page ------------------------------------------------
local panel = Addon.CreateSettingsPanel()
panel.refresh()

for _, case in ipairs({
  { slider = "readySlider", get = "GetReadyAfter", set = 12,
    max = Addon.RECALL_READY_MAX },
  { slider = "difficultSlider", get = "GetDifficultMinRatings", set = 18,
    max = Addon.RECALL_DIFFICULT_MAX },
}) do
  local s = rawget(panel, case.slider)
  assert(s, "the page has no " .. case.slider)

  -- The bounds are checked by dragging past them rather than by reading
  -- GetMinMaxValues back off the slider: the stub fabricates any method it is
  -- asked for, so reading the range would test the stub and pass whatever the
  -- page had set. Clamping is the addon's own code either way.
  s:GetScript("OnValueChanged")(s, 10000)
  assert(Addon[case.get]() == case.max,
    case.slider .. " let a drag past the top through: " .. tostring(Addon[case.get]()))

  -- Dragged, not set: OnValueChanged is what the player's hand reaches.
  s:GetScript("OnValueChanged")(s, case.set)
  assert(Addon[case.get]() == case.set,
    case.slider .. " did not move the setting: " .. tostring(Addon[case.get]()))

  -- The caption carries the figure, and a fresh panel.refresh has to redraw it
  -- -- SetValue fires OnValueChanged only when the value moves, so a page
  -- reopened on an unchanged setting kept the caption it was built with.
  local text = _G[s:GetName() .. "Text"]:GetText() or ""
  assert(text:find(tostring(case.set), 1, true),
    case.slider .. " caption does not show the value: " .. text)
  panel.refresh()
  text = _G[s:GetName() .. "Text"]:GetText() or ""
  assert(text:find(tostring(case.set), 1, true),
    case.slider .. " caption lost the value on refresh: " .. text)
end

-- Moving the difficult slider changes which words count, so the line under it
-- has to be redrawn then and not at the next panel refresh.
local noteLine = rawget(panel, "difficultNote")
assert(noteLine, "the page has no difficult-words line")
local dslider = rawget(panel, "difficultSlider")
dslider:GetScript("OnValueChanged")(dslider, 5)
assert(noteLine:GetText() == string.format(Addon.LABELS.difficultNote, 1, 5),
  "at five the line counts the word: " .. tostring(noteLine:GetText()))
dslider:GetScript("OnValueChanged")(dslider, 30)
assert(noteLine:GetText() == string.format(Addon.LABELS.difficultNote, 0, 30),
  "at thirty it counts none, and says thirty: " .. tostring(noteLine:GetText()))

print("recall-thresholds: ok")
