-- Run from the addon root:  lua tests/saved-state.test.lua
--
-- What the addon writes to disk, and what it will accept back.
--
-- The saved file is the one thing a player cannot repair. A window restored off
-- the edge of the screen cannot be dragged back; a value that throws while the
-- addon is loading takes the editor, the quest hooks and the settings panel with
-- it, and the only remedy left is deleting the file -- which deletes the word
-- list too.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

-- The legacy `words` key was an alias of the active locale's table. One table in
-- memory, but the saved-variables writer does not preserve identity, so every
-- word and its whole encounter set was written out twice. Nothing has read it
-- since a migration that can no longer run.
Addon.GetWordsTable()["hund"] = { word = "Hund", status = "learning" }
assert(WordHunterWoWDB.words == nil,
  "the legacy words table must not be carried, or every word is saved twice")
assert(WordHunterWoWDB.wordsByLocale.deDE.hund, "the real table still holds the word")

-- Encounter sets are what actually grow without bound: one key per quest, per
-- word, forever, re-parsed at every login. Common words appear in thousands.
local item = { word = "der", status = "known" }
for i = 1, 500 do
  Addon.recordEncounter(item, i, "Quest " .. i, 1000)
end
local kept = 0
for _ in pairs(item.encounteredQuests) do kept = kept + 1 end
assert(kept <= 201, "the encounter set has to be bounded, kept " .. kept)
assert(item.encounterCount == 500,
  "the count itself keeps rising -- it is the memory of which quests that is capped, got "
  .. tostring(item.encounterCount))

-- recordEncounter answers whether this was new. Callers rebuild the export from
-- that answer, and rebuilding costs a sort of the whole word table plus five
-- gsubs per word -- far too much to pay for a quest that changed nothing.
local fresh = { word = "neu" }
assert(Addon.recordEncounter(fresh, 7, "Q", 1000) == true, "a first sighting is new")
assert(Addon.recordEncounter(fresh, 7, "Q", 1000) == false, "the same quest again is not")

-- Geometry is restored while the addon is loading, so anything it will not
-- survive has to be rejected rather than passed to SetPoint.
local placed
local frame = setmetatable({
  ClearAllPoints = function() end,
  SetPoint = function(_, point) placed = point end,
  SetSize = function() end,
}, { __index = function() return function() end end })

local function restore(data)
  placed = nil
  WordHunterWoWDB.settings.frames["panel:npc"] = data
  return Addon.RestoreFramePosition(frame, "panel:npc", "CENTER", 0, 0, 430, 240)
end

assert(restore({ point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 430, h = 240 }),
  "a sane record is used")
assert(placed == "CENTER")

for name, bad in pairs({
  ["an anchor that is not one"] = { point = "MIDDLE", x = 0, y = 0, w = 430, h = 240 },
  ["a size of nothing"] = { point = "CENTER", x = 0, y = 0, w = 1, h = 1 },
  ["a size past any screen"] = { point = "CENTER", x = 0, y = 0, w = 99999, h = 99999 },
  ["coordinates that are not numbers"] = { point = "CENTER", x = "left", y = 0, w = 430, h = 240 },
  ["a table where a number belongs"] = { point = "CENTER", x = 0, y = 0, w = {}, h = 240 },
}) do
  assert(restore(bad) == false, name .. " must be refused")
  assert(placed == "CENTER", name .. " should fall back to the default position")
end

-- And there has to be a way back for a window already saved somewhere useless.
assert(Addon.ResetLayout, "a layout reset has to exist")
WordHunterWoWDB.settings.frames["panel:npc"] = { point = "CENTER", x = -9000, y = 0, w = 430, h = 240 }
Addon.ResetLayout()
assert(next(WordHunterWoWDB.settings.frames) == nil, "the reset clears the saved geometry")

local init = io.open("Init.lua"):read("a")
assert(init:find("Addon.ResetLayout", 1, true), "and it has to be reachable from a slash command")

print("saved-state: ok")
