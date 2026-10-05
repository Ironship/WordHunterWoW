-- Source variants and entity IDs must never resolve through native quest data.
dofile('tests/wowstub.lua')
for _, file in ipairs({'Core.lua','Compat.lua','UICommon.lua','Harvest.lua','QuestHistory.lua',
  'QuestPanel.lua','Editor.lua','QuestBrowser.lua','QuestReader.lua','ReferenceLibrary.lua'}) do dofile(file) end
local A = WordHunterWoW_Addon
GetBuildInfo = function() return '1.60.1', '', '', 16001 end
A.Compat.Refresh()
WordHunterWoWDB = {settings={targetLocale='deDE',frames={},integratedLayout=true},wordsByLocale={}}
A.initializeDatabase()
C_QuestLog, GetQuestLogQuestText = nil, nil
SelectQuestLogEntry = function() error('reference study must not select a live quest') end
WordHunterWoW_QuestDataByFlavor = {forever={deDE={[7]={title='Nativ',description='Native Geschichte.'}},
  enUS={[7]={title='Native',description='Native story.'}}}}
local key = 'multilanguage-classic-master'
WordHunterWoW_QuestSources = {[key]={label='Classic and seasonal source',locales={
  deDE={[7]={title='Quelle',description='Der Hund wartet.',completion='Danke Hund.',sourceObjective='Die Quelle spricht.'},
    [8]={title='Nur Deutsch',progress='Ein Hund.'}},
  enUS={[7]={title='Source',description='The dog waits.',completion='Thanks dog.',sourceObjective='The source speaks.'},
    [9]={title='English only',description='An English dog.'}}}}}
WordHunterWoW_EntityDataBySource = {['multilanguage-classic']={sourceLabel='Classic entity reference',kinds={
  item={deDE={[7]={name='Ein Gegenstand',text='Ein Hund.'}},enUS={[7]={name='An item',text='A dog.'}}},
  spell={deDE={[7]={name='Ein Zauber',text='Der Hund schläft.'}},enUS={}},
  npc={deDE={[7]={name='Eine Person',role='Gastwirt'}},enUS={[7]={name='A person',role='Innkeeper'}}}}}}
local function ref(kind, id, source) return 'reference:'..(source or key)..':'..kind..':'..id end
A.createPanel(); A.createEditor()
assert(A.OpenCatalogQuest(ref('quest',7),'deDE','completion'))
assert(A.lastQuest.text=='Danke Hund.' and A.lastQuest.id==ref('quest',7) and A.lastQuest.wordLocale=='deDE')
assert(A.lastQuest.voiceUnavailable and A.panel.sourceNote:IsShown())
assert(A.panel.enPlain=='Thanks dog.' and not A.lastQuest.readOnly)
assert(A.SetCatalogLocale('enUS') and A.lastQuest.text=='Thanks dog.' and A.lastQuest.catalogPhase=='completion')
assert(A.SetCatalogLocale('deDE') and A.SetCatalogPhase('sourceObjective'))
assert(A.panel.enPlain=='The source speaks.' and A.lastQuest.text=='Die Quelle spricht.')
assert(A.OpenCatalogQuest(ref('quest',9),'deDE') and A.lastQuest.readOnly and not A.lastQuest.wordLocale)
assert(not A.ResolveCatalogQuest(ref('quest',7),'deDE','invalid'))
assert(A.OpenCatalogQuest(ref('item',7,'multilanguage-classic'),'deDE'))
assert(A.lastQuest.text=='Ein Gegenstand\n\nEin Hund.' and A.panel.enPlain=='An item\n\nA dog.' and A.lastQuest.sourceId==7)
local clicked
for _, button in ipairs(A.panel.wordButtons) do
  if button:IsShown() and button.word=='Hund' then button:GetScript('OnClick')(button); clicked=true; break end
end
assert(clicked and A.selected.questId==ref('item',7,'multilanguage-classic') and A.selected.locale=='deDE')
assert(A.OpenCatalogQuest(ref('npc',7,'multilanguage-classic'),'deDE') and A.lastQuest.text=='Eine Person\n\nGastwirt')
assert(A.OpenCatalogQuest(7,'deDE') and A.lastQuest.text=='Native Geschichte.' and not A.panel.sourceNote:IsShown())
assert(WordHunterWoWDB.questTexts==nil and WordHunterWoWCorpus==nil)
local history=A.GetCharacterQuestHistory()
assert(not history[7] or not history[7].completed, 'source study must not award native quest completion')
A.toggleQuestBrowser()
assert(A.SetLibraryView(key..':quest'))
assert(A.questsFrame.resultCount==3 and A.questsFrame.filter=='database')
A.SetQuestCatalogFilter('completed')
assert(A.questsFrame.filter=='database', 'native history filters cannot claim source-version completion')
local row=A.questsFrame.rows[1]
row:GetScript('OnClick')(row)
assert(A.lastQuest.referenceSource==key)
assert(A.SetLibraryView('multilanguage-classic:item') and #A.CollectQuestCatalog()==1)
assert(not A.SetLibraryView('unknown') and A.GetLibraryView().kind=='item')
assert(A.SetLibraryView('game') and A.CollectQuestCatalog()[1].title=='Nativ')
print('reference-library: source/version/locale/phase/ID isolation + real reader/editor + catalog controls PASS')
