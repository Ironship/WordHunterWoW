-- Run from the addon root:  lua tests/harvest-export.test.lua
--
-- Getting the collected text out of the game. It used to be written to the
-- saved-variables file and the dialog explained where that file was and offered
-- a reload, because the file only reaches disk on reload or logout. That flow is
-- gone: the button now puts the blob straight into a box the player copies out
-- of, and no file is involved.
--
-- The version of this file that guarded the old flow could not fail. It asserted
-- that the old flow's labels and its path helper still existed, then read
-- Settings.lua as text and asserted the new flow's names appeared in it -- and
-- both were true at once, for as long as the dead half stayed in the tree. So
-- this one presses the button instead, and looks at what the player is shown.

local node = dofile('tests/wowstub.lua')

-- The dropdown API, recorded rather than drawn. The settings panel builds three
-- of them on the way to the export button.
UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_SetText = function(frame, text) frame.shownText = text end
UIDropDownMenu_CreateInfo = function() return {} end
UIDropDownMenu_AddButton = function() end
UIDropDownMenu_Initialize = function(frame, initializer) initializer(frame, 1) end

dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('Harvest.lua')
-- In .toc order: the settings panel is a set of controls over other files'
-- settings, and its quest log switch reads a getter QuestPanel.lua defines.
dofile('QuestPanel.lua')
dofile('Settings.lua')
local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS

WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
-- A real table: the harvest counter walks this one, and a manufactured node
-- hands it its own methods to count.
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()

-- Nothing writes a file any more, so nothing needs to say where one would land.
-- The helper that did is the piece that survived the last removal by itself and
-- kept a test alive around it; if it comes back, the flow has been half-replaced
-- a second time.
assert(rawget(Addon, 'HarvestExportPath') == nil,
  'the export writes no file, so nothing should be describing where one goes')

local panel = Addon.CreateSettingsPanel()
-- rawget: the panel is a stub frame, and reading a field it has not got back
-- manufactures a child frame, so a plain `panel.harvestExport` is truthy whether
-- the button was built or not.
local exportButton = rawget(panel, 'harvestExport')
assert(exportButton, 'the settings panel has to offer the export button')
local press = exportButton:GetScript('OnClick')
assert(press, 'and pressing it has to do something')

-- A dialog that has something to confirm shows both buttons. This is the state
-- the export's empty case has to undo, and the window is pooled, so it has to be
-- reached first for the next assertion to mean anything.
Addon.showConfirm(LABELS.resetDictionary, 'body', LABELS.confirmAction, function() end)
local confirm = Addon.confirmDialog
assert(confirm.action:IsShown(), 'a dialog with an action must offer its action button')

-- Nothing collected. There is nothing to confirm, so there must be exactly one
-- button. It used to pass LABELS.confirmCancel as the *action* text, which left
-- two buttons on screen both reading "Cancel".
press()
assert(confirm:IsShown(), 'with nothing collected the export has to say so')
assert(confirm.body:GetText() == LABELS.harvestExportEmpty,
  'and say it in the words meant for it, got: ' .. tostring(confirm.body:GetText()))
assert(not confirm.action:IsShown(),
  'nothing to confirm means no action button -- two buttons reading "Cancel" is what this replaced')
assert(confirm.cancel:GetText() == LABELS.confirmCancel, 'and Cancel is the way out')
confirm:Hide()

-- Now collect something. A passage and an unglossed word: the blob is built from
-- both, and its separator is the pipe that the copy box has to escape.
Addon.SetHarvestEnabled(true)
assert(Addon.HarvestText('objectives', 184, 'Bringt 8 Stuecke zaehes Wolfsfleisch.'),
  'the passage should have been collected')
assert(Addon.HarvestText('word', 184, 'Wolfsfleisch'), 'and the word with it')

press()
local copy = Addon.copyDialog
assert(copy and copy:IsShown(), 'with text collected the export has to open the copy box')
assert(not confirm:IsShown(), 'and must not also claim nothing was collected')
assert(copy.title:GetText() == LABELS.harvestExport, 'the box is titled for the export')

local blob = WordHunterWoWCorpusExport
assert(type(blob) == 'string' and blob:find('^WHC2|'), 'pressing it must build the blob, got ' .. tostring(blob))
-- Percent-encoded for the importer, so nothing a quest happens to contain can be
-- read as one of the separators. The spaces are just the cheapest proof it ran:
-- a passage of German that reaches the blob with its spaces intact did not go
-- through the encoder at all.
assert(blob:find('%%20') and not blob:find(' ', 1, true),
  'the passage should reach the blob percent-encoded, got ' .. blob)
