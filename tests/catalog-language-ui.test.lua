-- lua5.1 tests/catalog-language-ui.test.lua [before-ui-directory]
-- Real catalog/reader/editor callbacks, with one shared word key in DE and EN.
dofile('tests/wowstub.lua')
-- Blizzard creates child buttons shown; the generic base stub starts hidden.
local create = CreateFrame
CreateFrame = function(...)
  local frame = create(...)
  local mt = getmetatable(frame)
  setmetatable(frame, { __call = mt.__call, __index = function(self, key)
    if key == 'compact' then return nil end -- Addon's optional value, never a template child.
    return mt.__index(self, key)
  end })
  frame:Show()
  return frame
end
local before = arg[1]
for _, file in ipairs({ 'Core.lua', 'Compat.lua', 'Gamepad.lua', 'Recall.lua', 'UICommon.lua',
  'Harvest.lua', 'QuestHistory.lua', 'QuestPanel.lua', 'WordList.lua', 'Editor.lua', 'QuestBrowser.lua', 'QuestReader.lua' }) do
  local oldUI = before and (file == 'UICommon.lua' or file == 'QuestPanel.lua' or file == 'QuestBrowser.lua')
  dofile(oldUI and before .. '/' .. file or file)
end
local A = WordHunterWoW_Addon
local now = 1700000000
time = function() return now end
GetBuildInfo = function() return '1.60.1', '', '', 16001 end
A.Compat.Refresh()
assert(A.Compat.GameFlavor() == 'forever')
UnitGUID = function() return 'Player-catalog-language' end
UnitName = function() return 'Learner' end
C_QuestLog, GetQuestLogQuestText = nil, nil
SelectQuestLogEntry = function() error('offline catalog must not select a game quest') end
WordHunterWoWDB = { settings = { targetLocale = 'deDE', harvestCorpus = true, integratedLayout = true,
  recallCheck = true, frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
WordHunterWoW_QuestDataByFlavor = { forever = { sourceFlavor = 'classic',
  deDE = {
    [783] = { title = 'Die Bedrohung von innen', description = 'Der Wolf und Deutschwort warten.', objectives = 'Findet den Wolf.' },
    [7] = { title = 'Säuberung im Koboldlager', description = 'Die Kobolde warten.', objectives = 'Findet die Kobolde.' },
  },
  enUS = {
    [783] = { title = 'A Threat Within', description = 'The wolf and Englishword wait.', objectives = 'Find the wolf.' },
    [7] = { title = 'Kobold Camp Cleanup', description = 'The kobolds wait.', objectives = 'Find the kobolds.' },
    [777] = { title = 'English reference', description = 'Fallbackword waits.' },
  },
} }
WordHunterWoW_QuestEN = { [783] = { title = 'Retail replacement', description = 'Deathwing stole this Retail text.' } }
A.RegisterDictionaryProvider('deDE', 'fixture-de', { wolf = { word = 'Wolf', translation = 'DE dictionary', status = 'new' } })
A.RegisterDictionaryProvider('enUS', 'fixture-en', { wolf = { word = 'wolf', translation = 'EN dictionary', status = 'new' } })
A.RecordCharacterQuest(783, 'accepted', 'Die Bedrohung von innen', 'deDE')
A.RecordCharacterQuest(783, 'completed', 'Die Bedrohung von innen', 'deDE')
A.RecordCharacterQuest(7, 'accepted', 'Säuberung im Koboldlager', 'deDE')
A.createPanel()
A.panel.enScroll.GetVerticalScroll = function() return 0 end
A.createEditor()

local function click(frame)
  assert(frame and type(frame:GetScript('OnClick')) == 'function', 'expected a real UI click handler')
  frame:GetScript('OnClick')(frame, 'LeftButton')
end
local function row(id)
  for _, r in ipairs(A.questsFrame.rows) do if r:IsShown() and r.item.id == id then return r end end
  error('visible catalog row missing: ' .. id)
end
local function word(value)
  for _, b in ipairs(A.panel.wordButtons) do if b:IsShown() and b.word == value then return b end end
  error('visible reader word missing: ' .. value)
end
local function independent()
  assert(A.GetTargetLocale() == 'deDE' and WordHunterWoWDB.settings.targetLocale == 'deDE',
    'catalog language must not change the global learning language')
end
local function save(meaning)
  click(A.editor.statusButtons.learning)
  A.editor.translation:SetText(meaning)
  click(A.editor.save)
end

A.toggleQuestBrowser()
local f = A.questsFrame
local libraryLanguage = rawget(f, 'catalogLanguageButton')
assert(libraryLanguage and libraryLanguage:IsShown() and libraryLanguage:GetText() == 'German',
  'library needs a real German/English control, initially German')
assert(A.GetCatalogLocale() == 'deDE')
click(f.filterButtons.completed)
assert(f.resultCount == 1 and row(783).name:GetText() == 'Die Bedrohung von innen',
  'Completed must use this character history and the selected German title')
assert(not A.GetCharacterQuestHistory()[7].completed)
click(row(783))
local readerLanguage = rawget(A.panel, 'catalogLanguageButton')
assert(readerLanguage and readerLanguage:IsShown() and readerLanguage:GetText() == 'DE')
assert(A.lastQuest.wordLocale == 'deDE' and not A.lastQuest.readOnly and A.lastQuest.sourceFlavor == 'classic')
assert(A.lastQuest.text:find('Deutschwort', 1, true) and not A.lastQuest.text:find('Deathwing', 1, true))
assert(A.panel.enTitle:GetText() == 'A Threat Within', 'German companion column must also ignore the old Retail ID collision')
click(word('Wolf'))
assert(A.selected.locale == 'deDE' and A.editor.translation:GetText() == 'DE dictionary')
save('German saved meaning')
local de = A.GetWordsTable('deDE').wolf
assert(de.translation == 'German saved meaning' and A.GetWordsTable('enUS').wolf == nil)
de.statusChangedAt = now - 2 * 86400
click(word('Wolf'))
assert(A.selected.recallPending and A.editor.cover:IsShown())
click(A.editor.cover.buttons[3])
click(A.editor.cancel)
assert(A.GetRecallRow('wolf', false, 'deDE').ratingCount == 1)
assert(A.GetRecallRow('wolf', false, 'enUS') == nil)
assert(WordHunterWoWCorpus.byLocale.deDE['forever:word:Deutschwort'])
independent()

-- The compact reader control changes the real open quest, and keeps its geometry.
local width, height = A.panel:GetSize()
click(readerLanguage)
assert(A.GetCatalogLocale() == 'enUS' and readerLanguage:GetText() == 'EN')
assert(A.lastQuest.sourceLocale == 'enUS' and A.lastQuest.wordLocale == 'enUS'
  and not A.lastQuest.readOnly and A.lastQuest.voiceUnavailable)
assert(A.lastQuest.text:find('Englishword', 1, true) and not A.lastQuest.text:find('Deathwing', 1, true))
assert(A.panel.integratedLayout == false and not A.panel.enScroll:IsShown(), 'explicit English needs a single readable column')
assert(A.panel:GetWidth() == width and A.panel:GetHeight() == height, 'language switching must preserve reader size')
click(word('wolf'))
assert(A.selected.locale == 'enUS' and A.editor.translation:GetText() == 'EN dictionary',
  'English click must use English status/meaning despite the global German target')
save('English saved meaning')
local en = A.GetWordsTable('enUS').wolf
assert(en.translation == 'English saved meaning' and de.translation == 'German saved meaning')
assert(A.GetRecallRow('wolf', false, 'enUS').examples[1].text:find('Englishword', 1, true))
assert(A.GetRecallRow('wolf', false, 'deDE').examples[1].text:find('Deutschwort', 1, true))
en.statusChangedAt = now - 2 * 86400
click(word('wolf'))
assert(A.selected.recallPending and A.selected.locale == 'enUS', 'German recent rating cannot suppress the English recall check')
click(A.editor.cover.buttons[4])
click(A.editor.cancel)
assert(A.GetRecallRow('wolf', false, 'enUS').ratings[1].score == 4)
assert(A.GetRecallRow('wolf', false, 'deDE').ratingCount == 1)
assert(WordHunterWoWCorpus.byLocale.enUS['forever:word:Englishword'])
assert(not WordHunterWoWCorpus.byLocale.deDE['forever:word:Englishword'])
independent()

click(A.libraryReturnButton)
assert(f:IsShown() and not A.panel:IsShown() and A.GetCatalogLocale() == 'enUS')
assert(libraryLanguage:GetText() == 'English (US)' and row(783).name:GetText() == 'A Threat Within')
click(libraryLanguage)
assert(A.GetCatalogLocale() == 'deDE' and row(783).name:GetText() == 'Die Bedrohung von innen')
click(libraryLanguage)
click(row(783))
assert(A.lastQuest.wordLocale == 'enUS' and A.panel.title:GetText() == 'A Threat Within', 'English library row must open the actual English reader')
independent()

-- English obtained implicitly while German is requested remains read-only.
click(readerLanguage)
assert(A.OpenCatalogQuest(777))
assert(A.lastQuest.readOnly and A.lastQuest.sourceLocale == 'enUS' and A.lastQuest.wordLocale == nil)
local fallback = word('Fallbackword')
click(fallback)
assert(not A.editor:IsShown(), 'implicit English fallback must not open either vocabulary editor')
assert(not WordHunterWoWCorpus.byLocale.deDE['forever:word:Fallbackword']
  and not WordHunterWoWCorpus.byLocale.enUS['forever:word:Fallbackword'])

-- The catalog control stays out of ordinary native NPC reading.
GetQuestID = function() return 7 end
GetTitleText = function() return 'Säuberung im Koboldlager' end
GetQuestText = function() return 'Die Kobolde warten.' end
GetObjectiveText = function() return 'Findet die Kobolde.' end
QuestFrame:Show()
A.readCurrentQuest()
assert(not A.lastQuest.catalog and not readerLanguage:IsShown(), 'native reader must hide catalog-only language control')
assert(A.GetCharacterQuestHistory()[783].completed and not A.GetCharacterQuestHistory()[7].completed,
  'studying either language must preserve actual completion state')
independent()
print('catalog-language-ui: real DE/EN library and reader controls, flavor-safe text, isolated word save/recall/harvest, read-only fallback and native hiding: ok')
