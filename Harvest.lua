local Addon = WordHunterWoW_Addon

-- Blizzard's quest REST API publishes a quest's title and its offer text and
-- nothing else -- no objectives, no progress line, no hand-in line. The
-- dictionaries are built from that API, so a word that lives only in one of the
-- missing passages never reaches them: "Besichtigt" is absent from all 30815
-- German quests even though "besichtigen" and "Besichtigung" are both there.
-- NPC gossip is not in the API at all.
--
-- The game client has all of it. This records passages the player actually
-- meets so they can be exported and folded back into the corpus. Off by
-- default: it grows SavedVariables, and most players installed this to read
-- quests, not to collect them.

local MAX_ENTRIES = 20000
local MAX_TEXT = 4000
local KINDS = { title = true, description = true, objectives = true,
                progress = true, reward = true, gossip = true }

function Addon.GetHarvestEnabled()
  local v = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.harvestCorpus
  return v and true or false
end

function Addon.SetHarvestEnabled(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.harvestCorpus = not not value
  if Addon.settingsPanel and Addon.settingsPanel.refresh then Addon.settingsPanel.refresh() end
end

local function corpusTable()
  if type(WordHunterWoWCorpus) ~= "table" then WordHunterWoWCorpus = {} end
  if WordHunterWoWCorpus.version ~= 1 then
    WordHunterWoWCorpus.version = 1
    WordHunterWoWCorpus.byLocale = {}
  end
  if type(WordHunterWoWCorpus.byLocale) ~= "table" then WordHunterWoWCorpus.byLocale = {} end
  local locale = Addon.GetTargetLocale()
  if type(WordHunterWoWCorpus.byLocale[locale]) ~= "table" then
    WordHunterWoWCorpus.byLocale[locale] = {}
  end
  return WordHunterWoWCorpus.byLocale[locale]
end

function Addon.HarvestCount(locale)
  if type(WordHunterWoWCorpus) ~= "table" or type(WordHunterWoWCorpus.byLocale) ~= "table" then return 0 end
  local bucket = WordHunterWoWCorpus.byLocale[locale or Addon.GetTargetLocale()]
  if type(bucket) ~= "table" then return 0 end
  local n = 0
  for _ in pairs(bucket) do n = n + 1 end
  return n
end

-- Gossip carries no id to key on, so hash the text. djb2 over bytes, which is
-- enough to tell two greetings apart without pulling in a real digest.
local function textHash(text)
  local hash = 5381
  for i = 1, #text do
    hash = (hash * 33 + string.byte(text, i)) % 4294967296
  end
  return string.format("%x", hash)
end

function Addon.HarvestText(kind, questId, text)
  if not Addon.GetHarvestEnabled() then return false end
  if not KINDS[kind] then return false end
  text = Addon.trim(tostring(text or ""))
  if text == "" or #text > MAX_TEXT then return false end

  local bucket = corpusTable()
  questId = tonumber(questId) or 0
  -- A quest passage is uniquely identified by the quest and which passage it is.
  -- Gossip has neither, so it is keyed by its own content.
  local key = questId > 0 and (kind .. ":" .. questId) or (kind .. ":#" .. textHash(text))
  if bucket[key] then return false end
  if Addon.HarvestCount() >= MAX_ENTRIES then return false end
  bucket[key] = { kind = kind, id = questId, text = text }
  return true
end

function Addon.HarvestQuest(questId, passages)
  if not Addon.GetHarvestEnabled() then return end
  for kind, text in pairs(passages) do
    Addon.HarvestText(kind, questId, text)
  end
end

function Addon.HarvestGossip()
  if not Addon.GetHarvestEnabled() then return end
  local text = C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText()
  if not text or text == "" then return end
  Addon.HarvestText("gossip", 0, text)
end

function Addon.ClearHarvest()
  WordHunterWoWCorpus = { version = 1, byLocale = {} }
  WordHunterWoWCorpusExport = ""
end

-- The importer is a Python script, so hand it a flat percent-encoded blob
-- rather than making it parse the SavedVariables Lua. Same shape the word
-- export already uses.
local function encode(value)
  -- Parenthesised: gsub also returns a replacement count, and an unparenthesised
  -- call in the last slot of a table constructor would append it as a field.
  return (tostring(value or ""):gsub("([^A-Za-z0-9_.~%-])", function(byte)
    return string.format("%%%02X", string.byte(byte))
  end))
end

function Addon.rebuildHarvestExport()
  local locale = Addon.GetTargetLocale()
  local bucket = corpusTable()
  local keys = {}
  for key in pairs(bucket) do keys[#keys + 1] = key end
  table.sort(keys)
  local rows = {}
  for _, key in ipairs(keys) do
    local entry = bucket[key]
    rows[#rows + 1] = table.concat({ entry.kind, tostring(entry.id or 0), encode(entry.text) }, "|")
  end
  WordHunterWoWCorpusExport = "WHC1|" .. locale .. "|" .. table.concat(rows, ";")
  return #rows
end
