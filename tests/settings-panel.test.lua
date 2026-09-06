-- Run from the addon root:  lua tests/settings-panel.test.lua
--
-- Nothing used to build the settings panel outside the game, so a control added
-- with a nil global, or a row anchored past the bottom of the scroll box, only
-- showed up once someone logged in. Every control here is placed at a hand-
-- written offset, so inserting one moves every offset below it -- which is
-- exactly the kind of edit that needs a test rather than a careful reading.

local node = dofile('tests/wowstub.lua')

-- The dropdown API, recorded rather than drawn: the test needs to know which
-- entries a menu offers and which one it ticks.
local menus = {}
UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_SetText = function(frame, text) frame.shownText = text end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function(info) menus[#menus].entries[#menus[#menus].entries + 1] = info end
UIDropDownMenu_Initialize = function(frame, initializer)
  menus[#menus + 1] = { frame = frame, entries = {} }
  frame.menu = menus[#menus]
  initializer(frame, 1)
end

-- Frames remember where they were put and who owns them, so the layout can be
-- checked. The stub deliberately does not, because almost nothing else cares.
local placed = {}
local plainCreateFrame = CreateFrame
local function track(object, parent)
  object.parent = parent
  -- The tick is modelled for the same reason the stub models shown and sized:
  -- a field nothing has set answers with another frame, which is truthy, so an
  -- unmodelled GetChecked reports every box ticked -- and a switch that is meant
  -- to come up off would pass this file whatever the addon actually did.
  function object:SetChecked(value) self.checked = not not value end
  function object:GetChecked() return self.checked and true or false end
  function object:SetPoint(_, a, b)
    -- SetPoint("TOPLEFT", x, y) and SetPoint("TOPLEFT", frame, "TOPLEFT", x, y)
    if type(a) == "number" then self.x, self.y = a, b end
    return self
  end
  local created = object.CreateFontString
  function object:CreateFontString(...)
    local fs = type(created) == "function" and created(self, ...) or node()
    return track(fs, self)
  end
  placed[#placed + 1] = object
  return object
end
CreateFrame = function(kind, name, parent, template)
  return track(plainCreateFrame(kind, name, parent, template), parent)
end

WordHunterWoW_Addon = {}
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('Harvest.lua')
-- Loaded in the order the .toc loads it, and before Settings, because the panel
-- is only a set of controls over other files' settings: the quest log switch
-- and its wording both live with the behaviour they govern, and without this
-- the checkbox would be built against a nil getter.
dofile('QuestPanel.lua')
dofile('Settings.lua')
local Addon = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
-- A real table, not the stub's stand-in: the harvest counter walks this one,
-- and a manufactured node hands it its own methods to count.
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()

local panel = Addon.CreateSettingsPanel()
assert(panel, 'the settings panel did not build')

local box = _G.WordHunterWoWSettingsContent
local marking = _G.WordHunterWoWWordMarkingDropdown
-- rawget for the menu: it is a field the initializer above hangs on the frame,
-- and a stub frame manufactures a child for any field it has not got. Read
-- plainly, a dropdown that was built but never initialised answers with a frame,
-- the assertion passes, and the loop below walks a table that never ends.
assert(marking and rawget(marking, 'menu'), 'the word marking dropdown was never initialised')

-- Every mode the setting accepts has to be reachable from the menu, or a player
-- can end up with one they cannot get back out of.
local offered = {}
for _, info in ipairs(marking.menu.entries) do offered[info.value] = info end
for _, key in ipairs(Addon.WORD_MARKING_ORDER) do
  assert(offered[key], 'no menu entry for marking mode ' .. key)
  assert(offered[key].text == Addon.WORD_MARKINGS[key].name, key .. ': wrong label')
end
assert(#marking.menu.entries == #Addon.WORD_MARKING_ORDER, 'menu offers a mode the setting does not accept')
assert(offered[Addon.GetWordMarking()].checked, 'the current mode is not ticked')
assert(marking.shownText == Addon.WORD_MARKINGS[Addon.GetWordMarking()].name, 'dropdown shows the wrong mode')

offered.color.func(offered.color, 'color')
assert(Addon.GetWordMarking() == 'color', 'choosing a mode did not store it')
assert(marking.shownText == Addon.WORD_MARKINGS.color.name, 'dropdown text did not follow the choice')

-- Blizzard's own route into this panel calls refresh, not the setters, so the
-- controls have to be able to catch up with a value changed elsewhere.
Addon.SetWordMarking('underline')
panel.refresh()
assert(marking.shownText == Addon.WORD_MARKINGS.underline.name, 'refresh did not resync the dropdown')
local ticked
for _, info in ipairs(marking.menu.entries) do if info.checked then ticked = info.value end end
assert(ticked == 'underline', 'refresh left the tick on ' .. tostring(ticked))

-- The quest log switch. It is the one control here that governs whether a
-- window appears at all, so both positions have to be reachable and it has to
-- come up in the position a player who has never opened this panel is already
-- in -- unticked, the panel staying out of the quest log's way.
local questLogAuto = _G.WordHunterWoWQuestLogAutoCheck
assert(questLogAuto:GetChecked() == false, 'the quest log switch must come up unticked')
assert(_G.WordHunterWoWQuestLogAutoCheckText:GetText() == Addon.LABELS.questLogAutoLabel,
  'the switch is unlabelled, so nobody can tell what it does')
questLogAuto:SetChecked(true)
questLogAuto:GetScript('OnClick')(questLogAuto)
assert(Addon.GetQuestLogAutoOpen() == true, 'ticking the switch did not store the setting')

-- Blizzard's own route into this panel calls refresh, not the setters.
Addon.SetQuestLogAutoOpen(false)
panel.refresh()
assert(questLogAuto:GetChecked() == false, 'refresh did not resync the quest log switch')

-- The size sliders, which are the reason this panel has headings at all. The
-- complaint was that the word editor came up visibly bigger than the quest
-- panel with both sliders reading the same number -- and it does, because the
-- two surfaces start from different Blizzard fonts and one grows its window
-- while the other does not. No arrangement of the scaling makes equal numbers
-- look equal, so the panel has to stop offering two numbers that invite the
-- comparison: two headings, and a text size measured in points against a window
-- size measured in per cent.
for _, group in ipairs(Addon.SIZE_GROUPS) do
  for _, entry in ipairs(group.entries) do
    local suffix = entry.key:sub(1, 1):upper() .. entry.key:sub(2)
    local slider = _G['WordHunterWoW' .. suffix .. 'Slider']
    assert(rawget(_G, 'WordHunterWoW' .. suffix .. 'Slider'), entry.key .. ' has no slider in the panel')
    local label = Addon.LABELS[entry.label]
    local caption = _G[slider:GetName() .. 'Text']
    assert(caption:GetText() == label .. ' (' .. Addon.FormatSizeValue(group.unit, 1.0) .. ')',
      entry.key .. ' reads "' .. tostring(caption:GetText()) .. '"')
    assert(_G[slider:GetName() .. 'Low']:GetText() == Addon.FormatSizeValue(group.unit, Addon.TEXT_SCALE_MIN)
      and _G[slider:GetName() .. 'High']:GetText() == Addon.FormatSizeValue(group.unit, Addon.TEXT_SCALE_MAX),
      entry.key .. ": the ends of the slider are not in the unit its group is measured in")
    -- Spelled out rather than only compared against the formatter, which would
    -- agree with itself however both families came to be measured the same.
    local ending = group.unit == 'points' and 'pt%)$' or '%%%)$'
    assert(caption:GetText():find(ending), entry.key .. ' is not measured in ' .. group.unit)
    -- Moving it has to store the size and redraw the figure. A slider whose
    -- caption lags is worse than one with no caption: it reports a size the
    -- player is not looking at.
    slider:GetScript('OnValueChanged')(slider, 1.5)
    assert(Addon['Get' .. suffix]() == 1.5, entry.key .. ' did not store what the slider was moved to')
    assert(caption:GetText() == label .. ' (' .. Addon.FormatSizeValue(group.unit, 1.5) .. ')',
      entry.key .. ': the figure did not follow the slider')
  end
end

-- The headings and the small print under them. They are what the panel says
-- instead of the comment nobody reads, so their absence is the bug coming back.
local drawn = {}
for _, object in ipairs(placed) do
  local text = object.GetText and object:GetText()
  if type(text) == 'string' then drawn[text] = true end
end
for _, group in ipairs(Addon.SIZE_GROUPS) do
  assert(drawn[Addon.LABELS[group.heading]], Addon.LABELS[group.heading] .. ': heading never drawn')
  assert(drawn[Addon.LABELS[group.note]],
    Addon.LABELS[group.heading] .. ': the line saying what these numbers measure is missing')
  for _, entry in ipairs(group.entries) do
    if entry.note then
      assert(drawn[Addon.LABELS[entry.note]], entry.key .. ': its own note was never drawn')
    end
  end
end

-- Blizzard's own route in calls refresh, not the setters, and SetValue leaves
-- the figure alone when the slider is already at the value it is handed. So a
-- panel reopened after /whw reset showed the size it had been built with.
Addon.SetEditorScale(1.2)
panel.refresh()
assert(_G.WordHunterWoWEditorScaleSliderText:GetText()
    == Addon.LABELS.editorScaleLabel .. ' (' .. Addon.FormatSizeValue('percent', 1.2) .. ')',
  'refresh left the editor size reading ' .. tostring(_G.WordHunterWoWEditorScaleSliderText:GetText()))

-- The scroll box is a fixed height and everything in it is at a fixed offset.
-- Inserting a control pushes the rest down; if the box is not grown to match,
-- the last one cannot be scrolled to.
-- rawget: an unset field on a stub frame manufactures another stub rather than
-- answering nil, so GetHeight() cannot be trusted for a control that never had
-- one set. Only a height the addon actually asked for counts.
local boxHeight = rawget(box, 'h')
local lowest, lowestName = 0, '?'
for _, object in ipairs(placed) do
  if object.parent == box and type(object.y) == 'number' then
    local height = rawget(object, 'h')
    local depth = -object.y + (type(height) == 'number' and height or 0)
    if depth > lowest then lowest, lowestName = depth, object.GetName and object:GetName() or 'label' end
  end
end
assert(lowest > 0, 'no control was placed in the scroll box')
assert(lowest <= boxHeight,
  string.format('%s reaches %d, past the %d-high scroll box', lowestName, lowest, boxHeight))

print(string.format('settings-panel: %d controls, lowest reaches %d of %d', #placed, lowest, boxHeight))
