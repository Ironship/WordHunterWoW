local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS

-- The recall check: a word you are learning stops showing its meaning on the
-- first click and asks how well you knew it instead.
--
-- Colouring a word Learning is a promise to come back to it, and the panel
-- keeps that promise by showing it coloured in every later quest. What it
-- could not tell was whether the colour was still needed. A click opened the
-- editor with the meaning already filled in, so the moment of finding out --
-- did I know this? -- was over before it started. With the check on, a word
-- that has been Learning for a day asks first: five buttons, one to five, and
-- only then the meaning. The rating is the player's own verdict, which is what
-- every flashcard program uses too; matching a typed answer against a
-- translation is guesswork about synonyms and spelling, and a verdict is not.
--
-- Ratings and example sentences live beside the word list rather than inside
-- it, in WordHunterWoWDB.recallByLocale. Two reasons. The editor deletes a
-- word's own entry when its wording matches the dictionary's, on purpose, so
-- anything stored on that entry is gone the day the player types the pack's
-- own meaning back in. And a word with no entry of its own is not a table
-- that persists at all: GetEffectiveWord builds a fresh one from the
-- dictionary every call. A table of its own, keyed the same way and split by
-- language the way the words are, survives both and never touches the WHW3
-- export, which a desktop program parses column by column.
--
-- Every function here takes the clock as an argument, like recordEncounter and
-- computeStats, so a test can move time rather than the tests having to wait.

-- A day in Learning before the first question. Shorter, and the question
-- lands the same evening the word was marked, when it was looked up an hour
-- ago and the answer is memory of the page rather than of the word.
local ASK_AFTER = 24 * 60 * 60
-- Between questions on the same word. Twenty hours rather than a day, so a
-- word asked at eight in the evening is asked again the next evening at seven
-- rather than waiting for the day after.
local ASK_AGAIN_AFTER = 20 * 60 * 60
-- What is kept per word. Twenty ratings is plenty for an average and small
-- enough that a thousand rated words are still a few hundred kilobytes.
local RATINGS_KEPT = 20
local EXAMPLES_KEPT = 5
-- A quest sentence rarely passes two hundred characters; anything past this
-- is a paragraph that lost its full stops, not an example.
local EXAMPLE_MAX = 400
-- Difficult: enough ratings to mean something, and the recent ones low.
-- Five, not ten or twenty, because a word turns up in quests a handful of
-- times a month, and a threshold that takes a season to reach never fires.
local DIFFICULT_MIN_RATINGS = 5
local DIFFICULT_WINDOW = 10
local DIFFICULT_BELOW = 3.0
local SCORE_MIN, SCORE_MAX = 1, 5

Addon.RECALL_SCORE_MIN, Addon.RECALL_SCORE_MAX = SCORE_MIN, SCORE_MAX
Addon.RECALL_ASK_AFTER, Addon.RECALL_ASK_AGAIN_AFTER = ASK_AFTER, ASK_AGAIN_AFTER
Addon.RECALL_DIFFICULT_MIN_RATINGS = DIFFICULT_MIN_RATINGS

-- Off unless the player switched it on, and never seeded: nil reads as off,
-- the same way the quest log switch does it. Seeding would make an existing
-- profile and a fresh one differ for no reason.
function Addon.GetRecallCheck()
  local v = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.recallCheck
  return v and true or false
end

function Addon.SetRecallCheck(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.recallCheck = not not value
  -- Switched off under an open question, the question comes down with it.
  if not value and Addon.RevealRecall then Addon.RevealRecall() end
  if Addon.settingsPanel and Addon.settingsPanel.refresh then Addon.settingsPanel.refresh() end
end

-- The recall rows for the current language, made on first use the way
-- GetWordsTable makes its table. Keyed by wordKey, so a row and a word entry
-- for the same word share a key across the two tables.
function Addon.GetRecallTable()
  local locale = Addon.GetTargetLocale()
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.recallByLocale) ~= "table" then WordHunterWoWDB.recallByLocale = {} end
  if type(WordHunterWoWDB.recallByLocale[locale]) ~= "table" then WordHunterWoWDB.recallByLocale[locale] = {} end
  return WordHunterWoWDB.recallByLocale[locale]
