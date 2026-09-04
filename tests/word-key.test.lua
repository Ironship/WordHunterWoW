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

GetLocale = function() return "ruRU" end
WordHunterWoWDB = { settings = {} }
assert(Addon.GetTargetLocale() == "ruRU", "an unsupported client must not default to German")

print("word-key: ok")
