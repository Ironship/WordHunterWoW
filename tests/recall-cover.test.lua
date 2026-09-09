-- Run from the addon root:  lua tests/recall-cover.test.lua
--
-- The recall cover: a Learning word clicked in a quest asks how well it was
-- known before it shows its meaning. What this file holds is the one thing
-- the feature is for -- that the meaning is nowhere on screen until the
-- player has answered -- and the one thing that would make it useless: a
-- rating that needed Save to survive. Cancel is how most of these editors
-- close, and the verdict has to be on disk by then.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("Recall.lua")
dofile("UICommon.lua")
dofile("Editor.lua")
dofile("QuestPanel.lua")
dofile("WordList.lua")
local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS

local DAY, HOUR = 24 * 60 * 60, 60 * 60
local now = 1700000000
time = function() return now end

WordHunterWoWDB = {
  settings = { targetLocale = "deDE", frames = {}, recallCheck = true },
  wordsByLocale = { deDE = {
    hund = { word = "Hund", status = "learning", translation = "dog", note = "n", context = "Der Hund.",
      questId = "1", questTitle = "Old", statusChangedAt = now - 2 * DAY, updatedAt = now - 2 * DAY,
      firstSeenAt = now - 2 * DAY, lastSeenAt = now - DAY, encounterCount = 2 },
  } },
}
Addon.initializeDatabase()
-- A dictionary entry as well, so the reset-to-dictionary button has a reason
-- to exist -- its confirmation prints the dictionary's meaning, which is the
-- one other place the meaning could leak from.
Addon.RegisterDictionaryProvider("deDE", "test", { hund = { word = "Hund", translation = "dog", note = "" } })

