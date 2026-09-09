-- Run from the addon root:  lua tests/recall-logic.test.lua
--
-- The recall check's arithmetic, with the clock in the test's hand. Every rule
-- here is a number somebody will want to argue with later -- a day before the
-- first question, twenty hours between questions, five ratings and an average
-- under three for "difficult" -- so each is pinned at its edge, one second
-- either side, rather than only somewhere in the middle.
--
-- Written to run under Lua 5.1 as well as 5.4: the game client is 5.1, and
-- Recall.lua is the one file here whose sums a player's data depends on.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Recall.lua")
local Addon = WordHunterWoW_Addon

local DAY, HOUR = 24 * 60 * 60, 60 * 60
local now = 1700000000

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
Addon.initializeDatabase()
local words = Addon.GetWordsTable()

-- Off out of the box, and nil is off: a profile from before this existed must
-- not come up asking questions.
assert(Addon.GetRecallCheck() == false, "the recall check has to start off")
assert(WordHunterWoWDB.settings.recallCheck == nil, "and must not be seeded into the settings")
Addon.SetRecallCheck(true)
assert(Addon.GetRecallCheck() == true and WordHunterWoWDB.settings.recallCheck == true)

-- The rows live beside the words, split by language the same way.
local rows = Addon.GetRecallTable()
assert(rows == WordHunterWoWDB.recallByLocale.deDE, "rows are kept per language")
assert(next(rows) == nil, "and there are none to start with")
assert(Addon.GetRecallRow("hund") == nil, "asking for a row does not make one")
assert(Addon.GetRecallRow("") == nil and Addon.GetRecallRow(nil) == nil, "an empty key has no row")

-- The gate, one edge at a time. The entry is the player's own.
local hund = { word = "Hund", status = "learning", translation = "dog", statusChangedAt = now - DAY - 1, updatedAt = now - DAY - 1 }
words.hund = hund
assert(Addon.RecallDue(hund, nil, now) == true, "a day and a second in Learning is due")
hund.statusChangedAt = now - DAY + 1
assert(Addon.RecallDue(hund, nil, now) == false, "a second short of a day is not")
hund.statusChangedAt = now - DAY
assert(Addon.RecallDue(hund, nil, now) == true, "exactly a day is")
hund.status = "known"
assert(Addon.RecallDue(hund, nil, now) == false, "a Known word is never asked")
hund.status = "new"
assert(Addon.RecallDue(hund, nil, now) == false, "nor a New one")
hund.status = "learning"
-- A dictionary word carries no timestamps at all; GetEffectiveWord builds it
-- fresh each call. It must read as never due, not as due since 1970.
local dictOnly = { word = "Katze", status = "learning", translation = "cat" }
assert(Addon.RecallDue(dictOnly, nil, now) == false, "a word with no statusChangedAt is not due")
assert(Addon.RecallDue(nil, nil, now) == false and Addon.RecallDue("hund", nil, now) == false,
  "nothing to look at is not due")
-- statusChangedAt is the field, updatedAt the fallback older entries have.
assert(Addon.RecallDue({ status = "learning", updatedAt = now - 2 * DAY }, nil, now) == true,
  "an entry from before statusChangedAt existed still counts its age")

-- Once rated, not again for twenty hours.
assert(Addon.RecallDue(hund, { lastRatedAt = now - 20 * HOUR + 1 }, now) == false, "rated 19h59m ago: not yet")
assert(Addon.RecallDue(hund, { lastRatedAt = now - 20 * HOUR }, now) == true, "rated twenty hours ago: again")
assert(Addon.RecallDue(hund, { lastRatedAt = "soon" }, now) == true, "a broken lastRatedAt does not block")

-- RecallGated is the same question with the lookups done, and the setting
-- checked first.
assert(Addon.RecallGated("hund", now) == true, "own Learning word, a day old, check on: gated")
Addon.SetRecallCheck(false)
assert(Addon.RecallGated("hund", now) == false, "with the check off nothing is gated")
Addon.SetRecallCheck(true)
assert(Addon.RecallGated("katze", now) == false, "a word with no entry of its own is not gated")
Addon.RegisterDictionaryProvider("deDE", "test", { katze = { word = "Katze", translation = "cat", status = "learning" } })
assert(Addon.RecallGated("katze", now) == false,
  "a dictionary word marked Learning by the pack is still not the player's decision")
assert(Addon.RecallGated("", now) == false and Addon.RecallGated(nil, now) == false)

