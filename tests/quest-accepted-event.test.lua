-- Modern QUEST_ACCEPTED has only questId; legacy clients may send index,id.
local frames = {}
dofile('tests/wowstub.lua')
local create = CreateFrame
CreateFrame = function(...)
  local frame = create(...)
  frames[#frames + 1] = frame
  return frame
end
for line in io.lines('WordHunterWoW_Mainline.toc') do
  local file = line:match('^(%S+%.lua)%s*$')
  if file then assert(loadfile(file))('WordHunterWoW') end
end
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
UnitGUID = function() return 'Player-test-modern' end
local eventFrame
for _, frame in ipairs(frames) do
  if frame:GetScript('OnEvent') then eventFrame = frame end
end
assert(eventFrame, 'the manifest must register the real event dispatcher')
local handle = eventFrame:GetScript('OnEvent')
A.Compat.QuestIDForLogIndex = function(index) return index == 7 and 999 or nil end
handle(eventFrame, 'QUEST_ACCEPTED', 7)
assert((A.GetCharacterQuestHistory()[7] or {}).accepted == true, 'modern one-argument QUEST_ACCEPTED must record that exact quest ID, not reinterpret it as a log index')
assert(A.GetCharacterQuestHistory()[999] == nil, 'modern event must not record the quest occupying log row 7')
handle(eventFrame, 'QUEST_ACCEPTED', 4, 42)
assert((A.GetCharacterQuestHistory()[42] or {}).accepted, 'two-argument legacy event must still use the explicit quest ID')
print('quest-accepted-event: modern quest ID + legacy index/ID: ok')
