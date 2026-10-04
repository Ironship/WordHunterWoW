-- Native text must survive completion with corpus harvesting disabled.
dofile('tests/wowstub.lua')
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'UICommon.lua', 'QuestPanel.lua', 'Editor.lua',
    'QuestBrowser.lua', 'Harvest.lua', 'QuestHistory.lua', 'QuestReader.lua' }) do dofile(file) end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', harvestCorpus = false, frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
UnitGUID = function() return 'Player-observed-quest' end
UnitName = function() return 'Learner' end
GetBuildInfo = function() return '1.60.0', '', '', 16001 end
A.Compat.Refresh()
assert(A.Compat.GameFlavor() == 'forever')
SelectQuestLogEntry = function() error('archiving/library must never change selection') end
local inLog = true
C_QuestLog = {
  GetNumQuestLogEntries = function() return inLog and 1 or 0 end,
  GetInfo = function() return { questID = 218, title = 'Das gestohlene Tagebuch' } end,
}
A.SyncCharacterQuestHistory()
assert(A.GetCharacterQuestHistory()[218].titleLocale == 'deDE', 'live log titles have confirmed language')
GetQuestID = function() return 218 end
GetTitleText = function() return 'Das gestohlene Tagebuch' end
GetQuestText = function() return 'Der Hund wartet auf Learner.' end
GetObjectiveText = function() return 'Findet den Hund.' end
A.createPanel()
A.panel.enScroll.GetVerticalScroll = function() return 0 end
A.createEditor()
QuestFrame:Show()
A.lastPassage = 'offer'
A.readCurrentQuest()
local saved = A.GetObservedQuestTexts('deDE')[218]
assert(saved and saved.description == 'Der Hund wartet auf <name>.', 'NPC native description is saved with name normalization')
assert(saved.objectives == 'Findet den Hund.' and saved.title == 'Das gestohlene Tagebuch')
assert(WordHunterWoWDB.settings.harvestCorpus == false and WordHunterWoWCorpus == nil,
  'the independent library archive must not turn on or write the optional corpus')

-- Existing legacy log selection can fail and return another quest's text.
-- Such a read may not poison the new persistent native archive.
local logText, logTitle, selectedID = A.Compat.QuestLogText, A.Compat.TitleForQuestID, A.Compat.SelectedQuestID
A.Compat.QuestLogText = function() return 'Text eines anderen Quests.', 'Falsches Ziel.' end
A.Compat.TitleForQuestID = function() return 'Titel des angeforderten Quests' end
A.Compat.SelectedQuestID = function() return 999 end
A.readCurrentQuest(999, true)
assert(A.GetObservedQuestTexts('deDE')[999] == nil, 'explicit log reader must not archive unverified ID/text')
QuestInfoFrame = { questLog = true }
A.readCurrentQuest()
assert(A.GetObservedQuestTexts('deDE')[999] == nil, 'displayed log reader must not archive unverified ID/text')
QuestInfoFrame = nil
A.Compat.QuestLogText, A.Compat.TitleForQuestID, A.Compat.SelectedQuestID = logText, logTitle, selectedID

-- Use the real turn-in handler, then remove all live/corpus/database German.
local events, create = nil, CreateFrame
CreateFrame = function(...)
  local frame = create(...)
  if not events then events = frame end
  return frame
end
dofile('Init.lua')
CreateFrame = create
inLog = false
events:GetScript('OnEvent')(events, 'QUEST_TURNED_IN', 218)
assert(A.GetCharacterQuestHistory()[218].completed, 'actual turn-in event marks this character completed')
GetQuestLogQuestText = nil
QuestFrame:Hide()
A.lastQuest = nil
WordHunterWoW_QuestEN = { [218] = { title = 'The Stolen Journal', description = 'The dog waits.' },
  [219] = { title = 'Only English', description = 'The tree waits.' } }
WordHunterWoW_QuestData = nil
local rows = A.CollectQuestCatalog()
local row
for _, entry in ipairs(rows) do if entry.id == 218 then row = entry end end
assert(row and row.completed and row.title == 'Das gestohlene Tagebuch' and row.titleLocale == 'deDE'
  and row.titleSource == 'observed text', 'native completed title wins over English with explicit provenance')
assert(A.OpenCatalogQuest(218), 'completed native archive must reopen through the real reader')
assert(not A.lastQuest.readOnly and A.lastQuest.sourceLocale == 'deDE' and A.lastQuest.source == 'observed text')
assert(A.lastQuest.text == 'Der Hund wartet auf Learner.\n\nFindet den Hund.')
local word
for _, button in ipairs(A.panel.wordButtons) do
  if button:IsShown() and button.word == 'Hund' then word = button break end