end

function Addon.GetRecallRow(key, create)
  if type(key) ~= "string" or key == "" then return nil end
  local rows = Addon.GetRecallTable()
  local row = rows[key]
  if type(row) ~= "table" and create then
    row = { ratings = {}, ratingCount = 0, ratingSum = 0, examples = {} }
    rows[key] = row
  end
  -- A scalar where a row should be -- a hand-edited file -- is no row at
  -- all, rather than a value every reader has to be ready for.
  if type(row) ~= "table" then return nil end
  do
    -- Rows written by an earlier build, or edited by hand, may be missing a
    -- field. Filled in on read rather than by a migration, so the saved file
    -- needs no version stamp for this.
    if type(row.ratings) ~= "table" then row.ratings = {} end
    if type(row.examples) ~= "table" then row.examples = {} end
    if type(row.ratingCount) ~= "number" then row.ratingCount = #row.ratings end
    if type(row.ratingSum) ~= "number" then
      local sum = 0
      for _, r in ipairs(row.ratings) do sum = sum + (tonumber(r.score) or 0) end
      row.ratingSum = sum
    end
  end
  return row
end

-- Whether this word would be asked about now. Pure: the entry is the player's
-- own word entry (from GetWordsTable, never the throwaway GetEffectiveWord
-- makes for a dictionary word), the row is its recall row or nil.
--
-- Only a word the player marked Learning, and only once its status has stood
-- for a day. A dictionary word carries no statusChangedAt at all, and that is
-- the answer for it: the pack marking a word Learning is not the player
-- deciding to learn it, so it is never asked.
function Addon.RecallDue(entry, row, now)
  if type(entry) ~= "table" then return false end
  if Addon.EffectiveStatus(entry) ~= "learning" then return false end
  local since = entry.statusChangedAt or entry.updatedAt
  if type(since) ~= "number" or now - since < ASK_AFTER then return false end
  local last = type(row) == "table" and row.lastRatedAt
  if type(last) == "number" and now - last < ASK_AGAIN_AFTER then return false end
  return true
end

-- The same question with the lookups done and the setting consulted, which
-- is what the quest panel and the editor ask. The setting is checked first so
-- that with the check off -- the default -- a hover costs one boolean.
function Addon.RecallGated(key, now)
  if not Addon.GetRecallCheck() then return false end
  if type(key) ~= "string" or key == "" then return false end
  local entry = Addon.GetWordsTable()[key]
  if not entry then return false end
  local rows = WordHunterWoWDB and WordHunterWoWDB.recallByLocale
  local row = rows and rows[Addon.GetTargetLocale()] and rows[Addon.GetTargetLocale()][key]
  return Addon.RecallDue(entry, row, now or time())
end

local function validScore(score)
  score = tonumber(score)
  if not score or score < SCORE_MIN or score > SCORE_MAX or score ~= math.floor(score) then return nil end
  return score
end

