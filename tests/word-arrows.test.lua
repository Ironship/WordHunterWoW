-- Run from the addon root:  lua tests/word-arrows.test.lua
--
-- Navigation arrows in the word editor: Previous/Next buttons and left/right
-- arrow keys let a reader go through a quest word by word without clicking
-- each one with the mouse. The feature works from the quest panel and knows
-- when a word list opens the editor (no neighbours, buttons disabled).

local node = dofile("tests/wowstub.lua")

local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  function f:EnableGamePadButton(v) self.padEnabled = v end
  function f:CreateTexture()
    local texture = node()
    texture.isTexture = true
    function texture:SetColorTexture(...) self.color = { ... } end
    return texture
  end
  function f:SetEnabled(v) self._enabled = v end
  function f:IsEnabled() return self._enabled ~= false end
  function f:Enable() self:SetEnabled(true) end
  function f:Disable() self:SetEnabled(false) end
  return f
end

dofile("Core.lua")
dofile("Compat.lua")
dofile("Gamepad.lua")
dofile("Recall.lua")
dofile("UICommon.lua")
dofile("Editor.lua")
dofile("QuestPanel.lua")
dofile("WordList.lua")
local Addon = WordHunterWoW_Addon

local DAY = 24 * 60 * 60
local now = 1700000000
time = function() return now end

WordHunterWoWDB = {
  settings = { targetLocale = "deDE", frames = {}, recallCheck = false },
  wordsByLocale = { deDE = {
    hund = { word = "Hund", status = "learning", translation = "dog", note = "", context = "Der Hund.",
      questId = "1", questTitle = "Old", statusChangedAt = now - 2 * DAY, updatedAt = now - 2 * DAY,
      firstSeenAt = now - 2 * DAY, lastSeenAt = now - DAY, encounterCount = 2 },
    katze = { word = "Katze", status = "new", translation = "cat", note = "", context = "Die Katze.",
      questId = "1", questTitle = "Old", statusChangedAt = now, updatedAt = now,
      firstSeenAt = now, lastSeenAt = now, encounterCount = 1 },
  } },
}
Addon.initializeDatabase()

Addon.createPanel()
Addon.createEditor()
local panel, editor = Addon.panel, Addon.editor

-- --- buttons exist with correct labels ----------------------------------------
assert(panel.prevWord, "prevWord button exists")
assert(panel.nextWord, "nextWord button exists")
local inRow = 0
for _, action in ipairs(panel.actions) do
  if action == panel.prevWord or action == panel.nextWord then inRow = inRow + 1 end
end
assert(inRow == 2, "both sit in the panel's own button row, sized with it")
local LABELS = Addon.LABELS
assert(panel.prevWord._text == LABELS.prevWord, "prevWord has correct label")
assert(panel.nextWord._text == LABELS.nextWord, "nextWord has correct label")

-- --- open a word and navigate ------------------------------------------------
panel:Show()
Addon.lastQuest = { id = 1, title = "Nacht", passage = "offer",
  text = "Der Hund bellt laut in der Nacht und niemand im Dorf schläft. "
    .. "Die Katze schläft auf dem warmen Dach des alten Hauses am Fluss. "
    .. "Sucht die Zuflucht im Wald." }
Addon.refreshPanel()
local words, count = panel.wordButtons, panel.wordCount
assert(words and count and count > 10, "the panel laid out its words and said so")

-- Find specific words to test navigation
local word2Index, word3Index, word2, word3
for i = 1, count do
  if i == 2 and not word2 then word2Index = i; word2 = words[i] end
  if i == 3 and not word3 then word3Index = i; word3 = words[i] end
end
assert(word2 and word3, "fixture has at least 3 words")

-- Open word 2 with mouse click
word2:GetScript("OnClick")(word2)
assert(editor:IsShown(), "editor opens with mouse click")
assert(Addon.selected and Addon.selected.word == word2.word, "on the clicked word")
assert(Addon.lastOpened and Addon.lastOpened.index == word2Index, "lastOpened is recorded")

-- Next opens word 3
local origWord2 = Addon.selected.word
panel.nextWord:GetScript("OnClick")()
assert(Addon.selected.word == word3.word, "Next opens the next word")
assert(Addon.selected.word ~= origWord2, "moved forward")

-- Previous returns to word 2
panel.prevWord:GetScript("OnClick")()
assert(Addon.selected.word == origWord2, "Previous opens the previous word")

-- --- edge cases: no word to move to ------------------------------------------
-- Go back to word 2 and move to word 1
panel.nextWord:GetScript("OnClick")()
assert(Addon.selected.word == word3.word, "at word 3")

-- Move through all words to get to the first one
local firstWord = words[1]
while Addon.selected.word ~= firstWord.word and panel.prevWord:IsEnabled() do
  panel.prevWord:GetScript("OnClick")()
end

-- Now at or past the first word; try to go back further
local beforeAttempt = Addon.selected.word
local result = Addon.OpenNeighbourWord(-1)
assert(result == false, "OpenNeighbourWord returns false when at the edge")
assert(Addon.selected.word == beforeAttempt, "Addon.selected unchanged")

-- --- button enable/disable at edges ------------------------------------------
-- Open word 1 directly
words[1]:GetScript("OnClick")(words[1])
assert(Addon.selected.word == words[1].word, "opened word 1")
assert(not panel.prevWord:IsEnabled(), "prevWord disabled at first word")
assert(panel.nextWord:IsEnabled(), "nextWord enabled at first word")

