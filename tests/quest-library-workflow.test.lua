-- lua5.1 tests/quest-library-workflow.test.lua [retail|forever]
-- Follow real tab, checkbox, search, reader, word-editor and return callbacks.
dofile('tests/wowstub.lua')
local forever = arg[1] == 'forever'
local create = CreateFrame
SidePanelTabButtonMixin = {}
CreateFrame = function(kind, name, parent, template)
  local frame = create(kind, name, parent, template)
  frame._template, frame._checked = template, false
  function frame:SetChecked(value) self._checked = not not value end
  function frame:GetChecked() return self._checked end
  function frame:SetShown(value) if value then self:Show() else self:Hide() end end
  local setPoint = frame.SetPoint
  function frame:SetPoint(...)
    self._anchor = {...}; setPoint(self, ...)
  end
  if template == 'LargeSideTabButtonTemplate' then
    assert(kind == 'Frame', 'native book tabs are Frames')
    frame:SetSize(forever and 40 or 43, forever and 35 or 55)
    frame.Icon = {
      SetTexture=function(self,value) self.texture=value end,
      SetSize=function(self,w,h) self.width,self.height=w,h end,
      SetTexCoord=function() end,
      SetAtlas=function() error('book file textures must not be replaced by a nil native atlas') end,
    }
    frame.SelectedTexture={SetShown=function(self,value) self.shown=not not value end}
    if forever then
      function frame:SetFillToInterior(_,size) self.Icon:SetSize(size,size) end
    end
    function frame:SetChecked(value) self.Icon:SetAtlas(nil) end
    function frame:SetCustomOnMouseUpHandler(callback) self._customMouseUp=callback end
    frame:SetScript('OnMouseUp',function(self,button,inside) self._customMouseUp(self,button,inside) end)
  end
  return frame
end
for _, file in ipairs({'Core.lua','Compat.lua','Recall.lua','UICommon.lua','Harvest.lua',
  'QuestHistory.lua','QuestPanel.lua','WordList.lua','Editor.lua','QuestBrowser.lua','QuestReader.lua','ReferenceLibrary.lua'}) do dofile(file) end
local A = WordHunterWoW_Addon
if forever then GetBuildInfo = function() return '1.60.1', '', '', 16001 end end
A.Compat.Refresh()
local flavor = A.Compat.GameFlavor()
UnitGUID = function() return 'Player-library-workflow' end
C_QuestLog, GetQuestLogQuestText = nil, nil
A.Compat.QuestLogEntries = function() return {{id=1001,title='Aktueller Auftrag'}} end
SelectQuestLogEntry = function() error('offline reader must not change native log selection') end
WordHunterWoWDB = {settings={targetLocale='deDE',frames={},integratedLayout=true},wordsByLocale={}}
A.initializeDatabase()
WordHunterWoW_QuestDataByFlavor = {[flavor]={
  deDE={[104]={title='Nativer Titel',description='Die native Geschichte.'}},
  enUS={[104]={title='Native title',description='The native story.'}}}}
local key = forever and 'multilanguage-classic-master' or 'multilanguage-retail'
local de = {
  [31917]={title='Heimkehr des Zähmers',description='Der Zähmer kehrt zurück.'},
  [104]={title='Quellentitel',description='Eine andere Geschichte.',completion='Danke.'},
  [203]={title='Nur ein Titel'},
  [1001]={title='Auftrag aus Quelle',description='Der Auftrag wartet.'},
}
local en = {
  [31917]={title="A Tamer's Homecoming",description='The tamer returns.'},
  [104]={title='Source title',description='Another story.',completion='Thanks.'},
  [203]={title='Only a title'},
  [1001]={title='Current task',description='The task waits.'},
}
for id=2000,2045 do
  de[id]={title='Aufgabe '..id,description='Der Hund wartet.'}
  en[id]={title='Quest '..id,description='The dog waits.'}
end
WordHunterWoW_QuestSources = {
  [key]={label='MultiLanguage matching client',sourceFlavor=forever and 'classic-master' or 'retail',locales={deDE=de,enUS=en}},
  ['multilanguage-wrath']={sourceFlavor='wrath',locales={deDE={[88000]={title='Fremder Client',description='Falscher Text.'}}}},
}
WordHunterWoW_EntityDataBySource = {[key]={kinds={
  item={deDE={[99001]={name='Alabasterplattenstulpen',text='Rüstung.'}}},
  npc={deDE={[99002]={name='Apothekerin Zinge',role='Apothekerin'}}},
  spell={deDE={[99003]={name='Feuerball',text='Schaden.'}}}}}}