-- Writes the verdict the moment it is given. The editor's Save is not
-- involved: cancelling the editor is the natural end of "I only wanted to
-- check", and a rating that needed Save would be lost on most of them.
function Addon.RecordRating(key, score, now)
  score = validScore(score)
  if not score then return nil end
  local row = Addon.GetRecallRow(key, true)
  if not row then return nil end
  now = now or time()
  row.ratings[#row.ratings + 1] = { at = now, score = score }
  while #row.ratings > RATINGS_KEPT do table.remove(row.ratings, 1) end
  row.ratingCount = row.ratingCount + 1
  row.ratingSum = row.ratingSum + score
  row.lastRatedAt = now
  return row
end

local function cleanSentence(text)
  -- Collapsed, not only trimmed: a sentence that crossed a line break in the
  -- quest text and one that did not are the same example.
  return (Addon.trim(tostring(text or "")):gsub("%s+", " "))
end

-- Keeps the sentence the word was met in, up to five, oldest out first. The
-- same sentence twice -- the same quest read twice -- is kept once, in the
-- place it first had.
function Addon.RecordExample(key, text, questId, questTitle, now)
  text = cleanSentence(text)
  if text == "" or #text > EXAMPLE_MAX then return false end
  local row = Addon.GetRecallRow(key, true)
  if not row then return false end
  for _, example in ipairs(row.examples) do
    if example.text == text then return false end
  end
  row.examples[#row.examples + 1] = {
    text = text,
    questId = tostring(questId or ""),
    questTitle = Addon.trim(questTitle),
    at = now or time(),
  }
  while #row.examples > EXAMPLES_KEPT do table.remove(row.examples, 1) end
  return true
end

-- Mean of the most recent ratings, and how many went into it. Recent rather
-- than all-time, so a word that was hard in the spring and is easy now reads
-- as easy.
function Addon.RecallAverage(row)
  if type(row) ~= "table" or type(row.ratings) ~= "table" or #row.ratings == 0 then return nil, 0 end
  local n = math.min(DIFFICULT_WINDOW, #row.ratings)
  local sum = 0
  for i = #row.ratings - n + 1, #row.ratings do
    sum = sum + (tonumber(row.ratings[i].score) or 0)
  end
  return sum / n, n
end

-- Rated enough times to trust, and recently rated low. The status is the
-- caller's to check: a word since marked Known is not difficult whatever it
-- was rated while it was being learned.
function Addon.IsDifficult(row)
  if type(row) ~= "table" or (tonumber(row.ratingCount) or 0) < DIFFICULT_MIN_RATINGS then return false end
  local mean = Addon.RecallAverage(row)
  return mean ~= nil and mean < DIFFICULT_BELOW
end

-- Every difficult word still being learned, hardest first. Walks the recall
-- rows -- a few hundred at most -- and looks each word up, rather than
-- walking the dictionary's seventy thousand entries to find the few that
-- have a row.
function Addon.DifficultWords()
  local result = {}
  for key in pairs(Addon.GetRecallTable()) do
    local row = Addon.GetRecallRow(key)
    if row and Addon.IsDifficult(row) then
      local entry = Addon.GetEffectiveWord(key)
      if entry and Addon.EffectiveStatus(entry) == "learning" then
        local mean, n = Addon.RecallAverage(row)
        result[#result + 1] = {
          key = key,
          word = entry.word or key,
          translation = entry.translation or "",
          note = entry.note or "",
          examples = row.examples,
          mean = mean,
          recent = n,
          count = row.ratingCount,
          lastRatedAt = row.lastRatedAt,
        }
      end
    end
  end
  table.sort(result, function(a, b)
    if a.mean ~= b.mean then return a.mean < b.mean end
    return Addon.utf8Lower(a.word) < Addon.utf8Lower(b.word)
  end)
  return result
end

function Addon.CountDifficult()
  return #Addon.DifficultWords()
end

-- One line per word, tab-separated, which is what every flashcard importer
-- reads without being told anything: word, meaning, note, the example
-- sentences joined by " | ", the recent average, the number of ratings. No
-- header line, because an importer would make a card of it. Tabs and line
-- breaks inside a field would break the row, so they become spaces; the note
-- box is multi-line and a player's note may well have them.
local function cell(value)
  return (Addon.trim(tostring(value or "")):gsub("[\t\r\n]+", " "))
end

function Addon.BuildDifficultExport()
  local words = Addon.DifficultWords()
  local lines = {}
  for _, item in ipairs(words) do
    local examples = {}
    for _, example in ipairs(item.examples or {}) do
      examples[#examples + 1] = cell(example.text)
    end
    lines[#lines + 1] = table.concat({
      cell(item.word),
      cell(item.translation),
      cell(item.note),
      table.concat(examples, " | "),
      string.format("%.2f", item.mean),
      tostring(item.count),
    }, "\t")
  end
  return table.concat(lines, "\n"), #lines
end

-- The line the editor shows once a word has been rated at all: how many
-- times, and how it has been going lately.
function Addon.RecallSummary(key)
  local row = Addon.GetRecallRow(key)
  if not row or row.ratingCount == 0 then return nil end
  local mean = Addon.RecallAverage(row)
  return string.format(LABELS.recallHistory, mean or 0, row.ratingCount), mean, row.ratingCount
end
