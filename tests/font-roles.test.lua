-- Run from the addon root:  lua tests/font-roles.test.lua
--
-- Three windows open at once, one size setting each set to the same number, and
-- three different sizes of letter and three different button heights on screen.
-- The reason was never the sliders: the surfaces started from different
-- Blizzard font objects and the same two widgets were built at four hard-coded
-- heights, so the gap was already there at 100% and a multiplier only made it
-- wider. The same word was 12 in the quest panel, 10 in a word list row, and in
-- the editor's boxes it was whatever the player had set their CHAT window to.
--
-- So the sizes are named jobs now -- heading, body, label, meta -- and every
-- surface draws from those four instead of from nine font objects. This file
-- holds the part that matters: that the roles are one number each and follow
-- the client rather than being written down, that the surfaces reach them, that
-- the buttons are one height, and above all that reaching any of it did not
-- change a single string's colour. A font object carries a colour as well as a
-- size, and re-basing strings onto shared objects would have recoloured a dozen
-- headings with the whole suite still green -- so a role sets a size on top of
-- the object a string already has, and never swaps the object.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
dofile("Editor.lua")
dofile("WordList.lua")
dofile("Stats.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

local function eq(what, got, want)
  assert(got == want, ("%s: expected %s, got %s"):format(what, tostring(want), tostring(got)))
end

-- ---------------------------------------------------------------------------
-- One size per role, and the roles are what the settings panel quotes.
eq("the body role", Addon.RoleSize("body"), 12)
eq("the heading role", Addon.RoleSize("heading"), 16)
eq("the label role", Addon.RoleSize("label"), 10)
eq("the meta role", Addon.RoleSize("meta"), 10)
eq("a role multiplies", Addon.RoleSize("body", 1.5), 18)
eq("and the figure under the text slider is that same role",
  Addon.TextScalePoints(1.5), 18)
eq("one button height, off the body role", Addon.RoleButtonHeight(), 26)

-- The set follows the client rather than being written down: a player who has
-- turned the game's own font up keeps that. Each role is anchored to the object
-- it has always been drawn from, so each one is moved on its own to prove that
-- none of the four is a literal that merely happens to be right today.
local anchors = {
  body = "GameFontHighlight", heading = "GameFontNormalLarge",
  label = "GameFontNormalSmall", meta = "GameFontNormalSmall",
}
for role, name in pairs(anchors) do
  local real = _G[name]
  _G[name] = { GetFont = function() return "FRIZQT__.TTF", 18, "" end }
  eq(("the %s role reads its own anchor rather than a number"):format(role),
    Addon.RoleSize(role), 18)
  _G[name] = real
end
-- And with an anchor missing altogether -- a client that does not carry that
-- object -- the role falls back to its ratio of the panel's own body font
-- rather than to nothing.
local realLarge = _G.GameFontNormalLarge
_G.GameFontNormalLarge = nil
eq("a missing anchor falls back to the body ratio", Addon.RoleSize("heading"), 16)
_G.GameFontNormalLarge = realLarge
eq("an unknown role does nothing", Addon.RoleSize("banner"), nil)

-- ---------------------------------------------------------------------------
-- The three windows in the complaint, at 100% and at 150%.
--
-- The panel sizes its letters and the editor is scaled whole, so the two are
-- never comparable by reading GetFontSize alone: the editor's frame multiplies
-- everything inside it. Effective size is what a player sees, and it is what is
-- compared here.
local function effective(frame, fs)
  local size = fs:GetFontSize()
  return size and size * (frame:GetScale() or 1)
end

WordHunterWoWDB.wordsByLocale.deDE = {
  nachricht = { word = "Nachricht", translation = "message", status = "new" },
}

Addon.createPanel()
local panel = Addon.panel
Addon.createEditor()
Addon.openEditor("Nachricht", nil, 1, "Quest")
local editor = Addon.editor
Addon.toggleWordList()
local list = Addon.listFrame

local function setAll(scale)
  Addon.SetTextScale(scale)
  Addon.SetEditorScale(scale)
  Addon.SetListScale(scale)
  Addon.ApplyIntegratedLayout()
  Addon.refreshWordList()
end

local function firstRow()
  local rows = list.rows
  assert(rows and rows[1], "the word list should have built at least one row")
  return rows[1]
end

for _, scale in ipairs({ 1.0, 1.5 }) do
  setAll(scale)
  local want = 12 * scale
  -- The panel's own body text. Its clickable words are pooled behind a local,
  -- so the reachable body string on this surface is an action caption -- the
  -- same chromeFont path and the same role.
  eq(("the quest panel's body text at %d%%"):format(scale * 100),
    effective(panel, panel.actions[1]:GetFontString()), want)
  eq(("the quest panel's title at %d%%"):format(scale * 100),
    effective(panel, panel.title), 16 * scale)
  eq(("the editor's translation box at %d%%"):format(scale * 100),
    effective(editor, editor.translation), want)
  eq(("the editor's note box at %d%%"):format(scale * 100),
    effective(editor, editor.note), want)
  -- The search box is the same shared widget as the translation field, so the
  -- chat font reached into the word list as well as the editor.
  eq(("the word list's search box at %d%%"):format(scale * 100),
    effective(list, list.search), want)
  eq(("a word list row at %d%%"):format(scale * 100),
    effective(list, firstRow().name), want)
  -- The heading role is the one thing five of the six surfaces already agreed
  -- on, so it has to be exactly where it was or somebody's window moved.
  eq(("the editor's heading at %d%%"):format(scale * 100),
    effective(editor, editor.word), 16 * scale)
  -- Meta stays meta: the figures beside a row are not reading text and must not
  -- have been dragged up with the word they sit next to.
  eq(("a word list row's meta at %d%%"):format(scale * 100),
    effective(list, firstRow().meta), 10 * scale)
end
eq("and the word outranks its own metadata",
  firstRow().name:GetFontSize() > firstRow().meta:GetFontSize(), true)

-- The quest panel is still not a scaled window, which is the one thing about it
-- that must not change: it sits beside the game's own quest frame and the point
-- is how much text fits.
Addon.SetTextScale(2.0)
eq("the quest panel is never SetScale'd", panel:GetScale(), 1)

-- ---------------------------------------------------------------------------
-- The panel's chrome takes its size from the role and its family from the font
-- object, and those two are separable.
--
-- Today every object happens to carry the size its role does, so a chrome
-- string that had quietly gone back to reading its own object would measure
-- identical and nothing here would notice. Moving one object off its role is
-- what makes the wiring visible: the progress line is drawn with
-- GameFontDisableSmall and its role is anchored elsewhere, so if it follows the
-- object it goes to 20 and if it follows the role it stays at 10.
local realDisable = _G.GameFontDisableSmall
_G.GameFontDisableSmall = { GetFont = function() return "FRIZQT__.TTF", 20, "" end }
Addon.SetTextScale(1.0)
Addon.ApplyIntegratedLayout()
eq("the panel's progress line follows its role, not the object it is drawn with",
  effective(panel, panel.meta), 10)
_G.GameFontDisableSmall = realDisable
Addon.ApplyIntegratedLayout()

-- ---------------------------------------------------------------------------
-- A copy dialog opened from the editor -- the third window in the screenshot.
-- It takes its opener's scale, which is what stops a 150% editor putting up a
-- 100% dialog, and its text area was the fourth thing drawing from the chat
-- font.
setAll(1.5)
Addon.showCopyText("Copy", "text", nil, editor)
local copy = Addon.copyDialog
eq("a dialog opened from the editor takes the editor's scale", copy:GetScale(), 1.5)
eq("and its text box is the body role, not the player's chat size",
  effective(copy, copy.text), 18)

-- ---------------------------------------------------------------------------
-- Buttons. The complaint said "button size" before it said anything about
-- letters, and no slider ever addressed it: two widgets carried four heights
-- between them at 100%, in windows meant to sit side by side.
eq("the editor's status buttons", editor.statusButtons.new:GetHeight(), Addon.RoleButtonHeight())
eq("the editor's reset button", editor.resetDictionary:GetHeight(), Addon.RoleButtonHeight())
eq("the word list's filter buttons", list.filterButtons.all:GetHeight(), Addon.RoleButtonHeight())
Addon.showConfirm("t", "b", nil, function() end, editor)
eq("the confirmation's buttons", Addon.confirmDialog.cancel:GetHeight(), Addon.RoleButtonHeight())
-- Two windows at one setting therefore draw one button height on screen, which
-- is the whole of the complaint's first half.
eq("two windows at one setting show one button height",
  editor.statusButtons.new:GetHeight() * editor:GetScale(),
  list.filterButtons.all:GetHeight() * list:GetScale())

-- ---------------------------------------------------------------------------
-- The colour hazard, held two ways.
--
-- Nothing above would notice if a role had been applied by swapping a string's
-- font object: the sizes would come out identical and a dozen strings would
-- have quietly changed colour, because the Normal family is gold, Highlight is
-- white and DisableSmall is grey. So the colour is read off the string as a
-- real value, and the mechanism is watched as well -- a recolour by either
-- route has to be caught.
local function colorOf(fs) local r, g, b = fs:GetTextColor() return { r, g, b } end
local function sameColor(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

local gold = node():CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
assert(sameColor(colorOf(gold), { 1, 0.82, 0 }), "the stub lost the gold")
Addon.ApplyFontRole(gold, "heading")
eq("a gold caption really did re-size", gold:GetFontSize(), 16)
assert(sameColor(colorOf(gold), { 1, 0.82, 0 }),
  "a gold caption came back a different colour after a re-size")

local white = node():CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
Addon.ApplyFontRole(white, "body")
assert(sameColor(colorOf(white), { 1, 1, 1 }), "a white row name came back another colour")

local probe = node()
probe:SetFontObject("GameFontDisableSmall")
local beforePath = select(1, probe:GetFont())
local swapped = false
probe.SetFontObject = function() swapped = true end
Addon.ApplyFontRole(probe, "body")
eq("a role sets the size", probe:GetFontSize(), 12)
eq("off the string's own font, so the colour it came with is untouched",
  select(1, probe:GetFont()), beforePath)
assert(not swapped, "a role must never swap a string's font object: that changes its colour")

-- A string with no font of its own has nothing to re-font, and must be left
-- alone rather than given an invented one.
local bare = node()
Addon.ApplyFontRole(bare, "body")
eq("a string with no font is left alone", bare:GetFontSize(), nil)

print("font roles ok")
