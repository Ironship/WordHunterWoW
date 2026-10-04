-- Lua 5.1: large footer controls must fit without changing user geometry.
dofile('tests/wowstub.lua')
local create = CreateFrame
local timers = {}
C_Timer.NewTimer = function(_, fn)
  local timer = { fn = fn }
  function timer:Cancel() self.cancelled = true end
  timers[#timers + 1] = timer
  return timer
end
local function flush()
  while #timers > 0 do
    local batch = timers
    timers = {}
    for _, timer in ipairs(batch) do if not timer.cancelled then timer.fn() end end
  end
end
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  f.resizeHandle = false -- Never fabricate a grip and skip real save hooks.
  f._anchors = {}
  local hooks = {}
  function f:HookScript(event, fn)
    hooks[event] = hooks[event] or {}
    hooks[event][#hooks[event] + 1] = fn
  end
  local function emit(event, ...)
    local fn = f:GetScript(event)
    if fn then fn(f, ...) end
    for _, hook in ipairs(hooks[event] or {}) do hook(f, ...) end
  end
  function f:SetSize(w, h)
    local changed = self:GetWidth() ~= w or self:GetHeight() ~= h
    self.w, self.h = w, h
    if changed then emit('OnSizeChanged', w, h) end
  end
  function f:SetWidth(w) self:SetSize(w, self:GetHeight()) end
  function f:SetHeight(h) self:SetSize(self:GetWidth(), h) end
  function f:SetResizeBounds(minW, minH, maxW, maxH)
    self._bounds = { minW, minH, maxW, maxH }
    self:SetSize(math.max(minW, math.min(maxW, self:GetWidth())),
      math.max(minH, math.min(maxH, self:GetHeight())))
  end
  function f:SetPoint(point, relative, edge, x, y)
    if type(relative) == 'number' then x, y, relative, edge = relative, edge, parent, point end
    self._anchors[point] = { relative, edge or point, x or 0, y or 0 }
    if type(x) == 'number' and type(y) == 'number' and relative == UIParent then
      self._savedAnchor = { point, relative, edge, x, y }
    end
  end
  function f:ClearAllPoints() self._anchors = {} end
  function f:GetPoint() return unpack(self._savedAnchor or { 'CENTER', UIParent, 'CENTER', 0, 0 }) end
  function f:Show() local changed = not self.shown; self.shown = true; if changed then emit('OnShow') end end
  function f:Hide() local changed = self.shown; self.shown = false; if changed then emit('OnHide') end end
  local makeString = f.CreateFontString
  function f:CreateFontString(...)
    local fs = makeString(self, ...)
    fs._anchors = {}
    function fs:SetPoint(point, relative, edge, x, y)
      if type(relative) == 'number' then x, y, relative, edge = relative, edge, f, point end
      f.SetPoint(self, point, relative, edge, x, y)
    end
    fs.ClearAllPoints = f.ClearAllPoints
    return fs
  end
  return f
end
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'UICommon.lua', 'QuestPanel.lua', 'QuestReader.lua' }) do
  dofile(file == 'QuestPanel.lua' and arg[1] or file)
end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', readingMode = true, integratedLayout = true,
  frames = { ['panel:reading'] = { point = 'CENTER', relPoint = 'CENTER', x = 140, y = 92,
    w = 400, h = 650, userSized = true },
    ['panel:npc'] = { point = 'CENTER', relPoint = 'CENTER', x = 22, y = 18,
      w = 720, h = 427.6, userSized = true },
    ['panel:questlog'] = { point = 'CENTER', relPoint = 'CENTER', x = 44, y = 9,
      w = 720, h = 427.6, userSized = true } } }, wordsByLocale = {} }
A.initializeDatabase()
WordHunterWoW_QuestData = { deDE = { [7] = { title = 'Eine Aufgabe', description = 'Der Wolf wartet.' } },
  enUS = { [7] = { title = 'A quest', description = 'The wolf waits.' } } }
WordHunterWoW_QuestEN = { [7] = { title = 'A quest', description = 'The wolf waits.' } }
C_QuestLog = nil
SelectQuestLogEntry = function() error('catalog must not select a live quest') end
A.createPanel()
A.panel.enScroll.GetVerticalScroll = function() return 0 end
local panel = A.panel
local function rect(f)
  if f == panel then return 0, panel:GetWidth(), 0, panel:GetHeight() end
  local a = f._anchors.BOTTOMRIGHT or f._anchors.RIGHT
  assert(a, 'action must have a real bottom-right or right anchor')
  local l, r, b, t = rect(a[1])
  local right = (a[2] == 'LEFT' and l or r) + a[3]
  local bottom = (a[2] == 'LEFT' and ((b + t - f:GetHeight()) / 2) or b) + a[4]
  return right - f:GetWidth(), right, bottom, bottom + f:GetHeight()
