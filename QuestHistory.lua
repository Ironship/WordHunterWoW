local Addon = WordHunterWoW_Addon
local Compat = Addon.Compat

-- Per-character quest history: which quests THIS character accepted and
-- completed. Reading a quest's text, meeting one of its words, or another
-- character finishing it is not completing it, so this lives apart from the
-- word table and the corpus under WordHunterWoWDB.questHistory, one bucket
-- per character.
--
-- The key is UnitGUID while it answers a plain string, else the stable
-- name@realm fallback. There is no bucket for an unknown character: without
-- an identity nothing is recorded and reads answer {}.
--
-- Records carry completed, accepted, title and titleLocale when observed in
-- the live client. Legacy titles have no confirmed language. inLog is live
-- state from Compat.QuestLogEntries and is never
-- stored, so a repeatable back in the log stays completed. Syncing merges and
-- never deletes: an old completion survives every re-sync.

local legacyRequested = false

local function trim(value)
  if Addon.trim then return Addon.trim(value) end
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isSecret(value)
  if Addon.IsSecretValue then
    local ok, secret = pcall(Addon.IsSecretValue, value)
    if ok and secret then return true end
  end
  return false
end

-- The bucket key for this character, or nil when the client names nobody.
function Addon.CharacterQuestKey()
  if type(UnitGUID) == "function" then
    local ok, guid = pcall(UnitGUID, "player")
    if ok and type(guid) == "string" and not isSecret(guid) then
      guid = trim(guid)
      if guid ~= "" and guid ~= UNKNOWNOBJECT then
        return "guid:" .. guid
      end
    end
  end
  local name = nil
  if Addon.PlayerName then
    local ok, cached = pcall(Addon.PlayerName)
    if ok and type(cached) == "string" and cached ~= "" then
      name = cached
    end
  end
  if not name then return nil end
  if type(GetRealmName) == "function" then
    local ok, realm = pcall(GetRealmName)
    if ok and type(realm) == "string" and trim(realm) ~= "" then
      return "name:" .. name .. "@" .. trim(realm)
    end
  end
  return "name:" .. name
end

local function historyBucket(create)
  local key = Addon.CharacterQuestKey()
  if not key then return nil end
  if type(WordHunterWoWDB) ~= "table" then
    if not create then return nil end
    WordHunterWoWDB = {}
  end
  if type(WordHunterWoWDB.questHistory) ~= "table" then
    if not create then return nil end
    WordHunterWoWDB.questHistory = {}
  end
  local bucket = WordHunterWoWDB.questHistory[key]
  if type(bucket) ~= "table" then
    if not create then return nil end
    bucket = {}
    WordHunterWoWDB.questHistory[key] = bucket
  end
  return bucket
end

local function normalise(record)
  if type(record) ~= "table" then return nil end
  if record.accepted ~= true then record.accepted = false end
  if record.completed ~= true then record.completed = false end
  if record.title ~= nil and (type(record.title) ~= "string" or record.title == "") then
    record.title = nil
  end
  if record.titleLocale ~= nil and not Addon.SUPPORTED_LOCALES[record.titleLocale] then record.titleLocale = nil end
  return record
end

-- This character's history: numeric quest id -> { completed, accepted, title }.
-- The live table, answered read-only; {} when the client names nobody.
function Addon.GetCharacterQuestHistory()
  return historyBucket(false) or {}
end

-- Record that this character accepted or completed a quest. Never stores
-- descriptions or words, only the state and an optional title.
function Addon.RecordCharacterQuest(id, state, title, titleLocale)
  id = tonumber(id)
  if not id or id <= 0 or math.floor(id) ~= id then return nil end
  if state ~= "accepted" and state ~= "completed" then return nil end
  local bucket = historyBucket(true)
  if not bucket then return nil end
  local record = bucket[id]
  if type(record) ~= "table" then
    record = {}
    bucket[id] = record
  end
  normalise(record)
  if state == "accepted" then
    record.accepted = true
  else
    record.completed = true
  end
  if type(title) == "string" and trim(title) ~= "" then
    record.title = title
    record.titleLocale = titleLocale == Addon.TextLocale() and titleLocale or nil
  end
  return true
end

-- Only native observations enter this archive, apart from optional corpus
-- harvesting. Keep language and game separate: the same ID can be another
-- quest on Retail, Classic or Forever. Studying text records no completion.
function Addon.GetObservedQuestTexts(locale)
  local all = WordHunterWoWDB and WordHunterWoWDB.questTexts
  local flavor = Compat and Compat.GameFlavor() or "retail"
  local game = type(all) == "table" and all[flavor]
  local bucket = type(game) == "table" and game[locale or Addon.GetTargetLocale()]
  return type(bucket) == "table" and bucket or {}
end