A.RecordCharacterQuest(31917,'completed')
A.RecordCharacterQuest(104,'completed')
A.RecordCharacterQuest(999,'accepted','Abgebrochener Auftrag','deDE')
A.createPanel(); A.panel.enScroll.GetVerticalScroll=function() return 0 end; A.createEditor()
local function click(frame)
  if frame and frame._template=='LargeSideTabButtonTemplate' then
    frame:GetScript('OnMouseUp')(frame,'LeftButton',true)
    return
  end
  assert(frame and type(frame:GetScript('OnClick'))=='function')
  frame:GetScript('OnClick')(frame,'LeftButton')
end
local function row(id)
  for _, candidate in ipairs(A.questsFrame.rows) do
    if candidate:IsShown() and candidate.item.id==id then return candidate end
  end
  error('visible row missing: '..id)
end
local function search(text)
  local edit=A.questsFrame.search; edit:SetText(text); edit:GetScript('OnTextChanged')(edit)
end
A.toggleQuestBrowser()
local f=A.questsFrame
assert(f.tab=='my' and f.resultCount==3 and f.libraryTabs.my.SelectedTexture.shown and not f.libraryTabs.all.SelectedTexture.shown)
local first=f.libraryTabs.my
local tooltip
GameTooltip=CreateFrame('GameTooltip',nil,UIParent)
GameTooltip.SetText=function(_,value) tooltip=value end
assert(first:GetParent()==f and first._anchor[1]=='TOPLEFT' and first._anchor[2]==f and first._anchor[3]=='TOPRIGHT'
  and first._anchor[4]==-6 and first._anchor[5]==-100, 'side tabs must overlap the frame border instead of floating beside it')
assert(rawget(f,'catalogLanguageButton')==nil)
local icons={my='INV_Misc_GroupLooking',all='INV_Misc_Book_09',words='INV_Inscription_Tradeskill01'}
for index,key in ipairs({'my','all','words'}) do
  local tab=f.libraryTabs[key]
  tab:GetScript('OnEnter')(tab)
  assert(tooltip==({my='My quests',all='All in game quests',words='Words'})[key])
  assert(tab.Icon.width==24 and tab.Icon.height==24 and tab:GetParent()==f)
  assert(tab.Icon.texture=='Interface\\Icons\\'..icons[key], 'each library view needs a distinct recognizable symbol')
  if index>1 then
    local previous=f.libraryTabs[index==2 and 'my' or 'all']
    assert(tab._anchor[2]==previous and tab._anchor[3]=='BOTTOMLEFT' and tab._anchor[5]==-6,
      'side tabs must stack vertically without overlap')
  end
end
f.libraryTabs.all:GetScript('OnMouseUp')(f.libraryTabs.all,'LeftButton',false)
assert(f.tab=='my', 'a mouse-up outside the tab must not change views')
assert(row(31917).name:GetText()=="A Tamer's Homecoming\nHeimkehr des Zähmers")
assert(row(1001).name:GetText()=='Current task\nAktueller Auftrag', 'native current title wins over imported text')
assert(row(104).name:GetText()=='Native title\nNativer Titel')
f.currentOnlyCheck:SetChecked(true); click(f.currentOnlyCheck)
assert(f.resultCount==1 and row(1001) and A.GetCharacterQuestHistory()[31917].completed)
click(f.libraryTabs.all)
assert(f.tab=='all' and f.resultCount==51 and not f.currentOnlyCheck:IsShown() and f.libraryTabs.all.SelectedTexture.shown)
for _, item in ipairs(f.filtered) do
  assert(item.id~=99001 and item.id~=99002 and item.id~=99003 and item.id~=88000)
end
search('homecoming'); assert(f.resultCount==1 and row(31917))
search('heimkehr'); assert(f.resultCount==1 and row(31917))
click(row(31917))
assert(not f:IsShown() and A.panel:IsShown() and A.lastQuest.id==31917)
assert(not A.lastQuest.readOnly and A.lastQuest.wordLocale=='deDE' and A.lastQuest.text==de[31917].description)
assert(A.panel.enTitle:GetText()==en[31917].title and A.panel.enPlain==en[31917].description)
assert(A.lastQuest.voiceUnavailable and A.panel.sourceNote:IsShown())
local back=A.libraryReturnButton
assert(back._template=='LargeSideTabButtonTemplate' and back:GetParent()==A.panel,
  'return must be a native side tab parented to the reader')
assert(back._anchor[1]=='BOTTOMLEFT' and back._anchor[2]==A.panel and back._anchor[3]=='BOTTOMRIGHT'
  and back._anchor[4]==-6 and back._anchor[5]==12, 'return arrow belongs against the bottom-right border')