end
local function check(step, width)
  flush()
  local rects = {}
  for _, button in ipairs(panel.actions) do
    local l, r, b, t = rect(button)
    assert(l >= 18 - 0.001 and r <= width - 18 + 0.001,
      step .. ': footer control outside reader: ' .. l .. '..' .. r)
    for _, previous in ipairs(rects) do
      assert(r <= previous[1] or l >= previous[2] or t <= previous[3] or b >= previous[4],
        step .. ': footer controls overlap')
    end
    rects[#rects + 1] = { l, r, b, t }
    local _, footerY = panel.footerLine:GetAnchor('BOTTOMLEFT')
    assert(t < footerY, step .. ': footer control overlaps the legend/content boundary')
  end
  if panel.integratedLayout then
    local left, right = panel.meta._anchors.BOTTOMLEFT, panel.meta._anchors.BOTTOMRIGHT
    local l, r, b = rect(right[1])
    local metaRight = (right[2] == 'BOTTOMLEFT' and l or r) + right[3]
    assert(metaRight > left[3], step .. ': progress has reversed horizontal bounds')
    assert(math.abs(left[4] - (b + right[4])) < 0.001, step .. ': progress bottom anchors disagree')
    local metaTop = left[4] + panel.meta:GetHeight()
    for _, action in ipairs(rects) do
      assert(metaRight <= action[1] or left[3] >= action[2] or metaTop <= action[3] or left[4] >= action[4],
        step .. ': progress overlaps a footer control')
    end
    local _, footerY = panel.footerLine:GetAnchor('BOTTOMLEFT')
    assert(metaTop < footerY, step .. ': progress overlaps the legend/content boundary')
  end
  local saved = WordHunterWoWDB.settings.frames['panel:reading']
  assert(panel:GetWidth() == width and panel:GetHeight() == 650, step .. ': selected dimensions changed')
  assert(saved.w == width and saved.h == 650 and saved.x == 140 and saved.y == 92 and saved.userSized,
    step .. ': persisted geometry changed')
end
for _, width in ipairs({ 400, 600, 1139.2 }) do
  panel:SetSize(width, 650)
  -- The real size callback persists this explicitly chosen width.
  for _, scale in ipairs({ 2, 1, 1.55, 1.6 }) do
    A.SetTextScale(scale)
    assert(A.OpenCatalogQuest(7, 'deDE')); check('DE ' .. scale, width)
    assert(A.SetCatalogLocale('enUS')); check('EN ' .. scale, width)
    assert(A.SetCatalogLocale('deDE')); check('DE return ' .. scale, width)
    panel:Hide(); A.PlaceFrame(panel, 'panel')
    assert(A.OpenCatalogQuest(7, 'deDE')); check('close/restore ' .. scale, width)
    GetQuestID = function() return 8 end
    GetTitleText = function() return 'Eine native Aufgabe' end
    GetQuestText = function() return 'Der Wolf wartet.' end
    GetObjectiveText = function() return '' end
    QuestFrame:Show(); A.readCurrentQuest(); check('native ' .. scale, width)
  end
end
for key, position in pairs({ npc = { 22, 18 }, questlog = { 44, 9 } }) do
  local saved = WordHunterWoWDB.settings.frames['panel:' .. key]
  assert(saved.w == 720 and saved.h == 427.6 and saved.x == position[1] and saved.y == position[2] and saved.userSized,
    'reading footer changes must not overwrite the separate ' .. key .. ' layout')
end
-- Reading mode restores the actual separate NPC geometry, not a compact default.
A.SetReadingMode(false)
flush()
assert(A.GetLayoutContext() == 'npc' and panel:GetWidth() == 720 and panel:GetHeight() == 427.6)
local npc = WordHunterWoWDB.settings.frames['panel:npc']
assert(npc.x == 22 and npc.y == 18 and npc.userSized, 'NPC context position/size preference lost')
assert(panel.resizeHandle:GetScript('OnDragStart'), 'must exercise the real resize grip/save hooks')
print('footer-wrap: narrow/wide native and DE/EN catalog controls, progress, boundaries and saved geometry: ok')
