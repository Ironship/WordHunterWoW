-- English-only database text remains readable, never German vocabulary.
dofile('tests/wowstub.lua')
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
dofile('Editor.lua')
dofile('QuestReader.lua')
local A = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {} }, wordsByLocale = {} }
A.initializeDatabase()
A.createPanel()
A.createEditor()
WordHunterWoW_QuestEN = { [488] = { title = 'A Crown', description = 'The tree waits.', objectives = 'Find the crown.' } }
C_QuestLog = nil
GetQuestLogQuestText = nil
local lookups, harvests = 0, 0
A.GetEffectiveWord = function() lookups = lookups + 1 end
A.HarvestUnknownWord = function() harvests = harvests + 1 end
local opened = A.OpenCatalogQuest(488)
assert(opened and A.panel:IsShown(), 'English-only quests must display their real database text')
assert(A.lastQuest.sourceLocale == 'enUS' and A.lastQuest.readOnly, 'the source language must be explicit')
assert(lookups == 0 and harvests == 0, 'English fallback must not use German word status or harvest English as German')
assert(A.panel.integratedLayout == false, 'English fallback must be one readable column, not duplicated as German')
assert(A.panel.meta:GetText():find('English', 1, true) or A.panel.meta:GetText():find('Englisch', 1, true), 'the visible reader must identify English fallback')
assert(A.lastQuest.voiceUnavailable == true, 'fallback must explicitly disable German voice matching')
for _, button in ipairs(A.panel.wordButtons) do
  if button:IsShown() then
    local click = button:GetScript('OnClick')
    if click then click(button) end
  end
end
assert(not A.editor:IsShown(), 'English fallback must not open the German vocabulary editor')
assert(A.lastQuest.text:find('Find the crown.', 1, true), 'objectives must not be lost in fallback')
assert(next(A.GetWordsTable()) == nil, 'reading fallback must leave vocabulary intact')
print('quest-language-fallback: read-only English + honest language + no German pollution: ok')
