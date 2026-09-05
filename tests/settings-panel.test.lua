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
assert(marking and marking.menu, 'the word marking dropdown was never initialised')

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
