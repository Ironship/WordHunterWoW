-- Run from the addon root:  lua tests/panel-width.test.lua
--
-- The panel kept losing the width it had been dragged out to.
--
-- Turning the English column off leaves a window sized for two columns showing
-- one, so it is brought back down to the default. That is right. What was wrong
-- is when it ran: the layout is reapplied on every quest read, so a
-- single-column window the player had widened by hand was snapped back to
-- 430x240 the next time they talked to anyone. Together with a resize that
-- could get stuck on, this is the window that "sometimes bigger, sometimes
-- smaller".

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

-- Single column, widened by hand. Reading quest after quest must leave it alone.
Addon.SetIntegratedLayout(false)
Addon.ApplyIntegratedLayout()
panel:SetSize(900, 500)
for _ = 1, 3 do Addon.ApplyIntegratedLayout() end
assert(panel:GetWidth() == 900,
  "a hand-widened single-column panel must keep its width across quests, got " .. panel:GetWidth())

-- Turning the second column off is a different matter: the width belonged to a
-- layout that is no longer on screen, so it does come back down.
Addon.SetIntegratedLayout(true)
Addon.ApplyIntegratedLayout()
panel:SetSize(900, 500)
Addon.SetIntegratedLayout(false)
Addon.ApplyIntegratedLayout()
assert(panel:GetWidth() == 430,
  "dropping the second column should bring the width back down, got " .. panel:GetWidth())

-- And having come down, it stays down rather than being reset again.
panel:SetSize(760, 500)
Addon.ApplyIntegratedLayout()
assert(panel:GetWidth() == 760, "and must not keep resetting afterwards, got " .. panel:GetWidth())

-- A width that was never wide enough to be a two-column width is never touched.
Addon.SetIntegratedLayout(true)
Addon.ApplyIntegratedLayout()
panel:SetSize(620, 400)
Addon.SetIntegratedLayout(false)
Addon.ApplyIntegratedLayout()
assert(panel:GetWidth() == 620, "a narrow panel should be left as it is, got " .. panel:GetWidth())

-- Height is the other half of the same complaint, and the sharper one: the
-- panel grows to fit the quest, and that ran over a height the player had
-- dragged to. The guard for it looked under the bare key "panel" while sizes
-- are saved per layout context, so it never found anything and never held.
--
-- Landing 0.15s after the drag ends -- once the relayout was debounced -- this
-- is the window jumping a moment after you let go of the corner.
local key = Addon.LayoutKey("panel")
WordHunterWoWDB.settings.frames = {}
Addon.readCurrentQuest()
panel:SetSize(900, 700)
Addon.refreshPanel()
assert(panel:GetHeight() ~= 700,
  "with no size of the player's own the panel should still grow to fit the quest")

WordHunterWoWDB.settings.frames[key] = { w = 900, h = 700, userSized = true }
panel:SetSize(900, 700)
Addon.refreshPanel()
assert(panel:GetHeight() == 700,
  "a height the player dragged to must survive a refresh, got " .. panel:GetHeight())

-- Saved under the context-qualified key, which is where it is written. Reading
-- the bare name found nothing, which is how this went unnoticed.
assert(WordHunterWoWDB.settings.frames["panel"] == nil,
  "sizes are not stored under the bare key, so nothing should read them there")

print("panel-width: ok")
