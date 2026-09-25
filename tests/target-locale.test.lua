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

local function stored(target)
  WordHunterWoWDB = { settings = { targetLocale = target } }
  Addon.initializeDatabase()
  return Addon.GetTargetLocale()
end

-- The Forever profile: English stored by the old default over German text. It
-- can never match a word, so it is corrected to the text language.
cvars.textLocale, client = "deDE", "enUS"
assert(stored("enUS") == "deDE", "English stored over German text has to become German, got " .. tostring(Addon.GetTargetLocale()))

-- The same language in another variant is the player's to keep.
cvars.textLocale, client = "esES", "esES"
assert(stored("esMX") == "esMX", "esMX over esES text is the same language and must stay")
cvars.textLocale = "enGB"
assert(stored("enUS") == "enUS", "enUS over enGB text is the same language and must stay")

-- Without a named text language nothing stored is second-guessed: GetLocale()
-- is the very answer that was wrong.
cvars.textLocale, client = nil, "enUS"
assert(stored("frFR") == "frFR", "with no textLocale a stored language must survive, got " .. tostring(Addon.GetTargetLocale()))
cvars.textLocale = "ruRU"
assert(stored("frFR") == "frFR", "an unsupported text language corrects nothing")

print("target-locale: a fresh profile learns the language the quest text is in")
