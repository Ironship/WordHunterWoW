-- Run from the addon root:  lua tests/encounter-record.test.lua
--
-- Saving a word without changing anything clears it: the meaning and the status
-- came from the pack, and an overlay holding them would freeze that wording
-- against every later pack update. What is not the pack's is the record of
-- having met the word -- how many quests it has turned up in, and when it was
-- first and last seen -- and that used to be cleared along with the wording. The
-- word dropped out of "Most encountered" and its ready-for-Known count went back
-- to zero, for having pressed Save and changed nothing.
--
-- So the editor now leaves that record behind, marked, and both walkers have to
-- read such an entry as "the pack's wording, with this player's encounters on
-- top" rather than as a player entry with no meaning in it. This is the pair of
-- walkers, checked against each other.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE" }, wordsByLocale = {} }
Addon.initializeDatabase()

local pack = {
  hund = { word = "Hund", translation = "dog", status = "known" },
  wolf = { word = "Wolf", translation = "wolf", status = "new" },
}
assert(Addon.RegisterDictionaryProvider("deDE", "pack", pack))

-- What the editor leaves for a word it was asked to save unchanged. The
-- statusChangedAt is from the player's own history, not from the save.
Addon.GetWordsTable("deDE").hund = {
  word = "Hund", encounterOnly = true,
  encounterCount = 39, encounteredQuests = { ["184"] = true, ["200"] = true },
  firstSeenAt = 1000, lastSeenAt = 2000, statusChangedAt = 1500,
}

-- The lookup. The pack's meaning has to come back, not be hidden behind a record
-- that has nothing to say about meaning.
local effective, fromDictionary = Addon.GetEffectiveWord("hund", "deDE")
assert(fromDictionary, "the pack's word must be the one shown, not the record")
assert(effective.translation == "dog" and effective.status == "known",
  "and it must be the pack's wording, got " .. tostring(effective.translation))
assert(effective.encounterCount == 39 and effective.statusChangedAt == 1500
  and effective.firstSeenAt == 1000,
  "with the player's own encounters laid over it")

-- The walk, which is what every list in the addon is drawn from. It has to agree
-- with the lookup, and it has to visit the word once: an encounter record that
-- hid the pack's entry and then also came back as a user entry would put the
-- same word on the list twice.
local visits, asDictionary, asUser = 0, nil, nil
Addon.ForEachEffectiveWord(function(key, entry, isDictionary)
  if key ~= "hund" then return end
  visits = visits + 1
  if isDictionary then asDictionary = entry else asUser = entry end
end, "deDE")
assert(visits == 1, "the word must be walked once, not twice, got " .. visits)
assert(asDictionary and not asUser, "and walked as the pack's word")
assert(asDictionary.translation == "dog" and asDictionary.encounterCount == 39,
  "carrying the player's encounters")

-- The pack's own table is a read-only overlay. Laying a record over it must not
-- write into it, or the record would survive a reload it never should have.
assert(pack.hund.encounterCount == nil and pack.hund.encounterOnly == nil,
  "the pack's table must not be written into")

-- A word the player has actually edited still wins outright: the record is only
-- about words where there is nothing of theirs to keep.
Addon.GetWordsTable("deDE").wolf = { word = "Wolf", translation = "my wolf", status = "learning" }
local wolf, wolfFromDictionary = Addon.GetEffectiveWord("wolf", "deDE")
assert(not wolfFromDictionary and wolf.translation == "my wolf",
  "a word the player wrote is still theirs")

-- And a record with no pack word behind it is still a word the player has met:
-- dropping it would lose the only thing known about it.
Addon.GetWordsTable("deDE").einhorn = {
  word = "Einhorn", encounterOnly = true, encounterCount = 3, firstSeenAt = 500,
}
local unicorn, unicornFromDictionary = Addon.GetEffectiveWord("einhorn", "deDE")
assert(not unicornFromDictionary and unicorn.encounterCount == 3,
  "a record with no pack word behind it is all there is, and stays")
local walked = false
Addon.ForEachEffectiveWord(function(key) if key == "einhorn" then walked = true end end, "deDE")
assert(walked, "and the walk has to reach it too, or it vanishes from every list")

print("encounter-record: ok")
