-- Run from the addon root:  lua tests/book-reader.test.lua
--
-- A readable item -- a journal, a letter, a page in a book -- was the one
-- passage of the language being learned with no way in. The words of an NPC's
-- conversation were clickable and the same sentence in Kearnen's Journal was
-- not, because Blizzard draws a book in a frame of its own and this addon only
-- ever read the quest and gossip APIs. The words are the same words either
-- way; the only thing missing was a way to reach them.
--
-- This file is the book's version of tests/quest-passages.test.lua. What it
-- pins is that a page becomes clickable words at all, that turning a page
-- follows the page rather than leaving the first one up, that the same auto-
-- open switch governs it as governs a conversation, and that a closed book
-- takes its panel with it.

local node = dofile("tests/wowstub.lua")
UIParent = node()

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
local panel = Addon.panel

-- The readable-item window as Blizzard builds it: a frame, the page in a font
-- string of its own, and the book's name over it. Built by hand because the
-- stub models no part of the item-text UI -- which is what makes the absence
-- this file is written against reproducible outside the game.
local function region(text)
  local r = node()
  r.GetText = function() return type(text) == "function" and text() or text end
  return r
end

-- A stub frame records hooks rather than running them on Show/Hide the way the
-- client does, so a test that wants one fires it. Hooks are kept alongside the
-- script rather than as it: see wowstub.lua.
local function fire(frame, event)
  for _, fn in ipairs(rawget(frame, "hooks")[event] or {}) do fn(frame) end
end

local PAGE_ONE = "Die Wachen dieses Turms scheinen besonders anfaellig fuer meine Angriffe."
local PAGE_TWO = "Der Patrouilleur kam zu den Bueschen, wo ich den Leichnam hingezerrt hatte."

local book = node()
ItemTextFrame = book
book:Show()
local page = PAGE_ONE
ItemTextGetText = function() return page end
ItemTextGetItem = function() return "Kearnens Tagebuch" end
book.ItemTextItemText = region(function() return page end)
book.ItemTextTitleText = region("Kearnens Tagebuch")
-- The page button, globally named as Blizzard's template names it. A page turn
-- is the one thing that changes a book's text in place, so it is the one thing
-- the panel has to follow by itself.
local pageButton = node()
ItemTextNextPageButton = pageButton

Addon.hookBookUi()
assert(#(rawget(book, "hooks").OnShow or {}) > 0, "the book window has to be followed")
assert(#(rawget(pageButton, "hooks").OnClick or {}) > 0,
  "a page turn has to be followed, or the panel reads page one for the whole book")

-- A word button the player can actually press. Read off the panel rather than
-- built here: the claim under test is that the page reached the panel as
-- clickable words, so the buttons have to be the panel's own.
local function wordButton(word)
  for _, button in ipairs(panel.wordButtons or {}) do
    if button:IsShown() and button.word == word then return button end
  end
end

-- Manual is the default, as it is for a conversation.
Addon.SetNpcReaderAutoOpen(false)
Addon.readBook()
assert(Addon.lastQuest and Addon.lastQuest.passage == "book",
  "a book must be read as its own passage, got " .. tostring(Addon.lastQuest and Addon.lastQuest.passage))
assert(Addon.lastQuest.title == "Kearnens Tagebuch",
  "the book is read under its own name, got " .. tostring(Addon.lastQuest.title))
assert(Addon.lastQuest.text == PAGE_ONE,
  "the page the client has loaded is the page that gets read: " .. tostring(Addon.lastQuest.text))
assert(not panel:IsShown(), "a book must not open the panel on its own any more than gossip does")

-- Now the words themselves. A book is not a quest and has no quest id, so
-- nothing is archived and nothing is counted -- the point of the whole thing is
-- the words, and they have to arrive as the panel's own buttons.
Addon.readBook(true)
assert(panel:IsShown(), "asking for a book has to open the panel")
assert(panel.renderedText == PAGE_ONE, "the panel has to have drawn the page")
local wachen = assert(wordButton("Wachen"), "the page's words must be clickable, got none")
assert(wordButton("Angriffe"), "every word on the page, not only the first")
assert(wachen:GetScript("OnClick"), "and pressing one has to do something")

local savedEditor = Addon.openEditor
local opened
Addon.openEditor = function(word) opened = word end
wachen:GetScript("OnClick")(wachen)
assert(opened == "Wachen", "clicking a word in a book must open its editor, got " .. tostring(opened))
Addon.openEditor = savedEditor

-- Turning the page. This is the one thing that changes a book's text without
-- closing and reopening the window, and a panel left on the first page for the
-- whole book is exactly the fault this whole feature is here to avoid.
page = PAGE_TWO
fire(pageButton, "OnClick")
assert(Addon.lastQuest.text == PAGE_TWO,
  "a page turn has to follow the page, got " .. tostring(Addon.lastQuest.text))
assert(panel.renderedText == PAGE_TWO, "and re-draw the panel on it")
assert(wordButton("Patrouilleur"), "the new page's words must be clickable too")

-- The same switch a conversation uses. Reading a book is being spoken at, and
-- a player who does not want the panel opening itself while an NPC talks does
-- not want it opening itself while they read.
Addon.SetNpcReaderAutoOpen(true)
panel:Hide()
fire(book, "OnShow")
assert(panel:IsShown(), "with the NPC switch on, a book opens the panel")

-- A closed book takes its panel with it, the bargain GOSSIP_CLOSED keeps.
fire(book, "OnHide")
assert(not panel:IsShown(), "closing the book must close a panel showing it")

-- And one the player opened on something else is left alone.
Addon.lastQuest = { id = 0, title = "Gossip", text = "Wo wartet der Bote?", passage = "gossip" }
panel:Show()
fire(book, "OnHide")
assert(panel:IsShown(), "closing a book must not close a panel showing something else")

-- The two-page book keeps its text in regions rather than in the API. Reached
-- through the same reader, because a book is a book whichever frame it is
-- drawn in.
ItemTextGetText = nil
book.ItemTextItemText = region("")
ItemTextFrame = nil
local spread = node()
BookFrame = spread
spread:Show()
spread.BookPage1 = region("Die erste Seite.")
spread.BookPage2 = region("Die zweite Seite.")
spread.BookTitle = region("Das zweite Buch")
Addon.readBook(true)
assert(Addon.lastQuest.title == "Das zweite Buch",
  "the two-page book is read under its own name, got " .. tostring(Addon.lastQuest.title))
assert(Addon.lastQuest.text == "Die erste Seite.\n\nDie zweite Seite.",
  "both pages must reach the panel, got " .. tostring(Addon.lastQuest.text))
assert(wordButton("zweite"), "and the second page's words must be clickable")

print("book-reader: ok")
