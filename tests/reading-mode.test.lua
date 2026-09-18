-- Run from the addon root:  lua tests/reading-mode.test.lua
--
-- Reading mode: the panel large and centred, the game dimmed behind it.
--
-- It is a layout context and not a size the panel is pushed to, and that is the
-- whole design. SaveFramePosition stores a frame's size as well as its place,
-- so a mode that resized the existing window would have the new size written
-- back on the way past and hand the player a larger panel every session --
-- a fault this project has already paid for once. A context has its own
-- remembered geometry, so the panel somebody dragged into a corner is still in
-- that corner when they come out.
--
-- Every assertion below is made once where it should hold and once where it
-- should not.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }

-- No quest frame and no quest log, so the ordinary answer is "npc".
QuestFrame, WorldMapFrame = nil, nil

-- --- made on demand ---------------------------------------------------------
-- Checked first, because it can only be checked once: a player who never turns
-- reading mode on should not carry a full-screen frame for the whole session,
-- and every SetReadingMode(true) below would make one.
assert(Addon.readingDim == nil, "the dimmer must not exist before it is needed")
Addon.ApplyReadingDim()
assert(Addon.readingDim == nil, "and must not be made just to be hidden")

-- --- the context is the mechanism -------------------------------------------
assert(Addon.GetReadingMode() == false, "reading mode starts off")
assert(Addon.GetLayoutContext() == "npc",
  "without it the context is unchanged, got " .. Addon.GetLayoutContext())

Addon.SetReadingMode(true)
assert(Addon.GetReadingMode(), "the setter did not take")
assert(Addon.GetLayoutContext() == "reading",
  "reading mode has to be its own context, got " .. Addon.GetLayoutContext())
assert(Addon.LayoutKey("panel") == "panel:reading",
  "and the panel's saved key has to follow it, got " .. Addon.LayoutKey("panel"))

Addon.SetReadingMode(false)
assert(Addon.GetLayoutContext() == "npc", "leaving it puts the context back")
assert(Addon.LayoutKey("panel") == "panel:npc", "and the key with it")

-- --- it beats the observations ----------------------------------------------
-- The other contexts are read off what the game is showing. Reading mode is a
-- choice, so it wins over both -- otherwise opening a quest giver would drop
-- the player out of it mid-paragraph.
QuestFrame = { IsShown = function() return true end }
assert(Addon.GetLayoutContext() == "npc", "a quest giver is npc")
Addon.SetReadingMode(true)
assert(Addon.GetLayoutContext() == "reading",
  "a quest giver must not pull the player out of reading mode")
Addon.SetReadingMode(false)
QuestFrame = nil

-- --- the geometry is a real one ---------------------------------------------
local reading = Addon.LAYOUT_DEFAULTS.reading
assert(reading and reading.panel, "reading mode has no panel default")
local npc = Addon.LAYOUT_DEFAULTS.npc.panel
assert(reading.panel.w > npc.w,
  "the reading panel has to be wider than the ordinary one: "
  .. reading.panel.w .. " vs " .. npc.w)
assert(reading.panel.h > npc.h, "and taller")
assert(reading.panel.point == "CENTER", "and centred")
-- Every context has to carry a default for every window PlaceFrame is called
-- with, or the call silently does nothing and the window stays where the last
-- context left it.
for key in pairs(Addon.LAYOUT_DEFAULTS.npc) do
  assert(reading[key], "reading mode has no default for " .. key)
end

-- --- the two geometries are remembered apart ---------------------------------
-- The point of a context. A panel dragged while reading must not move the
-- panel the player uses beside the game.
WordHunterWoWDB.settings.frames = {}
-- Shaped the way SaveFramePosition reads a frame: GetPoint(1) and GetSize().
local function fakeFrame(point, x, y, w, h)
  return {
    GetPoint = function() return point, nil, point, x, y end,
    GetSize = function() return w, h end,
  }
end
Addon.SaveFramePosition(fakeFrame("CENTER", 5, 6, 980, 660), "panel:reading")
Addon.SaveFramePosition(fakeFrame("LEFT", 1, 2, 430, 240), "panel:npc")
local frames = WordHunterWoWDB.settings.frames
assert(frames["panel:reading"] and frames["panel:npc"], "both keys should be stored")
assert(frames["panel:reading"].w == 980 and frames["panel:npc"].w == 430,
  "the two sizes must not overwrite each other")

-- --- the dimmer follows the panel, not the setting ---------------------------
-- Switching reading mode on while standing in a town must darken nothing:
-- there is no quest on screen to read. It did, the first time this was built,
-- and the owner saw it before anyone had spoken to a quest giver.
Addon.panel = nil
Addon.SetReadingMode(true)
Addon.ApplyReadingDim()
assert(Addon.readingDim == nil or Addon.readingDim.shown == false,
  "reading mode with no panel on screen must not dim the game")

-- A panel that exists but is closed is the same case.
-- Enough of a frame for PlaceFrame to put down without complaint: it is called
-- whenever the mode changes, and a panel that cannot be placed would fail the
-- test for a reason that has nothing to do with dimming.
local fakePanel = { shown = false }
function fakePanel:IsShown() return self.shown end
function fakePanel:ClearAllPoints() end
function fakePanel:SetPoint() end
function fakePanel:SetSize() end
function fakePanel:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
function fakePanel:GetSize() return 980, 660 end
Addon.panel = fakePanel
Addon.ApplyReadingDim()
assert(Addon.readingDim == nil or Addon.readingDim.shown == false,
  "a closed panel must not dim the game either")

-- Open it, and now there is something to read.
fakePanel.shown = true
Addon.ApplyReadingDim()
local dim = Addon.readingDim
assert(dim, "an open panel in reading mode made no dimmer")
assert(dim.shown ~= false, "the dimmer should be showing")

-- And closing the panel takes the dim away without leaving reading mode.
fakePanel.shown = false
Addon.ApplyReadingDim()
assert(dim.shown == false, "closing the panel has to undim the game")
assert(Addon.GetReadingMode(), "but must not switch reading mode off")
fakePanel.shown = true
Addon.ApplyReadingDim()
-- Not asserted here: that the dimmer takes no mouse input. It must not -- a
-- full-screen frame swallowing clicks would put the quest's own accept button
-- out of reach, which is the one thing a reading mode cannot do -- but the stub
-- fabricates EnableMouse and would answer whatever the assertion hoped for.
-- A test that cannot fail is worse than none, so this one is left to the eye.

Addon.SetReadingMode(false)
Addon.ApplyReadingDim()
assert(dim.shown == false, "leaving reading mode has to hide the dimmer")

print("reading-mode: ok")
