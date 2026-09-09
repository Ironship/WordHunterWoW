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

-- A first login: no saved variables at all. Every other test in this suite hands
-- initializeDatabase a table that is already most of the way there, so until now
-- nothing ran the branch that builds one from nothing -- and it could not have,
-- because the stub used to manufacture WordHunterWoWDB the moment anything read
-- it, which meant "not a table" was a state no test could put the addon in.
-- This is the path every fresh install takes exactly once, and it is the one
-- where a throw costs the player the editor, the quest hooks and the settings
-- panel at the same time.
assert(rawget(_G, "WordHunterWoWDB") == nil, "this has to start from nothing to mean anything")
-- French, not the stub's German: deDE is also the fallback when the client's
-- language is one the addon does not support, so a deDE client cannot tell the
-- two branches apart and an assertion made on one would pass for the other.
GetLocale = function() return "frFR" end
Addon.initializeDatabase()
local settings = WordHunterWoWDB.settings
assert(type(WordHunterWoWDB) == "table" and type(settings) == "table",
  "a first login has to end up with a database")
assert(settings.targetLocale == "frFR",
  "a first login reads the language the client is in, got " .. tostring(settings.targetLocale))
-- One locale's table, empty: initializeDatabase ends by asking for the target
-- locale's words, so the table a first login will write into already exists.
assert(type(WordHunterWoWDB.wordsByLocale) == "table"
  and type(WordHunterWoWDB.wordsByLocale.frFR) == "table"
  and next(WordHunterWoWDB.wordsByLocale.frFR) == nil,
  "the target locale needs an empty word table, not a missing one")
assert(WordHunterWoWDB.words == nil, "the legacy alias must not be created on a fresh install")
assert(type(settings.frames) == "table", "geometry has somewhere to go")
assert(settings.background == Addon.DefaultBackgroundStyle(),
  "the background falls back to the default, got " .. tostring(settings.background))
assert(settings.opacity == 1.0, "opaque until asked otherwise, got " .. tostring(settings.opacity))
for _, key in ipairs(Addon.TEXT_SCALE_KEYS) do
  assert(settings[key] == 1.0, key .. " should start at 1.0, got " .. tostring(settings[key]))
end
-- Defaults to on: the column inside the quest window is the layout the addon is
-- described by, and a nil here is not the same as false.
assert(settings.integratedLayout == true, "the integrated layout is the one out of the box")
-- Stamped, or every login after this one replays all four migrations.
assert(WordHunterWoWDB.version == 11, "the fresh database is stamped current, got " .. tostring(WordHunterWoWDB.version))

-- And a client in a language the addon has no dictionary for still has to end
-- up somewhere it can work. German is the fallback because it is the language
-- the addon was written for.
WordHunterWoWDB = nil
GetLocale = function() return "koKR" end
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.targetLocale == "deDE",
  "an unsupported client language falls back to German, got "
  .. tostring(WordHunterWoWDB.settings.targetLocale))
GetLocale = function() return "deDE" end

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

local init = io.open("Init.lua"):read("*a")
assert(init:find("Addon.ResetLayout", 1, true), "and it has to be reachable from a slash command")


print("saved-state: ok")
