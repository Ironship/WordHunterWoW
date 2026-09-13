-- Run from the addon root:  lua tests/word-key.test.lua

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
GetLocale = function() return "deDE" end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon

assert(Addon.cleanWord("¿Dónde?") == "Dónde", "Spanish inverted marks must strip")
assert(Addon.cleanWord("¡Hola!") == "Hola", "inverted exclamation must strip")
assert(Addon.wordKey("¿Dónde?") == Addon.wordKey("dónde"), "lookup must survive Spanish punctuation")

assert(Addon.wordKey("Straße") == "strasse", "ß folds to ss in the key")
assert(Addon.utf8Lower("Straße") == "strasse", "search must fold ß the same way")
assert(Addon.utf8Lower("STRASSE"):find("strasse", 1, true) or Addon.utf8Lower("Straße") == "strasse")

-- A client in a language this addon has no dictionary for. The getter and
-- initializeDatabase used to answer this differently -- the getter returned the
-- client's own locale, the initialiser wrote German -- and the two rationales
-- were each written down as though the other did not exist.
--
-- German wins, because the getter's answer was the one with a cost. Nothing is
-- spared by returning ruRU: initializeDatabase writes deDE into the settings a
-- moment later anyway, so the difference only ever showed before it ran, and
-- what it did there was make GetWordsTable build wordsByLocale.ruRU on demand
-- and leave it in the saved variables for good. A German dictionary over
-- Korean quest text highlights nothing and the player can pick a language; a
-- junk locale table on disk is not so easily undone.
GetLocale = function() return "ruRU" end
WordHunterWoWDB = { settings = {} }
assert(Addon.GetTargetLocale() == "deDE",
  "an unsupported client falls back to German, as initializeDatabase does")

-- The point of the fix is that the two agree, so ask them both rather than
-- pinning each to a constant that could drift apart again.
WordHunterWoWDB = nil
Addon.initializeDatabase()
assert(WordHunterWoWDB.settings.targetLocale == Addon.GetTargetLocale(),
  "the getter and the initialiser answer the same for an unsupported client")
GetLocale = function() return "deDE" end

print("word-key: ok")
