-- lua5.1 tests/quest-catalog-language.test.lua [baseline-source-directory]
-- Catalog language is separate from the global learning language.
dofile('tests/wowstub.lua')
local baseline = arg[1]
local owned = { ['Core.lua'] = true, ['Recall.lua'] = true, ['Editor.lua'] = true,
  ['Harvest.lua'] = true, ['QuestReader.lua'] = true }
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'Recall.lua', 'UICommon.lua', 'Editor.lua',
    'QuestPanel.lua', 'WordList.lua', 'QuestBrowser.lua', 'Harvest.lua', 'QuestHistory.lua', 'QuestReader.lua' }) do
  dofile(baseline and owned[file] and baseline .. '/' .. file or file)
end
local A = WordHunterWoW_Addon
assert(type(A.GetCatalogLocale) == 'function', 'catalog language needs its own session locale API')
GetBuildInfo = function() return '1.60.1', '', '', 16001 end
A.Compat.Refresh()
assert(A.Compat.GameFlavor() == 'forever')
UnitGUID = function() return 'Player-catalog-languages' end
UnitName = function() return 'Learner' end
WordHunterWoWDB = { settings = { targetLocale = 'deDE', targetLocaleChosen = true,
  harvestCorpus = true, frames = {} }, wordsByLocale = {
  deDE = { gift = { word = 'Gift', status = 'known', translation = 'poison' } },
} }
A.initializeDatabase()
A.RegisterDictionaryProvider('deDE', 'de-fixture', { gift = { word = 'Gift', translation = 'poison' } })
A.RegisterDictionaryProvider('enUS', 'en-fixture', { gift = { word = 'gift', translation = 'present' } })
local de = { title = 'Eine Bedrohung', description = 'Das Gift bleibt.', objectives = 'Sprecht mit McBride.' }
local en = { title = 'A Threat Within', description = 'The gift remains.', objectives = 'Speak with McBride.' }
WordHunterWoW_QuestData = { deDE = { [888] = { title = 'Legacy', description = 'Legacy mixed-version data.' } } }
WordHunterWoW_QuestEN = {
  [783] = { title = 'Retail 783', description = 'Deathwing and his Twilight armies.' },
  [888] = { title = 'Retail 888', description = 'A wrong-version fallback.' },
}
WordHunterWoW_QuestDataByFlavor = {
  retail = { deDE = { [783] = { title = 'Retail', description = 'Deathwing.' } }, enUS = WordHunterWoW_QuestEN },
  classic = { deDE = { [783] = de }, enUS = { [783] = en } },
  forever = { sourceFlavor = 'classic', deDE = { [783] = de }, enUS = { [783] = en } },
}
C_QuestLog, GetQuestLogQuestText = nil, nil
SelectQuestLogEntry = function() error('completed catalog reading must never select a live quest') end
A.RecordCharacterQuest(783, 'completed')
A.createPanel()
A.panel.enScroll.GetVerticalScroll = function() return 0 end
A.createEditor()
WordHunterWoWDB.settings.frames[A.LayoutKey('panel')] = { w = 1000, h = 700, userSized = true }
assert(A.GetCatalogLocale() == 'deDE' and A.GetTargetLocale() == 'deDE')
assert(A.ResolveCatalogQuest(888) == nil, 'qualified pack must not fall through to legacy wrong-version IDs')
assert(A.GetEnglishQuestRecord(783) == en, 'ID783 must resolve the qualified Classic offer, not Retail backfill')
local _, sourceFlavor = A.GetQuestDatabase('deDE')
assert(sourceFlavor == 'classic', 'Forever sharing must preserve explicitly declared Classic provenance')
assert(A.OpenCatalogQuest(783))
assert(A.lastQuest.wordLocale == 'deDE' and A.lastQuest.sourceLocale == 'deDE'
  and A.lastQuest.sourceFlavor == 'classic' and not A.lastQuest.readOnly)
assert(A.lastQuest.text:find('Das Gift bleibt.', 1, true) and not A.lastQuest.text:find('Deathwing', 1, true))
local function wordButton(word)
  for _, button in ipairs(A.panel.wordButtons) do
    if button:IsShown() and button.word == word then return button end
  end
  error('missing real clickable word: ' .. word)
