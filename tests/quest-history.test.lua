-- Run from the addon root:  lua tests/quest-history.test.lua
--
-- Per-character quest history: which quests THIS character accepted and
-- completed. Reading a quest's words (or another character's deeds) is not
-- completing it, so history lives apart from the word table and the corpus,
-- keyed by UnitGUID when it answers plainly and by name@realm otherwise.
-- There is deliberately no bucket for "unknown character": without an
-- identity nothing is recorded and nothing is returned.
--
-- Records carry exactly: completed (bool), accepted (bool), title (string or
-- nil). inLog is live state from Compat.QuestLogEntries and is never stored.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("Harvest.lua")

local loaded, loadErr = pcall(dofile, "QuestHistory.lua")
assert(loaded, "QuestHistory.lua must load: " .. tostring(loadErr))
local Addon = WordHunterWoW_Addon
assert(type(Addon.GetCharacterQuestHistory) == "function",
  "QuestHistory.lua must provide Addon.GetCharacterQuestHistory")
assert(type(Addon.SyncCharacterQuestHistory) == "function",
  "QuestHistory.lua must provide Addon.SyncCharacterQuestHistory")
assert(type(Addon.RecordCharacterQuest) == "function",
  "QuestHistory.lua must provide Addon.RecordCharacterQuest")
assert(type(Addon.CharacterQuestKey) == "function",
  "QuestHistory.lua must provide Addon.CharacterQuestKey")
assert(type(Addon.Compat.CompletedQuestIDs) == "function",
  "Compat.lua must provide Compat.CompletedQuestIDs")

local function clearApi()
  for _, name in ipairs({
    "UnitGUID", "UnitName", "UnitNameUnmodified", "GetUnitName", "GetRealmName",
    "C_QuestLog", "GetQuestsCompleted", "RequestQuestsCompleted",
    "GetQuestLogIndexByID", "GetQuestLogTitle", "GetNumQuestLogEntries",
    "IsQuestFlaggedCompleted", "IsQuestFlaggedCompletedOnAccount",
    "issecretvalue", "UNKNOWNOBJECT",
  }) do _G[name] = nil end
end

local function freshDb()
  WordHunterWoWDB = nil
  Addon.initializeDatabase()
end

local function historySize(h)
  local n = 0
  for _ in pairs(h) do n = n + 1 end
  return n
end

local function useGuid(guid)
  clearApi()
  UnitGUID = function(unit)
    assert(unit == "player", "identity is only ever read for the player")
    return guid
  end
end

-- No identity at all: nothing recorded, nothing returned, no shared bucket --
clearApi()
freshDb()
assert(historySize(Addon.GetCharacterQuestHistory()) == 0, "unknown character has no history")
assert(Addon.CharacterQuestKey() == nil, "unknown character has no key")
assert(Addon.RecordCharacterQuest(40, "completed") == nil, "unknown character records nothing")
assert(Addon.SyncCharacterQuestHistory() == nil, "unknown character syncs nothing")
local buckets = WordHunterWoWDB.questHistory
assert(buckets == nil or historySize(buckets) == 0, "there must be no shared unknown-character bucket")
assert(Addon.RecordCharacterQuest(0, "completed") == nil, "id 0 is rejected")
assert(Addon.RecordCharacterQuest(-3, "completed") == nil, "negative ids are rejected")
assert(Addon.RecordCharacterQuest("abc", "completed") == nil, "non-numeric ids are rejected")
assert(Addon.RecordCharacterQuest(nil, "completed") == nil, "nil ids are rejected")
print("  unknown character records nothing and leaves no bucket")

-- GUID identity: accept then complete, exact record fields -------------------
useGuid("Player-1-0001")
freshDb()
assert(Addon.CharacterQuestKey() == "guid:Player-1-0001", "key is the plain GUID")
assert(Addon.RecordCharacterQuest(40, "accepted", "A Threat Within") == true)
local h = Addon.GetCharacterQuestHistory()
assert(historySize(h) == 1, "one quest recorded")
local rec = h[40]
assert(type(rec) == "table", "records are tables keyed by numeric id")
assert(rec.accepted == true and rec.completed == false,
  "accepted is true, completed is an explicit false")
