-- lua5.1 tests/quest-library-tab.test.lua [forever|retail|classic] [baseline-source-directory]
-- Focused real-template, visibility and clipping regression; no frame-field fabrication.
dofile('tests/wowstub.lua')
local classic, retail, baseline = arg[1] == 'classic', arg[1] == 'retail', arg[2]
local create, frames, spellbookCalls = CreateFrame, {}, 0
local function visible(frame)
  if not rawget(frame, 'shown') then return false end
  local parent = rawget(frame, '_parent')
  return not parent or visible(parent)
end
local function emit(frame, event, ...)
  local script = frame.scripts[event]
  if script then script(frame, ...) end
  for _, hook in ipairs(frame._hooks[event] or {}) do hook(frame, ...) end
end
local function changeShown(frame, shown)
  local before = {}
  for _, other in ipairs(frames) do before[other] = visible(other) end
  rawset(frame, 'shown', shown)
  for _, other in ipairs(frames) do
    local after = visible(other)
    if before[other] ~= after then emit(other, after and 'OnShow' or 'OnHide') end
  end
end
CreateFrame = function(kind, name, parent, template)
  local frame = create(kind, name, parent, template)
  frame._template, frame._hooks = template, {}
  frame._checked, frame._mouseEnabled = false, false
  rawset(frame, 'shown', true)
  frames[#frames + 1] = frame
  function frame:HookScript(event, fn)
    assert(type(fn) == 'function', 'frame hooks must be real functions')
    self._hooks[event] = self._hooks[event] or {}
    table.insert(self._hooks[event], fn)
  end
  function frame:IsVisible() return visible(self) end
  function frame:Show() changeShown(self, true) end
  function frame:Hide() changeShown(self, false) end
  function frame:SetChecked(value) self._checked = not not value end
  function frame:GetChecked() return self._checked end
  function frame:EnableMouse(value) self._mouseEnabled = value end
  function frame:SetClipsChildren(value) self._clipsChildren = value end
  function frame:SetPoint(point, relative, relativePoint, x, y)
    self._anchor = { point, relative, relativePoint, x, y }
  end
  function frame:ClearAllPoints() self._anchor = nil end
  function frame:GetPoint() return unpack(self._anchor or {}) end
  function frame:GetLeft()
    if self._rect then return self._rect.left end
    local a = assert(self._anchor, 'geometry requires an actual anchor')
    return (a[3] == 'TOPRIGHT' and a[2]:GetRight() or a[2]:GetLeft()) + a[4]
  end
  function frame:GetTop()
    if self._rect then return self._rect.top end
    local a = assert(self._anchor, 'geometry requires an actual anchor')
    return (a[3] == 'BOTTOMLEFT' and a[2]:GetBottom() or a[2]:GetTop()) + a[5]
  end
  function frame:GetRight() return self:GetLeft() + self:GetWidth() end
  function frame:GetBottom() return self:GetTop() - self:GetHeight() end
  if template == 'LargeSideTabButtonTemplate' then
    assert(kind == 'Frame', 'native side-tab template is a Frame, not a Button')
    frame:SetSize(retail and 43 or 40, retail and 55 or 35)
    frame.Icon = {
      SetTexture = function(self, texture) self.texture = texture end,
      SetSize = function(self, width, height) self.width, self.height = width, height end,
      SetTexCoord = function(self, ...) self.coords = { ... } end,
      SetAtlas = function(self, atlas) assert(type(atlas) == 'string', 'Retail must not receive a nil book atlas'); self.atlas = atlas end,
    }
    frame.SelectedTexture = { SetShown = function(self, shown) self.shown = not not shown end }
    frame.GetChecked = nil -- The native Frame reports selection through its texture.
    if not retail then
      function frame:SetFillToInterior(fill, width)
        self._fill, self._iconWidth = fill, width
        self.Icon:SetSize(width, width)
        self.Icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
      end
    end
    function frame:SetChecked(checked)
      local atlas = checked and self.activeAtlas or self.inactiveAtlas
      if retail or atlas then self.Icon:SetAtlas(atlas) end
      self.SelectedTexture:SetShown(checked)
    end
    function frame:SetCustomOnMouseUpHandler(fn) self._customMouseUp = fn end
    frame:SetScript('OnMouseDown', function(self) self._pressed = true end)
    frame:SetScript('OnMouseUp', function(self, button, inside)
      self._pressed = false
      if self._customMouseUp then self._customMouseUp(self, button, inside) end
    end)
    setmetatable(frame, nil) -- Missing native methods/children must fail, not fabricate.
  elseif template == 'SpellBookSkillLineTabTemplate' then
    assert(kind == 'CheckButton', 'Classic side-tab template is a CheckButton')
    frame:SetSize(32, 32)
    function frame:SetNormalTexture(texture) self._normalTexture = texture end
    frame._normalTextureRegion={
      ClearAllPoints=function(self) self.anchor=nil end,
      SetPoint=function(self,point) self.anchor=point end,
      SetSize=function(self,w,h) self.width,self.height=w,h end,
    }
    function frame:GetNormalTexture() return self._normalTextureRegion end
    frame:SetScript('OnClick', function() spellbookCalls = spellbookCalls + 1 end)
    setmetatable(frame, nil)
  end
  return frame
end
local function fixture(parent, left, top, width, height)
  local frame = CreateFrame('Frame', nil, parent)
  frame._rect = { left = left or 0, top = top or 0 }
  frame:SetSize(width or 900, height or 650)
  setmetatable(frame, nil) -- Absent Blizzard tabs and hosts stay absent.
  return frame
end
UIParent = fixture(nil, 0, 1000, 1920, 1080)
UIParent:SetScale(0.8)
QuestFrame = fixture(UIParent, 100, 800, 400, 650)
QuestFrame:Hide()
GossipFrame = nil
QuestMapFrame, WorldMapFrame, QuestLogFrame = nil, nil, nil
if classic then SidePanelTabButtonMixin = nil else SidePanelTabButtonMixin = {} end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = classic and 2 or 1, 1
GetBuildInfo = function()
  if classic then return '1.15.9', '62222', '', 11509 end
  if retail then return '12.1.0', '69933', '', 120100 end
  return '1.60.1', '69893', '', 16001
end
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'UICommon.lua', 'QuestPanel.lua', 'WordList.lua', 'QuestBrowser.lua' }) do
  dofile(baseline and (file == 'QuestPanel.lua' or file == 'QuestBrowser.lua') and baseline .. '/' .. file or file)