Addon.createPanel()
Addon.createEditor()
local editor = Addon.editor
assert(editor.cover and editor.cover.buttons and #editor.cover.buttons == 5, "the editor needs a cover with five buttons")
assert(editor.cover.show and editor.cancel, "and a way past it, and a Cancel a test can press")

-- Modelled where the stub only pretends: focus, the reset button's SetShown,
-- and keyboard propagation, because the feature turns on all three.
local focused, noteFocused = false, false
editor.translation.SetFocus = function() focused = true end
editor.translation.ClearFocus = function() focused = false end
editor.note.SetFocus = function() noteFocused = true end
editor.note.ClearFocus = function() noteFocused = false end
editor.cover.EnableKeyboard = function(self, v) self.keyboard = v end
-- The panel's side of the reveal, counted rather than drawn: recall-hover
-- drives the real one.
local revealed = 0
Addon.RevealSelectedHighlight = function() revealed = revealed + 1 end
editor.resetDictionary.SetShown = function(self, v) if v then self:Show() else self:Hide() end end
local propagated
editor.cover.SetPropagateKeyboardInput = function(_, v) propagated = v end

local function seen(text)
  for _, s in ipairs(CAPTURE_TEXT or {}) do
    if s == text then return true end
  end
  return false
end

local function openFromPanel()
  CAPTURE_TEXT = {}
  Addon.openEditor("Hund", "Der Hund bellt.", 184, "Sten", { origin = "panel" })
end

-- Gated: the meaning is held back everywhere it could show.
editor.note:SetFocus()
openFromPanel()
assert(not noteFocused, "the note box gives up focus too")
assert(editor:IsShown(), "the editor opens")
assert(editor.cover:IsShown(), "and the cover is up for a Learning word two days old")
assert(Addon.selected.recallPending == true, "the editor knows it is waiting for a verdict")
assert(not editor.translation:IsShown() and not editor.noteScroll:IsShown() and not editor.meaningLabel:IsShown(),
  "the meaning and note boxes are hidden, not merely covered")
assert(not editor.statusButtons.learning:IsShown(), "and the status buttons with them")
assert(not editor.resetDictionary:IsShown(), "reset-to-dictionary would print the meaning, so it is hidden too")
assert(editor.translation:GetText() == "" and editor.note:GetText() == "", "the boxes hold nothing")
-- Cancel is left alone; the stub never shows a button by itself, so only the
-- one that is hidden and shown on purpose can be measured here.
assert(not editor.save:IsShown(), "Save is away with the boxes")
-- Save reached anyway -- Enter in a box, say -- must not write the empty
-- boxes over the meaning. It shows the meaning instead.
editor.save:GetScript("OnClick")()
assert(WordHunterWoWDB.wordsByLocale.deDE.hund.translation == "dog", "a Save under the cover saved nothing")
assert(not editor.cover:IsShown() and editor.translation:GetText() == "dog", "and took the cover down instead")
assert(editor.save:IsShown(), "and Save is back with the boxes")
assert(Addon.GetRecallRow("hund").ratingCount == 0, "without counting as a rating")
assert(revealed == 1, "showing the meaning asks the panel to light the English word")
editor:Hide()
openFromPanel()
assert(editor.cover:IsShown(), "unrated, the word asks again")
-- Now the boxes have been shown once, so hiding them is a real transition
-- and not the stub's starting state.
assert(not editor.translation:IsShown() and not editor.noteScroll:IsShown() and not editor.meaningLabel:IsShown()
  and not editor.noteLabel:IsShown() and not editor.statusLabel:IsShown() and not editor.save:IsShown()
  and not editor.statusButtons.learning:IsShown() and not editor.resetDictionary:IsShown(),
  "the boxes are hidden again once they have been shown")
assert(editor.cover.keyboard == true, "out of combat the cover takes the keys")
assert(not seen("dog") and not seen("n"), "the meaning was never written to any string")
assert(not focused, "no box has focus, or the number keys would type into it")
assert(editor.word:GetText() == "Hund" and editor.context:GetText() == "Der Hund bellt.",
  "the word and its sentence are what is shown")
assert(editor.cover.soFar:GetText() == "", "nothing rated yet, nothing to summarise")
-- Opening a Learning word from a quest keeps the sentence, rated or not.
local row = Addon.GetRecallRow("hund")
assert(row and #row.examples == 1 and row.examples[1].text == "Der Hund bellt." and row.examples[1].questId == "184",
  "the sentence the word was met in is kept on opening")
assert(row.ratingCount == 0, "opening is not a rating")

-- A verdict: written at once, and the meaning appears.
editor.cover.buttons[3]:GetScript("OnClick")(editor.cover.buttons[3])
assert(row.ratingCount == 1 and row.ratings[1].score == 3 and row.lastRatedAt == now, "the rating is on the row")
assert(not editor.cover:IsShown() and editor.translation:IsShown(), "the cover is down")
assert(editor.translation:GetText() == "dog" and editor.note:GetText() == "n", "and the boxes are filled")
assert(focused, "the meaning box has focus again, as it does on an ordinary open")
assert(editor.resetDictionary:IsShown(), "reset-to-dictionary is back")
assert(Addon.selected.recallPending == false)
assert((editor.history:GetText() or ""):find("Recall 3.0 (1)", 1, true),
  "the history line carries the verdict: " .. tostring(editor.history:GetText()))
assert(revealed == 2, "a rating asks the panel to light the English word")

-- Cancel, and the rating is still there. Nothing was saved through Save.
editor.cancel:GetScript("OnClick")()
assert(not editor:IsShown(), "Cancel closes the editor")
assert(WordHunterWoWDB.recallByLocale.deDE.hund.ratingCount == 1, "the rating survived Cancel")
assert(WordHunterWoWDB.wordsByLocale.deDE.hund.translation == "dog", "and the word itself is untouched")
Addon.CloseAll()
assert(WordHunterWoWDB.recallByLocale.deDE.hund.ratingCount == 1, "and CloseAll")

-- Just rated: opened again, it shows the meaning straight away.
openFromPanel()
assert(not editor.cover:IsShown() and editor.translation:GetText() == "dog", "rated a moment ago, not asked again")
assert(editor.cover.soFar:GetText() == "", "the summary line belongs to the cover only")
editor:Hide()

-- Twenty hours on: asked again, this time answered from the keyboard.
now = now + 20 * HOUR
openFromPanel()
assert(editor.cover:IsShown(), "twenty hours later the question is back")
assert(editor.cover.soFar:GetText() == string.format(LABELS.recallSoFar, 1, 3.0),
  "and the cover says how it has gone so far: " .. tostring(editor.cover.soFar:GetText()))
propagated = nil
editor.cover:GetScript("OnKeyDown")(editor.cover, "5")
assert(row.ratingCount == 2 and row.ratings[2].score == 5, "the 5 key is a rating")
assert(not editor.cover:IsShown() and editor.translation:GetText() == "dog")
assert(focused, "the meaning box has focus after a key rating -- the stub's timer runs at once")
-- The key was kept from the action bar, and the cover was then put back to
-- letting keys through: a flag left at "keep" would eat every key the next
-- time the cover came up in combat, where it cannot be changed.
assert(propagated == true, "the cover rests at letting keys through, last set " .. tostring(propagated))
-- With nothing pending, every key is let through -- Escape has to reach the
-- editor's own hook.
editor.cover:GetScript("OnKeyDown")(editor.cover, "5")
assert(propagated == true, "a number with no question pending is not taken")
assert(row.ratingCount == 2, "and is not a rating")
editor:Hide()

now = now + 20 * HOUR
openFromPanel()
assert(editor.cover:IsShown())
editor.cover:GetScript("OnKeyDown")(editor.cover, "ESCAPE")
assert(propagated == true, "Escape passes through the cover")
assert(editor.cover:IsShown(), "and is not a rating either")
editor.cover:GetScript("OnKeyDown")(editor.cover, "NUMPAD2")
assert(row.ratingCount == 3 and row.ratings[3].score == 2, "the number pad works too")
editor:Hide()

-- In combat the cover takes no keys: the game's own rule stops it choosing
-- which keys to keep, so it keeps none. The buttons still work.
now = now + 20 * HOUR
InCombatLockdown = function() return true end
openFromPanel()
assert(editor.cover:IsShown() and editor.cover.keyboard == false, "in combat the cover's keyboard is off")
editor.cover:GetScript("OnKeyDown")(editor.cover, "2")
assert(row.ratingCount == 3, "a digit in combat is not a rating")
assert(propagated == true, "and is let through to the game")
editor.cover.buttons[2]:GetScript("OnClick")(editor.cover.buttons[2])
assert(row.ratingCount == 4 and row.ratings[4].score == 2, "the buttons still rate in combat")
editor:Hide()
-- Combat ending while a cover is up hands the keys back.
now = now + 20 * HOUR
openFromPanel()
assert(editor.cover.keyboard == false)
InCombatLockdown = function() return false end
editor.cover:GetScript("OnEvent")(editor.cover, "PLAYER_REGEN_ENABLED")
assert(editor.cover.keyboard == true, "leaving combat switches the keys back on")
editor.cover:GetScript("OnKeyDown")(editor.cover, "4")
assert(row.ratingCount == 5 and row.ratings[5].score == 4, "and they rate again")
editor:Hide()
InCombatLockdown = nil

-- Looking without answering.
now = now + 20 * HOUR
openFromPanel()
assert(editor.cover:IsShown())
editor.cover.show:GetScript("OnClick")()
assert(not editor.cover:IsShown() and editor.translation:GetText() == "dog", "Show meaning takes the cover down")
assert(row.ratingCount == 5 and row.lastRatedAt == now - 20 * HOUR, "and is not a rating of any kind")
editor:Hide()

-- Switching the check off under an open question takes the question down,
-- so the panel -- which reads the setting live -- and the editor agree.
now = now + 20 * HOUR
openFromPanel()
assert(editor.cover:IsShown())
Addon.SetRecallCheck(false)
assert(not editor.cover:IsShown() and editor.translation:GetText() == "dog", "switching off reveals")
assert(row.ratingCount == 5, "without a rating")
Addon.SetRecallCheck(true)
editor:Hide()

-- Changing the language closes the editor: a verdict given after the change
-- would be filed under the new language.
openFromPanel()
assert(editor.cover:IsShown())
Addon.SetTargetLocale("frFR")
assert(not editor:IsShown(), "a language change closes the editor")
editor.cover:GetScript("OnKeyDown")(editor.cover, "3")
assert(next(Addon.GetRecallTable()) == nil, "and nothing is written under the new language")
Addon.SetTargetLocale("deDE")
assert(Addon.GetRecallRow("hund").ratingCount == 5, "the German rows are as they were")

-- The gate, from the editor's side. Each of these opens straight to the meaning.
now = now + 20 * HOUR
local words = Addon.GetWordsTable()
local function opensOpen(why, ...)
  CAPTURE_TEXT = {}
  Addon.openEditor(...)
  assert(not editor.cover:IsShown() and editor.translation:GetText() == "dog", why)
  editor:Hide()
end
opensOpen("no origin -- the word list -- never asks", "Hund", "Der Hund.", 1, "Old")
opensOpen("an origin other than the panel never asks", "Hund", "Der Hund.", 1, "Old", { origin = "list" })
words.hund.status = "known"
opensOpen("a Known word is not asked", "Hund", "Der Hund bellt.", 184, "Sten", { origin = "panel" })
words.hund.status = "learning"
words.hund.statusChangedAt = now - HOUR
opensOpen("Learning for an hour is not asked", "Hund", "Der Hund bellt.", 184, "Sten", { origin = "panel" })
words.hund.statusChangedAt = now - 2 * DAY
Addon.SetRecallCheck(false)
opensOpen("with the check off nothing is asked", "Hund", "Der Hund bellt.", 184, "Sten", { origin = "panel" })
Addon.SetRecallCheck(true)
openFromPanel()
assert(editor.cover:IsShown(), "and with it on, the same word is")
editor:Hide()

-- The word list's own click, which passes no origin.
Addon.toggleWordList()
local listRow = Addon.listFrame.rows and Addon.listFrame.rows[1]
assert(listRow and listRow.key == "hund", "the word list shows the word")
CAPTURE_TEXT = {}
listRow:GetScript("OnClick")(listRow)
assert(editor:IsShown() and not editor.cover:IsShown() and editor.translation:GetText() == "dog",
  "from the word list the meaning is beside the word already, so it is never asked")
Addon.listFrame:Hide()
editor:Hide()

-- A word the dictionary marks Learning but the player never touched: no entry,
-- no question, and opening it makes no entry either.
Addon.RegisterDictionaryProvider("deDE", "test", {
  hund = { word = "Hund", translation = "dog", note = "" },
  katze = { word = "Katze", translation = "cat", status = "learning" },
})
CAPTURE_TEXT = {}
Addon.openEditor("Katze", "Die Katze.", 2, "Two", { origin = "panel" })
assert(not editor.cover:IsShown() and editor.translation:GetText() == "cat", "a dictionary word opens open")
assert(words.katze == nil, "and gets no entry of its own from being opened")
assert(Addon.GetRecallRow("katze") == nil, "nor a recall row")
editor:Hide()

-- Saving a word as Learning keeps its sentence; saving it as anything else
-- does not start collecting.
Addon.openEditor("Baum", "Der Baum steht.", 3, "Three", { origin = "panel" })
editor.translation:SetText("tree")
Addon.selected.status = "learning"
editor.save:GetScript("OnClick")()
assert(words.baum and words.baum.status == "learning", "saved as Learning")
local baum = Addon.GetRecallRow("baum")
assert(baum and #baum.examples == 1 and baum.examples[1].text == "Der Baum steht.", "and the sentence went with it")
Addon.openEditor("Stein", "Der Stein liegt.", 3, "Three", { origin = "panel" })
editor.translation:SetText("stone")
Addon.selected.status = "known"
editor.save:GetScript("OnClick")()
assert(words.stein and Addon.GetRecallRow("stein") == nil, "a Known word collects no sentences")

-- The cover follows the editor's own scale, being a child of it: nothing to
-- assert beyond the parent, which the stub records.
assert(editor.cover:GetParent() == editor, "the cover is part of the editor")
assert(editor.cover.buttons[1]:GetHeight() == Addon.RoleButtonHeight(), "one button height, like every other button")

print("recall-cover: ok")
