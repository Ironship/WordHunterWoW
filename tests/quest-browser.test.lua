-- Run from the addon root: lua tests/quest-browser.test.lua
-- Rows open the existing learning reader, not a second plain-text reader.
dofile('tests/wowstub.lua')
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
dofile('QuestBrowser.lua')
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
WordHunterWoW_QuestEN = { [61] = { title = 'Kobold Camp Cleanup', description = 'A description.' } }
C_QuestLog = nil
local opened
A.OpenCatalogQuest = function(id) opened = id return true end
A.toggleQuestBrowser()
local f = A.questsFrame
assert(f and f:IsShown(), 'the catalog must open')
assert(f.tab == 'my' and f.resultCount == 0, 'the first view must contain only current and completed quests')
f.libraryTabs.all:GetScript('OnClick')(f.libraryTabs.all)
local row = f.rows[1]
assert(row and row:IsShown() and row.item.id == 61, 'database row is missing')
row:GetScript('OnClick')(row)
assert(opened == 61, 'clicking a quest must open the standard WordHunter reader with the numeric quest ID')
assert(not f:IsShown(), 'the list must not cover the standard reader after a successful click')
A.toggleQuestBrowser()
WordHunterWoW_QuestEN = {}
for id = 1, 255 do
  WordHunterWoW_QuestEN[id] = { title = string.format('Quest %03d with a full readable title', id) }
end
A.refreshQuestBrowser()
assert(f.resultCount == 255, 'the catalog must expose all 255 results, not silently truncate at 200')
assert(type(f.nextPage:GetScript('OnClick')) == 'function', 'all results must be reachable with page controls')
local visited = {}
repeat
  for _, visible in ipairs(f.rows) do
    if visible:IsShown() then visited[visible.item.id] = true end
  end
  if f.page >= f.pageCount then break end
  f.nextPage:GetScript('OnClick')(f.nextPage)
until false
local n = 0
for _ in pairs(visited) do n = n + 1 end
assert(n == 255 and visited[255], 'paging must reach every database quest exactly once')
assert(f.rows[1].name:GetWidth() > f.questContent:GetWidth() / 2,
  'titles must use the full list width, not half of an already narrow column')
A.GetCharacterQuestHistory = function()
  return { [1] = { completed = true }, [2] = { accepted = true } }
end
C_QuestLog = {
  GetNumQuestLogEntries = function() return 1 end,
  GetInfo = function() return { questID = 3, title = 'Aktive Aufgabe' } end,
  IsQuestFlaggedCompletedOnAccount = function() error('account-wide flags are not character history') end,
}
A.refreshQuestBrowser()
A.SetQuestCatalogFilter('completed')
assert(f.resultCount == 1 and f.rows[1].item.id == 1, 'Completed must use character-specific history')
A.SetQuestCatalogFilter('history')
assert(f.resultCount == 3, 'history includes accepted, completed and currently active quests only')
A.SetQuestCatalogFilter('log')
assert(f.resultCount == 1 and f.rows[1].item.id == 3, 'the active log filter must exclude unrelated database quests')
A.SetQuestCatalogFilter('database')
f.search:SetText('255')
f.search:GetScript('OnTextChanged')(f.search)
assert(f.resultCount == 1 and f.rows[1].item.id == 255 and f.page == 1, 'ID search must reach quests beyond the first page')
f.search:SetText('no matching title')
f.search:GetScript('OnTextChanged')(f.search)
assert(f.resultCount == 0 and f.pageCount == 1 and f.empty:IsShown(), 'empty searches need a safe, visible empty state')
f.search:SetText('')
f.search:GetScript('OnTextChanged')(f.search)
SelectQuestLogEntry = function() error('catalog listing must never change the game log selection') end
A.refreshQuestBrowser()
assert(rawget(f, 'questTextBody') == nil and rawget(f, 'wordRows') == nil,
  'the old plain-text / saved-word preview must be removed, not remain behind the catalog')
print('quest-browser reader route, paging, filters, search: ok')
