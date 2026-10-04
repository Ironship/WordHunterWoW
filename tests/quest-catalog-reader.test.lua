-- lua tests/quest-catalog-reader.test.lua
-- A database-only quest must render in the REAL clickable-word panel.
dofile('tests/wowstub.lua')
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
dofile('Editor.lua')
dofile('QuestBrowser.lua')
local loadReader = loadfile('QuestReader.lua')
if loadReader then loadReader() end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', integratedLayout = true, frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
A.createPanel()
-- This harness does not model scroll offsets; the real client starts at 0.
A.panel.enScroll.GetVerticalScroll = function() return 0 end
A.createEditor()
WordHunterWoW_QuestData = { deDE = {
  [61] = { title = 'Eine Aufgabe', description = 'Der Hund wartet auf {name}.', objectives = 'Findet den Hund.' },
} }
WordHunterWoW_QuestEN = { [61] = { title = 'A quest', description = 'The dog waits for {name}.', objectives = 'Find the dog.' } }
C_QuestLog = nil
UnitName = function() return 'Learner' end
SelectQuestLogEntry = function() error('opening an offline quest must not select a game quest') end
local voiceRendered
A.OnQuestPanelRendered = function(quest, panel) voiceRendered = { quest = quest, panel = panel } end
assert(type(A.OpenCatalogQuest) == 'function', 'the standard reader route is missing')
assert(A.OpenCatalogQuest(61), 'opening a database-only quest failed')
assert(A.lastQuest.id == 61 and A.lastQuest.passage == 'offer', 'reader needs numeric ID and offer passage for voice packs')
assert(A.lastQuest.text:find('Findet den Hund.', 1, true), 'objectives must be clickable along with the description')
assert(A.lastQuest.text:find('Learner', 1, true), 'player-name placeholder must be resolved')
assert(A.panel:IsShown() and A.panel.wordCount > 0, 'the real word-learning panel must render')
assert(voiceRendered and voiceRendered.quest == A.lastQuest and voiceRendered.panel == A.panel,
  'the existing voice panel-render hook must run')
local word
for _, button in ipairs(A.panel.wordButtons) do
  if button:IsShown() and button.word == 'Hund' then word = button break end
end
assert(word, 'quest text must expose real clickable word buttons')
word:GetScript('OnClick')(word)
assert(A.editor:IsShown() and A.selected.questId == '61' and A.selected.word == 'Hund',
  'clicking a word must open the existing status editor with quest context')
assert(not A.GetCharacterQuestHistory or not (A.GetCharacterQuestHistory()[61] or {}).completed,
  'studying a quest must not mark it completed')
assert(A.libraryReturnButton and A.libraryReturnButton:IsShown(), 'the reader needs an obvious return to the quest library')
A.libraryReturnButton:GetScript('OnClick')(A.libraryReturnButton)
assert(A.questsFrame and A.questsFrame:IsShown() and not A.panel:IsShown() and not A.editor:IsShown(),
  'returning to the library must close the reader and its editor')
-- Library left open under the reader: Back must keep it shown, not toggle it away.
assert(A.OpenCatalogQuest(61), 'reopening the quest failed')
A.questsFrame:Show()
A.editor:Show()
assert(A.panel:IsShown() and A.questsFrame:IsShown(), 'setup needs reader and library both visible')
A.libraryReturnButton:GetScript('OnClick')(A.libraryReturnButton)
assert(A.questsFrame:IsShown(),
  'Back with the library already open must leave it shown, not toggle it hidden')
assert(not A.panel:IsShown() and not A.editor:IsShown(), 'Back must still close the reader and its editor')
print('quest-catalog real reader + editor + voice hook + return: ok')
