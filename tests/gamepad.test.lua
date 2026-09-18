-- Run from the addon root:  lua tests/gamepad.test.lua
--
-- The controller: a cursor over the quest's words, moved by the D-pad and
-- pressed by the face buttons, that goes through the same OnEnter and OnClick
-- the mouse does. What this file holds is that the cursor lands where the eye
-- would put it, that a press reaches the code a click reaches -- the editor,
-- the rating, the save -- and that a press the panel does not answer is handed
-- back to the game rather than eaten.
--
-- The client's side is modelled where the stub only pretends: whether a frame
-- asked for pad buttons, and what the handler told the client about
-- propagation, because the feature is nothing without both.

local node = dofile("tests/wowstub.lua")

local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  function f:EnableGamePadButton(v) self.padEnabled = v end
  -- Marked, so a test can tell a texture this made from a table the stub
  -- manufactured for a field nobody wrote.
  function f:CreateTexture()
    local texture = node()
    texture.isTexture = true
    function texture:SetColorTexture(...) self.color = { ... } end
    return texture
  end
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
  settings = { targetLocale = "deDE", frames = {}, recallCheck = true },
  wordsByLocale = { deDE = {
    hund = { word = "Hund", status = "learning", translation = "dog", note = "", context = "Der Hund.",
      questId = "1", questTitle = "Old", statusChangedAt = now - 2 * DAY, updatedAt = now - 2 * DAY,
      firstSeenAt = now - 2 * DAY, lastSeenAt = now - DAY, encounterCount = 2 },
  } },
}
Addon.initializeDatabase()
Addon.RegisterDictionaryProvider("deDE", "test", {
  hund = { word = "Hund", translation = "dog", note = "" },
  katze = { word = "Katze", translation = "cat", note = "" },
})

assert(Addon.GetGamePadEnabled() == true, "on by default, with nothing stored")

