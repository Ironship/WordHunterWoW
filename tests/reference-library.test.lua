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
    [8]={title='Nur Deutsch',progress='Ein Hund.'},
    [10]={title='Deutscher Titel'}, [11]={title='Deutscher Titel ohne Dialog'},
    [13]={title='Deutscher Titel mit Dialog',description='Der Hund wartet.'}},
  enUS={[7]={title='Source',description='The dog waits.',completion='Thanks dog.',sourceObjective='The source speaks.'},
    [9]={title='English only',description='An English dog.'},
    [10]={title='English title'}, [11]={title='English title with dialogue',description='An English dog.'},
    [12]={title='English-only title'}, [13]={title='English-only counterpart title'}}}}}
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
assert(A.OpenCatalogQuest(ref('quest',10),'deDE') and A.lastQuest.text=='Deutscher Titel')
assert(A.lastQuest.catalogPhase=='title' and not A.lastQuest.readOnly and A.lastQuest.wordLocale=='deDE')
assert(A.panel.enPlain=='English title' and A.lastQuest.referenceNote:find('Title-only',1,true))
assert(not A.ResolveCatalogQuest(ref('quest',10),'deDE','completion'), 'title-only study must not invent dialogue')
assert(A.SetCatalogLocale('enUS') and A.lastQuest.text=='English title' and A.lastQuest.catalogPhase=='title')
assert(A.OpenCatalogQuest(ref('quest',11),'deDE') and A.lastQuest.text=='Deutscher Titel ohne Dialog' and not A.lastQuest.readOnly)
assert(A.SetCatalogPhase('offer') and A.lastQuest.readOnly and A.lastQuest.text=='An English dog.')
assert(A.OpenCatalogQuest(ref('quest',12),'deDE') and A.lastQuest.catalogPhase=='title' and A.lastQuest.readOnly)
assert(A.OpenCatalogQuest(ref('quest',13),'deDE') and A.lastQuest.catalogPhase=='offer' and A.lastQuest.text=='Der Hund wartet.')
assert(not A.panel.enCanHighlight, 'a bare English title is not English offer text')
assert(A.SetCatalogPhase('title') and A.lastQuest.text=='Deutscher Titel mit Dialog' and A.panel.enPlain=='English-only counterpart title')
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
assert(A.SetQuestLibraryTab('all'))
assert(A.questsFrame.resultCount==7 and A.questsFrame.filter=='database')
local row
for _, candidate in ipairs(A.questsFrame.rows) do
  if candidate:IsShown() and candidate.item.id==8 then row=candidate end
end
assert(row and row.name:GetText()=='Nur Deutsch')
row:GetScript('OnClick')(row)
assert(A.lastQuest.id==8 and A.lastQuest.text=='Ein Hund.' and A.lastQuest.wordLocale=='deDE')
assert(not A.SetLibraryView('multilanguage-classic:item') and not A.SetLibraryView('unknown'),
  'entity views must not appear in the quest library')
local byID={}
for _, entry in ipairs(A.CollectQuestCatalog()) do byID[entry.id]=entry end
assert(byID[7].title=='Nativ' and byID[7].englishTitle=='Native', 'native titles take precedence over imported titles')
WordHunterWoW_EntityDataBySource['multilanguage-retail'] = {viewLabel='ML Retail', kinds={
  item={deDE={[7]={name='Anderer Gegenstand',text='Neue Geschichte.'}},
    enUS={[7]={name='Another item',text='A new story.'}}}, spell={deDE={},enUS={}}}}
WordHunterWoW_QuestSources['multilanguage-wrath'] = {viewLabel='ML Wrath',locales={
  enUS={[7]={title='Wrath source',description='English source only.'}}}}
WordHunterWoW_QuestSources['bad:key'] = {locales={deDE={[1]={title='Invalid namespace'}}}}
local seen, stable = {}, {}
for index, view in ipairs(A.GetLibraryViews()) do seen[view.key]=true; stable[index]=view.key end
assert(not seen['multilanguage-retail:item'] and seen['multilanguage-wrath:quest'])
assert(not seen['multilanguage-retail:spell'] and not seen['bad:key:quest'])
for index, view in ipairs(A.GetLibraryViews()) do assert(stable[index]==view.key) end
assert(not A.SetLibraryView('multilanguage-retail:item'))
assert(A.OpenCatalogQuest(ref('item',7,'multilanguage-retail'),'deDE'))
assert(A.lastQuest.text=='Anderer Gegenstand\n\nNeue Geschichte.' and A.panel.enPlain=='Another item\n\nA new story.')
assert(A.OpenCatalogQuest(ref('item',7,'multilanguage-classic'),'deDE') and A.lastQuest.text=='Ein Gegenstand\n\nEin Hund.')
assert(A.OpenCatalogQuest(ref('quest',7,'multilanguage-wrath'),'deDE') and A.lastQuest.readOnly and not A.lastQuest.wordLocale)
assert(A.lastQuest.text=='English source only.' and A.lastQuest.voiceUnavailable)
byID={}
for _, entry in ipairs(A.CollectQuestCatalog()) do byID[entry.id]=entry end
assert(byID[7].title=='Nativ' and #A.CollectQuestCatalog()==7,
  'matching quest sources enrich native IDs without duplicate entities or foreign editions')
print('reference-library: source/version/locale/phase/ID isolation + real reader/editor + catalog controls PASS')
