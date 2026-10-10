-- Lua 5.1: completed/offline dialogue is the same clickable reader in DE/EN.
dofile('tests/wowstub.lua')
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'Recall.lua', 'UICommon.lua', 'Harvest.lua',
  'QuestHistory.lua', 'QuestPanel.lua', 'Editor.lua', 'QuestBrowser.lua', 'QuestReader.lua' }) do dofile(file) end
local A = WordHunterWoW_Addon
GetBuildInfo = function() return '1.60.1', '', '', 16001 end
A.Compat.Refresh()
UnitGUID = function() return 'Player-catalog-passages' end
UnitName = function() return 'Learner' end
WordHunterWoWDB = { settings = { targetLocale = 'deDE', harvestCorpus = false, integratedLayout = true, frames = {} }, wordsByLocale = {
  deDE = { hund = { word = 'Hund', translation = 'dog', status = 'known' } },
} }
A.initializeDatabase()
C_QuestLog, GetQuestLogQuestText = nil, nil
SelectQuestLogEntry = function() error('offline dialogue must not select a live quest') end
local source = 'MultiLanguage Classic pinned revision'
local de = { title = 'Ein Auftrag', progress = 'Habt Ihr den Hund gesehen?', completion = 'Danke, der Hund ist zurück.',
  progressSource = source, completionSource = source, progressSourceFlavor = 'classic', completionSourceFlavor = 'classic' }
local en = { title = 'A task', progress = 'Have you seen the dog?', completion = 'Thank you, the dog is back.',
  progressSource = source, completionSource = source, progressSourceFlavor = 'classic', completionSourceFlavor = 'classic' }
WordHunterWoW_QuestDataByFlavor = { forever = { sourceFlavor = 'classic', deDE = { [900] = de,
  [901] = { title = 'Ein Angebot', description = 'Der Hund wartet.', completion = 'Danke.' },
  [902] = { title = 'Ein Teil', description = 'Der Hund wartet.' } }, enUS = { [900] = en,
  [902] = { title = 'A part', description = 'The dog waits.', completion = 'The dog returned.', completionSource = source } } } }
WordHunterWoW_QuestEN = WordHunterWoW_QuestDataByFlavor.forever.enUS
A.RecordCharacterQuest(900, 'completed')
A.createPanel(); A.panel.enScroll.GetVerticalScroll = function() return 0 end; A.createEditor()
local rendered
A.OnQuestPanelRendered = function(quest) rendered = quest end
assert(A.OpenCatalogQuest(900), 'a dialogue-only offline quest must be readable')
assert(A.lastQuest.catalogPhase == 'progress' and A.lastQuest.passage == 'progress' and A.lastQuest.wordLocale == 'deDE')
assert(A.lastQuest.sourceFlavor == 'classic' and A.lastQuest.voiceUnavailable and rendered.voiceUnavailable,
  'imported dialogue must expose its Classic provenance and stop unrelated audio')
assert(A.panel.enPlain == en.progress and A.panel.enCanHighlight, 'parallel English must show progress without an offer-only caveat')
assert(WordHunterWoWDB.questTexts == nil and WordHunterWoWCorpus == nil, 'studying bundled dialogue must not archive it as an observation')
local function click(word)
  for _, b in ipairs(A.panel.wordButtons) do
    if b:IsShown() and b.word == word then b:GetScript('OnClick')(b); return end
  end
  error('missing real clickable word: ' .. word)
end
click('Hund')
assert(A.selected.locale == 'deDE' and A.editor.translation:GetText() == 'dog')
local phaseButton = A.panel.catalogPhaseButton
phaseButton:GetScript('OnClick')(phaseButton)
assert(A.lastQuest.catalogPhase == 'completion' and A.lastQuest.passage == 'reward' and A.lastQuest.text == de.completion)
assert(A.panel.enPlain == en.completion and not A.editor:IsShown() and A.selected == nil,
  'phase switching must clear the old word context and match the English completion')
assert(rawget(A.panel, 'catalogLanguageButton') == nil)
assert(A.SetCatalogLocale('enUS'))
assert(A.lastQuest.catalogPhase == 'completion' and A.lastQuest.wordLocale == 'enUS' and A.lastQuest.text == en.completion)
assert(A.GetTargetLocale() == 'deDE' and A.lastQuest.voiceUnavailable, 'English study must not change the German learning profile or play German audio')
assert(A.SetCatalogLocale('deDE'))
assert(A.lastQuest.catalogPhase == 'completion' and A.lastQuest.wordLocale == 'deDE' and A.lastQuest.text == de.completion)
assert(A.GetWordsTable('deDE').hund.status == 'known' and A.GetCharacterQuestHistory()[900].completed,
  'switching languages/phases must preserve vocabulary and actual completion history')
