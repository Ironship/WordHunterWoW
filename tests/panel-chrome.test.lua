-- Run from the addon root:  lua tests/panel-chrome.test.lua
--
-- The quest panel scaled its words and nothing else. "Quest panel text" re-fonts
-- every token and grows the rows under them, but the title above the text, the
-- progress line, the legend along the bottom and the buttons beside it were
-- created once with a fixed font object and never touched again -- so at 200%
-- the panel was a large paragraph inside small furniture, and next to the word
-- editor, which is scaled whole and grows uniformly, it read as two windows
-- stuck together.
--
-- The part that is easy to get wrong is not the font, and it is not the same
-- trap the rows were. Every offset in this window is measured down from the top
-- or up from the bottom: growing the title's letters without growing its 21px
-- box clips them, and growing the box without moving the -36 the progress line
-- sits at drops the line on top of the title. Font, box and offset have to move
-- together or the panel is worse at 200% than it was before.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

-- The second column only exists when there is English text to put in it.
WordHunterWoW_QuestEN = {}
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
local panel = Addon.panel

local function size(scale, enScale)
  Addon.SetTextScale(scale)
  Addon.SetEnPanelTextScale(enScale or scale)
  Addon.ApplyIntegratedLayout()
end

local function y(frame, point)
  local _, value = frame:GetAnchor(point)
  return value
end

-- ---------------------------------------------------------------------------
-- At 100% nothing may have moved.
--
-- This is a rewrite of a layout that was written out as literal offsets, and
-- the only honest way to make that safe is to pin the numbers it used to
-- produce. Every figure below is read off the constructor as it stood.
size(1.0)
panel:SetSize(720, 500)
Addon.ApplyIntegratedLayout()
local function at(what, frame, point, expected)
  local value = y(frame, point)
  assert(value == expected,
    ("%s %s should still be at %s, got %s"):format(what, point, expected, tostring(value)))
end
at("the title", panel.title, "TOPLEFT", -12)
at("the English heading", panel.enTitle, "TOPLEFT", -12)
at("the quest text", panel.scroll, "TOPLEFT", -36)
at("the English column", panel.enScroll, "TOPLEFT", -36)
at("the quest text's bottom", panel.scroll, "BOTTOMRIGHT", 72)
at("the rule between the columns", panel.divider, "TOP", -52)
at("the footer rule", panel.footerLine, "BOTTOMLEFT", 67)
at("the progress line", panel.meta, "BOTTOMLEFT", 15)
assert(panel.title.h == 21, "the title's box was 21 tall, got " .. tostring(panel.title.h))
assert(panel.meta.h == 14, "the progress line's box was 14 tall, got " .. tostring(panel.meta.h))
for index, item in ipairs(panel.legend) do
  local x, dotY = item.dot:GetAnchor("BOTTOMLEFT")
  assert(x == 18 + (index - 1) * 96 and dotY == 50,
    ("legend dot %d has moved: (%s,%s)"):format(index, tostring(x), tostring(dotY)))
  assert(item.dot.w == 7 and item.dot.h == 7, "the dots were 7x7")
end
assert(panel.actions[1].w == 118 and panel.actions[1].h == 26, "Copy quest text was 118x26")
assert(panel.actions[2].w == 52 and panel.actions[2].h == 26, "Words was 52x26")

-- ---------------------------------------------------------------------------
-- The font, the box and the offset, all three.
--
-- Any one of them alone is a worse panel than the one being fixed: letters
-- without a box are clipped, a box without an offset overlaps the line under it,
-- and an offset without either is a gap.
local titleAt = {}
for _, scale in ipairs({ 1.0, 2.0 }) do
  size(scale)
  titleAt[scale] = {
    font = panel.title:GetFontSize(),
    box = panel.title.h,
    top = y(panel.title, "TOPLEFT"),
    under = y(panel.scroll, "TOPLEFT"),
  }