-- What the handler told the client, press by press.
local propagated = {}
Addon.SafePropagate = function(_, v) propagated[#propagated + 1] = v end
local function lastPropagated() return propagated[#propagated] end

-- The panel's hover, counted: the cursor must give a word the same OnEnter.
local lit = {}
local highlight = Addon.HighlightEnglishForWord
Addon.HighlightEnglishForWord = function(word, ...)
  lit[#lit + 1] = word
  return highlight(word, ...)
end

Addon.createPanel()
Addon.createEditor()
local panel, editor = Addon.panel, Addon.editor

-- --- attached to whatever takes Escape ----------------------------------------
assert(panel.padEnabled == true, "the panel asked the client for pad buttons")
assert(editor.padEnabled == true, "and so did the editor")
assert(type(panel:GetScript("OnGamePadButtonDown")) == "function", "the panel has the handler")
assert(type(editor:GetScript("OnGamePadButtonDown")) == "function", "so does the editor")

-- A quest long enough to wrap: the D-pad moves by line as well as by word.
panel:Show()
Addon.lastQuest = { id = 1, title = "Nacht", passage = "offer",
  text = "Der Hund bellt laut in der Nacht und niemand im Dorf schläft. "
    .. "Die Katze schläft auf dem warmen Dach des alten Hauses am Fluss. "
    .. "Sucht die Zuflucht im Wald." }
Addon.refreshPanel()
local words, count = panel.wordButtons, panel.wordCount
assert(words and count and count > 10, "the panel laid out its words and said so")
local lines, seenLine = {}, {}
for i = 1, count do
  local y = words[i].gridY
  if type(y) == "number" and not seenLine[y] then
    seenLine[y] = true
    lines[#lines + 1] = y
  end
end
assert(#lines >= 2, "the fixture must wrap onto more than one line; it made " .. #lines)

local function press(button, frame)
  return Addon.GamePadButton(frame or panel, button)
end

-- --- the cursor ---------------------------------------------------------------
assert(Addon.GamePadFocus() == nil, "nothing is focused before the first press")
assert(press("PADDRIGHT") == true, "the first press is taken")
local index, focused = Addon.GamePadFocus()
assert(index == 1 and focused == words[1], "and lands on the first word")
local cursor = Addon.GamePadCursor(panel.content)
assert(cursor and cursor.isTexture, "the cursor is a texture on the scroll child")
assert(cursor.target == words[1] and cursor:IsShown(), "drawn on the word")
assert(lit[#lit] == words[1].word, "the word got the hover's OnEnter, got " .. tostring(lit[#lit]))
assert(lastPropagated() == false, "a press the panel answered is kept from the game")

press("PADDRIGHT")
assert(Addon.GamePadFocus() == 2, "right moves one word")
for _ = 1, 5 do press("PADDLEFT") end
assert(Addon.GamePadFocus() == 1, "left stops at the first word rather than leaving")
assert(lastPropagated() == false, "and a press at the edge is still the panel's")

-- Down from the first word of a line is the first word of the next line: the
-- nearest centre, and nothing is nearer than the word directly underneath.
local first = words[1]
press("PADDDOWN")
local _, below = Addon.GamePadFocus()
assert(below and below ~= first and below.gridY < first.gridY, "down goes to the line below")
assert(below.gridX == first.gridX, "onto the word that starts it, not one further along")
-- Up is the same rule the other way: the first line, and on it the word whose
-- centre is nearest -- which need not be the word it came down from, since
-- the one that starts a line can be narrower than the one under it. The rule
-- is restated here in the test's own arithmetic rather than taken on trust.
press("PADDUP")
local _, up = Addon.GamePadFocus()
assert(up and up.gridY == first.gridY, "up returns to the first line")
local function centreOf(b) return b.gridX + b.gridW / 2 end
for i = 1, count do
  local b = words[i]
  if b.gridY == first.gridY and b.word ~= "" then
    assert(math.abs(centreOf(b) - centreOf(below)) >= math.abs(centreOf(up) - centreOf(below)),
      "onto the word nearest the one it left: got " .. tostring(up.word) .. ", but " .. tostring(b.word) .. " is nearer")
  end
end

-- --- the scroll frame follows -------------------------------------------------
local scrollTop = 0
panel.scroll.GetHeight = function() return 20 end
panel.scroll.GetVerticalScroll = function() return scrollTop end
panel.scroll.SetVerticalScroll = function(_, v) scrollTop = v end
press("PADDDOWN")
local _, second = Addon.GamePadFocus()
local top, bottom = -second.gridY, -second.gridY + second:GetHeight()
assert(scrollTop <= top and bottom <= scrollTop + 20, string.format(
  "the focused word is inside the window: word %d-%d, window %d-%d", top, bottom, scrollTop, scrollTop + 20))
press("PADDUP")
assert(scrollTop <= -first.gridY, "and scrolls back up for the first line")
panel.scroll.GetHeight, panel.scroll.GetVerticalScroll, panel.scroll.SetVerticalScroll = nil, nil, nil

-- --- a press the panel does not answer ----------------------------------------
assert(press("PADRTRIGGER") == false, "a trigger means nothing here")
assert(lastPropagated() == true, "and is handed back to the game")

-- --- opening a word -----------------------------------------------------------
-- Onto "Hund", Learning and two days old: the editor opens with the question
-- strip up, exactly as a click would open it.
local hundIndex
for i = 1, count do
  if words[i].word == "Hund" then hundIndex = i break end
end
assert(hundIndex, "the fixture has Hund")
while Addon.GamePadFocus() ~= hundIndex do
  local before = Addon.GamePadFocus()
  press("PADDRIGHT")
  assert(Addon.GamePadFocus() ~= before, "could not reach Hund")
end
press("PAD1")
assert(editor:IsShown(), "PAD1 opens the editor")
assert(Addon.selected and Addon.selected.word == "Hund", "on the focused word")
assert(editor.cover:IsShown() and Addon.selected.recallPending == true, "with the question up")
local strip = Addon.GamePadCursor(editor.cover)
assert(strip and strip.isTexture and strip.target == editor.cover.buttons[3],
  "and the cursor on the middle rating, so the player sees where they are")

-- --- rating from the pad ------------------------------------------------------
press("PADDRIGHT", editor)
assert(strip.target == editor.cover.buttons[4], "right moves the rating up")
for _ = 1, 3 do press("PADDRIGHT", editor) end
assert(strip.target == editor.cover.buttons[5], "and stops at five")
press("PADDLEFT", editor)
assert(strip.target == editor.cover.buttons[4], "left brings it down")
press("PAD1", editor)
local row = Addon.GetRecallRow("hund")
assert(row and row.ratingCount == 1 and row.ratings[1].score == 4, "PAD1 gives the verdict under the cursor")
assert(not editor.cover:IsShown() and Addon.selected.recallPending == false, "and the strip comes down")
assert(not strip:IsShown(), "taking its cursor with it")

-- --- the status, and Save -----------------------------------------------------
assert(Addon.selected.status == "learning")
press("PADDRIGHT", editor)
assert(Addon.selected.status == "known", "right moves the status along")
press("PADDRIGHT", editor)
press("PADDRIGHT", editor)
assert(Addon.selected.status == "ignored", "and stops at the last one")
press("PADDLEFT", editor)
assert(Addon.selected.status == "known")
press("PAD1", editor)
assert(WordHunterWoWDB.wordsByLocale.deDE.hund.status == "known", "PAD1 is Save")
if editor:IsShown() then
  press("PAD2", editor)
  assert(not editor:IsShown(), "PAD2 is Cancel")
end
assert(panel:IsShown(), "and closing the editor leaves the panel")

-- --- opened by the mouse, the question waits for the first D-pad press --------
WordHunterWoWDB.wordsByLocale.deDE.hund.status = "learning"
WordHunterWoWDB.wordsByLocale.deDE.hund.statusChangedAt = now - 2 * DAY
now = now + 3 * DAY
words[hundIndex]:GetScript("OnClick")(words[hundIndex])
assert(editor:IsShown() and editor.cover:IsShown(), "the question is up again after three days")
assert(not strip:IsShown(), "with no cursor: the mouse opened it")
press("PAD2", editor)
assert(not editor.cover:IsShown(), "PAD2 puts the question away")
assert(Addon.GetRecallRow("hund").ratingCount == 1, "and later is not a verdict")
editor.cancel:GetScript("OnClick")()
assert(not editor:IsShown())

-- --- windows over the panel ---------------------------------------------------
press("PAD3")
assert(Addon.listFrame and Addon.listFrame:IsShown(), "PAD3 opens the word list")
assert(press("PADDRIGHT") == false and lastPropagated() == true,
  "the list is not driven from the pad; the press goes to the game")
press("PAD3")
assert(not Addon.listFrame:IsShown(), "and PAD3 closes it again")
press("PAD3")
press("PAD2")
assert(not Addon.listFrame:IsShown() and panel:IsShown(), "PAD2 over the list closes the list, not the panel")

press("PAD4")
assert(Addon.GetReadingMode() == true, "PAD4 is reading mode")
press("PAD4")
assert(Addon.GetReadingMode() == false, "both ways")

-- --- a new layout forgets the index -------------------------------------------
press("PADDRIGHT")
assert(Addon.GamePadFocus() ~= nil)
Addon.refreshPanel()
assert(Addon.GamePadFocus() == nil, "the pooled buttons were reused; the index means nothing now")
assert(not cursor:IsShown(), "and the cursor is off the screen")
press("PADDRIGHT")
assert(Addon.GamePadFocus() == 1, "the next press starts again from the first word")

-- --- switched off -------------------------------------------------------------
Addon.SetGamePadEnabled(false)
assert(Addon.GetGamePadEnabled() == false and WordHunterWoWDB.settings.gamepad == false, "stored")
assert(press("PADDRIGHT") == false, "off, the panel answers nothing")
assert(lastPropagated() == true, "and everything goes to the game")
assert(Addon.GamePadFocus() == 1, "nothing moved")
Addon.SetGamePadEnabled(true)

-- --- PAD2 closes --------------------------------------------------------------
press("PAD2")
assert(not panel:IsShown(), "PAD2 on the panel closes it")

print("gamepad: ok")
