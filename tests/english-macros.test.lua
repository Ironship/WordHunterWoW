-- Run from the addon root:  lua tests/english-macros.test.lua
--
-- The client substitutes $C, $N, $R and $g...:...; in quest text before it ever
-- reaches an addon, so the German column -- read from the game -- shows
-- "Krieger!" where the source says "$C!". The English column is read out of the
-- stored corpus instead, where the macro is kept exactly as Blizzard wrote it,
-- and nothing had resolved it: the same quest read "$C! I thought I would die
-- out here with none to know of it." beside "Krieger! Ich dachte schon...".
--
-- Every field the reader can put on screen now goes through the same
-- substitution the catalog's own records do -- and the stored record is not
-- written into, because it is read again for the next quest.

dofile("tests/wowstub.lua")

for _, file in ipairs({ "Core.lua", "Compat.lua", "UICommon.lua", "QuestReader.lua" }) do dofile(file) end
local A = WordHunterWoW_Addon

GetBuildInfo = function() return "1.60.1", "", "", 16001 end
A.Compat.Refresh()
UnitGUID = function() return "Player-english-macros" end
UnitName = function() return "Learner" end
UnitClass = function() return "Krieger", "WARRIOR" end
UnitRace = function() return "Mensch", "Human" end
UnitSex = function() return 3 end   -- female

WordHunterWoWDB = { settings = { targetLocale = "deDE", targetLocaleChosen = true, frames = {} }, wordsByLocale = {} }
A.initializeDatabase()

local SOURCE = "$C! I thought I would die out here with none to know of it."
local raw = {
  title = "$C!",
  description = SOURCE,
  objectives = "Kill Sarkoth and bring his claw back to $N, $R.",
  progress = "$g Brother:Sister;, you are hurt.",
  completion = "Well done, $N.",
}
local plain = { title = "Plain", description = "Nothing to substitute here." }
WordHunterWoW_QuestEN = { [901] = raw, [902] = plain }
WordHunterWoW_QuestDataByFlavor = {
  forever = { sourceFlavor = "classic", deDE = {}, enUS = { [901] = raw, [902] = plain } },
}

local entry = assert(A.GetEnglishQuestRecord(901), "the English record has to resolve")
-- The English record gets the English names, which is the point: the German
-- column says "Krieger" because the game's own text says it, and this column
-- says "Warrior" because the text it is showing is English.
assert(entry.description == "Warrior! I thought I would die out here with none to know of it.",
  "the class macro must be resolved, got " .. entry.description)
assert(entry.title == "Warrior!", "the title goes through it too, got " .. entry.title)
assert(entry.objectives == "Kill Sarkoth and bring his claw back to Learner, Human.",
  "the name and the race must be resolved, got " .. entry.objectives)
-- Female on this character, so the female half of the gender macro.
assert(entry.progress == "Sister, you are hurt.",
  "the gender macro must pick a side and drop its delimiters, got " .. entry.progress)
assert(entry.completion == "Well done, Learner.", "and every passage, not only the offer")
for _, field in ipairs({ "title", "description", "objectives", "progress", "completion" }) do
  assert(not tostring(entry[field]):find("$", 1, true),
    "no macro may survive in " .. field .. ": " .. tostring(entry[field]))
end

-- The record in the database is not the one handed out when something changed,
-- or the substitution would be baked into the stored text and read back by the
-- next quest -- and the German catalog, which reads the same database, would be
-- served English class names.
assert(raw.description == SOURCE, "the stored record must not be written into")
assert(raw.title == "$C!" and raw.objectives:find("$N", 1, true),
  "no field of the stored record may be rewritten")

-- A record with no macro comes back as itself. This runs on every render, and
-- copying the quest database's own table for nothing is a cost nobody asked for.
assert(A.GetEnglishQuestRecord(902) == plain,
  "a record carrying no macro must be handed back untouched")

print("english-macros: ok")
