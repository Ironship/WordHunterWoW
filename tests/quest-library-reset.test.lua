-- Run from the addon root: lua tests/quest-library-reset.test.lua
-- /whw reset must put the quest library back where it started, like every
-- other window: a library dragged off-screen is just as unrecoverable.
dofile('tests/wowstub.lua')
dofile('Core.lua')
dofile('Compat.lua')
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
-- Ordinary (npc) context: no game quest windows open in this harness.
QuestFrame, WorldMapFrame = nil, nil
local ctx = A.GetLayoutContext()
local def = A.LAYOUT_DEFAULTS[ctx] and A.LAYOUT_DEFAULTS[ctx].quests
assert(def, 'no quests default for layout context ' .. tostring(ctx))
-- A library the player dragged off the edge of the screen, with the bad
-- geometry saved. Explicit geometry methods: the stub fabricates answers for
-- methods it is not given, so only methods stubbed here prove anything.
local placed = {}
A.questsFrame = {
  ClearAllPoints = function(self) placed.cleared = true end,
  SetPoint = function(self, point, parent, rel, x, y)
    placed.point, placed.rel, placed.x, placed.y = point, rel, x, y
  end,
  SetSize = function(self, w, h) placed.w, placed.h = w, h end,
}
WordHunterWoWDB.settings.frames[A.LayoutKey('quests')] =
  { point = 'TOPRIGHT', relPoint = 'TOPRIGHT', x = -9000, y = -9000, w = 560, h = 460 }
A.ResetLayout()
assert(next(WordHunterWoWDB.settings.frames) == nil, 'the reset clears the saved geometry')
assert(placed.cleared, 'the reset must move the library window itself, not just forget its record')
assert(placed.point == def.point and placed.rel == (def.relPoint or def.point)
  and placed.x == def.x and placed.y == def.y,
  'the reset must put the library back at its default position')
assert(placed.w == def.w and placed.h == def.h,
  'the reset must put the library back at its default size')
print('quest-library reset: ok')