assert(rec.title == "A Threat Within", "title is stored")
assert(rec.inLog == nil, "inLog is live state and is never stored")
assert(Addon.RecordCharacterQuest(40, "completed") == true)
assert(h[40].completed == true and h[40].accepted == true, "completing keeps the accept")
assert(h[40].title == "A Threat Within", "completing without a title keeps the old one")
assert(Addon.RecordCharacterQuest(40, "seen") == nil, "unknown states are rejected")
assert(Addon.RecordCharacterQuest(40, "completed", "") == true, "empty titles are ignored")
assert(h[40].title == "A Threat Within", "empty titles do not clobber")
print("  guid identity records accepted/completed with exact fields")

-- A secret GUID is never a key: fall back to the stable name -----------------
clearApi()
local SECRET = "secret-guid-value"
issecretvalue = function(v) return v == SECRET end
UnitGUID = function() return SECRET end
UnitName = function() return "Aryo" end
freshDb()
assert(Addon.CharacterQuestKey() == "name:Aryo", "a secret GUID falls back to the name")
assert(Addon.RecordCharacterQuest(40, "completed") == true)
for key in pairs(WordHunterWoWDB.questHistory) do
  assert(not tostring(key):find("secret"), "the secret value must never become a key")
end
assert(Addon.GetCharacterQuestHistory()[40].completed == true)
-- A GUID reader that throws is the same as no GUID reader.
UnitGUID = function() error("gone") end
assert(Addon.CharacterQuestKey() == "name:Aryo", "a throwing GUID reader falls back to the name")
-- With a realm the fallback is stable per character.
GetRealmName = function() return "Realm" end
assert(Addon.CharacterQuestKey() == "name:Aryo@Realm", "realm joins the fallback key")
print("  secret or throwing GUIDs fall back to name, never stored")

-- Two characters never share history -----------------------------------------
useGuid("Player-1-AAAA")
freshDb()
assert(Addon.RecordCharacterQuest(40, "completed") == true)
UnitGUID = function() return "Player-1-BBBB" end
assert(historySize(Addon.GetCharacterQuestHistory()) == 0, "the second character starts empty")
assert(Addon.RecordCharacterQuest(61, "accepted", "Kobold Camp Cleanup") == true)
UnitGUID = function() return "Player-1-AAAA" end
local a = Addon.GetCharacterQuestHistory()
assert(a[40] and a[40].completed == true, "first character kept its completion")
assert(a[61] == nil, "the second character's quest leaked across")
UnitGUID = function() return "Player-1-BBBB" end
local b = Addon.GetCharacterQuestHistory()
assert(b[61] and b[61].accepted == true, "second character kept its accept")
assert(b[40] == nil, "the first character's quest leaked across")
assert(historySize(WordHunterWoWDB.questHistory) == 2, "one bucket per character")
print("  characters are isolated by GUID")

-- Completed ids come from the bulk APIs, never the account-wide flag ---------
clearApi()
IsQuestFlaggedCompletedOnAccount = function() error("account-wide flag must never be consulted") end
C_QuestLog = { GetAllCompletedQuestIDs = function() return { 40, 61, "nope", -5, 0 } end }
local ids = Addon.Compat.CompletedQuestIDs()
assert(type(ids) == "table" and #ids == 2 and ids[1] == 40 and ids[2] == 61,
  "retail answers the numeric ids only")
-- Classic fills a table with id -> true instead of answering a list.
clearApi()
IsQuestFlaggedCompletedOnAccount = function() error("account-wide flag must never be consulted") end
GetQuestsCompleted = function(out)
  out[7], out[8], out[9] = true, true, false
  return out