-- A lone "|" is a UI escape in the game's font strings, and the blob is full of
-- them. Doubling is how every export box in the game shows a pipe.
assert(copy.text:GetText() == (blob:gsub('|', '||')),
  'the box has to show the blob with its pipes doubled, or the game eats the text')

-- The one thing the old dialog said that the new one did not: where the block is
-- meant to go. Nothing else in the addon names a destination, so the copy box
-- takes its own hint here instead of the generic "press Ctrl+C".
assert(copy.hint:GetText() == LABELS.harvestExportHint,
  'the export box needs its own hint, got: ' .. tostring(copy.hint:GetText()))
assert(LABELS.harvestExportHint:find('CurseForge', 1, true)
  and LABELS.harvestExportHint:find('Discord', 1, true),
  'and that hint is the only place the addon says where to send the block')

-- The window is pooled. A hint one caller set must not still be up for the next.
Addon.showCopyText(LABELS.copyWord, 'Hund')
assert(copy.hint:GetText() == LABELS.copyHint,
  'copying a word must get the plain hint back, got: ' .. tostring(copy.hint:GetText()))

-- Pressing it again. The first export moved the live table into the blob and
-- emptied it, so a second press finds nothing collected -- but the blob has not
-- reached disk yet, and telling the player nothing was collected would be a lie.
assert(Addon.HarvestCount() == 0, 'the export empties the live table')
press()
assert(copy:IsShown() and copy.text:GetText() == (blob:gsub('|', '||')),
  'a second export must offer the same blob again rather than claim there is nothing')

-- A dialog is the size of the window it came out of.
--
-- This is the owner's screenshot: the editor dragged to 150%, and the
-- confirmation it opened sitting beside it at 100% with smaller buttons and
-- smaller text. SCALED_WINDOWS names four frames and neither dialog is among
-- them, so nothing ever scaled either one.
--
-- Measured against four different openers, because the obvious fix -- giving
-- the dialogs the editor's own setting -- is wrong for three of them. They are
-- opened from the editor, from the quest panel, from the settings page, and
-- from a slash command with no window at all.
-- Two plain frames rather than the real editor and panel. What is under test is
-- the contract -- a dialog is the size of whoever opened it -- and standing it
-- up against the real windows would test their wiring as well, which is what
-- makes a failure here hard to read.
local editorFrame, questFrame = CreateFrame('Frame'), CreateFrame('Frame')
editorFrame:SetScale(1.5)
questFrame:SetScale(1)

Addon.showCopyText('t', 'v', nil, editorFrame)
assert(math.abs(Addon.copyDialog:GetScale() - 1.5) < 0.001,
  'a dialog opened from the editor at 150% came out at '
  .. Addon.copyDialog:GetScale() .. ' -- the mismatch in the screenshot')
-- Straight from 1.5 to no opener at all, deliberately. The slash command has no
-- window behind it and must come out at 1 -- but checked after a scaled opener
-- rather than after an unscaled one, or a dialog that simply keeps whatever it
-- had last would read as correct.
Addon.showCopyText('t', 'v', nil, nil)
assert(math.abs(Addon.copyDialog:GetScale() - 1) < 0.001,
  "a dialog opened from nothing kept the last opener's scale: "
  .. Addon.copyDialog:GetScale())
Addon.showCopyText('t', 'v', nil, editorFrame)
Addon.showCopyText('t', 'v', nil, questFrame)
assert(math.abs(Addon.copyDialog:GetScale() - 1) < 0.001,
  "a dialog opened from the quest panel took someone else's scale: "
  .. Addon.copyDialog:GetScale())
-- The pool is the trap: the scale of the last opener must not stick to the next.
editorFrame:SetScale(2)
Addon.showConfirm('t', 'b', 'go', function() end, editorFrame)
assert(math.abs(Addon.confirmDialog:GetScale() - 2) < 0.001,
  "the pooled dialog kept a previous scale instead of taking the new opener's")
Addon.showConfirm('t', 'b', 'go', function() end, questFrame)
assert(math.abs(Addon.confirmDialog:GetScale() - 1) < 0.001,
  "the pooled dialog kept the editor's scale when opened from the quest panel")
editorFrame:SetScale(1)
print('  a dialog is the size of the window that opened it')

print('harvest-export: ok')
