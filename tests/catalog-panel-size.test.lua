-- Lua 5.1: a read-only English catalog passage must not shrink the reader.
-- SetSize emits OnSizeChanged and HookScript callbacks as in the client, so
-- assertions include the real saved geometry, not merely a mock frame size.
dofile('tests/wowstub.lua')
local makeFrame = CreateFrame
local pending = {}
C_Timer.NewTimer = function(_, fn)
  local timer = { fn = fn }
  function timer:Cancel() self.cancelled = true end
  pending[#pending + 1] = timer
  return timer
end
local function flush()
  while #pending > 0 do
    local batch = pending
    pending = {}
    for _, timer in ipairs(batch) do if not timer.cancelled then timer.fn() end end
  end
end
CreateFrame = function(...)
  local f = makeFrame(...)
  -- The generic node fabricates unknown fields; a real new frame has no grip.
  f.resizeHandle = false
  local hooks = {}
  function f:HookScript(name, fn)
    hooks[name] = hooks[name] or {}
    table.insert(hooks[name], fn)
  end
  local function emit(name, ...)
    local base = f:GetScript(name)
    if base then base(f, ...) end
    for _, hook in ipairs(hooks[name] or {}) do hook(f, ...) end
  end
  function f:SetSize(w, h)
    local changed = self:GetWidth() ~= w or self:GetHeight() ~= h
    self.w, self.h = w, h
    if changed then emit('OnSizeChanged', w, h) end
  end
  function f:SetWidth(w) self:SetSize(w, self:GetHeight()) end
  function f:SetHeight(h) self:SetSize(self:GetWidth(), h) end
  local anchor = { 'CENTER', UIParent, 'CENTER', 0, 0 }
  local setPoint = f.SetPoint
  function f:SetPoint(point, relative, relPoint, x, y)
    setPoint(self, point, relative, relPoint, x, y)
    if type(x) == 'number' and type(y) == 'number' then
      anchor = { point, relative, relPoint, x, y }
    end
  end
  function f:GetPoint() return unpack(anchor) end
  function f:Show()
    local changed = not self.shown
    self.shown = true
    if changed then emit('OnShow') end
  end
  function f:Hide()
    local changed = self.shown
    self.shown = false
    if changed then emit('OnHide') end
  end
  return f
end
for _, name in ipairs({'Core.lua','Compat.lua','UICommon.lua','QuestPanel.lua','QuestReader.lua'}) do dofile(name) end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', readingMode = true, integratedLayout = true,
  frames = { ['panel:reading'] = { point = 'CENTER', relPoint = 'CENTER', x = 144.8, y = 92,
    w = 1139.2, h = 747.6, userSized = true } } }, wordsByLocale = {} }
A.initializeDatabase()
WordHunterWoW_QuestData = { deDE = { [61] = {
  title = 'Eine Aufgabe', description = 'Der Hund wartet.', objectives = 'Findet den Hund.' } } }
WordHunterWoW_QuestEN = {
  [61] = { title = 'A quest', description = 'The dog waits.', objectives = 'Find the dog.' },
  [62] = { title = 'English reference', description = 'An English-only passage.', objectives = 'Read it.' },
}
C_QuestLog = nil
SelectQuestLogEntry = function() error('library reading must not change native quest selection') end
A.createPanel()
A.panel.enScroll.GetVerticalScroll = function() return 0 end
if arg[1] ~= 'first-reference' then
  assert(A.OpenCatalogQuest(61))
  flush()
end
assert(A.panel.integratedLayout == true, 'setup must start with two columns')
assert(A.panel:GetWidth() == 1139.2 and A.panel:GetHeight() == 747.6, 'setup must restore the large reader')
assert(A.OpenCatalogQuest(62))
flush()
assert(A.lastQuest.readOnly and A.panel.integratedLayout == false, 'setup must switch to an English-only reference')
local saved = WordHunterWoWDB.settings.frames['panel:reading']
print('reference size '..A.panel:GetWidth()..' x '..A.panel:GetHeight()
  ..'; saved '..tostring(saved.w)..' x '..tostring(saved.h)..'; userSized='..tostring(saved.userSized))
assert(A.panel:GetWidth() == 1139.2 and A.panel:GetHeight() == 747.6,
  'English-only reference must not shrink the manually sized reading window')
assert(saved.w == 1139.2 and saved.h == 747.6 and saved.userSized,
  'automatic column changes must not overwrite the saved large reading size')
assert(saved.x == 144.8 and saved.y == 92, 'reading must preserve the chosen position')
-- Closing and restoring exercises the same persisted settings used on /reload.
A.panel:Hide()
A.panel:SetSize(400, 330)
A.PlaceFrame(A.panel, 'panel')
assert(A.panel:GetWidth() == 1139.2 and A.panel:GetHeight() == 747.6,
  'the large reading size must roundtrip through the persisted geometry')
assert(A.OpenCatalogQuest(61))
flush()
assert(A.panel:GetWidth() == 1139.2 and A.panel:GetHeight() == 747.6,
  'returning to the normal German/English reader must keep the same large size')
-- The same frame serves /whw and live NPC quests. Do not retain the catalog's
-- read-only state or compact size on that existing, non-catalog entry point.
GetQuestID = function() return 63 end
GetTitleText = function() return 'Eine normale Aufgabe' end
GetQuestText = function() return 'Der Hund wartet auf Euch.' end
GetObjectiveText = function() return 'Findet den Hund.' end
A.readCurrentQuest()
A.panel:Show()
flush()
assert(A.lastQuest and not A.lastQuest.readOnly and A.panel.integratedLayout,
  'the native reader must return to the normal learning layout')
assert(A.panel:GetWidth() == 1139.2 and A.panel:GetHeight() == 747.6,
  'the normal reader must retain the chosen size after catalog reading')
print('catalog-panel-size: ok')
