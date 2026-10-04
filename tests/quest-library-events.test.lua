-- Open libraries must refresh when character quest state changes.
local frames = {}
dofile('tests/wowstub.lua')
local create = CreateFrame
CreateFrame = function(...) local f = create(...) frames[#frames + 1] = f return f end
for line in io.lines('WordHunterWoW_Mainline.toc') do
  local file = line:match('^(%S+%.lua)%s*$')
  if file then assert(loadfile(file))('WordHunterWoW') end
end
local A = WordHunterWoW_Addon
local eventFrame
for _, frame in ipairs(frames) do if frame:GetScript('OnEvent') then eventFrame = frame end end
local handle = eventFrame:GetScript('OnEvent')
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
UnitGUID = function() return 'Player-quest-updates' end
A.createPanel()
A.createEditor()
WordHunterWoW_QuestEN = { [42] = { title = 'A quest', description = 'The real text.' } }
A.toggleQuestBrowser()
A.SetQuestCatalogFilter('completed')
assert(A.questsFrame.resultCount == 0, 'this character has not completed any quest yet')
handle(eventFrame, 'QUEST_TURNED_IN', 42)
assert(A.questsFrame.resultCount == 1 and A.questsFrame.rows[1].item.id == 42,
  'turning in a quest must update the open Completed filter without closing/reopening the library')
A.SetQuestCatalogFilter('history')
handle(eventFrame, 'QUEST_ACCEPTED', 99)
assert(A.questsFrame.resultCount == 2, 'a new accepted quest must also appear in the open history filter')
assert(A.OpenCatalogQuest(42, 'enUS'))
A.editor:Show()
handle(eventFrame, 'QUEST_FINISHED')
assert(A.panel:IsShown() and A.editor:IsShown(), 'closing an NPC must leave an independent catalog reader open')
A.lastQuest.catalog = nil
handle(eventFrame, 'QUEST_FINISHED')
assert(not A.panel:IsShown() and not A.editor:IsShown(), 'closing an NPC must still close its native reader')
print('quest-library-events: visible filters update after acceptance and completion: ok')