end
assert(word and word:GetScript('OnClick'), 'native archive still renders real clickable words')
word:GetScript('OnClick')(word)
assert(A.editor:IsShown() and A.selected.word == 'Hund' and A.selected.questId == '218')
assert(A.OpenCatalogQuest(219) and A.lastQuest.readOnly and A.lastQuest.sourceLocale == 'enUS',
  'English-only completed quests keep their honest read-only fallback')
assert(A.GetObservedQuestTexts('deDE')[219] == nil, 'reading English cannot create a German archive')

-- Title-only history preserves unknown titles without claiming German content.
local history = A.GetCharacterQuestHistory()
history[220] = { completed = true, title = 'Gesicherter deutscher Titel', titleLocale = 'deDE' }
history[221] = { completed = true, title = 'Alter Titel unbekannter Sprache' }
history[222] = { completed = true, title = 'Old unknown title' }
WordHunterWoW_QuestEN[220] = { title = 'English 220' }
WordHunterWoW_QuestEN[221] = { title = 'English 221' }
WordHunterWoW_QuestData = { deDE = { [222] = { title = 'Titel aus deutscher Datenbank' } } }
local byID = {}
for _, entry in ipairs(A.CollectQuestCatalog()) do byID[entry.id] = entry end
assert(byID[220].title == history[220].title and byID[220].titleLocale == 'deDE'
  and byID[220].titleSource == 'quest history')
assert(byID[221].title == history[221].title and byID[221].titleLocale == nil
  and byID[221].titleSource == 'quest history', 'unknown legacy title remains usable without impersonating confirmed German')
assert(byID[222].title == 'Titel aus deutscher Datenbank', 'unknown legacy title must not replace localized known data')
WordHunterWoW_QuestEN[221].description = 'English-only historical text.'
assert(A.OpenCatalogQuest(221) and A.lastQuest.readOnly and A.lastQuest.sourceLocale == 'enUS',
  'a saved title of unknown language must never unlock English as German vocabulary')

-- Actual live log reads are captured too, without moving the selection.
GetBuildInfo = function() return '12.1.0', '', '', 120100 end
A.Compat.Refresh()
C_QuestLog.GetLogIndexForQuestID = function(id) return id == 223 and 1 or nil end
C_QuestLog.GetTitleForQuestID = function() return 'Aus dem Log' end
GetQuestLogQuestText = function(index)
  assert(index == 1)
  return 'Ein lebendiger Text.', 'Ein lebendiges Ziel.'
end
local live = A.ResolveCatalogQuest(223)
assert(live and live.source == 'quest log' and A.GetObservedQuestTexts('deDE')[223], 'safe native log read is archived')
assert(A.GetObservedQuestTexts('deDE')[218] == nil, 'Forever text must never be reused for Retail sharing the quest ID')
GetQuestLogQuestText = nil
assert(A.ResolveCatalogQuest(218).readOnly, 'wrong-flavor German archive cannot suppress English fallback')
GetBuildInfo = function() return '1.60.0', '', '', 16001 end
A.Compat.Refresh()
assert(A.ResolveCatalogQuest(218).source == 'observed text', 'the original flavor still owns its native snapshot')
assert(A.ArchiveNativeQuest(218, { objectives = 'Neues Ziel.' }, 'deDE'))
assert(A.GetObservedQuestTexts('deDE')[218].description == saved.description,
  'objective-only observation must preserve an existing description')
assert(not A.ArchiveNativeQuest(218, { description = 'English fallback', readOnly = true }, 'deDE'))
assert(not A.ArchiveNativeQuest(218, { description = 'Catalog text', catalog = true }, 'deDE'))
assert(not A.ArchiveNativeQuest(218, { description = 'Another language' }, 'enUS'))
assert(not A.ArchiveNativeQuest(0, { description = 'Not a quest' }, 'deDE'))
GetLocale = function() return 'enUS' end
assert(A.ArchiveNativeQuest(224, { description = 'Actual native English.' }, 'enUS'))
assert(A.GetObservedQuestTexts('enUS')[224] and A.GetObservedQuestTexts('deDE')[224] == nil,
  'native English remains in its actual language even when the learning target is German')
GetLocale = function() return 'deDE' end
WordHunterWoW_QuestEN[224] = { title = 'English 224', description = 'English reference.' }
assert(A.ResolveCatalogQuest(224).readOnly, 'an English native snapshot cannot satisfy the German reader')
A.initializeDatabase()
dofile('QuestHistory.lua')
assert(A.GetObservedQuestTexts('deDE')[218].description == saved.description,
  'native snapshots survive database initialization and module reload')
assert(WordHunterWoWDB.settings.harvestCorpus == false and WordHunterWoWCorpus == nil)
print('quest-observed-text: native capture, completion, clickable reopening, provenance, language/flavor isolation: ok')