end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
A.createPanel()
assert(A.Compat.GameFlavor() == (classic and 'classic' or retail and 'retail' or 'forever'))
assert(A.AttachQuestsLogButton() == nil and A.questsLogButton == nil, 'late-loaded log must not create an orphan tab')
local root = fixture(UIParent, 100, 800)
root:SetScale(0.625)
root:SetClipsChildren(true)
root:Hide()
local map, host, details, quests, events, legend
if classic then
  QuestLogFrame, host = root, root
else
  WorldMapFrame = root
  map = fixture(root, 650, 775, 350, 600)
  QuestMapFrame = map
  host, details = fixture(map), fixture(map)
  host:SetClipsChildren(true)
  details:Hide()
  map.QuestsFrame, map.DetailsFrame = host, details
  quests = fixture(map, root:GetRight() + 2, root:GetTop() - 53, 40, 35)
  events = fixture(map, root:GetRight() + 2, quests:GetBottom() - 3, 40, 35)
  legend = fixture(map, root:GetRight() + 2, events:GetBottom() - 3, 40, 35)
  map.QuestsTab, map.EventsTab, map.MapLegendTab = quests, events, legend
  quests:Hide(); events:Hide(); legend:Hide() -- Forever hides these; Lorever still anchors to QuestsTab.
end
assert(A.QuestsLogButtonHost() == host, 'host chooser must use the list, never the details pane')
local b = assert(A.AttachQuestsLogButton(), 'late-loaded list must attach the tab')
assert(b._template == (classic and 'SpellBookSkillLineTabTemplate' or 'LargeSideTabButtonTemplate'),
  'library must use the real native side-tab template or Classic skill-line fallback')
assert(b:GetParent() == UIParent, 'side-tab must avoid clipped map/list ancestors by parenting to UIParent')
local ancestor = b:GetParent()
while ancestor do
  assert(ancestor ~= root and ancestor ~= host and not ancestor._clipsChildren, 'raised strata cannot bypass ancestor clipping')
  ancestor = ancestor:GetParent()
end
assert(b:GetFrameStrata() == 'FULLSCREEN_DIALOG' and b:GetFrameLevel() == 40, 'tab must stay above the reader')
assert(not b:IsShown(), 'UIParent child must explicitly hide while map/log root is hidden')
if classic then
  assert(b:GetWidth() == 32 and b:GetHeight() == 32 and b._normalTexture == 'Interface\\Icons\\INV_Misc_Book_09')
  local texture=b:GetNormalTexture()
  assert(texture.width==24 and texture.height==24 and texture.anchor=='CENTER', 'Classic must shrink only the icon')