-- Ratings. Refused outside one to five, and only whole numbers.
for _, bad in ipairs({ 0, 6, 2.5, "x", nil, -1 }) do
  assert(Addon.RecordRating("hund", bad, now) == nil, "score " .. tostring(bad) .. " must be refused")
end
assert(Addon.GetRecallRow("hund") == nil, "a refused rating leaves no row behind")
local row = Addon.RecordRating("hund", 3, now)
assert(row and row == Addon.GetRecallRow("hund"), "a rating makes the row and returns it")
assert(#row.ratings == 1 and row.ratings[1].score == 3 and row.ratings[1].at == now)
assert(row.ratingCount == 1 and row.ratingSum == 3 and row.lastRatedAt == now)
assert(Addon.RecordRating("hund", "4", now + 1), "a numeric string is a score")
assert(row.ratingCount == 2 and row.ratingSum == 7 and row.lastRatedAt == now + 1)
assert(Addon.RecallGated("hund", now + 1) == false, "just rated: not asked again")
assert(Addon.RecallGated("hund", now + 1 + 20 * HOUR) == true, "twenty hours on: asked again")

-- Twenty are kept; the count and the sum go on counting.
for i = 1, 30 do Addon.RecordRating("hund", 5, now + 10 + i) end
assert(#row.ratings == 20, "only the last twenty ratings are kept, got " .. #row.ratings)
assert(row.ratingCount == 32 and row.ratingSum == 7 + 150, "the count and sum are all-time")
assert(row.ratings[1].at == now + 10 + 11, "and it is the oldest that go")

-- The average looks at the last ten, so a word that was hard and is easy now
-- reads as easy, and the other way round.
local mean, n = Addon.RecallAverage(row)
assert(mean == 5 and n == 10, "ten fives average five")
assert(Addon.RecallAverage(nil) == nil and select(2, Addon.RecallAverage({ ratings = {} })) == 0)

-- Difficult: five ratings, recent average under three.
local function rated(key, scores)
  rows[key] = nil
  for i, score in ipairs(scores) do Addon.RecordRating(key, score, now + i) end
  return Addon.GetRecallRow(key)
end
assert(Addon.IsDifficult(rated("a", { 1, 1, 1, 1 })) == false, "four ratings are not enough, however low")
assert(Addon.IsDifficult(rated("b", { 1, 1, 1, 1, 1 })) == true, "five ones are difficult")
assert(Addon.IsDifficult(rated("c", { 3, 3, 3, 3, 3 })) == false, "an average of exactly three is not")
assert(Addon.IsDifficult(rated("d", { 3, 3, 3, 3, 2 })) == true, "2.8 is")
assert(Addon.IsDifficult(rated("e", { 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 })) == false,
  "ten old ones under ten recent fives: the recent ten decide")
assert(Addon.IsDifficult(rated("f", { 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 })) == true,
  "and the other way round")
assert(Addon.IsDifficult(nil) == false and Addon.IsDifficult({}) == false)

-- A row from an older build, missing fields, is repaired on read rather than
-- by a migration.
rows.alt = { ratings = { { at = now, score = 2 }, { at = now, score = 4 } } }
local alt = Addon.GetRecallRow("alt")
assert(alt.ratingCount == 2 and alt.ratingSum == 6 and type(alt.examples) == "table",
  "a bare row gets its count, sum and examples filled in")

-- Examples: trimmed and collapsed, five kept, the same sentence once.
rows.hund = nil
assert(Addon.RecordExample("hund", "  Der Hund   bellt.\n", 184, " Sten ", now) == true)
local ex = Addon.GetRecallRow("hund").examples
assert(#ex == 1 and ex[1].text == "Der Hund bellt." and ex[1].questId == "184" and ex[1].questTitle == "Sten"
  and ex[1].at == now, "the sentence is kept cleaned, with where it came from")
assert(Addon.RecordExample("hund", "Der Hund bellt.", 185, "Other", now + 1) == false, "the same sentence again is not a second example")
assert(#ex == 1 and ex[1].questId == "184", "and the first keeps its place")
assert(Addon.RecordExample("hund", "   ", 1, "", now) == false, "blank is nothing")
assert(Addon.RecordExample("hund", string.rep("x", 401), 1, "", now) == false, "a paragraph is not an example")
for i = 1, 6 do Addon.RecordExample("hund", "Satz " .. i, i, "", now + i) end
assert(#ex == 5 and ex[1].text == "Satz 2" and ex[5].text == "Satz 6",
  "five are kept and the oldest goes, got " .. #ex .. " starting " .. tostring(ex[1].text))
assert(Addon.RecordExample("", "Satz", 1, "", now) == false, "no key, no row")

-- Difficult words are the ones still being learned. The word list decides the
-- status; the rows only remember the ratings.
for _, key in ipairs({ "a", "b", "c", "d", "e", "f", "alt" }) do rows[key] = nil end
words.hund = hund
rated("hund", { 1, 2, 1, 2, 1 })
words.baum = { word = "Baum", status = "learning", translation = "tree", note = "line one\nline two", statusChangedAt = now - 2 * DAY }
rated("baum", { 2, 2, 2, 2, 2, 2 })
Addon.RecordExample("baum", "Ein Baum.", 1, "", now)
Addon.RecordExample("baum", "Noch ein\tBaum.", 2, "", now)
words.haus = { word = "Haus", status = "known", translation = "house", statusChangedAt = now - 2 * DAY }
rated("haus", { 1, 1, 1, 1, 1 })
rated("katze", { 1, 1, 1, 1, 1 })
rated("gone", { 1, 1, 1, 1, 1 })
local difficult = Addon.DifficultWords()
local names = {}
for _, item in ipairs(difficult) do names[#names + 1] = item.word end
assert(#difficult == 3, "three are difficult and still Learning, got " .. table.concat(names, ","))
assert(names[1] == "Katze" and names[2] == "Hund" and names[3] == "Baum",
  "hardest first (1.0, 1.4, 2.0): got " .. table.concat(names, ","))
-- Katze is a dictionary word the pack marks Learning; its ratings still count
-- it, and its meaning comes from the pack since the player never wrote one.
assert(difficult[1].translation == "cat", "a dictionary word exports the pack's meaning")
assert(Addon.CountDifficult() == 3)
-- Haus is Known now, gone has no word anywhere: neither is exported.

-- The export: one line a word, six tab-separated cells, sentences joined by
-- a pipe, and no tab or line break inside a cell.
local text, count = Addon.BuildDifficultExport()
assert(count == 3, "the count is the number of lines")
local lines = {}
for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
assert(#lines == 3, "three lines, got " .. #lines)
for _, line in ipairs(lines) do
  local _, tabs = line:gsub("\t", "")
  assert(tabs == 5, "six cells means five tabs, got " .. tabs .. " in: " .. line)
end
assert(lines[1] == "Katze\tcat\t\t\t1.00\t5", "got: " .. lines[1])
assert(lines[2] == "Hund\tdog\t\t\t1.40\t5", "got: " .. lines[2])
assert(lines[3] == "Baum\ttree\tline one line two\tEin Baum. | Noch ein Baum.\t2.00\t6", "got: " .. lines[3])

-- Nothing difficult: an empty string and zero, which is what the button and
-- the slash command test for.
WordHunterWoWDB.recallByLocale.deDE = {}
local empty, zero = Addon.BuildDifficultExport()
assert(empty == "" and zero == 0, "no difficult words is an empty export")

-- The summary line the editor shows.
assert(Addon.RecallSummary("hund") == nil, "no ratings, no summary")
Addon.RecordRating("hund", 2, now)
Addon.RecordRating("hund", 3, now)
local summary, avg, total = Addon.RecallSummary("hund")
assert(summary == string.format(Addon.LABELS.recallHistory, 2.5, 2) and avg == 2.5 and total == 2,
  "got " .. tostring(summary))

-- Nothing here reaches the export the desktop program parses.
words.hund.context = "Der Hund bellt."
words.hund.questId, words.hund.questTitle = "184", "Sten"
Addon.rebuildExport()
local before = WordHunterWoWExport
Addon.RecordRating("hund", 5, now + 5)
Addon.RecordExample("hund", "Noch ein Satz.", 1, "", now)
Addon.rebuildExport()
assert(WordHunterWoWExport == before, "ratings and examples must not change the WHW3 blob")
for rowText in before:sub(6):gmatch("[^;]+") do
  local _, commas = rowText:gsub(",", "")
  assert(commas == 12, "a WHW3 row is thirteen columns, got " .. (commas + 1))
end

-- Another language has rows of its own.
Addon.SetTargetLocale("frFR")
assert(next(Addon.GetRecallTable()) == nil, "French starts with no rows")
assert(Addon.CountDifficult() == 0)
Addon.SetTargetLocale("deDE")
assert(Addon.GetRecallRow("hund"), "and German still has its rows")

print("recall-logic: ok")
