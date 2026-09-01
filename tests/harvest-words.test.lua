-- Run from the addon root:  lua tests/harvest-words.test.lua
--
-- The collector offers every word the dictionary has no entry for. "Kill 12
-- kobolds" therefore offered 12, and it was not wrong -- no dictionary covers
-- it. But a bare number teaches nobody anything and quest text is full of
-- them, so they arrive in every batch sent for translation. A real Classic
-- session collected ten unknown words and two of them were "12" and "6".

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
GetLocale = function() return "deDE" end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
UnitName = function() return "Ironship" end

dofile("Core.lua")
dofile("Harvest.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { harvestCorpus = true, targetLocale = "deDE" } }
WordHunterWoWCorpus = nil

assert(Addon.HarvestUnknownWord("Zaubernotizen"), "a real word is vocabulary")
assert(Addon.HarvestUnknownWord("mach's"), "so is a contraction")
assert(Addon.HarvestUnknownWord("Verständnisamulette"), "and a compound with umlauts")

assert(not Addon.HarvestUnknownWord("12"), "a bare number is a quantity, not a word")
assert(not Addon.HarvestUnknownWord("6"), "however short")
assert(not Addon.HarvestUnknownWord("100"), "or long")
assert(not Addon.HarvestUnknownWord("--"), "punctuation is not vocabulary either")
assert(not Addon.HarvestUnknownWord(""), "nor is nothing")

-- a number attached to a word is still a word
assert(Addon.HarvestUnknownWord("12er"), "12er is a word, not a quantity")

-- The player's own name is in the quest text addressed to them and in gossip,
-- and no dictionary covers it -- but collecting it would ship one player's
-- character name to everyone in the next release. A real session collected it.
assert(not Addon.HarvestUnknownWord("Ironship"), "the player's own name is not vocabulary")
assert(not Addon.HarvestUnknownWord("ironship"), "whatever case the text uses")
assert(Addon.HarvestUnknownWord("Ironshipper"), "a different word that merely starts the same is fine")

-- The guard above covers single words. A passage carries the name too -- gossip
-- says "Ah, da seid Ihr ja, Ironship!" -- and that went in verbatim, so the name
-- reached the corpus one level up from where the guard was. A real export
-- contained four character names collected exactly this way.
Addon.SetHarvestEnabled(true)
assert(Addon.HarvestText("description", 101, "Ah, da seid Ihr ja, Ironship! Wir haben Euch erwartet."),
  "a passage is still collected")
local function corpusEntries()
  local byLocale = WordHunterWoWCorpus and WordHunterWoWCorpus.byLocale or {}
  return byLocale[Addon.GetTargetLocale()] or {}
end
local stored
for _, entry in pairs(corpusEntries()) do
  if entry.kind == "description" and entry.id == 101 then stored = entry.text end
end
assert(stored, "the passage should be in the corpus")
assert(not stored:find("Ironship", 1, true),
  "the player's name must not reach the corpus in a passage either: " .. stored)
assert(stored:find("<name>", 1, true), "it is replaced rather than dropped: " .. stored)
assert(stored:find("erwartet", 1, true), "and the rest of the passage is untouched")

-- A word that merely contains the name is left alone; only the name itself goes.
assert(Addon.HarvestText("description", 102, "Der Ironshipper wartet."))
for _, entry in pairs(corpusEntries()) do
  if entry.kind == "description" and entry.id == 102 then
    assert(entry.text:find("Ironshipper", 1, true) or entry.text:find("<name>per", 1, true),
      "substitution inside a longer word is acceptable but the text must survive: " .. entry.text)
  end
end

print("harvest-words: ok")