end
wordButton('Gift'):GetScript('OnClick')(wordButton('Gift'))
assert(A.editor:IsShown() and A.selected.locale == 'deDE' and A.editor.translation:GetText() == 'poison')
A.editor:Hide()
local width, height = A.panel:GetSize()
assert(A.SetCatalogLocale('enUS'))
assert(A.GetTargetLocale() == 'deDE' and WordHunterWoWDB.settings.targetLocale == 'deDE', 'catalog switch must leave global learning setting German')
assert(A.lastQuest.id == 783 and A.lastQuest.wordLocale == 'enUS' and not A.lastQuest.readOnly
  and A.lastQuest.voiceUnavailable, 'explicit English is editable English, with German voice unavailable')
assert(A.panel:GetWidth() == width and A.panel:GetHeight() == height, 'language switching must preserve user-sized reader geometry')
assert(not A.panel.integratedLayout, 'explicit English must not duplicate itself into an English companion column')
wordButton('gift'):GetScript('OnClick')(wordButton('gift'))
assert(A.selected.locale == 'enUS' and A.editor.translation:GetText() == 'present', 'same key must use its English dictionary')
A.selected.status = 'learning'
A.editor.translation:SetText('a present')
A.editor.save:GetScript('OnClick')(A.editor.save)
assert(A.GetWordsTable('enUS').gift.translation == 'a present')
assert(A.GetWordsTable('deDE').gift.translation == 'poison' and A.GetWordsTable('deDE').gift.status == 'known', 'English Save must preserve German vocabulary')
assert(A.GetRecallRow('gift', nil, 'enUS').examples[1].text == 'The gift remains.')
assert(A.GetRecallRow('gift', nil, 'deDE') == nil, 'English examples must never enter German recall')
assert(WordHunterWoWLanguage == 'de' and not WordHunterWoWExport:find('a%%20present'), 'global export must still represent the German profile')
local now = time()
A.GetWordsTable('enUS').gift.statusChangedAt = now - 3 * 86400
A.SetRecallCheck(true)
wordButton('gift'):GetScript('OnClick')(wordButton('gift'))
assert(A.selected.locale == 'enUS' and A.selected.recallPending, 'English recall due state must use English rows and status')
A.editor.cover.buttons[4]:GetScript('OnClick')(A.editor.cover.buttons[4])
assert(A.GetRecallRow('gift', nil, 'enUS').ratingCount == 1 and A.GetRecallRow('gift', nil, 'deDE') == nil,
  'actual editor rating buttons must write only the frozen English locale')
A.editor.translation:SetText('present')
A.selected.status = 'new'
A.editor.save:GetScript('OnClick')(A.editor.save)
assert(A.GetWordsTable('enUS').gift == nil and A.GetWordsTable('deDE').gift.translation == 'poison',
  'resetting an overlay to its dictionary must remove only the English entry')
assert(A.SetCatalogLocale('deDE') and A.lastQuest.wordLocale == 'deDE' and A.GetTargetLocale() == 'deDE')
wordButton('Gift'):GetScript('OnClick')(wordButton('Gift'))
assert(A.selected.locale == 'deDE' and A.editor.translation:GetText() == 'poison')
assert(A.GetCharacterQuestHistory()[783].completed, 'language switching/studying must preserve character completion state')
local byID = {}
for _, row in ipairs(A.CollectQuestCatalog()) do byID[row.id] = row end
assert(byID[783].completed and byID[783].title == de.title, 'Completed and All quests must use the localized qualified title')

-- The locale is frozen even if a later global settings change happens.
A.openEditor('gift', 'Frozen English context.', 783, en.title, { locale = 'enUS' })
A.selected.status = 'learning'
A.editor.translation:SetText('frozen English')
WordHunterWoWDB.settings.targetLocale = 'frFR'
A.editor.save:GetScript('OnClick')(A.editor.save)
assert(A.GetWordsTable('enUS').gift.translation == 'frozen English' and A.GetWordsTable('frFR').gift == nil)
WordHunterWoWDB.settings.targetLocale = 'deDE'
assert(A.HarvestUnknownWord('different', 783, 'enUS'))
assert(WordHunterWoWCorpus.byLocale.enUS['forever:word:different'] and not WordHunterWoWCorpus.byLocale.deDE['forever:word:different'])
A.rebuildHarvestExport()
assert(WordHunterWoWCorpus.byLocale.enUS['forever:word:different'], 'exporting German harvest must preserve unexported English text')