end
ids = Addon.Compat.CompletedQuestIDs()
local seen = {}
for _, id in ipairs(ids) do seen[id] = true end
assert(seen[7] and seen[8] and not seen[9] and #ids == 2, "classic answers the true flags only")
clearApi()
assert(Addon.Compat.CompletedQuestIDs() == nil, "no API means nil, not empty or false")
C_QuestLog = { GetAllCompletedQuestIDs = function() error("gone") end }
assert(Addon.Compat.CompletedQuestIDs() == nil, "a throwing bulk API means nil")
GetQuestsCompleted = function() error("gone") end
C_QuestLog = nil
assert(Addon.Compat.CompletedQuestIDs() == nil, "a throwing classic API means nil")
print("  bulk completion apis are normalised, account flag untouched")

-- Sync merges: old completions stay, words are not completions ----------------
useGuid("Player-1-AAAA")
freshDb()
WordHunterWoWDB.questHistory = {
  ["guid:Player-1-AAAA"] = { [999] = { completed = true } },
}
Addon.GetWordsTable().hund = { word = "Hund", status = "learning", translation = "dog",
  questId = "61", questTitle = "Kobold Camp Cleanup" }
C_QuestLog = {
  GetAllCompletedQuestIDs = function() return { 999, 1000 } end,
  GetNumQuestLogEntries = function() return 1 end,
  GetInfo = function(index)
    if index == 1 then return { questID = 40, title = "A Threat Within" } end
    return nil
  end,
}
assert(Addon.SyncCharacterQuestHistory() == true)
h = Addon.GetCharacterQuestHistory()
assert(h[999] and h[999].completed == true, "the imported completion survives a re-sync")
assert(h[999].accepted == false, "legacy records normalise to explicit booleans")
assert(h[1000] and h[1000].completed == true and h[1000].accepted == false,
  "new completions arrive as completed-only")
assert(h[40] and h[40].accepted == true and h[40].title == "A Threat Within",
  "the current log arrives as accepted with its title")
assert(h[40].completed == false, "being in the log is not being completed")
assert(h[61] == nil, "a word met in a quest is not a completed quest")
assert(h[999].inLog == nil and h[40].inLog == nil, "sync never stores live log state")
-- Words, settings and corpus are untouched by history.
assert(Addon.GetWordsTable().hund ~= nil, "history never drops words")
assert(WordHunterWoWDB.settings.targetLocale ~= nil, "history never drops settings")
print("  sync merges snapshots without dropping records or inventing completions")

-- Repeatables stay completed while back in the log ----------------------------
useGuid("Player-1-AAAA")
freshDb()
C_QuestLog = {
  GetAllCompletedQuestIDs = function() return { 40 } end,
  GetNumQuestLogEntries = function() return 1 end,
  GetInfo = function() return { questID = 40, title = "A Threat Within" } end,
}
assert(Addon.RecordCharacterQuest(40, "completed", "A Threat Within") == true)
assert(Addon.SyncCharacterQuestHistory() == true)
h = Addon.GetCharacterQuestHistory()
assert(h[40].completed == true, "a repeatable back in the log stays completed")
assert(h[40].accepted == true, "the re-accept is recorded alongside")
local inLog = false
for _, e in ipairs(Addon.Compat.QuestLogEntries()) do
  if tonumber(e.id) == 40 then inLog = true end
end
assert(inLog, "inLog stays a separate live answer from the log")
print("  repeatables remain completed with inLog separate")

-- Classic asks the server once per session, then imports on the answer --------
clearApi()
freshDb()
useGuid("Player-1-AAAA")
local legacyData = {}
local requested = 0
GetQuestsCompleted = function(out)
  for id in pairs(legacyData) do out[id] = true end
  return out
end
RequestQuestsCompleted = function() requested = requested + 1 end
GetNumQuestLogEntries = function() return 0 end
assert(Addon.SyncCharacterQuestHistory() == true)
assert(requested == 1, "the legacy catalogue is requested")
assert(Addon.SyncCharacterQuestHistory() == true)
assert(requested == 1, "the legacy catalogue is requested only once per session")
legacyData[7] = true
assert(Addon.SyncCharacterQuestHistory() == true, "QUEST_QUERY_COMPLETE syncs the answer")
assert(Addon.GetCharacterQuestHistory()[7]
  and Addon.GetCharacterQuestHistory()[7].completed == true,
  "the queried completion is imported")
assert(requested == 1, "importing the answer requests nothing further")
print("  legacy catalogue is requested once, imported on QUEST_QUERY_COMPLETE")

-- Reloading the files keeps every character and every word --------------------
local before = historySize(Addon.GetCharacterQuestHistory())
assert(before > 0, "the reload test needs history to keep")
local wordsBefore = historySize(Addon.GetWordsTable())
assert(loadfile("QuestHistory.lua"))("WordHunterWoW")
assert(Addon.GetCharacterQuestHistory()[7]
  and Addon.GetCharacterQuestHistory()[7].completed == true,
  "history survives a file reload")
assert(historySize(Addon.GetWordsTable()) == wordsBefore, "words survive a file reload")
print("  file reload keeps history, words and settings")

-- Event lifecycle: accepts and turn-ins record, nothing reads quest text ------
local realCreateFrame = CreateFrame
local eventsFrame, registered = nil, {}
CreateFrame = function(kind, name, parent, template)
  local f = realCreateFrame(kind, name, parent, template)
  if kind == "Frame" and name == nil and eventsFrame == nil then
    eventsFrame = f
    f.RegisterEvent = function(self, event) registered[#registered + 1] = event end
  end
  return f
end
local initOk, initErr = pcall(dofile, "Init.lua")
CreateFrame = realCreateFrame
assert(initOk, "Init.lua must load: " .. tostring(initErr))
assert(eventsFrame, "Init.lua must create its event frame")
local function wants(event)
  for _, name in ipairs(registered) do if name == event then return true end end
  return false
end
for _, event in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_LOG_UPDATE", "QUEST_QUERY_COMPLETE" }) do
  assert(wants(event), "Init.lua must register " .. event)
end
local onEvent = eventsFrame:GetScript("OnEvent")
assert(type(onEvent) == "function", "the event frame needs its OnEvent script")

useGuid("Player-1-EVNT")
freshDb()
Addon.hookQuestUi = function() end
local readerFired = false
Addon.readCurrentQuest = function() readerFired = true end
C_QuestLog = {
  GetAllCompletedQuestIDs = function() return {} end,
  GetNumQuestLogEntries = function() return 0 end,
}
onEvent(eventsFrame, "QUEST_ACCEPTED", 7, 40)
h = Addon.GetCharacterQuestHistory()
assert(h[40] and h[40].accepted == true, "QUEST_ACCEPTED records the accept")
assert(not readerFired, "accepting must not trigger the quest reader")
onEvent(eventsFrame, "QUEST_ACCEPTED", 9)
h = Addon.GetCharacterQuestHistory()
assert(h[9] and h[9].accepted == true, "modern one-argument accept records that quest id")
onEvent(eventsFrame, "QUEST_TURNED_IN", 40)
assert(Addon.GetCharacterQuestHistory()[40].completed == true, "QUEST_TURNED_IN records the completion")
assert(not readerFired, "turning in must not trigger the quest reader")
C_QuestLog.GetAllCompletedQuestIDs = function() return { 40, 100 } end
onEvent(eventsFrame, "QUEST_LOG_UPDATE")
assert(Addon.GetCharacterQuestHistory()[100]
  and Addon.GetCharacterQuestHistory()[100].completed == true,
  "QUEST_LOG_UPDATE re-syncs")
assert(not readerFired, "log updates must not trigger the quest reader")
onEvent(eventsFrame, "QUEST_QUERY_COMPLETE")
assert(not readerFired, "query answers must not trigger the quest reader")
onEvent(eventsFrame, "PLAYER_LOGIN")
assert(not readerFired, "login syncs without reading quest text")
onEvent(eventsFrame, "PLAYER_ENTERING_WORLD")
assert(not readerFired, "entering the world syncs without reading quest text")
print("  quest events record and sync without touching the quest reader")

print("quest-history: ok")
