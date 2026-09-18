-- Run from the addon root:  lua tests/background-default.test.lua
--
-- A fresh install opens on parchment, on both games.
--
-- It used to differ per game -- tooltip on Classic, midnight on Retail -- and
-- the split is gone rather than retargeted: UI-DialogBox-Background is the
-- frame a quest giver's text is drawn on in every version of the game, so it
-- belongs on both. What is still worth guarding is the part that has nothing to
-- do with which style it is: a player who has picked one keeps it, on either
-- game, and a "default" that quietly overrides a stored choice is a bug, not a
-- theme. Every assertion below is made once where it should hold and once where
-- it should not.

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
assert(Addon.GetBackgroundStyle() == "dialog",
  "Retail should start on parchment, got " .. Addon.GetBackgroundStyle())

onGame(2, 1)
assert(Addon.GetBackgroundStyle() == "dialog",
  "Classic should start on parchment too, got " .. Addon.GetBackgroundStyle())
assert(Addon.BACKGROUNDS.dialog.name:find("Parchment", 1, true),
  "the default should be the style presented as Parchment")
-- Dark text on light, which is most of the reason for it. Read off the style
-- rather than asserted as a constant: the panel takes its text colour from
-- here, so a style whose readingColor went light would be a different default
-- wearing the same name.
local ink = Addon.BACKGROUNDS.dialog.readingColor
assert(ink and ink[1] < 0.3 and ink[2] < 0.3 and ink[3] < 0.3,
  "parchment has to carry dark reading ink")

-- Season of Discovery is Classic too, and must not fall back to Retail's.
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
C_Seasons = { GetActiveSeason = function() return 2 end }
Addon.Compat.Refresh()
assert(Addon.Compat.IsSeasonOfDiscovery())
assert(Addon.GetBackgroundStyle() == "dialog", "SoD gets parchment like everything else")

-- a stored choice wins on both ------------------------------------------------
WordHunterWoWDB.settings.background = "dialog"
onGame(2, 1)
assert(Addon.GetBackgroundStyle() == "dialog", "Classic must not override a stored choice")
onGame(1, 1)
assert(Addon.GetBackgroundStyle() == "dialog", "Retail must not override a stored choice")

-- and a stored value that is not a real style falls back rather than breaking
WordHunterWoWDB.settings.background = "no-such-style"
onGame(2, 1)
assert(Addon.GetBackgroundStyle() == "dialog", "an unknown stored style should fall back")
onGame(1, 1)
assert(Addon.GetBackgroundStyle() == "dialog", "and fall back the same way on Retail")

-- Without the compatibility layer -- an older load order, or the file missing --
-- the addon must still answer, and the answer no longer depends on it at all,
-- which is the point of collapsing the two branches into one.
local saved = Addon.Compat
Addon.Compat = nil
WordHunterWoWDB.settings.background = nil
assert(Addon.GetBackgroundStyle() == "dialog",
  "with no compatibility layer the answer must still be parchment")
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
assert(WordHunterWoWDB.settings.background == "dialog",
  "a fresh Classic database should be seeded with parchment, got "
  .. tostring(WordHunterWoWDB.settings.background))

WordHunterWoWDB = { version = 11 }
onGame(1, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "dialog",
  "a fresh Retail database must be seeded with parchment too, got "
  .. tostring(WordHunterWoWDB.settings.background))

-- An install carrying the old unconditional stamp is migrated once, because on
-- Classic that value cannot be a real choice: the addon was never released
-- there. A style the player actually picked is left alone -- and Retail, where
-- midnight was both the stamp and a style somebody could have chosen on
-- purpose, is not migrated at all. That is why this change does not reach an
-- existing profile: only a fresh one, and a Classic one that never had a say.
WordHunterWoWDB = { version = 10, settings = { background = "midnight" } }
onGame(2, 1)
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.background == "dialog", "the old stamp should be migrated on Classic")
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
