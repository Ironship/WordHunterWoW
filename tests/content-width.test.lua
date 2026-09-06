-- Run from the addon root:  lua tests/content-width.test.lua
--
-- The words were laid out into a frame wider than the pane that shows them, so
-- the right-hand end of every full line was clipped: drawn, counted, and not on
-- screen.
--
-- Two numbers described the same column and neither knew about the other. The
-- pane is anchored with one pair of insets in the layout; the content was sized
-- from the panel's width less an inset written out by hand somewhere else. In
-- the single-column layout the pane comes out 50px narrower than the panel and
-- the content 48, so two pixels were lost from every line -- small enough that
-- nobody reported it and constant enough that it was always there. The floor in
-- that same expression makes it much worse when the window is dragged narrow:
-- the content stops shrinking at 200 while the pane keeps going, and at the
-- 400px resize minimum in two columns a 200px content sits in a 160px pane.
--
-- Measured against the pane rather than against the formula, because the
-- formula is the thing that was wrong. A test that re-derived the expected
-- width the same way the code does would have agreed with the bug.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

-- Without the log's own text every read comes back empty and refreshPanel
-- returns before it sizes anything, so the assertions below would pass on air.
GetQuestLogQuestText = function()
  return "Ein Bote wartet am Tor und traegt eine Nachricht.", "Sprecht mit dem Boten."
end
QuestMapFrame_GetDetailQuestID = function() return 184 end

WordHunterWoW_QuestEN = { [184] = "A messenger waits at the gate." }
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
local panel = Addon.panel
panel:Show()

-- The stub resolves no anchors, so a pane's width is whatever it is told. That
-- is the whole input here: the code under test may not assume a pane is as wide
-- as it would like it to be.
local function paneIs(wide, enWide)
  panel.scroll.w = wide
  if panel.enScroll then panel.enScroll.w = enWide or wide end
end

local function render()
  Addon.readCurrentQuest(184)
end

local function check(label)
  local pane, content = panel.scroll:GetWidth(), panel.content:GetWidth()
  assert(content <= pane,
    ("%s: the words are laid out %d wide in a %d pane -- %d px of every full "
     .. "line is clipped"):format(label, content, pane, content - pane))
  if panel.enContent and panel.enScroll:IsShown() then
    local enPane, enContent = panel.enScroll:GetWidth(), panel.enContent:GetWidth()
    assert(enContent <= enPane,
      ("%s: the English is laid out %d wide in a %d pane"):format(label, enContent, enPane))
  end
end

-- One column, at the width the panel opens at. -------------------------------
Addon.SetIntegratedLayout(false)
paneIs(382)
render()
check("one column, default width")

-- One column, dragged to the 400px resize minimum. ---------------------------
paneIs(350)
render()
check("one column, narrowest the panel goes")

-- Two columns, where the floor in the old expression bites hardest. ----------
Addon.SetIntegratedLayout(true)
paneIs(160, 162)
render()
check("two columns, narrowest the panel goes")

-- A pane that cannot say how wide it is yet keeps whatever the panel guessed,
-- rather than collapsing the column to nothing on the first render.
paneIs(0, 0)
render()
assert(panel.content:GetWidth() > 0,
  "an unmeasured pane collapsed the column instead of leaving the guess alone")

-- Room to grow is not taken away. A pane wider than the text needs must leave
-- the content where the panel put it, or the clamp has quietly become the rule.
Addon.SetIntegratedLayout(false)
paneIs(4000)
render()
assert(panel.content:GetWidth() < 4000,
  "the content was stretched to the pane instead of being clamped by it")

print("content-width: ok")