end
assert(titleAt[2.0].font == titleAt[1.0].font * 2,
  ("the title has to grow with the setting, got %s then %s")
    :format(titleAt[1.0].font, titleAt[2.0].font))
assert(titleAt[2.0].box == titleAt[1.0].box * 2,
  ("and its box with it, or the letters are clipped: %s then %s")
    :format(titleAt[1.0].box, titleAt[2.0].box))
-- Offsets run downwards, so "further down" is more negative.
assert(titleAt[2.0].under <= titleAt[1.0].under - (titleAt[2.0].box - titleAt[1.0].box),
  ("the text under the title has to move down by at least what the title gained, %s then %s")
    :format(titleAt[1.0].under, titleAt[2.0].under))
assert(titleAt[2.0].top < titleAt[1.0].top,
  ("the space above it grows too, or a doubled title sits tight under the border, %s then %s")
    :format(titleAt[1.0].top, titleAt[2.0].top))

-- The progress line is the string the growing title used to land on, and it is
-- the one the player watches change as they mark words.
local metaAt = {}
for _, scale in ipairs({ 1.0, 2.0 }) do
  size(scale)
  metaAt[scale] = { font = panel.meta:GetFontSize(), box = panel.meta.h,
    bottom = y(panel.meta, "BOTTOMLEFT") }
end
assert(metaAt[2.0].font == metaAt[1.0].font * 2, "the progress line follows the setting too")
assert(metaAt[2.0].box == metaAt[1.0].box * 2, "so does the box it is drawn in")
assert(metaAt[2.0].bottom > metaAt[1.0].bottom,
  "and it lifts off the bottom edge with the buttons beside it")
-- Bounded on the right in both arrangements. It shares the footer with three
-- buttons that are now twice as wide, and a progress line free to run as far as
-- it likes goes straight under them.
assert(select(1, panel.meta:GetAnchor("BOTTOMRIGHT")) ~= nil,
  "the progress line needs a right-hand edge to stop at in the two-column layout")
Addon.SetIntegratedLayout(false)
size(2.0)
assert(select(1, panel.meta:GetAnchor("TOPRIGHT")) ~= nil,
  "and one in the single-column layout")
Addon.SetIntegratedLayout(true)
size(1.0)

-- ---------------------------------------------------------------------------
-- The legend and the buttons along the bottom, and the room they take from the
-- text above them.
local footAt = {}
for _, scale in ipairs({ 1.0, 2.0 }) do
  size(scale)
  panel:SetSize(720, 500)
  Addon.ApplyIntegratedLayout()
  footAt[scale] = {
    legendFont = panel.legend[1].text:GetFontSize(),
    dot = panel.legend[1].dot.w,
    dotY = select(2, panel.legend[1].dot:GetAnchor("BOTTOMLEFT")),
    caption = panel.actions[1]:GetFontString():GetFontSize(),
    buttonW = panel.actions[1].w,
    buttonH = panel.actions[1].h,
    band = y(panel.scroll, "BOTTOMRIGHT"),
    rule = y(panel.footerLine, "BOTTOMLEFT"),
  }
end
assert(footAt[2.0].legendFont == footAt[1.0].legendFont * 2, "the legend's labels follow the setting")
assert(footAt[2.0].dot == footAt[1.0].dot * 2, "and the colour dots beside them")
assert(footAt[2.0].dotY > footAt[1.0].dotY, "the legend row lifts as the buttons under it grow")
assert(footAt[2.0].caption == footAt[1.0].caption * 2, "the buttons' captions follow it as well")
assert(footAt[2.0].buttonW == footAt[1.0].buttonW * 2 and footAt[2.0].buttonH == footAt[1.0].buttonH * 2,
  "and their boxes, or the caption grows out of the button")
