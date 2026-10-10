-- lua5.1 tests/quest-record-completion.test.lua [baseline-source-directory]
-- Incomplete native observations must not hide compatible stored quest fields.
dofile('tests/wowstub.lua')
local source = arg[1] or '.'
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'Recall.lua', 'UICommon.lua', 'Harvest.lua',
  'QuestHistory.lua', 'QuestPanel.lua', 'Editor.lua', 'QuestReader.lua' }) do dofile(source .. '/' .. file) end
local A = WordHunterWoW_Addon
GetBuildInfo = function() return '1.60.1', '', '', 16001 end
A.Compat.Refresh()
UnitGUID = function() return 'Player-record-completion-test' end
WordHunterWoWDB = { settings = { targetLocale = 'deDE', harvestCorpus = false, frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
C_QuestLog, GetQuestLogQuestText = nil, nil
SelectQuestLogEntry = function() error('offline quest reading must not change selection') end
local de = { title = 'Gespeicherter Titel', description = 'Die vollständige Beschreibung.', objectives = 'Gespeichertes Ziel.', flavor = 'forever', locale = 'deDE' }
local en = { title = 'Stored title', description = 'The complete description.', objectives = 'Stored objective.', flavor = 'forever', locale = 'enUS' }
WordHunterWoW_QuestDataByFlavor = { forever = { deDE = { [901] = de }, enUS = { [901] = en } } }
GetQuestID = function() return 901 end
GetTitleText = function() return 'Nativer Titel' end
GetQuestText = function() error('native description temporarily unavailable') end
GetObjectiveText = function() return 'Geht zum Dorf.' end
assert(A.CaptureNativeQuestOffer(901))
local archive = A.GetObservedQuestTexts('deDE')[901]
assert(archive.description == nil and archive.objectives == 'Geht zum Dorf.')
local q = assert(A.ResolveCatalogQuest(901, 'deDE'))
assert(q.text == de.description .. '\n\nGeht zum Dorf.', 'objective-only native archive must retain the compatible full DE description')
assert(q.title == 'Nativer Titel' and not q.readOnly and q.wordLocale == 'deDE')
assert(q.descriptionSource == 'database' and q.objectivesSource == 'observed text')
assert(archive.description == nil and de.objectives == 'Gespeichertes Ziel.', 'resolving must not copy database text into player archives or mutate the database')
A.createPanel(); A.panel.enScroll.GetVerticalScroll = function() return 0 end; A.createEditor()
assert(A.OpenCatalogQuest(901, 'deDE') and A.panel.wordCount > 4)
local clicked = false
for _, b in ipairs(A.panel.wordButtons) do
  if b:IsShown() and b.word == 'Beschreibung' then
    b:GetScript('OnClick')(b)
    assert(A.editor:IsShown() and A.selected.locale == 'deDE')
    clicked = true
    break
  end
end
assert(clicked, 'the supplemented description must have a real clickable word')

-- Observed text takes priority field by field; a known native description is never overwritten.
A.ArchiveNativeQuest(901, { description = 'Die native Beschreibung.' }, 'deDE')
q = assert(A.ResolveCatalogQuest(901, 'deDE'))
assert(q.text == 'Die native Beschreibung.\n\nGeht zum Dorf.')

-- The companion and explicit English reader share the same missing-field behavior.
GetLocale = function() return 'enUS' end
GetTitleText = function() return 'Native title' end
GetObjectiveText = function() return 'Go to the village.' end
assert(A.CaptureNativeQuestOffer(901))
GetLocale = function() return 'deDE' end
local english = assert(A.GetEnglishQuestRecord(901))
assert(english.description == en.description and english.objectives == 'Go to the village.' and english.title == 'Native title')
assert(A.OpenCatalogQuest(901, 'enUS'))
assert(A.lastQuest.text == en.description .. '\n\nGo to the village.' and A.lastQuest.wordLocale == 'enUS')
assert(A.GetObservedQuestTexts('enUS')[901].description == nil and A.GetTargetLocale() == 'deDE')

-- Only a compatible source can fill a missing field, even when the bucket is mislabeled.
WordHunterWoWDB.questTexts.forever.deDE[901].description = nil
de.sourceFlavor = 'retail'
q = assert(A.ResolveCatalogQuest(901, 'deDE'))
assert(q.text == 'Geht zum Dorf.' and not q.readOnly, 'Retail description must not fill a Forever observation')
de.sourceFlavor = nil; de.locale = 'enUS'
q = assert(A.ResolveCatalogQuest(901, 'deDE'))
assert(q.text == 'Geht zum Dorf.', 'English description in a mislabeled bucket must not become German')
de.locale = 'deDE'
WordHunterWoWDB.questTexts = nil
de.description, de.objectives = '', ''
q = assert(A.ResolveCatalogQuest(901, 'deDE'))
assert(q.catalogPhase == 'title' and q.text == de.title and not q.readOnly and q.voiceUnavailable,
  'a known German title remains learnable when German dialogue is absent')
q = assert(A.ResolveCatalogQuest(901, 'deDE', 'offer'))
assert(q.readOnly and q.sourceLocale == 'enUS' and not q.wordLocale and q.voiceUnavailable, 'English-only fallback keeps the read-only and voice guards')
assert(WordHunterWoWCorpus == nil and not WordHunterWoWDB.questTexts)
print('quest-record-completion: DE/EN missing fields, actual reader/editor, native priority, compatibility and no archive/database mutation: ok')
