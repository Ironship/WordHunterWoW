-- Run from WordHunterWoW: lua tests/english-highlight-ui.test.lua
-- Keep WordHunterWoW-ENPanel beside it to exercise both real UI paths.
local node = dofile('tests/wowstub.lua')
local frames = {}
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  f.parent = parent
  f.glow, f.whwReadingBackground = false, false
  function f:CreateTexture()
    local texture = node()
    function texture:SetColorTexture(...) self.color = {...} end
    return texture
  end
  function f:GetHeight() return rawget(self, 'h') or 240 end
  function f:GetWidth() return rawget(self, 'w') or 430 end
  function f:GetVerticalScroll() return rawget(self, '_scroll') or 0 end
  function f:SetVerticalScroll(value) self._scroll = value end
  function f:CreateFontString()
    local fs = node()
    function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
    return fs
  end
  frames[#frames + 1] = f
  return f
end
WordHunterWoW_Addon = {}
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
local Addon = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.RegisterDictionaryProvider('deDE', 'test', { zuflucht = { translation = 'refuge' } })
WordHunterWoW_QuestEN = {
  [1] = { title = 'Refuge', description = 'Wait... "Yes!"\n\nFind  the refuge.\n\nFind  the refuge.',
    completion = 'You made it.' },
  [2] = { title = 'Other', description = 'The refuge is here.' },
}
Addon.createPanel()
local panel = Addon.panel
panel:Show()
local source = 'Wartet... "Ja!"\n\nSucht die Zuflucht.\n\nSucht die Zuflucht.'
Addon.lastQuest = { id = 1, text = source, passage = 'offer' }
Addon.refreshPanel()
local function buttons(word)
  local result = {}
  for _, f in ipairs(frames) do
    if f.parent == panel.content and f:IsShown() and rawget(f, 'word') == word then result[#result + 1] = f end
  end
  return result
end
local function highlighted()
  local red, yellow = {}, {}
  for _, f in ipairs(frames) do
    if f.parent == panel.enContent and f:IsShown() then
      local c = f.text.color
      if c[1] == Addon.COLORS.enWordHighlight[1] and c[2] == Addon.COLORS.enWordHighlight[2] then red[#red + 1] = f
      elseif c[1] == Addon.COLORS.enHighlight[1] and c[2] == Addon.COLORS.enHighlight[2] then yellow[#yellow + 1] = f end
    end
  end
  return red, yellow
end
local repeats = buttons('Zuflucht')
assert(#repeats == 2 and repeats[2].sentenceIndex == 4, 'layout lost the second occurrence')
repeats[2].scripts.OnEnter(repeats[2])
assert(repeats[2].wordOccurrence == 1, 'unexpected occurrence ' .. tostring(repeats[2].wordOccurrence))
assert(next(Addon.MatchEnglishTokenIndexes('Find  the refuge.', 'Zuflucht', 1)), 'dictionary lookup missing')
local red, yellow = highlighted()
assert(panel.enScroll:GetVerticalScroll() == 0, 'hover scrolled a sentence already in view')
assert(#red == 1 and red[1].sentenceIndex == 4 and #yellow == 2,
  'hover lit the wrong sentence or word: red=' .. #red .. ', yellow=' .. #yellow)
repeats[2].scripts.OnLeave(repeats[2])
red, yellow = highlighted()
assert(#red == 0 and #yellow == 0, 'hover did not clear')
Addon.openEditor = function() end
repeats[1].scripts.OnClick(repeats[1])
repeats[2].scripts.OnEnter(repeats[2])
repeats[2].scripts.OnLeave(repeats[2])
red, yellow = highlighted()
assert(#red == 0 and #yellow == 3 and yellow[1].sentenceIndex == 3, 'leave did not restore clicked sentence')
Addon.lastQuest = { id = 1, text = 'Ihr habt es geschafft.', passage = 'reward' }
Addon.refreshPanel()
red, yellow = highlighted()
assert(#red == 0 and #yellow == 0, 'same quest, new passage retained old highlights')
Addon.lastQuest = { id = 2, text = 'Wo ist die Zuflucht?', passage = 'reward' }
Addon.refreshPanel()
Addon.HighlightEnglishForWord('Zuflucht', 1, 1)
red, yellow = highlighted()
assert(#red == 0 and #yellow == 0, 'offer fallback highlighted as if it were the reward')
Addon.lastQuest = { id = 999, text = source, passage = 'offer' }
Addon.refreshPanel()
Addon.HighlightEnglishForWord('Zuflucht', 3, 1)
red, yellow = highlighted()
assert(#red == 0 and #yellow == 0, 'missing translation message got highlighted')

-- Separate ENPanel: repeated sentence must use its span, preserve spaces,
-- and reject a hover for a different quest or passage.
WordHunterWoWDB.settings.integratedLayout = false
Addon.ApplyIntegratedLayout()
Addon.lastQuest = { id = 1, text = source, passage = 'offer' }
GetQuestID = function() return 1 end
QuestFrame:Show()
WordHunterWoWENPanelDB = {}
assert(loadfile('../WordHunterWoW-ENPanel/ENPanel.lua'))('WordHunterWoW-ENPanel')
local events = frames[#frames]
events.scripts.OnEvent(nil, 'ADDON_LOADED', 'WordHunterWoW-ENPanel')
events.scripts.OnEvent(nil, 'QUEST_DETAIL')
local enPanel = Addon.enPanel
Addon.OnHighlightEnglishForWord('Zuflucht', Addon.lastQuest, 4, 1)
local rendered = enPanel.text:GetText()
local expected = 'Wait... "Yes!"\n\nFind  the refuge.\n\n' .. Addon.ColorHex('enHighlight')
  .. 'Find|r  ' .. Addon.ColorHex('enHighlight') .. 'the|r ' .. Addon.ColorHex('enWordHighlight') .. 'refuge.|r'
assert(rendered == expected, 'wrong repeated sentence or lost whitespace: ' .. rendered)
Addon.OnHighlightEnglishForWord(nil, Addon.lastQuest)
assert(enPanel.text:GetText() == WordHunterWoW_QuestEN[1].description, 'separate hover did not clear')
Addon.OnHighlightEnglishForWord('Zuflucht', { id = 2, text = source, passage = 'offer' }, 4, 1)
assert(enPanel.text:GetText() == WordHunterWoW_QuestEN[1].description, 'stale quest highlighted')
Addon.OnHighlightEnglishForWord('Zuflucht', { id = 1, text = source, passage = 'reward' }, 4, 1)
assert(enPanel.text:GetText() == WordHunterWoW_QuestEN[1].description, 'stale passage highlighted')

-- Actual panel rendering, not just palette arithmetic: all themes and clients
-- must use neutral German letters and the same background behind the EN word.
WordHunterWoWDB.settings.integratedLayout = true
Addon.lastQuest = { id = 1, text = source, passage = 'offer' }
Addon.ApplyIntegratedLayout()
WordHunterWoWDB.settings.wordMarking = 'underline'
for _, family in ipairs({'retail', 'classic', 'sod'}) do
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = family == 'retail' and 1 or 2, 1
  Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
  C_Seasons = { GetActiveSeason = function() return family == 'sod' and 2 or 0 end }
  Addon.Compat.Refresh()
  for _, theme in ipairs(Addon.BACKGROUND_ORDER) do
    Addon.SetBackgroundStyle(theme)
    Addon.refreshPanel()
    local clicked = buttons('Zuflucht')[2]
    assert(clicked.text.color[1] == Addon.COLORS.text[1], 'status repainted the German letters')
    clicked.scripts.OnEnter(clicked)
    red, yellow = highlighted()
    assert(#red == 1 and #yellow == 2, family .. '/' .. theme .. ': highlight missing')
    for i = 1, 4 do
      assert(red[1].glow.color[i] == yellow[1].glow.color[i], 'red word has a competing red background')
      assert(red[1].glow.color[i] == Addon.COLORS.enHighlightBackground[i], 'highlight ignored shared palette')
    end
    clicked.scripts.OnLeave(clicked)
  end
end

-- Underline, colour, or both. A word that is marked has to be visibly marked in
-- every mode: an underline one pixel high on 24-point letters was there without
-- being legible, which is the complaint this setting answers.
local status = Addon.COLORS.new
for _, mode in ipairs(Addon.WORD_MARKING_ORDER) do
  Addon.SetWordMarking(mode)
  assert(Addon.GetWordMarking() == mode, 'marking setting was not stored')
  for _, size in ipairs({0.8, 1.0, 2.0}) do
    Addon.SetTextScale(size)
    Addon.refreshPanel()
    local marked = buttons('Zuflucht')[1]
    local plain = buttons('die')[1]
    local coloured = marked.text.color[1] == status[1] and marked.text.color[2] == status[2]
    assert(coloured == (mode ~= 'underline'), mode .. ': wrong letter colour')
    assert(plain.text.color[1] == Addon.COLORS.text[1], mode .. ': unknown word was painted')
    assert(marked.underline.shown == (mode ~= 'color'), mode .. ': wrong underline visibility')
    assert(not plain.underline.shown, mode .. ': unknown word was underlined')
    if mode ~= 'color' then
      assert(marked.underline.color[4] == 1, mode .. ': underline is see-through')
      assert(marked.underline.h == Addon.UnderlineThickness(size),
        mode .. ': underline ignored the text size at ' .. size)
      assert(marked.underline.h >= 2, mode .. ': underline thinner than two pixels')
    end
  end
end
assert(Addon.UnderlineThickness(2.0) > Addon.UnderlineThickness(1.0), 'thickness does not follow the text size')
Addon.SetTextScale(1.0)
Addon.SetWordMarking('both')
print('english-highlight-ui: ok')