else
  assert(b:GetWidth() == (retail and 43 or 40) and b:GetHeight() == (retail and 55 or 35), 'native tab dimensions must stay intact')
  assert(b.Icon.texture == 'Interface\\Icons\\INV_Misc_Book_09' and b._mouseEnabled)
  assert(b.Icon.width == 24 and b.Icon.height == 24 and b.Icon.coords[1] == 0.03125 and b.Icon.coords[2] == 0.96875,
    'both native API versions must use the same book extent and crop')
  assert(type(b._customMouseUp) == 'function' and b:GetScript('OnClick') == nil, 'native Frame must use custom mouse-up, not OnClick')
end
local function anchor(relative, relativePoint, x, y)
  local point, actual, edge, ax, ay = b:GetPoint()
  assert(point == 'TOPLEFT' and actual == relative and edge == relativePoint and ax == x and ay == y,
    'side-tab anchor must follow native stack or outer root with the reserved lane')
end
if classic then anchor(root, 'TOPRIGHT', 2, -96) else anchor(quests, 'BOTTOMLEFT', 0, -43) end
root:Show()
assert(b:IsVisible() and host:IsVisible(), 'showing the root must show the tab without selecting a quest')
assert(b:GetLeft() >= root:GetRight() + 2, 'book rectangle must lie outside the outer map/log edge')
assert(math.abs(b:GetEffectiveScale() - root:GetEffectiveScale()) < 0.00001, 'tab must match root effective scale')
if not classic then
  local loreverBottom = quests:GetBottom() - 3 - 32
  assert(b:GetTop() <= loreverBottom - 8, 'hidden QuestsTab must reserve Lorever height, its 3px offset and 8px gap')
  events:Show(); anchor(events, 'BOTTOMLEFT', 0, -43)
  legend:Show(); anchor(legend, 'BOTTOMLEFT', 0, -43)
  quests:Show(); anchor(legend, 'BOTTOMLEFT', 0, -43)
  legend:Hide(); anchor(events, 'BOTTOMLEFT', 0, -43)
  events:Hide(); anchor(quests, 'BOTTOMLEFT', 0, -43)
  quests:Hide(); anchor(quests, 'BOTTOMLEFT', 0, -43)
  map.QuestsTab, map.EventsTab, map.MapLegendTab = nil, nil, nil
  A.RefreshQuestsLogButton(); anchor(root, 'TOPRIGHT', 2, -96)
  map.QuestsTab, map.EventsTab, map.MapLegendTab = quests, events, legend
  A.RefreshQuestsLogButton(); anchor(quests, 'BOTTOMLEFT', 0, -43)
  details:Show(); details:Hide()
  assert(b:IsVisible(), 'details visibility must not affect the library list tab')
  host:Hide(); assert(not b:IsShown(), 'hidden quest-list mode must explicitly hide the external tab')
  host:Show(); assert(b:IsVisible(), 'returning to list mode must restore the tab')
  map:Hide(); assert(not b:IsShown(), 'hidden intermediate QuestMapFrame must also hide the tab')
  map:Show(); assert(b:IsVisible())
  host:Hide(); root:Hide(); root:Show()
  assert(not b:IsShown(), 'root show cannot expose the tab while list mode remains hidden')
  host:Show(); assert(b:IsVisible())
