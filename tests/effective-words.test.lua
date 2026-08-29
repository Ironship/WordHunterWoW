-- Run from the addon root:  lua tests/effective-words.test.lua
--
-- Dictionaries are overlays. The words a player has saved are theirs and must
-- win over anything a dictionary addon supplies, and a dictionary word the
-- player has never touched has to read as New. That was covered only by
-- grepping the source for one particular line, which went stale the moment the
-- loop was refactored into ForEachEffectiveWord. This checks the behaviour.

strlower = string.lower
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
time = os.time
GetLocale = function() return "deDE" end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
local locale = Addon.GetTargetLocale()

assert(Addon.RegisterDictionaryProvider(locale, "test-dict", {
  ["besichtigt"] = { word = "Besichtigt", translation = "visited", note = "" },
  ["mauer"] = { word = "Mauer", translation = "wall", note = "" },
}), "the dictionary provider was refused")

-- a word the player has saved and marked, on top of the same key
Addon.GetWordsTable()["mauer"] = { word = "Mauer", translation = "my own", status = "known" }

local words = Addon.GetEffectiveWords()

local dict = words["besichtigt"]
assert(dict, "a dictionary word never reached the effective set")
assert(dict.translation == "visited", "wrong translation: " .. tostring(dict.translation))
assert(dict.status == "new", "an untouched dictionary word should read as New, got " .. tostring(dict.status))
assert(dict.builtInDictionary, "a dictionary word should be marked as coming from one")
assert(dict.dictionaryProvider == "test-dict", "wrong provider: " .. tostring(dict.dictionaryProvider))
print("  dictionary words arrive, and default to New")

local mine = words["mauer"]
assert(mine.translation == "my own", "the player's own translation was overwritten by the dictionary")
assert(mine.status == "known", "the player's own status was lost: " .. tostring(mine.status))
assert(not mine.builtInDictionary, "the player's own word was marked as coming from a dictionary")
print("  the player's own words win over the dictionary")

-- and the dictionary is never copied into the player's saved data
local saved = Addon.GetWordsTable()
assert(saved["besichtigt"] == nil, "a dictionary word was copied into SavedVariables")
local n = 0
for _ in pairs(saved) do n = n + 1 end
assert(n == 1, "SavedVariables should hold only the player's own word, holds " .. n)
print("  nothing from the dictionary is written into SavedVariables")

-- a status a dictionary file made up must not be trusted through
Addon.RegisterDictionaryProvider(locale, "test-dict", {
  ["turm"] = { word = "Turm", translation = "tower", status = "nonsense" },
})
assert(Addon.GetEffectiveWords()["turm"].status == "new",
       "an unrecognised status was passed straight through")
print("  an unrecognised status falls back to New")

print("effective-words: all assertions passed")
