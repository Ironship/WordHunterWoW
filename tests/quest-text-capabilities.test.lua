-- lua5.1 tests/quest-text-capabilities.test.lua [baseline-directory|-] [case|all]
dofile('tests/wowstub.lua')
local source = arg[1] and arg[1] ~= '-' and arg[1] or '.'
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'QuestHistory.lua', 'QuestReader.lua' }) do dofile(source .. '/' .. file) end
local A, mode = WordHunterWoW_Addon, arg[2] or 'all'
WordHunterWoWDB = { settings = { targetLocale = 'deDE' }, wordsByLocale = {} }
A.initializeDatabase()
UnitGUID = function() return 'Player-quest-text-test' end
local function run(name, fn) if mode == 'all' or mode == name then fn(); print('quest-text-capabilities ' .. name .. ': ok') end end
local function legacy(version, start, getter)
  GetBuildInfo = function() return version, '', '', version == '1.15.9' and 11509 or 120100 end
  WOW_PROJECT_ID = version == '1.15.9' and 2 or 1
  A.Compat.Refresh()
  C_QuestLog = nil
  local selection = start
  GetQuestLogSelection = function() return selection end
  SelectQuestLogEntry = function(index) selection = index end
  GetQuestLogQuestText = getter
  return function() return selection end
end

run('modern', function()
  GetBuildInfo = function() return '1.60.1', '', '', 16001 end
  A.Compat.Refresh(); assert(A.Compat.GameFlavor() == 'forever')
  local selected, asked = 902, nil
  C_QuestLog = {
    GetLogIndexForQuestID = function(id) return id == 901 and 2 or nil end,
    GetSelectedQuest = function() return selected end,
    GetTitleForQuestID = function() return 'Neue Quest' end,
  }
  GetQuestLogSelection = nil
  SelectQuestLogEntry = function() error('Mainline-family getter must not select a log entry') end
  GetQuestLogQuestText = function(index) asked = index; assert(index == 2); return 'Neue Beschreibung.', 'Neues Ziel.' end
  local desc, obj = A.Compat.QuestLogText(2)
  assert(asked == 2 and desc == 'Neue Beschreibung.' and obj == 'Neues Ziel.' and selected == 902)
  local q = assert(A.ResolveCatalogQuest(901, 'deDE'), 'unselected indexed Forever quest must be readable')
  assert(q.text == 'Neue Beschreibung.\n\nNeues Ziel.' and q.sourceLocale == 'deDE' and selected == 902)
  assert(A.GetObservedQuestTexts('deDE')[901].description == 'Neue Beschreibung.')
end)

run('legacy-zero', function()
  local selection = legacy('1.15.9', 0, function(index) assert(index == nil); return 'Beschreibung.', 'Ziel.' end)
  local desc = A.Compat.QuestLogText(2)
  assert(desc == 'Beschreibung.' and selection() == 0, 'a known deselected legacy state must be restored')
end)

run('legacy-retail', function()
  local selection = legacy('12.1.0', 3, function(index) assert(index == nil, 'legacy getter ignores indices even on a Retail-family flavor'); return 'Beschreibung.', 'Ziel.' end)
  local desc = A.Compat.QuestLogText(2)
  assert(desc == 'Beschreibung.' and selection() == 3)
end)

run('legacy-error', function()
  local selection = legacy('1.15.9', 3, function() error('original getter failure') end)
  local ok, message = pcall(A.Compat.QuestLogText, 2)
  assert(not ok and tostring(message):find('original getter failure', 1, true))
  assert(selection() == 3, 'a throwing legacy getter must still restore the prior selection')
  local selectEntry = SelectQuestLogEntry
  SelectQuestLogEntry = function(index) selectEntry(index); if index == 2 then error('selection failure') end end
  ok, message = pcall(A.Compat.QuestLogText, 2)
  assert(not ok and tostring(message):find('selection failure', 1, true))
  assert(selection() == 3, 'a selection setter that throws after moving must still be restored')
end)