-- Missing German is still an honest read-only English fallback.
WordHunterWoW_QuestDataByFlavor.forever.enUS[784] = { title = 'English only', description = 'The tree waits.' }
local fallback = A.ResolveCatalogQuest(784, 'deDE')
assert(fallback.readOnly and fallback.sourceLocale == 'enUS' and not fallback.wordLocale)
assert(not A.ResolveCatalogQuest(784, 'enUS').readOnly, 'explicit English request may learn the available English text')
WordHunterWoW_QuestDataByFlavor.forever.enUS[785] = { title = 'Partial native', objectives = 'Speak to McBride.',
  description = 'Deathwing Retail backfill', descriptionSource = 'retail-backfill' }
assert(not A.GetEnglishQuestRecord(785).description:find('Deathwing', 1, true), 'known Retail backfill may not impersonate native Classic/Forever text')
WordHunterWoW_QuestDataByFlavor.forever.enUS[786] = { title = 'Wrong game', description = 'Retail offer.', flavor = 'retail' }
assert(A.GetEnglishQuestRecord(786) == nil, 'declared wrong-flavor record must never enter the current reader')

-- Native collected text and fresh NPC text outrank the community fallback.
WordHunterWoW_QuestDataByFlavor.forever.deDE[789] = { title = 'Static', description = 'Static Classic description.' }
WordHunterWoWCorpus.byLocale.deDE = { ['forever:description:789'] = {
  id = 789, kind = 'description', flavor = 'forever', text = 'Native Forever balance change.' } }
assert(A.ResolveCatalogQuest(789, 'deDE').text == 'Native Forever balance change.')
WordHunterWoW_QuestDataByFlavor.forever.deDE[790] = { title = 'Static', description = 'Static offer.' }
A.lastQuest = { id = 790, title = 'NPC', text = 'Actual fresh offer.', passage = 'offer', sourceFlavor = 'forever' }
assert(A.ResolveCatalogQuest(790, 'deDE').text == 'Actual fresh offer.')
A.lastQuest = nil
assert(A.ArchiveNativeQuest(783, { title = 'Native', description = 'Actual observed German.' }, 'deDE'))
assert(A.ResolveCatalogQuest(783, 'deDE').source == 'observed text', 'observed client snapshots must still outrank the bundled corpus')

-- Personalize the source language; English class/race names cannot be German.
UnitClass = function() return 'Paladin', 'PALADIN' end
UnitRace = function() return 'Mensch', 'Human' end
UnitSex = function() return 3 end
WordHunterWoW_QuestDataByFlavor.forever.enUS[791] = { title = '$N', description = 'Hello $n, $c $r, $gfriend:heroine;.' }
local tokens = A.ResolveCatalogQuest(791, 'enUS')
assert(tokens.title == 'Learner' and tokens.text == 'Hello Learner, Paladin Human, heroine.')
WordHunterWoW_QuestDataByFlavor.forever.deDE[791] = { title = '{name}', description = 'Hallo <name>, $C $R, $gHeld:Heldin;.' }
assert(A.ResolveCatalogQuest(791, 'deDE').text == 'Hallo Learner, Paladin Mensch, Heldin.')
assert(A.OpenCatalogQuest(791, 'enUS') and A.GetCatalogLocale() == 'enUS'
  and A.GetTargetLocale() == 'deDE', 'explicit open must also synchronize the independent library language')
assert(A.SetCatalogLocale('deDE'))
WordHunterWoW_QuestDataByFlavor = nil
assert(A.ResolveCatalogQuest(888, 'deDE').text == 'Legacy mixed-version data.', 'legacy flat localized packs remain compatible')
assert(not A.SetCatalogLocale('invalid') and A.GetCatalogLocale() == 'deDE')
print('quest-catalog-language: qualified data, clickable DE/EN, frozen words/recall, geometry, harvest/export isolation and fallback: ok')
