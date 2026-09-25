-- Run from the addon root:  lua tests/target-locale.test.lua
--
-- A fresh profile learns the language the quest text is shown in. That is the
-- textLocale CVar, not the client's GetLocale(): the Forever beta showed German
-- quest text while GetLocale() answered enUS, the new profile was written as
-- English, and not one word on screen was coloured.

strlower = string.lower
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
time = os.time

local cvars = { textLocale = "deDE" }
GetCVar = function(name) return cvars[name] end
local client = "enUS"
GetLocale = function() return client end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon

local function fresh()
  WordHunterWoWDB = nil
  Addon.initializeDatabase()
  return Addon.GetTargetLocale(), WordHunterWoWDB.settings.targetLocale
end

-- German text on an English client: learn German, and write it down so.
local target, stored = fresh()
assert(target == "deDE", "German text on an English client has to mean German, got " .. tostring(target))
assert(stored == "deDE", "the new profile has to be written as German, got " .. tostring(stored))

-- Before the profile exists the answer is the same, not only after it.
WordHunterWoWDB = nil
assert(Addon.GetTargetLocale() == "deDE", "without a profile the text language still decides")

-- No answer from the CVar: the client's own locale, as before.
cvars.textLocale = nil
target = fresh()
assert(target == "enUS", "with no text language the client's locale decides, got " .. tostring(target))

-- A text language this addon has no dictionary for is not taken.
cvars.textLocale, client = "ruRU", "frFR"
target = fresh()
assert(target == "frFR", "an unsupported text language falls back to the client, got " .. tostring(target))

-- A language the player chose is kept whatever the client says.
cvars.textLocale, client = "deDE", "enUS"
WordHunterWoWDB = { settings = { targetLocale = "esES" } }
Addon.initializeDatabase()
assert(Addon.GetTargetLocale() == "esES", "a stored choice must survive, got " .. tostring(Addon.GetTargetLocale()))

print("target-locale: a fresh profile learns the language the quest text is in")
