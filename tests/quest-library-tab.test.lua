-- lua5.1 tests/quest-library-tab.test.lua [classic] [baseline-source-directory]
-- Focused real-template, visibility and clipping regression; no frame-field fabrication.
dofile('tests/wowstub.lua')
local classic, baseline = arg[1] == 'classic', arg[2]
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
    frame:SetSize(40, 35) -- Representative atlas-derived OnLoad size; preserve it.
    frame.Icon = { SetTexture = function(self, texture) self.texture = texture end }
    function frame:SetFillToInterior(fill, width) self._fill, self._iconWidth = fill, width end
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
QuestMapFrame, WorldMapFrame, QuestLogFrame = nil, nil, nil
if classic then SidePanelTabButtonMixin = nil else SidePanelTabButtonMixin = {} end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = classic and 2 or 1, 1
GetBuildInfo = function()
  if classic then return '1.15.9', '62222', '', 11509 end
  return '1.60.1', '69893', '', 16001
end
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'UICommon.lua', 'QuestPanel.lua', 'QuestBrowser.lua' }) do
  dofile(baseline and (file == 'QuestPanel.lua' or file == 'QuestBrowser.lua') and baseline .. '/' .. file or file)
end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
assert(A.Compat.GameFlavor() == (classic and 'classic' or 'forever'))
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
else
  assert(b:GetWidth() == 40 and b:GetHeight() == 35, 'native atlas-derived tab dimensions must stay intact')
  assert(b.Icon.texture == 'Interface\\Icons\\INV_Misc_Book_09' and b._fill and b._iconWidth == 40 and b._mouseEnabled)
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
local hookCount = #(root._hooks.OnShow or {})
assert(A.AttachQuestsLogButton() == b and A.AttachQuestsLogButton() == b, 'repeated attach must reuse the original side tab')
A.hookQuestUi()
assert(A.questsLogButton == b and #(root._hooks.OnShow or {}) == hookCount, 'late lifecycle hooks must not duplicate the tab or visibility hooks')
local templateCount = 0
for _, frame in ipairs(frames) do if frame._template == b._template then templateCount = templateCount + 1 end end
assert(templateCount == 1, 'one side-tab template instance per session')

local function leftClick()
  if classic then emit(b, 'OnClick', 'LeftButton') else emit(b, 'OnMouseDown', 'LeftButton'); emit(b, 'OnMouseUp', 'LeftButton', true) end
end
if not classic then
  emit(b, 'OnMouseUp', 'RightButton', true)
  emit(b, 'OnMouseUp', 'LeftButton', false)
  assert(A.questsFrame == nil and not b:GetChecked(), 'right-click or release outside must not toggle the library')
end
leftClick()
local browser = assert(A.questsFrame, 'side-tab must open the actual quest browser')
assert(browser:IsShown() and b:GetChecked(), 'actual browser OnShow must check the tab')
assert(spellbookCalls == 0, 'Classic inherited spellbook OnClick must be replaced')
if not classic then assert(not b._pressed, 'native mouse-up must preserve pressed-icon cleanup') end
local close
for _, frame in ipairs(frames) do
  if frame:GetParent() == browser and frame._template == 'UIPanelCloseButton' then close = frame end
end
assert(close and type(close:GetScript('OnClick')) == 'function', 'use the actual browser close button')
emit(close, 'OnClick', 'LeftButton')
assert(not browser:IsShown() and not b:GetChecked(), 'browser X must clear selected tab state')
leftClick(); emit(browser, 'OnKeyDown', 'ESCAPE')
assert(not browser:IsShown() and not b:GetChecked(), 'browser Escape must clear selected tab state')
leftClick(); browser:Hide()
assert(not b:GetChecked(), 'direct browser hide must clear selected tab state')
browser:Show(); assert(b:GetChecked(), 'direct browser show must select the tab')
leftClick(); assert(not browser:IsShown() and not b:GetChecked(), 'tab toggle must also close the real browser')
print('quest-library-tab: ' .. (classic and 'Classic fallback' or 'Forever native') .. ', outside clipping, reserved lane, visibility, scale, mouse and real browser state: ok')