assert(back.Icon.texture=='Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up' and back.Icon.width==24
  and back.Icon.height==24 and not back.SelectedTexture.shown)
assert(back:GetFrameLevel()==A.panel:GetFrameLevel()+2 and rawget(A.panel,'catalogLanguageButton')==nil)
back:GetScript('OnMouseUp')(back,'RightButton',true)
back:GetScript('OnMouseUp')(back,'LeftButton',false)
assert(A.panel:IsShown() and not f:IsShown(), 'return only on a left release inside the tab')
local token
for _, button in ipairs(A.panel.wordButtons) do if button:IsShown() and button.word=='Zähmer' then token=button end end
assert(token); click(token)
assert(A.selected.locale=='deDE' and A.editor:IsShown())
click(A.editor.statusButtons.learning); A.editor.translation:SetText('tamer'); click(A.editor.save)
assert(A.GetWordsTable('deDE')[A.wordKey('Zähmer')].translation=='tamer')
assert(WordHunterWoWDB.questTexts==nil, 'static quest study must not manufacture a native archive')
click(A.libraryReturnButton)
assert(f:IsShown() and f.tab=='all' and f.search:GetText()=='heimkehr' and f.resultCount==1)
search(''); click(f.nextPage)
assert(f.page==2)
local secondPageID=f.rows[1].item.id
click(f.rows[1]); click(A.libraryReturnButton)
assert(f.page==2 and row(secondPageID), 'return must preserve the library page')
assert(A.OpenCatalogQuest(104,'deDE') and A.lastQuest.text=='Die native Geschichte.' and not A.panel.sourceNote:IsShown(),
  'an imported later passage must not relabel the native opening text')
assert(A.SetCatalogPhase('completion') and A.lastQuest.text=='Danke.' and A.lastQuest.voiceUnavailable)
assert(A.OpenCatalogQuest(203,'deDE') and A.lastQuest.catalogPhase=='title' and A.lastQuest.text=='Nur ein Titel')
assert(A.panel.enPlain=='Only a title' and A.lastQuest.referenceNote:find('Title-only',1,true))
click(A.libraryReturnButton); click(f.libraryTabs.my)
assert(f.resultCount==1 and f.currentOnlyCheck:IsShown())
f.currentOnlyCheck:SetChecked(false); click(f.currentOnlyCheck)
assert(f.resultCount==3 and row(31917).item.completed and not A.GetCharacterQuestHistory()[203])
click(f.libraryTabs.words)
local words=f.wordsView
assert(f:IsShown() and words:IsShown() and not f.questScroll:IsShown() and not f.search:IsShown()
  and f.viewTitle:GetText()=='Words' and A.listFrame==nil, 'Words must be a third view in the same library window')
assert(words.rows[1].name:GetText()=='Zähmer' and words.rows[1].meta:GetText()=='tamer')
click(words.rows[1]); assert(A.selected.locale=='deDE' and A.editor:IsShown())
A.editor.translation:SetText('a tamer'); click(A.editor.save)
assert(words.rows[1].meta:GetText()=='a tamer', 'saving from Words must refresh the visible shared list')
A.GetWordsTable('enUS').tamer={word='tamer',translation='Zähmer',status='known'}
A.SetTargetLocale('enUS')
assert(words.wordLocale=='enUS' and words.rows[1].name:GetText()=='tamer' and A.GetTargetLocale()=='enUS')
click(words.rows[1]); assert(A.selected.locale=='enUS' and A.editor.translation:GetText()=='Zähmer')
click(A.editor.cancel)
A.SetTargetLocale('deDE')
click(words.filterButtons.known)
assert(not words.rows[1]:IsShown(), 'Words status filters must apply to the selected language')
click(words.filterButtons.learning); assert(words.rows[1]:IsShown())
words.search:SetText('unmatched'); words.search:GetScript('OnTextChanged')(words.search)
assert(not words.rows[1]:IsShown())
click(f.libraryTabs.my)
assert(f.questScroll:IsShown() and f.search:IsShown() and not words:IsShown() and f.viewTitle:GetText()=='My quests')
click(f.libraryTabs.words)
assert(words.search:GetText()=='unmatched' and not words.rows[1]:IsShown(), 'Words search is independent of quest search')
local walks, walk=0,A.ForEachEffectiveWord
A.ForEachEffectiveWord=function(...) walks=walks+1; return walk(...) end
f:Hide(); A.refreshWordList()
assert(walks==0, 'closing the library must stop hidden Words dictionary walks')
print('quest-library-workflow: '..flavor..' attached distinct-icon tabs, bottom return arrow, no language buttons, Words/editor/filter, quests and return state PASS')