-- Move to the last word
local lastWord = words[count]
lastWord:GetScript("OnClick")(lastWord)
assert(Addon.selected.word == lastWord.word, "opened last word")
assert(panel.prevWord:IsEnabled(), "prevWord enabled at last word")
assert(not panel.nextWord:IsEnabled(), "nextWord disabled at last word")

-- --- keyboard navigation without focused box --------------------------------
words[2]:GetScript("OnClick")(words[2])
assert(Addon.selected.word == words[2].word, "opened word 2")

local propagated = {}
local origSafePropagate = Addon.SafePropagate
Addon.SafePropagate = function(_, v) propagated[#propagated + 1] = v end

-- Right key without focused box opens next
editor:GetScript("OnKeyDown")(editor, "RIGHT")
local afterRight = Addon.selected.word
assert(afterRight == words[3].word, "RIGHT key opens next word")
assert(propagated[#propagated] == false, "propagate spy saw false (key consumed)")

-- Move back to word 2 and test with a focused box
words[2]:GetScript("OnClick")(words[2])
propagated = {}
local focusBox = CreateFrame("EditBox")
function focusBox:SetFocus() end
function focusBox:ClearFocus() end
GetCurrentKeyBoardFocus = function() return focusBox end

editor:GetScript("OnKeyDown")(editor, "RIGHT")
assert(Addon.selected.word == words[2].word, "RIGHT key does not move when box has focus")
assert(propagated[#propagated] == true, "propagate spy saw true (key not consumed)")

GetCurrentKeyBoardFocus = nil
Addon.SafePropagate = origSafePropagate

-- --- keyboard navigation key consumption at edges --------------------------
-- Issue: LEFT/RIGHT keys not consumed when no neighbor word exists.
-- When at first/last word, keys should be consumed even if no navigation occurs.
words[1]:GetScript("OnClick")(words[1])
assert(Addon.selected.word == words[1].word, "at first word")
propagated = {}
Addon.SafePropagate = function(_, v) propagated[#propagated + 1] = v end

-- LEFT key at first word should be consumed (propagate false)
editor:GetScript("OnKeyDown")(editor, "LEFT")
assert(Addon.selected.word == words[1].word, "LEFT at first word does not navigate")
assert(propagated[#propagated] == false, "LEFT key consumed at first word (propagate false)")

-- Move to last word and test RIGHT
local lastWord = words[count]
lastWord:GetScript("OnClick")(lastWord)
assert(Addon.selected.word == lastWord.word, "at last word")
propagated = {}

-- RIGHT key at last word should be consumed (propagate false)
editor:GetScript("OnKeyDown")(editor, "RIGHT")
assert(Addon.selected.word == lastWord.word, "RIGHT at last word does not navigate")
assert(propagated[#propagated] == false, "RIGHT key consumed at last word (propagate false)")

Addon.SafePropagate = origSafePropagate

-- --- Escape still closes ---------------------------------------------------
propagated = {}
Addon.SafePropagate = function(_, v) propagated[#propagated + 1] = v end
editor:GetScript("OnKeyDown")(editor, "ESCAPE")
assert(not editor:IsShown(), "ESCAPE closes the editor")
assert(propagated[#propagated] == false, "ESCAPE was consumed")
Addon.SafePropagate = origSafePropagate
propagated = {}
panel:Show()  -- Reopen the panel since ESCAPE closed it

-- --- controller navigation -----------------------------------------------
words[2]:GetScript("OnClick")(words[2])
assert(editor:IsShown() and Addon.selected.word == words[2].word, "opened word 2 again")

-- PADRSHOULDER opens next
Addon.GamePadButton(editor, "PADRSHOULDER")
assert(Addon.selected.word == words[3].word, "PADRSHOULDER opens next word")

-- PADLSHOULDER opens previous
Addon.GamePadButton(editor, "PADLSHOULDER")
assert(Addon.selected.word == words[2].word, "PADLSHOULDER opens previous word")

-- --- opened from the word list: the panel forgets the click ----------------
-- The editor is showing a word from nowhere in this quest, so Next starts the
-- quest from its first word, and Previous has nowhere to go.
-- The controller's cursor is the panel's own and would still count; a re-flow
-- clears it, so this case is about the list alone.
Addon.refreshPanel()
Addon.openEditor(words[2].word, "context", 1, "title", { origin = "list" })
assert(editor:IsShown() and Addon.selected.word == words[2].word, "opened from word list")
assert(not panel.prevWord:IsEnabled(), "nothing to go back to")
assert(panel.nextWord:IsEnabled(), "Next starts the quest over")
assert(Addon.OpenNeighbourWord(1) == true, "Next opens the first word")
assert(Addon.selected.word == words[1].word, "the first word, got " .. tostring(Addon.selected.word))

-- --- a new layout forgets the click ----------------------------------------
-- The pool is reused, so an index from before the re-flow names whatever word
-- landed there. Not trusted: Next starts the quest over instead.
words[3]:GetScript("OnClick")(words[3])
assert(Addon.selected.word == words[3].word, "opened word 3")
local oldSerial = panel.layoutSerial
Addon.refreshPanel()
assert(panel.layoutSerial ~= oldSerial, "refreshPanel numbers the new layout")
assert(not panel.prevWord:IsEnabled() and panel.nextWord:IsEnabled(),
  "after a re-flow the buttons read as a fresh quest")
assert(Addon.OpenNeighbourWord(1) == true)
assert(Addon.selected.word == words[1].word,
  "a stale index is not walked on from; got " .. tostring(Addon.selected.word))

print("word-arrows: ok")