assert(footAt[2.0].rule > footAt[1.0].rule, "the rule above the legend rises with it")
-- The one that matters most: a footer that grew while the text above it did not
-- stop any higher is a footer drawn over the last two lines of the quest.
assert(footAt[2.0].band >= footAt[1.0].band + (footAt[2.0].rule - footAt[1.0].rule),
  ("the text has to stop above the taller footer, got %s then %s")
    :format(footAt[1.0].band, footAt[2.0].band))

-- ---------------------------------------------------------------------------
-- The legend has to stay inside the window, and inside itself.
--
-- Its four entries used to be stepped at a flat 96px, which is the width of the
-- longest label at 100% and nothing at any other size: at twice that the labels
-- are wider than the step past them, so each dot lands inside the label before
-- it. Wider still and the row walks off the right-hand edge of the panel, where
-- there is no scrolling and no way to know it is there.
local function checkLegend(where)
  local rows = {}
  for index, item in ipairs(panel.legend) do
    local x, dotY = item.dot:GetAnchor("BOTTOMLEFT")
    local entry = { left = x, right = x + item.dot.w + item.text:GetStringWidth() }
    assert(entry.right <= panel:GetWidth() - 18,
      ("%s: legend entry %d runs off the panel, ends at %.0f of %s")
        :format(where, index, entry.right, panel:GetWidth()))
    local row = rows[dotY]
    if row then
      assert(entry.left >= row.right,
        ("%s: legend entry %d starts at %.0f, inside the one before it, which ends at %.0f")
          :format(where, index, entry.left, row.right))
    end
    rows[dotY] = entry
  end
  local ys = {}
  for value in pairs(rows) do ys[#ys + 1] = value end
  table.sort(ys)
  return ys
end

Addon.SetIntegratedLayout(false)
size(1.0)
panel:SetSize(400, 300)
Addon.ApplyIntegratedLayout()
assert(#checkLegend("100% on the narrowest panel") == 1,
  "at 100% the four entries have always shared one row and must go on doing so")
size(2.0)
panel:SetSize(720, 500)
Addon.ApplyIntegratedLayout()
checkLegend("200% on a wide panel")
panel:SetSize(400, 300)
Addon.ApplyIntegratedLayout()
local ys = checkLegend("200% on the narrowest panel")
assert(#ys > 1, "four entries this size cannot share one row of a 400px panel")
-- And a second row has to be given room rather than drawn over the first.
assert(ys[2] - ys[1] >= panel.legend[1].dot.h,
  "two legend rows must not overlap, they are " .. (ys[2] - ys[1]) .. " apart")

-- These four words are translated. A language whose word for "Learning" runs to
-- three times the length is not a hypothetical -- LABELS exists so that one
-- person can replace the lot of them -- and a step wide enough for the English
-- set is not a step, it is a coincidence that holds in one language.
for _, item in ipairs(panel.legend) do item.text:SetText("Noch nicht gelernt") end
size(1.0)
panel:SetSize(720, 500)
Addon.ApplyIntegratedLayout()
checkLegend("long labels at 100%")
size(2.0)
Addon.ApplyIntegratedLayout()
checkLegend("long labels at 200%")
for index, status in ipairs({ "new", "learning", "known", "ignored" }) do
  panel.legend[index].text:SetText(Addon.STATUS_LABELS[status])
end
Addon.SetIntegratedLayout(true)

-- ---------------------------------------------------------------------------
-- Each column's heading follows its own column.
--
-- The two columns are already sized by two different settings. A heading tied
-- to the wrong one is the very fault this fixes, moved one column across: turn
-- "English text" up and the English column grows under a heading that did not.
size(2.0, 1.0)
assert(panel.title:GetFontSize() == 32 and panel.enTitle:GetFontSize() == 16,
  ("the quest setting must move only its own heading, got %s and %s")
    :format(panel.title:GetFontSize(), panel.enTitle:GetFontSize()))
size(1.0, 2.0)
assert(panel.title:GetFontSize() == 16 and panel.enTitle:GetFontSize() == 32,
  ("and the English setting only the English one, got %s and %s")
    :format(panel.title:GetFontSize(), panel.enTitle:GetFontSize()))
assert(panel.enTitle.h == panel.title.h * 2,
  ("the English heading's box follows its own setting as well, got %s against %s")
    :format(tostring(panel.enTitle.h), tostring(panel.title.h)))
assert(y(panel.enScroll, "TOPLEFT") < y(panel.scroll, "TOPLEFT"),
  "the taller heading's column has to start lower than the other one")
-- The rule between the columns starts below both of them. Measured from the
-- quest side alone it would begin level with the taller heading's letters and
-- draw a line up the side of them.
assert(y(panel.divider, "TOP") <= math.min(y(panel.enScroll, "TOPLEFT"), y(panel.scroll, "TOPLEFT")),
  ("the rule has to clear the deeper of the two headings, rule at %s against %s")
    :format(y(panel.divider, "TOP"), y(panel.enScroll, "TOPLEFT")))
size(1.0)

-- ---------------------------------------------------------------------------
-- The slider has to move the chrome now, not on the next quest.
--
-- A player drags a slider with the panel open in front of them. Re-fonting the
-- words on the spot and leaving the title until the next quest is read is the
-- same complaint in slower motion, and it is worse to watch: half the window
-- answers and half does not.
GetQuestText = function() return "Bringt acht Stuecke zaehes Wolfsfleisch zurueck zu mir" end
GetObjectiveText = function() return "" end
QuestFrame:Show()
Addon.readCurrentQuest()
assert(panel:IsShown(), "the panel should be up for the rest of this")
local before = { title = panel.title:GetFontSize(), meta = panel.meta:GetFontSize(),
  legend = panel.legend[1].text:GetFontSize() }
-- No second read of the quest: only the setting moves.
Addon.SetTextScale(2.0)
assert(panel.title:GetFontSize() == before.title * 2, "the title should answer the slider at once")
assert(panel.meta:GetFontSize() == before.meta * 2, "so should the progress line")
assert(panel.legend[1].text:GetFontSize() == before.legend * 2, "and the legend")

-- The English half of the same thing. That setting reaches the separate English
-- window through ApplyWindowScale, and the column inside this panel is drawn
-- here rather than there -- so nothing was telling this panel anything at all.
local enBefore = panel.enTitle:GetFontSize()
Addon.SetEnPanelTextScale(2.0)
assert(panel.enTitle:GetFontSize() == enBefore * 2,
  ("the English column's heading should answer its own slider at once, got %s then %s")
    :format(enBefore, panel.enTitle:GetFontSize()))

-- ---------------------------------------------------------------------------
-- The window grows to fit the quest, and the furniture is part of what has to
-- fit. That allowance was a flat 136 measured once at 100%.
WordHunterWoWDB.settings.frames = {}
local heightAt = {}
for _, scale in ipairs({ 1.0, 2.0 }) do
  Addon.SetTextScale(scale)
  Addon.SetEnPanelTextScale(scale)
  Addon.readCurrentQuest()
  heightAt[scale] = { panel = panel:GetHeight(), content = panel.content:GetHeight(),
    chrome = panel.chromeHeight }
end
assert(heightAt[2.0].chrome > heightAt[1.0].chrome,
  "the chrome itself is taller at twice the size")
assert(heightAt[2.0].panel - heightAt[2.0].content >= heightAt[2.0].chrome,
  ("the window has to leave room for its own furniture: %s - %s is under %s")
    :format(heightAt[2.0].panel, heightAt[2.0].content, heightAt[2.0].chrome))
-- And the corner cannot be dragged down over it either.
assert(type(panel.chromeMinHeight) == "number" and panel.chromeMinHeight >= heightAt[2.0].chrome,
  "the resize floor has to clear the chrome, got " .. tostring(panel.chromeMinHeight))

print("panel-chrome: ok")