function Addon.ArchiveNativeQuest(id, record, locale)
  id = tonumber(id)
  if not id or id <= 0 or id == math.huge or id ~= math.floor(id)
      or type(record) ~= "table" or record.catalog or record.readOnly
      or locale ~= Addon.TextLocale() or not Addon.SUPPORTED_LOCALES[locale] then return false end
  local function text(value)
    if type(value) ~= "string" or isSecret(value) then return "" end
    value = trim(value)
    return Addon.WithoutPlayerName and Addon.WithoutPlayerName(value) or value
  end
  local description, objectives = text(record.description), text(record.objectives)
  if description == "" and objectives == "" then return false end
  local flavor = Compat and Compat.GameFlavor() or "retail"
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.questTexts) ~= "table" then WordHunterWoWDB.questTexts = {} end
  local all = WordHunterWoWDB.questTexts
  if type(all[flavor]) ~= "table" then all[flavor] = {} end
  if type(all[flavor][locale]) ~= "table" then all[flavor][locale] = {} end
  local bucket = all[flavor][locale]
  local saved = type(bucket[id]) == "table" and bucket[id] or {}
  local title = text(record.title)
  if title ~= "" then saved.title = title end
  -- A later objective-only observation must not erase a known description.
  if description ~= "" then saved.description = description end
  if objectives ~= "" then saved.objectives = objectives end
  bucket[id] = saved
  return true
end

-- QUEST_DETAIL's NPC offer can disappear before the deferred UI refresh, for
-- example when a party accepts immediately. Snapshot raw native API results
-- synchronously; never substitute an event/log ID for the API's actual ID.
function Addon.CaptureNativeQuestOffer(expectedID)
  local function read(getter)
    if type(getter) ~= "function" then return nil end
    local ok, value = pcall(getter)
    if ok and not isSecret(value) then return value end
  end
  local id = read(GetQuestID)
  if type(id) ~= "number" and type(id) ~= "string" then return false end
  id = tonumber(id)
  if not id or id <= 0 or id == math.huge or id ~= math.floor(id) then return false end
  if expectedID ~= nil and id ~= tonumber(expectedID) then return false end
  local locale = read(Addon.TextLocale)
  if type(locale) ~= "string" or not Addon.SUPPORTED_LOCALES[locale] then return false end
  local record = { title = read(GetTitleText), description = read(GetQuestText), objectives = read(GetObjectiveText) }
  local ok, saved = pcall(Addon.ArchiveNativeQuest, id, record, locale)
  return ok and saved == true
end

local function retailBulkAvailable()
  return type(C_QuestLog) == "table"
    and type(C_QuestLog.GetAllCompletedQuestIDs) == "function"
end

local function legacyAvailable()
  return type(GetQuestsCompleted) == "function"
    and type(RequestQuestsCompleted) == "function"
end

-- Merge this character's completions and current log into history. Snapshots
-- add and never drop: an old completion outlives every re-sync, and a word
-- met in a quest never becomes a completion. Answers true once an identity
-- exists, nil without one.
function Addon.SyncCharacterQuestHistory()
  local bucket = historyBucket(true)
  if not bucket then return nil end
  for _, record in pairs(bucket) do normalise(record) end
  if retailBulkAvailable() then
    local ok, ids = pcall(Compat.CompletedQuestIDs)
    if ok and type(ids) == "table" then
      local seen = {}
      for _, id in pairs(ids) do
        id = tonumber(id)
        if id and id > 0 and math.floor(id) == id and not seen[id] then
          seen[id] = true
          local record = bucket[id]
          if type(record) ~= "table" then
            record = {}
            bucket[id] = record
          end
          normalise(record)
          record.completed = true
        end
      end
    end
  elseif legacyAvailable() then
    -- Classic only answers after being asked, on QUEST_QUERY_COMPLETE. Asked
    -- once per session; whatever is known already still merges below.
    if not legacyRequested then
      legacyRequested = true
      pcall(RequestQuestsCompleted)
    end
    local ok, ids = pcall(Compat.CompletedQuestIDs)
    if ok and type(ids) == "table" then
      for _, id in pairs(ids) do
        id = tonumber(id)
        if id and id > 0 and math.floor(id) == id then
          local record = bucket[id]
          if type(record) ~= "table" then
            record = {}
            bucket[id] = record
          end
          normalise(record)
          record.completed = true
        end
      end
    end
  end
  if Compat and Compat.QuestLogEntries then
    local ok, entries = pcall(Compat.QuestLogEntries)
    if ok and type(entries) == "table" then
      for _, entry in pairs(entries) do
        if type(entry) == "table" then
          local id = tonumber(entry.id)
          if id and id > 0 and math.floor(id) == id then
            local record = bucket[id]
            if type(record) ~= "table" then
              record = {}
              bucket[id] = record
            end
            normalise(record)
            record.accepted = true
            if type(entry.title) == "string" and trim(entry.title) ~= "" then
              record.title = entry.title
              record.titleLocale = Addon.TextLocale()
            end
          end
        end
      end
    end
  end
  return true
end