end
root:Hide(); assert(not b:IsShown())
root:Show(); assert(b:IsVisible())
root:SetScale(0.9)
A.RefreshQuestsLogButton()
assert(math.abs(b:GetEffectiveScale() - root:GetEffectiveScale()) < 0.00001, 'refresh must track changed root scale without double scaling')
A.AttachQuestLogButton()
local hookCount = #(root._hooks.OnShow or {})
assert(A.AttachQuestsLogButton() == b and A.AttachQuestsLogButton() == b, 'repeated attach must reuse the original side tab')
A.hookQuestUi()
assert(A.questsLogButton == b and #(root._hooks.OnShow or {}) == hookCount, 'late lifecycle hooks must not duplicate the tab or visibility hooks')
local templateCount = 0
for _, frame in ipairs(frames) do if frame._template == b._template then templateCount = templateCount + 1 end end
assert(templateCount == 3, 'one library tab, one map reader tab and one NPC reader tab per session')

local function leftClick()
  if classic then emit(b, 'OnClick', 'LeftButton') else emit(b, 'OnMouseDown', 'LeftButton'); emit(b, 'OnMouseUp', 'LeftButton', true) end
end
local function checked()
  if classic then return b:GetChecked() end
  assert(b.Icon.texture == 'Interface\\Icons\\INV_Misc_Book_09' and b.Icon.atlas == nil,
    'selection and mouse events must preserve the book file texture')
  assert(b.Icon.width == 24 and b.Icon.height == 24, 'selection must preserve the shared icon size')
  return b.SelectedTexture.shown
end
if not classic then
  emit(b, 'OnMouseUp', 'RightButton', true)
  emit(b, 'OnMouseUp', 'LeftButton', false)
  assert(A.questsFrame == nil and not checked(), 'right-click or release outside must not toggle the library')
end
leftClick()
local browser = assert(A.questsFrame, 'side-tab must open the actual quest browser')
assert(browser:IsShown() and checked(), 'actual browser OnShow must check the tab')
local previous
for _, key in ipairs({'my','all','words'}) do
  local tab=assert(browser.libraryTabs[key])
  assert(tab:GetParent()==browser and tab._template==b._template and tab:IsVisible(),
    'all three library views must use the same native side-tab template and follow the library lifecycle')
  local point, relative, edge, x, y=tab:GetPoint()
  if previous then
    assert(point=='TOPLEFT' and relative==previous and edge=='BOTTOMLEFT' and x==0 and y==-6)
    assert(tab:GetTop()<=previous:GetBottom()-6, 'book tabs must not overlap')
  else
    assert(point=='TOPLEFT' and relative==browser and edge=='TOPRIGHT' and x==-6 and y==-100)
  end
  assert(tab:GetLeft()==browser:GetRight()-6, 'tabs must overlap the frame border to remove the visible gap')
  assert(math.abs(tab:GetEffectiveScale()-browser:GetEffectiveScale())<0.00001, 'parent scale must reach each side tab exactly once')
  if classic then assert(tab:GetNormalTexture().width==24 and tab:GetNormalTexture().height==24)
  else assert(tab.Icon.width==24 and tab.Icon.height==24 and tab.Icon.atlas==nil) end
  previous=tab
end
local originalScale=browser:GetScale()
browser:SetScale(1.5)
assert(math.abs(browser.libraryTabs.words:GetEffectiveScale()-browser:GetEffectiveScale())<0.00001)
browser:SetScale(originalScale)
assert(spellbookCalls == 0, 'Classic inherited spellbook OnClick must be replaced')
if not classic then assert(not b._pressed, 'native mouse-up must preserve pressed-icon cleanup') end
local close
for _, frame in ipairs(frames) do
  if frame:GetParent() == browser and frame._template == 'UIPanelCloseButton' then close = frame end
end
assert(close and type(close:GetScript('OnClick')) == 'function', 'use the actual browser close button')
emit(close, 'OnClick', 'LeftButton')
assert(not browser:IsShown() and not checked(), 'browser X must clear selected tab state')
for _, tab in pairs(browser.libraryTabs) do assert(not tab:IsVisible(), 'closed library must not leave an orphan side tab') end
leftClick(); emit(browser, 'OnKeyDown', 'ESCAPE')
assert(not browser:IsShown() and not checked(), 'browser Escape must clear selected tab state')
leftClick(); browser:Hide()
assert(not checked(), 'direct browser hide must clear selected tab state')
browser:Show(); assert(checked(), 'direct browser show must select the tab')
leftClick(); assert(not browser:IsShown() and not checked(), 'tab toggle must also close the real browser')

local reader = assert(A.questLogButton, 'reader must be created beside the library')
assert(reader._template == b._template and reader:GetParent() == UIParent,
  'reader must share the native tab style and escape clipping')
local readerIcon=classic and reader:GetNormalTexture() or reader.Icon
assert(readerIcon.width==24 and readerIcon.height==24)
local rp, relative, re, rx, ry = reader:GetPoint()
assert(rp == 'TOPLEFT' and relative == b and re == 'BOTTOMLEFT' and rx == 0 and ry == -8,
  'reader must sit immediately below QUESTS')
assert(math.abs(reader:GetEffectiveScale() - b:GetEffectiveScale()) < 0.00001,
  'both tabs must use the same scale')
if not classic then
  assert(reader.Icon.texture == 'Interface\\Icons\\INV_Misc_Book_11' and reader.Icon.atlas == nil)
  assert(reader.Icon.width == 24 and reader.Icon.height == 24, 'Reader icon must fit inside the native tab border')
  assert(reader:IsVisible(), 'the quest list must expose Reader without opening quest details')
  details:Show()
end
assert(reader:IsVisible(), 'visible quest details must show the reader tab')
QuestFrame:Hide()
QuestMapFrame_GetDetailQuestID = function() return 184 end
GetQuestLogQuestText = function() return 'Ein Bote wartet am Tor.', 'Sprecht mit dem Boten.' end
local function readerClick()
  if classic then emit(reader, 'OnClick', 'LeftButton')
  else emit(reader, 'OnMouseDown', 'LeftButton'); emit(reader, 'OnMouseUp', 'LeftButton', true) end
end
local function readerChecked()
  return classic and reader:GetChecked() or (not classic and reader.SelectedTexture.shown)
end
A.panel:Hide()
assert(not readerChecked())
if not classic then
  emit(reader, 'OnMouseUp', 'RightButton', true)
  emit(reader, 'OnMouseUp', 'LeftButton', false)
  assert(not A.panel:IsShown(), 'right-click or release outside must not open Reader')
end
local oldMapID, oldSelected = QuestMapFrame_GetDetailQuestID, A.Compat.SelectedQuestID
QuestMapFrame_GetDetailQuestID = function() return 0 end
A.Compat.SelectedQuestID = function() return 0 end
readerClick()
assert(not A.panel:IsShown(), 'without a selected quest, Reader must not reuse stale NPC text')
QuestMapFrame_GetDetailQuestID, A.Compat.SelectedQuestID = oldMapID, oldSelected
readerClick()
assert(A.panel:IsShown() and readerChecked() and A.lastQuest.id == 184,
  'Reader must open the selected quest and select its own tab')
readerClick()
assert(not A.panel:IsShown() and not readerChecked(), 'Reader must toggle closed and clear selection')
A.panel:Show(); assert(readerChecked())
A.panel:Hide(); assert(not readerChecked(), 'closing Reader through its own window must clear selection')
if not classic then
  details:Hide(); assert(reader:IsVisible(), 'returning to the quest list must retain Reader')
  details:Show(); assert(reader:IsVisible())
end
root:Hide(); assert(not reader:IsShown(), 'Reader must not remain floating when the map closes')
root:Show(); assert(reader:IsVisible())
local oldTooltip, title = GameTooltip
GameTooltip = { SetOwner = function() end, SetText = function(_, text) title = text end,
  AddLine = function() end, Show = function() end, Hide = function() end }
emit(reader, 'OnEnter')
assert(title == 'WordHunterWoW - Reader', 'reader tooltip must have its requested name')
GameTooltip = oldTooltip
print('quest-library-tab: ' .. (classic and 'Classic fallback' or retail and 'Retail native' or 'Forever native') .. ', outside clipping, reserved lane, visibility, scale, mouse and real browser state: ok')

-- NPC entry works independently of the load-on-demand map and reads the active passage.
root:Hide()
QuestMapFrame, WorldMapFrame, QuestLogFrame = nil, nil, nil
local npcTab = assert(A.npcReaderButton)
assert(npcTab:GetParent() == UIParent and npcTab._template == b._template)
local npcIcon=classic and npcTab:GetNormalTexture() or npcTab.Icon
assert(npcIcon.width==24 and npcIcon.height==24)
assert(not npcTab:IsShown(), 'no floating tab after NPC closes')
QuestFrame:SetScale(0.7)
QuestFrame:Show()
GetQuestID = function() return 783 end
QuestInfoFrame = { questLog = true } -- A stale log marker must not steal the NPC tab's text.
assert(npcTab:IsVisible(), 'quest offer exposes the manual Reader entry')
local np, nh, ne, nx, ny = npcTab:GetPoint()
assert(np == 'TOPLEFT' and nh == QuestFrame and ne == 'TOPRIGHT' and nx == 2 and ny == -110)
assert(math.abs(npcTab:GetEffectiveScale() - QuestFrame:GetEffectiveScale()) < 0.00001)
local function npcClick()
  if classic then emit(npcTab, 'OnClick', 'LeftButton')
  else emit(npcTab, 'OnMouseUp', 'LeftButton', true) end
end
A.panel:Hide(); A.lastPassage = 'offer'
A.readCurrentQuest()
assert(not A.panel:IsShown(), 'NPC offer must wait for a click by default')
npcClick()
assert(A.panel:IsShown() and A.lastQuest.id ~= 184 and A.lastQuest.text:find('Wolfsfleisch', 1, true),
  'NPC tab must ignore the map-selected quest and show the current NPC text')
npcClick(); assert(not A.panel:IsShown())
GetProgressText = function() return 'Habt Ihr die Aufgabe erledigt?' end
GetRewardText = function() return 'Gut gemacht.' end
for _, passage in ipairs({ 'progress', 'reward' }) do
  A.lastPassage = passage; A.readCurrentQuest()
  assert(not A.panel:IsShown())
  npcClick(); assert(A.panel:IsShown() and A.lastQuest.passage == passage)
  npcClick()
end
A.SetNpcReaderAutoOpen(true); A.readCurrentQuest()
assert(A.panel:IsShown(), 'opt-in restores NPC automatic opening')
A.SetNpcReaderAutoOpen(false); A.panel:Hide()
QuestFrame:Hide(); assert(not npcTab:IsShown())
-- Gossip may arrive later, through a separate Blizzard UI addon.
GossipFrame = fixture(UIParent, 500, 800, 400, 650)
GossipFrame:Hide()
A.AttachNpcReaderButton(); A.AttachNpcReaderButton()
assert(A.npcReaderButton == npcTab and #(GossipFrame._hooks.OnShow or {}) == 1)
GetGossipText = function() return 'Willkommen, Reisender.' end
GossipFrame:Show(); assert(npcTab:IsVisible())
assert(select(2, npcTab:GetPoint()) == GossipFrame, 'tab must move to the dialogue window')
A.readGossip(); assert(not A.panel:IsShown(), 'gossip defaults to manual too')
npcClick(); assert(A.panel:IsShown() and A.lastQuest.passage == 'gossip' and A.lastQuest.id == 0)
npcClick(); assert(not A.panel:IsShown())
A.SetNpcReaderAutoOpen(true); A.readGossip(); assert(A.panel:IsShown())
A.panel:Hide(); GossipFrame:Hide(); assert(not npcTab:IsShown())
print('npc-reader-tab: manual offer/progress/reward/gossip, opt-in, late load, native scale and visibility: ok')

-- The new return tab uses the same strict native/fallback model and lifecycle.
dofile('QuestReader.lua')
WordHunterWoW_QuestDataByFlavor = {[A.Compat.GameFlavor()]={
  deDE={[9001]={title='Eine Aufgabe',description='Der Hund wartet.'}},
  enUS={[9001]={title='A task',description='The dog waits.'}},
}}
GetQuestLogQuestText=nil
A.panel.enScroll.GetVerticalScroll=function() return 0 end
browser:Hide()
assert(A.OpenCatalogQuest(9001,'deDE'))
local back=assert(A.libraryReturnButton)
assert(back:GetParent()==A.panel and back._template==b._template and back:IsVisible())
local bp,br,be,bx,by=back:GetPoint()
assert(bp=='BOTTOMLEFT' and br==A.panel and be=='BOTTOMRIGHT' and bx==-6 and by==12)
if classic then
  assert(back._normalTexture=='Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up')
  assert(back:GetNormalTexture().width==24 and back:GetNormalTexture().height==24)
else assert(back.Icon.texture=='Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up' and back.Icon.width==24 and back.Icon.height==24) end
local scale=A.panel:GetScale()
A.panel:SetScale(1.4)
assert(math.abs(back:GetEffectiveScale()-A.panel:GetEffectiveScale())<0.00001)
A.panel:SetScale(scale)
A.panel:Hide(); assert(not back:IsVisible(), 'a closed reader must not leave the return tab floating')
A.panel:Show(); assert(back:IsVisible())
if classic then emit(back,'OnClick','LeftButton') else emit(back,'OnMouseUp','LeftButton',true) end
assert(browser:IsShown() and not A.panel:IsShown() and not back:IsVisible())
assert(A.OpenCatalogQuest(9001,'deDE') and A.libraryReturnButton==back, 'reopening must reuse the return tab')
GossipFrame:Show(); A.readGossip(true)
assert(A.panel:IsShown() and not back:IsShown(), 'native dialogue must hide the library-only return tab')
assert(rawget(A.panel,'catalogLanguageButton')==nil and rawget(browser,'catalogLanguageButton')==nil)
print('reader-return-tab: bottom arrow, native/fallback style, parent scale, hide/show, reuse and NPC transition: ok')
