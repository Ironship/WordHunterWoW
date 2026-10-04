-- lua tests/quest-catalog.test.lua
-- A database catalog is not just the active log or quests attached to words.
dofile('tests/wowstub.lua')
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
dofile('QuestBrowser.lua')
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
WordHunterWoW_QuestEN = {
  [40] = { title = 'Active quest', description = 'The active quest.' },
  [61] = { title = 'Never accepted', description = 'A quest in the installed database.' },
  [777] = { title = 'Older completion', description = 'A quest completed before installing the addon.' },
}
C_QuestLog = {
  GetNumQuestLogEntries = function() return 1 end,
  GetInfo = function() return { questID = 40, title = 'Aktive Aufgabe' } end,
}
A.GetCharacterQuestHistory = function()
  return { [777] = { completed = true }, [900] = { accepted = true, title = 'Abandoned quest' } }
end
A.toggleQuestBrowser()
local titles = {}
for _, row in ipairs(A.questsFrame.rows) do
  if row:IsShown() then titles[row.item.id] = row.name:GetText() end
end
assert(titles[61] == 'Never accepted', 'the database quest absent from log and saved words must be listed')
assert(titles[777] == 'Older completion', 'an old completion in the database must be listed')
assert(titles[900] == 'Abandoned quest', 'character accepted history must survive absence from current log and DB')
local completed
for _, row in ipairs(A.questsFrame.rows) do
  if row:IsShown() and row.item.id == 777 then completed = row.item.completed end
end
assert(completed == true, 'character history, not saved words or account-wide flags, must determine completion')
print('quest-catalog database + character history: ok')
WordHunterWoWCorpus = { byLocale = { deDE = {
  ['classic:description:501'] = { id = 501, kind = 'description', text = 'Falscher Client', flavor = 'classic' },
  ['title:61'] = { id = 61, kind = 'title', text = 'Lokaler Titel', flavor = 'retail' },
} } }
A.refreshQuestBrowser()
local foundWrongClient = false
for _, row in ipairs(A.questsFrame.rows) do
  if row:IsShown() and row.item.id == 501 then foundWrongClient = true end
end
assert(not foundWrongClient, 'the library must not mix quests captured on a different game flavor')
print('quest-catalog corpus flavor isolation: ok')
