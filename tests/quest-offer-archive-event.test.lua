-- lua5.1 tests/quest-offer-archive-event.test.lua [forever|retail|classic]
-- Party-fast acceptance can clear the native offer before a zero-delay UI read.
dofile('tests/wowstub.lua')
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'UICommon.lua', 'Harvest.lua', 'QuestHistory.lua',
  'QuestPanel.lua', 'Editor.lua', 'QuestBrowser.lua', 'QuestReader.lua' }) do dofile(file) end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', harvestCorpus = false, frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
UnitGUID = function() return 'Player-party-fast' end
UnitName = function() return 'Learner' end
local flavor = arg[1] or 'forever'
assert(flavor == 'forever' or flavor == 'retail' or flavor == 'classic')
local version, interface = '1.60.0', 16001
if flavor == 'retail' then version, interface = '12.1.0', 120100 end
if flavor == 'classic' then version, interface = '1.15.9', 11509; WOW_PROJECT_ID = 2 end
GetBuildInfo = function() return version, '', '', interface end
A.Compat.Refresh()
assert(A.Compat.GameFlavor() == flavor)
C_QuestLog = { GetNumQuestLogEntries = function() return 0 end }
SelectQuestLogEntry = function() error('offer capture must never change log selection') end
GetQuestLogQuestText = function() error('offer capture must never use a legacy log getter') end
local id, offer = 783, true
GetQuestID = function() return offer and id or 0 end
GetTitleText = function() return offer and 'Die Bedrohung von innen' or '' end
GetQuestText = function() return offer and 'Der Hund wartet auf Learner.' or '' end
GetObjectiveText = function() return offer and 'Findet den Hund.' or '' end
local due, reads = {}, 0
C_Timer.After = function(_, fn) due[#due + 1] = fn end
local nativeReader = A.readCurrentQuest
A.readCurrentQuest = function(...) reads = reads + 1 return nativeReader(...) end
local eventFrame, create = nil, CreateFrame
CreateFrame = function(...)
  local frame = create(...)
  if not eventFrame then eventFrame = frame end
  return frame
end
dofile('Init.lua')
CreateFrame = create
local onEvent = eventFrame:GetScript('OnEvent')
onEvent(eventFrame, 'QUEST_DETAIL')
assert(#due == 1 and reads == 0, 'UI still refreshes later rather than opening during the event')
local saved = A.GetObservedQuestTexts('deDE')[783]
assert(saved and saved.description == 'Der Hund wartet auf <name>.' and saved.objectives == 'Findet den Hund.',
  'native offer must already be archived before a deferred UI callback runs')
offer = false
onEvent(eventFrame, 'QUEST_ACCEPTED', 783)
onEvent(eventFrame, 'QUEST_TURNED_IN', 783)
for _, callback in ipairs(due) do callback() end
assert(reads == 1 and A.GetCharacterQuestHistory()[783].completed)
assert(A.GetObservedQuestTexts('deDE')[783].description == saved.description,
  'fast acceptance/turn-in and empty deferred APIs cannot erase the native snapshot')
A.lastQuest = nil
WordHunterWoW_QuestEN = { [783] = { title = 'Retail replacement', description = 'Deathwing reference.' } }
A.createPanel()
A.panel.enScroll.GetVerticalScroll = function() return 0 end
A.createEditor()
assert(A.OpenCatalogQuest(783) and not A.lastQuest.readOnly and A.lastQuest.sourceLocale == 'deDE',
  'completed Forever quest must reopen its actual German offer through the normal reader')
assert(not A.lastQuest.text:find('Deathwing', 1, true))
local word
for _, button in ipairs(A.panel.wordButtons) do
  if button:IsShown() and button.word == 'Hund' then word = button break end
end
assert(word and word:GetScript('OnClick'), 'native archived words remain clickable without a dictionary data copy')
word:GetScript('OnClick')(word)
assert(A.editor:IsShown() and A.selected.word == 'Hund' and A.selected.questId == '783')
assert(WordHunterWoWDB.settings.harvestCorpus == false and WordHunterWoWCorpus == nil)

-- Acceptance is a second chance only if the current native NPC ID matches.
offer, id = true, 5261
onEvent(eventFrame, 'QUEST_ACCEPTED', 783)
assert(A.GetObservedQuestTexts('deDE')[5261] == nil, 'unrelated NPC offer cannot be captured by another accepted ID')
onEvent(eventFrame, 'QUEST_ACCEPTED', 8, 5261)
assert(A.GetObservedQuestTexts('deDE')[5261], 'legacy index/quest-ID accept can capture the matching native offer')
id = 7
onEvent(eventFrame, 'QUEST_PROGRESS')
onEvent(eventFrame, 'QUEST_COMPLETE')
assert(A.GetObservedQuestTexts('deDE')[7] == nil, 'progress/hand-in events cannot masquerade as an offer')

-- Missing/throwing APIs and unknown language quietly leave state events usable.
GetQuestID = nil
assert(A.CaptureNativeQuestOffer() == false)
GetQuestID = function() error('native API temporarily unavailable') end
assert(A.CaptureNativeQuestOffer() == false)
GetQuestID = function() return 7 end
GetQuestText = function() error('no offer available') end
GetObjectiveText = nil
assert(A.CaptureNativeQuestOffer() == false)
local textLocale = A.TextLocale
A.TextLocale = function() error('CVar temporarily unavailable') end
assert(A.CaptureNativeQuestOffer() == false)
A.TextLocale = textLocale
GetQuestText = function() return 'Actual native English.' end
GetLocale = function() return 'enUS' end
assert(A.CaptureNativeQuestOffer(7))
assert(A.GetObservedQuestTexts('enUS')[7] and A.GetObservedQuestTexts('deDE')[7] == nil,
  'captured native English must never be labeled German merely because the learning target is German')
assert(WordHunterWoWDB.settings.harvestCorpus == false and WordHunterWoWCorpus == nil)
print('quest-offer-archive-event: ' .. flavor .. ', synchronous party-fast offer, correct accept ID, clickable completion, safe API/language guards: ok')
