-- Run from the addon root:  lua tests/recall-settings.test.lua
--
-- The settings page's side of the recall check: the switch, the count under
-- it, and the export button. Pressed, not read: the harvest export test found
-- that a test which greps for a button's name passes for as long as the name
-- is somewhere in the file, which is not the same as the button working.

local node = dofile('tests/wowstub.lua')

UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_SetText = function(frame, text) frame.shownText = text end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function() end
UIDropDownMenu_Initialize = function(frame, initializer) initializer(frame, 1) end

dofile('Core.lua')
dofile('Compat.lua')
dofile('Recall.lua')
dofile('UICommon.lua')
dofile('Harvest.lua')
dofile('QuestPanel.lua')
dofile('Settings.lua')
local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS

local now = 1700000000
time = function() return now end

WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()

local panel = Addon.CreateSettingsPanel()
local check = rawget(_G, 'WordHunterWoWRecallCheck')
assert(check, 'the settings page has no recall switch')
-- The tick, modelled: unmodelled it answers with a frame, which is truthy,
-- and a switch that has to come up off would pass whatever the page did.
function check:SetChecked(value) self.checked = not not value end
function check:GetChecked() return self.checked and true or false end
panel.refresh()
assert(check:GetChecked() == false, 'the recall switch has to come up off')
assert(_G.WordHunterWoWRecallCheckText:GetText() == LABELS.recallLabel, 'and say what it does')

check:SetChecked(true)
check:GetScript('OnClick')(check)
assert(Addon.GetRecallCheck() == true, 'ticking it stores the setting')
-- The setter refreshes the page itself: /whw recall off has to move a switch
-- that is on screen.
Addon.SetRecallCheck(false)
assert(check:GetChecked() == false, 'the setter resyncs the switch on the open page')
WordHunterWoWDB.settings.recallCheck = true
panel.refresh()
assert(check:GetChecked() == true, 'and refresh resyncs it after a change made elsewhere')
Addon.SetRecallCheck(false)

-- The count under it, filled by refresh like the harvest note.
local note = rawget(panel, 'difficultNote')
assert(note, 'the page has no difficult-words line')
assert(note:GetText() == string.format(LABELS.difficultNote, 0), 'got: ' .. tostring(note:GetText()))

-- Nothing difficult: a dialog with nothing to confirm, Cancel alone.
local button = rawget(panel, 'difficultExport')
assert(button, 'the page has no export button')
local press = button:GetScript('OnClick')
Addon.showConfirm('t', 'b', LABELS.confirmAction, function() end)
press()
local confirm = Addon.confirmDialog
assert(confirm:IsShown() and confirm.body:GetText() == LABELS.difficultExportEmpty,
  'with nothing difficult the export says so: ' .. tostring(confirm.body:GetText()))
assert(not confirm.action:IsShown(), 'and offers nothing to confirm')
confirm:Hide()

-- One difficult word, and the list goes into the copy box the way the harvest
-- does, pipes doubled for display.
local words = Addon.GetWordsTable()
words.hund = { word = 'Hund', status = 'learning', translation = 'dog', note = 'a note', statusChangedAt = now - 3 * 86400 }
for i = 1, 5 do Addon.RecordRating('hund', 1, now + i) end
Addon.RecordExample('hund', 'Der Hund bellt.', 1, 'Q', now)
Addon.RecordExample('hund', 'Der Hund schläft.', 2, 'Q', now)
panel.refresh()
assert(note:GetText() == string.format(LABELS.difficultNote, 1), 'the count follows the rows: ' .. tostring(note:GetText()))
panel:SetScale(1.3)
press()
local copy = Addon.copyDialog
assert(copy and copy:IsShown(), 'a difficult word opens the copy box')
assert(copy.title:GetText() == LABELS.difficultExport, 'under its own title')
assert(copy.hint:GetText() == LABELS.difficultExportHint, 'with the hint that says where the list goes')
local expected = (Addon.BuildDifficultExport():gsub('|', '||'))
assert(copy.text:GetText() == expected, 'the box holds the export: ' .. tostring(copy.text:GetText()))
assert(expected:find('Der Hund bellt. || Der Hund schläft.', 1, true), 'sentences are joined by a pipe, shown doubled')
assert(math.abs(copy:GetScale() - 1.3) < 0.001, 'and the box is the size of the page it came from: ' .. tostring(copy:GetScale()))
panel:SetScale(1)

-- The switch and the export sit at fixed offsets, so the layout test can see
-- them, and above the harvest block they pushed down.
local harvest = rawget(_G, 'WordHunterWoWHarvestCheck')
local _, checkY = check:GetAnchor('TOPLEFT')
local _, buttonY = button:GetAnchor('TOPLEFT')
local _, harvestY = harvest:GetAnchor('TOPLEFT')
assert(checkY > buttonY and buttonY > harvestY, ('switch %d, export %d, harvest %d: not in that order'):format(checkY, buttonY, harvestY))

print('recall-settings: ok')
