-- Run from the addon root:  lua tests/settings-panel.test.lua
--
-- The settings window's controls, built outside the game. A control added with
-- a nil global, or a row that ends past the bottom of its tab's scroll box,
-- only showed up once someone logged in.
--
-- Rewritten for 1.20, when the settings moved out of the page in Blizzard's
-- options canvas and into the addon's own window. It pins the same behaviour it
-- did for the page: every word marking mode is offered and the current one is
-- marked, the quest log and controller switches come up in the right position
-- with their labels, every size slider carries its unit and follows a drag,
-- the headings and notes are drawn, refresh catches up with a change made
-- elsewhere, and nothing sits past the end of the box it scrolls in. What
-- changed is how the choice is read: the page used Blizzard's dropdown, whose
-- API this file used to record; the window opens a menu of its own, which is
-- opened and read here instead.

local node = dofile('tests/wowstub.lua')

-- Every string drawn, so the headings and notes can be looked for, and the
-- tick modelled on every frame.
local placed = {}
local plainCreateFrame = CreateFrame
local function track(object)
  -- The tick is modelled for the same reason the stub models shown and sized:
  -- a field nothing has set answers with another frame, which is truthy, so an
  -- unmodelled GetChecked reports every box ticked -- and a switch that is meant
  -- to come up off would pass this file whatever the addon actually did.
  function object:SetChecked(value) self.checked = not not value end
  function object:GetChecked() return self.checked and true or false end
  local created = object.CreateFontString
  function object:CreateFontString(...)
    local fs = type(created) == "function" and created(self, ...) or node()
    return track(fs)
  end
  placed[#placed + 1] = object
  return object
end
CreateFrame = function(kind, name, parent, template)
  return track(plainCreateFrame(kind, name, parent, template))
end

WordHunterWoW_Addon = {}
dofile('Core.lua')
dofile('Compat.lua')
dofile('Gamepad.lua')
dofile('UICommon.lua')
dofile('Harvest.lua')
-- Loaded in the order the .toc loads it, and before Settings, because the
-- window is only a set of controls over other files' settings: the quest log
-- switch and its wording both live with the behaviour they govern.
dofile('QuestPanel.lua')
dofile('Settings.lua')
local Addon = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
-- A real table, not the stub's stand-in: the harvest counter walks this one,
-- and a manufactured node hands it its own methods to count.
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()

local window = Addon.CreateSettingsPanel()
assert(window, 'the settings window did not build')
assert(rawget(_G, 'WordHunterWoWSettingsWindow') == window, 'the window is not reachable by its name')

-- The choice for word marking, opened the way a click opens it.
local marking = rawget(_G, 'WordHunterWoWWordMarkingDropdown')
assert(marking, 'there is no word marking choice')
local shown = rawget(_G, 'WordHunterWoWWordMarkingDropdownText')
assert(shown, 'the choice has no text of its own')
local function openMenu()
  marking:GetScript('OnClick')(marking)
  local menu = Addon.settingsMenu
  assert(menu and menu:IsShown(), 'clicking the choice did not open its menu')
  -- rawget: a field the menu has not been given would be manufactured, and a
  -- loop over a manufactured table never ends.
  local entries = rawget(menu, 'entries')
  assert(type(entries) == 'table', 'the menu kept no list of what it offers')
  local offered = {}
  for index, entry in ipairs(entries) do
    offered[entry.value] = { entry = entry, button = menu.buttons[index] }
  end
  return menu, entries, offered
end

-- Every mode the setting accepts has to be reachable from the menu, or a player
-- can end up with one they cannot get back out of.
local menu, entries, offered = openMenu()
for _, key in ipairs(Addon.WORD_MARKING_ORDER) do
  assert(offered[key], 'no menu entry for marking mode ' .. key)
  assert(offered[key].entry.label == Addon.WORD_MARKINGS[key].name, key .. ': wrong label')
end
assert(#entries == #Addon.WORD_MARKING_ORDER, 'menu offers a mode the setting does not accept')
assert(offered[Addon.GetWordMarking()].button.current == true, 'the current mode is not marked')
for key, item in pairs(offered) do
  assert(item.button.current == (key == Addon.GetWordMarking()), key .. ' is marked but is not the current mode')
end
assert(shown:GetText() == Addon.WORD_MARKINGS[Addon.GetWordMarking()].name, 'the choice shows the wrong mode')

offered.color.button:GetScript('OnClick')(offered.color.button)
assert(Addon.GetWordMarking() == 'color', 'choosing a mode did not store it')
assert(not menu:IsShown(), 'and the menu stays open after the choice')
assert(shown:GetText() == Addon.WORD_MARKINGS.color.name, 'the choice text did not follow the choice')

-- A second click on the choice closes the menu it opened.
marking:GetScript('OnClick')(marking)
marking:GetScript('OnClick')(marking)
assert(not menu:IsShown(), 'a second click on the choice has to close its menu')

-- A setting changed elsewhere -- a slash command, another window -- reaches the
-- controls through refresh, not through the controls' own scripts.
Addon.SetWordMarking('underline')
window.refresh()
assert(shown:GetText() == Addon.WORD_MARKINGS.underline.name, 'refresh did not resync the choice')
menu, entries, offered = openMenu()
local marked
for key, item in pairs(offered) do if item.button.current then marked = key end end
assert(marked == 'underline', 'refresh left the mark on ' .. tostring(marked))
menu:Hide()

-- The quest log switch. It is the one control here that governs whether a
-- window appears at all, so both positions have to be reachable and it has to
-- come up in the position a player who has never opened this window is already
-- in -- unticked, the panel staying out of the quest log's way.
local questLogAuto = _G.WordHunterWoWQuestLogAutoCheck
assert(questLogAuto:GetChecked() == false, 'the quest log switch must come up unticked')
assert(_G.WordHunterWoWQuestLogAutoCheckText:GetText() == Addon.LABELS.questLogAutoLabel,
  'the switch is unlabelled, so nobody can tell what it does')
questLogAuto:SetChecked(true)
questLogAuto:GetScript('OnClick')(questLogAuto)
assert(Addon.GetQuestLogAutoOpen() == true, 'ticking the switch did not store the setting')

Addon.SetQuestLogAutoOpen(false)
window.refresh()
assert(questLogAuto:GetChecked() == false, 'refresh did not resync the quest log switch')

-- The controller switch: on for a player who has never opened this window. A
-- pad that is on in the game and ignored by the panel would be the surprise,
-- so the switch exists to turn the panel's share off, not on.
local pad = _G.WordHunterWoWGamepadCheck
assert(pad:GetChecked() == true, 'the controller switch must come up ticked')
assert(_G.WordHunterWoWGamepadCheckText:GetText() == Addon.LABELS.gamepadLabel,
  'the controller switch is unlabelled, so nobody can tell what it does')
pad:SetChecked(false)
pad:GetScript('OnClick')(pad)
assert(Addon.GetGamePadEnabled() == false, 'unticking the switch did not store the setting')
Addon.SetGamePadEnabled(true)
window.refresh()
assert(pad:GetChecked() == true, 'refresh did not resync the controller switch')

-- The size sliders, which are the reason the Sizes tab has headings at all.
-- The complaint was that the word editor came up visibly bigger than the quest
-- panel with both sliders reading the same number -- and it does, because the
-- two surfaces start from different Blizzard fonts and one grows its window
-- while the other does not. No arrangement of the scaling makes equal numbers
-- look equal, so the window has to stop offering two numbers that invite the
-- comparison: two headings, and a text size measured in points against a window
-- size measured in per cent.
for _, group in ipairs(Addon.SIZE_GROUPS) do
  for _, entry in ipairs(group.entries) do
    local suffix = entry.key:sub(1, 1):upper() .. entry.key:sub(2)
    local slider = _G['WordHunterWoW' .. suffix .. 'Slider']
    assert(rawget(_G, 'WordHunterWoW' .. suffix .. 'Slider'), entry.key .. ' has no slider in the window')
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

-- The headings and the small print under them. They are what the window says
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

-- A size changed elsewhere reaches the figure through refresh. SetValue leaves
-- the figure alone when the slider is already at the value it is handed, so a
-- window reopened after /whw reset showed the size it had been built with.
Addon.SetEditorScale(1.2)
window.refresh()
assert(_G.WordHunterWoWEditorScaleSliderText:GetText()
    == Addon.LABELS.editorScaleLabel .. ' (' .. Addon.FormatSizeValue('percent', 1.2) .. ')',
  'refresh left the editor size reading ' .. tostring(_G.WordHunterWoWEditorScaleSliderText:GetText()))

-- Each tab scrolls its own rows. A row that ends past the bottom of its tab's
-- scroll box cannot be scrolled to -- and it is exactly what adding a row to a
-- long tab without growing the box would do. Measured at the largest text size
-- too, where the rows are deepest.
local rowsSeen = 0
for _, scale in ipairs({ 1.0, 2.0 }) do
  Addon.SetTextScale(scale)
  window.refresh()
  for _, tab in ipairs(window.tabs) do
    -- rawget: an unset field on a stub frame manufactures another stub rather
    -- than answering nil, so only a height the addon actually asked for counts.
    local boxHeight = rawget(tab.content, 'h')
    assert(type(boxHeight) == 'number', tab.id .. ': the scroll box was never given a height')
    local lowest = 0
    for _, row in ipairs(tab.rows) do
      assert(type(row.y) == 'number' and type(row.h) == 'number', tab.id .. ': a row was never placed')
      lowest = math.max(lowest, -row.y + row.h)
      rowsSeen = rowsSeen + 1
    end
    assert(#tab.rows == 0 or lowest > 0, tab.id .. ': no row was placed in the scroll box')
    assert(lowest <= boxHeight,
      string.format('%s at %.1f: the last row reaches %.1f, past the %.1f-high scroll box',
        tab.id, scale, lowest, boxHeight))
  end
end
Addon.SetTextScale(1.0)

print(string.format('settings-panel: %d frames, %d rows over %d tabs at two sizes', #placed, rowsSeen / 2, #window.tabs))
