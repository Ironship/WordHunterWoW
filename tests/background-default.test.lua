-- Run from the addon root:  lua tests/background-default.test.lua
--
-- The panel starts in a different skin on Classic, where the whole interface is
-- the old tooltip frame and the midnight style looks bolted on. Only the
-- default moves: a player who has picked a style keeps it on both games, which
-- is the part worth guarding -- a "default" that quietly overrides a stored
-- choice is a bug, not a theme.

strlower = string.lower
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
time = os.time
GetLocale = function() return "deDE" end

dofile("Core.lua")
dofile("Compat.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.GetBackgroundStyle and Addon.Compat, "Core.lua and Compat.lua must both be loaded")

local function onGame(projectId, mainline)
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = projectId, mainline
  C_Seasons, Enum = nil, nil
  Addon.Compat.Refresh()
end

-- no stored choice ------------------------------------------------------------
WordHunterWoWDB = { settings = {} }

onGame(1, 1)
assert(Addon.GetBackgroundStyle() == "midnight",
  "Retail should still start on midnight, got " .. Addon.GetBackgroundStyle())

onGame(2, 1)
assert(Addon.GetBackgroundStyle() == "tooltip",
  "Classic should start on the tooltip skin, got " .. Addon.GetBackgroundStyle())
assert(Addon.BACKGROUNDS.tooltip.name:find("Classic Dark", 1, true),
  "the Classic default should be the style presented as Classic Dark")

-- Season of Discovery is Classic too, and must not fall back to Retail's.
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
C_Seasons = { GetActiveSeason = function() return 2 end }
Addon.Compat.Refresh()
assert(Addon.Compat.IsSeasonOfDiscovery())
assert(Addon.GetBackgroundStyle() == "tooltip", "SoD should get the Classic default")

-- a stored choice wins on both ------------------------------------------------
WordHunterWoWDB.settings.background = "dialog"
onGame(2, 1)
assert(Addon.GetBackgroundStyle() == "dialog", "Classic must not override a stored choice")
onGame(1, 1)
assert(Addon.GetBackgroundStyle() == "dialog", "Retail must not override a stored choice")

-- and a stored value that is not a real style falls back rather than breaking
WordHunterWoWDB.settings.background = "no-such-style"
onGame(2, 1)
assert(Addon.GetBackgroundStyle() == "tooltip", "an unknown stored style should fall back")

-- Without the compatibility layer -- an older load order, or the file missing --
-- the addon must still answer, and answer the way it always did.
local saved = Addon.Compat
Addon.Compat = nil
WordHunterWoWDB.settings.background = nil
assert(Addon.GetBackgroundStyle() == "midnight",
  "with no compatibility layer the answer must be the original default")
Addon.Compat = saved

print("background-default: ok")

-- The read side alone was not enough: initializeDatabase stamps a value into
-- the settings on first run, and while it stamped "midnight" unconditionally
-- the branch above could never be reached in a real game. Both sides now come
-- from one function, and this is what proves it.
-- Stamped at the current schema version on purpose, so the migration below is
-- skipped and this tests the seed alone. Without that the migration repairs a
-- bad seed and the assertion passes either way -- which it did, the first time
-- this was written.
Addon.Compat = saved
WordHunterWoWDB = { version = 11 }
onGame(2, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "tooltip",
  "a fresh Classic database should be seeded with the Classic default, got "
  .. tostring(WordHunterWoWDB.settings.background))

WordHunterWoWDB = { version = 11 }
onGame(1, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "midnight",
  "a fresh Retail database must be seeded exactly as before")

-- An install carrying the old unconditional stamp is migrated once, because on
-- Classic that value cannot be a real choice: the addon was never released
-- there. A style the player actually picked is left alone.
WordHunterWoWDB = { version = 10, settings = { background = "midnight" } }
onGame(2, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "tooltip", "the old stamp should be migrated on Classic")
assert(WordHunterWoWDB.version == 11, "the migration must move the schema version forward")

WordHunterWoWDB = { version = 10, settings = { background = "dialog" } }
onGame(2, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "dialog", "a chosen style must survive the migration")

-- and Retail is not touched by it at all
WordHunterWoWDB = { version = 10, settings = { background = "midnight" } }
onGame(1, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "midnight", "Retail installs must not be migrated")

-- running twice must not undo the player's next choice
onGame(2, 1)
WordHunterWoWDB = { version = 10, settings = { background = "midnight" } }
Addon.initializeDatabase()
WordHunterWoWDB.settings.background = "midnight"   -- the player picks it deliberately
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "midnight",
  "once migrated, a deliberate midnight on Classic must stick")

print("background-default: seeding and migration ok")
