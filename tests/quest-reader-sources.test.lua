-- lua tests/quest-reader-sources.test.lua
-- Safe sources and placeholder handling without touching Blizzard selection.
dofile('tests/wowstub.lua')
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestReader.lua')
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE' }, wordsByLocale = {} }
A.initializeDatabase()
UnitName = function() return 'Learner-Realm' end
C_QuestLog = nil
SelectQuestLogEntry = function() error('library reads must not change the selected live quest') end
WordHunterWoW_QuestData = { deDE = { ['61'] = { title = 'Titel', description = 'Hallo <name>, $N und {name}.', objectives = 'Findet den Hund.' } } }
local q = A.ResolveCatalogQuest('61')
assert(q and not q.readOnly and q.text:find('Hallo Learner, Learner und Learner.', 1, true), 'localized source and all name placeholders must resolve')
assert(q.text:find('\n\nFindet den Hund.', 1, true), 'description and objective remain separate paragraphs')
assert(q.passage == 'offer' and q.sourceLocale == 'deDE', 'localized offer keeps voice and learning context')
WordHunterWoW_QuestData = nil
WordHunterWoWCorpus = { byLocale = { deDE = {
  ['retail-description'] = { kind = 'description', id = 61, text = 'Retail-Text', flavor = 'retail' },
  ['classic-description'] = { kind = 'description', id = 61, text = 'Classic-Text', flavor = 'classic' },
  ['title:61'] = { kind = 'title', id = 61, text = 'Gespeicherter Titel', flavor = 'retail' },
} } }
q = A.ResolveCatalogQuest(61)
assert(q and q.text == 'Retail-Text' and q.title == 'Gespeicherter Titel', 'corpus must not mix clients sharing the same quest ID')
WordHunterWoW_QuestEN = { [62] = { title = 'Title only' }, [63] = { title = 'An objective', objectives = 'Find the dog.' } }
q = assert(A.ResolveCatalogQuest(62))
assert(q.catalogPhase == 'title' and q.text == 'Title only' and q.readOnly and q.voiceUnavailable
  and q.referenceNote:find('Title-only', 1, true), 'a title-only record must open with an explicit absence of dialogue')
assert(not A.ResolveCatalogQuest(62, 'deDE', 'offer'), 'a bare title must not impersonate quest dialogue')
q = A.ResolveCatalogQuest(63)
assert(q and q.readOnly and q.text == 'Find the dog.', 'objective-only English records are still readable')
for _, invalid in ipairs({ 0, -1, 1.5, math.huge, 'bad', {} }) do assert(A.ResolveCatalogQuest(invalid) == nil, 'invalid quest IDs must be rejected') end
WordHunterWoWCorpus = nil
WordHunterWoW_QuestEN = nil
C_QuestLog = {
  GetLogIndexForQuestID = function(id) return id == 61 and 1 or nil end,
  GetTitleForQuestID = function() return 'Live Titel' end,
}
GetQuestLogQuestText = function(index)
  assert(index == 1, 'Retail reads the requested log index')
  return 'Aktueller Text', 'Aktuelles Ziel'
end
q = A.ResolveCatalogQuest(61)
assert(q and q.text == 'Aktueller Text\n\nAktuelles Ziel' and q.source == 'quest log', 'native Retail text must be usable without changing selection')
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
A.Compat.Refresh()
A.Compat.QuestLogIndexForID = function() return 1 end
A.Compat.SelectedQuestID = function() return 99 end
GetQuestLogQuestText = function() error('legacy reads must not return another selected quest') end
WordHunterWoW_QuestEN = { [61] = { title = 'English', description = 'Safe database fallback' } }
q = A.ResolveCatalogQuest(61)
assert(q and q.readOnly and q.text == 'Safe database fallback', 'unselected Classic quest must use honest fallback rather than selecting it')
A.Compat.SelectedQuestID = function() return 61 end
GetQuestLogQuestText = function() return 'Ausgewählter Text', 'Ziel' end
q = A.ResolveCatalogQuest(61)
assert(q and not q.readOnly and q.text == 'Ausgewählter Text\n\nZiel', 'already selected legacy quest can be read without changing selection')
print('quest-reader-sources: localized, corpus, live, fallback, validation, no selection: ok')