phaseButton:GetScript('OnClick')(phaseButton)
assert(A.lastQuest.catalogPhase == 'progress')
assert(A.OpenCatalogQuest(901) and A.lastQuest.catalogPhase == 'offer' and A.lastQuest.passage == 'offer', 'default offer behavior remains compatible')
assert(A.SetCatalogPhase('completion') and not (A.GetCharacterQuestHistory()[901] or {}).completed,
  'reading a completion passage must never mark the quest completed')
assert(A.OpenCatalogQuest(902, 'deDE', 'completion'))
assert(A.lastQuest.readOnly and A.lastQuest.catalogPhase == 'completion' and A.lastQuest.passage == 'reference'
  and A.lastQuest.sourceLocale == 'enUS' and A.lastQuest.wordLocale == nil, 'a missing German phase uses an honest English reference')
assert(A.SetCatalogLocale('enUS') and A.lastQuest.catalogPhase == 'completion' and not A.lastQuest.readOnly)
assert(A.SetCatalogLocale('deDE') and A.lastQuest.catalogPhase == 'completion' and A.lastQuest.readOnly)
assert(not A.SetCatalogPhase('invalid') and A.lastQuest.catalogPhase == 'completion')

-- Optional corpus entries use the old reward key; wrong-flavor entries stay out.
WordHunterWoWCorpus = { byLocale = { deDE = {
  ['forever:reward:903'] = { id = 903, kind = 'reward', flavor = 'forever', text = 'Der gesammelte Hund ist zurück.', observedPassage = 'reward' },
  ['classic:progress:903'] = { id = 903, kind = 'progress', flavor = 'classic', text = 'Falscher Client.' },
} } }
assert(A.ResolveCatalogQuest(903).catalogPhase == 'completion' and A.ResolveCatalogQuest(903).text == 'Der gesammelte Hund ist zurück.')
assert(A.ResolveCatalogQuest(903, 'deDE', 'progress') == nil)
WordHunterWoWCorpus = nil

-- Native NPC observations win per field, without archiving stale offscreen getters.
GetQuestID = function() return 900 end
GetTitleText = function() return 'Der native Auftrag' end
GetQuestText = function() return 'Stale offer from another passage.' end
GetObjectiveText = function() return 'Stale objectives.' end
GetProgressText = function() return 'Der native Hund wartet noch.' end
GetRewardText = function() return 'Stale reward.' end
QuestFrame:Show(); A.lastPassage = 'progress'; A.readCurrentQuest()
local native = assert(A.GetObservedQuestTexts('deDE')[900])
assert(native.progress == 'Der native Hund wartet noch.' and native.description == nil and native.objectives == nil and native.completion == nil)
local resolved = assert(A.ResolveCatalogQuest(900, 'deDE', 'progress'))
assert(resolved.text == native.progress and resolved.sourceFlavor == 'forever' and not resolved.voiceUnavailable)
assert(A.ResolveCatalogQuest(900, 'deDE', 'completion').text == de.completion and native.completion == nil)
assert(de.progress == 'Habt Ihr den Hund gesehen?' and not (A.GetCharacterQuestHistory()[901] or {}).completed)
assert(not phaseButton:IsShown(), 'native NPC reading must hide catalog-only phase controls')

-- The optional harvest must use the same phase guard as the native archive.
-- Otherwise a stale GetRewardText is reopened ahead of the imported completion.
A.SetHarvestEnabled(true)
WordHunterWoWCorpus = {version = 1, byLocale = {deDE = {
  ['forever:reward:900'] = {id = 900, kind = 'reward', flavor = 'forever', text = 'Unverified old reward.'},
}}}
assert(A.ResolveCatalogQuest(900, 'deDE', 'completion').text == de.completion,
  'an old all-getter harvest must not be trusted as a completion')
A.readCurrentQuest()
local collected = WordHunterWoWCorpus.byLocale.deDE
assert(collected['forever:progress:900'].text == native.progress)
assert(collected['forever:reward:900'].text == 'Unverified old reward.'
  and not collected['forever:reward:900'].observedPassage and not collected['forever:description:900']
  and not collected['forever:objectives:900'], 'harvesting progress must not collect stale offscreen getters')
resolved = assert(A.ResolveCatalogQuest(900, 'deDE', 'completion'))
assert(resolved.text == de.completion and resolved.phaseSource == source and resolved.voiceUnavailable,
  'harvested offscreen text must not replace the imported completion or enable wrong audio')
GetRewardText = function() return 'Der native Hund ist zurück.' end
A.lastPassage = 'reward'; A.readCurrentQuest()
assert(collected['forever:reward:900'].text == 'Unverified old reward.', 'old entries remain preserved')
assert(A.ResolveCatalogQuest(900, 'deDE', 'completion').text == 'Der native Hund ist zurück.',
  'an actually displayed completion must still be collected and preferred')
print('quest-catalog-passages: completed offline dialogue, real DE/EN controls, word states, native priority, provenance and no completion/archive/audio leakage: ok')
