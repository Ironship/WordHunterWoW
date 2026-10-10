-- Same-title variants stay independently readable, searchable and tracked.
dofile('tests/wowstub.lua')
local create = CreateFrame
CreateFrame = function(...)
  local frame = create(...)
  function frame:SetShown(value) if value then self:Show() else self:Hide() end end
  return frame
end
for _, file in ipairs({'Core.lua','Compat.lua','Recall.lua','UICommon.lua','Harvest.lua',
  'QuestHistory.lua','QuestPanel.lua','WordList.lua','Editor.lua','QuestBrowser.lua','QuestReader.lua'}) do dofile(file) end
local A = WordHunterWoW_Addon
UnitGUID = function() return 'Player-variants-test' end
C_QuestLog, GetQuestLogQuestText = nil, nil
WordHunterWoWDB = {settings={targetLocale='deDE',frames={}},wordsByLocale={}}
A.initializeDatabase()
WordHunterWoW_QuestDataByFlavor = {retail={enUS={
  [1001]={title='On The Mend',description='Visit Erma.'},
  [1002]={title='On The Mend',description='Visit Shelby.'},
  [1003]={title='Another quest',description='Visit Erma.'},
  [1004]={title='On The Mend',description='Completely different dialogue.'},
},deDE={
  [1001]={title='Auf dem Wege der Besserung',description='Sucht Erma auf.'},
  [1002]={title='Auf dem Wege der Besserung',description='Sucht Shelby auf.'},
  [1003]={title='Auf dem Wege der Besserung',description='Sucht Erma auf.'},
  [1004]={title='Auf dem Wege der Besserung',description='Eine andere Geschichte.'},
}}}
for _, id in ipairs({1001,1003,1004}) do A.RecordCharacterQuest(id,'completed') end
A.Compat.QuestLogEntries = function() return {{id=1002,title='Auf dem Wege der Besserung'}} end
A.createPanel(); A.panel.enScroll.GetVerticalScroll=function() return 0 end; A.createEditor()
A.toggleQuestBrowser()
local f=A.questsFrame
local function click(button) button:GetScript('OnClick')(button,'LeftButton') end
local function find(id)
  for _, row in ipairs(f.rows) do if row:IsShown() and row.item.id==id then return row end end
end
local function search(text)
  f.search:SetText(text); f.search:GetScript('OnTextChanged')(f.search)
end
assert(f.idCount==4 and f.resultCount==2, 'two bilingual title families, four quest IDs')
assert(f.pageLabel:GetText():find('2 entries / 4 IDs',1,true))
local parent=find(1002)
assert(parent and parent.item.inLog and not parent.item.completed, 'current variant is the default reader')
assert(#parent.item.members==3 and parent.variants:IsShown())
assert(parent.variants.label:GetText()=='3 variants >', 'the plain button has an explicit visible label')
assert(not find(1001) and not find(1004), 'same-title variants start collapsed')
click(parent.variants)
assert(find(1001) and find(1004) and f.resultCount==2 and f.idCount==4)
assert(not find(1001).variants:IsShown(), 'child rows must not inherit a pooled parent expander')
click(find(1004))
assert(A.lastQuest.id==1004 and A.lastQuest.text=='Eine andere Geschichte.', 'different dialogue is preserved')
click(A.libraryReturnButton)
click(find(1002).variants)
assert(not find(1001) and not find(1004), 'collapse hides the extra versions')
click(find(1002))
assert(A.lastQuest.id==1002 and A.lastQuest.text=='Sucht Shelby auf.')
click(A.libraryReturnButton)
search('1001')
assert(f.idCount==1 and f.resultCount==1 and find(1001), 'ID search selects the requested version')
click(find(1001))
assert(A.lastQuest.id==1001 and A.lastQuest.text=='Sucht Erma auf.')
click(A.libraryReturnButton)
search('')
A.SetQuestLibraryCurrentOnly(true)
assert(f.idCount==1 and f.resultCount==1 and find(1002), 'current-only excludes completed siblings')
A.SetQuestLibraryCurrentOnly(false)
A.SetQuestLibraryTab('all')
assert(f.idCount==4 and f.resultCount==2, 'the game catalog also groups title variants')
A.SetQuestCatalogFilter('completed')
assert(f.idCount==3 and f.resultCount==2 and find(1001) and not find(1002))
local history=A.GetCharacterQuestHistory()
assert(history[1001].completed and history[1003].completed and history[1004].completed
  and history[1002].accepted and not history[1002].completed,
  'grouping never rewrites completion history')
local raw=A.CollectQuestCatalog('my')
assert(#raw==4, 'the raw catalog retains every quest ID for other callers')
print('quest-library-variants: PASS')
