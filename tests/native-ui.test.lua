-- Native chrome must preserve the existing Reader/token/list behavior.
local node = dofile('tests/wowstub.lua')
UIParent = node()
local create = CreateFrame
local templates = {}
C_Texture = { GetAtlasInfo = function(name) return { width=8, height=8 } end }
ButtonFrameTemplate_HidePortrait = function(frame) frame.portraitHidden = true end
CreateFrame = function(kind, name, parent, template)
  local frame = create(kind, name, parent, template)
  if template and (template:find('DefaultPanelFlatTemplate',1,true) or template:find('ButtonFrameTemplate',1,true)) then
    templates[name] = template
    function frame:SetTitle(title) self.nativeTitle = title end
    frame.CloseButton = create('Button', nil, frame)
    frame.Inset = create('Frame', nil, frame)
  elseif template == 'SearchBoxTemplate' then
    frame:SetScript('OnTextChanged', function() end)
    frame.nativeChanged = frame:GetScript('OnTextChanged')
    function frame:HookScript(event, handler) self.nativeHook = handler end
  elseif template == 'UIPanelScrollFrameTemplate' then
    local bar = create('Slider', nil, frame)
    frame.ScrollBar = bar
    local thumb = node()
    function bar:GetThumbTexture() return thumb end
    bar.ScrollUpButton, bar.ScrollDownButton = node(), node()
  elseif template == 'InsetFrameTemplate' then frame.Bg = node() end
local drawTexture = frame.CreateTexture
function frame:CreateTexture(...)
  local texture = drawTexture(self, ...)
  function texture:SetAtlas(atlas) self.paintedAtlas = atlas end
  function texture:SetColorTexture(...) self.paintedColor = {...}; self.paintedAtlas=nil end
  return texture
end
  return frame
end
dofile('Core.lua'); dofile('Compat.lua'); dofile('UICommon.lua'); dofile('QuestPanel.lua')
dofile('WordList.lua'); dofile('QuestBrowser.lua'); dofile('Editor.lua'); dofile('Gamepad.lua'); dofile('Recall.lua'); dofile('Harvest.lua'); dofile('Settings.lua')
local A = WordHunterWoW_Addon
WordHunterWoWDB = {settings={targetLocale='deDE',background='native',frames={}},words={},wordsByLocale={}}
A.initializeDatabase()
A.createPanel()
assert(A.panel.whwNativeStyle == 'reader' and templates.WordHunterWoWFrame:find('ButtonFrameTemplate',1,true))
assert(A.panel.nativeTitle == 'WordHunterWoW')
assert(A.panel.headingRule, 'Reader must have a native heading divider')
assert(A.ReaderInk(A.panel)[1] == .25)
A.lastQuest={id=184,title='Eine lange deutsche Aufgabe',text='Der Hund wartet. Der Hund rennt.',english='The dog waits. The dog runs.'}
A.panel:Show(); A.refreshPanel()
local _, titleY=A.panel.title:GetAnchor('TOPLEFT')
assert(titleY <= -40, 'quest headings must clear the native title bar')
assert(A.panel.chromeHeight > 0 and A.panel.content, 'native chrome preserves Reader layout')
local button={text=node(),underline=node()}
A.StyleWordButton(button,'known','underline',2,A.ReaderInk(A.panel))
assert(button.text:GetTextColor() == .25, 'parchment keeps word text in ink')
assert(button.underline:IsShown(), 'learning status remains visible without colored words')
A.toggleQuestBrowser()
assert(A.questsFrame.whwNativeStyle == 'library' and A.questsFrame.portraitHidden)
assert(A.questsFrame.search and A.questsFrame.contentInset)
-- The words view's inset hangs off the words view, not off the library frame.
-- It used to hang off the frame and be shown and hidden by hand from the view's
-- own OnShow and OnHide, and on the quests tab it was left up with its bottom
-- border drawn straight through the pagination label: the view's scroll ends 52
-- pixels above the frame's bottom and the page label sits at 47 to 59, so the
-- two bands cross. A child of the view goes away when the view does, and there
-- is nothing left to keep in step.
assert(A.questsFrame.wordsView and A.questsFrame.wordsView.contentInset
  and A.questsFrame.wordsView.contentInset:GetParent() == A.questsFrame.wordsView,
  'the words view inset must be a child of the words view, or it outlives it')
assert(A.questsFrame.search:GetScript('OnTextChanged') == A.questsFrame.search.nativeChanged, 'native search clear/placeholder handler must be retained')
assert(not A.questsFrame.catalogTitle:IsShown(), 'native header must not have a second overlapping title')
A.toggleWordList()
assert(A.listFrame.whwNativeStyle == 'library' and A.listFrame.contentInset)
assert(A.panel.scroll.ScrollBar:GetWidth()==8, 'native scrollbar keeps the existing slider and uses a slim width')
A.createEditor()
assert(A.editor.whwNativeStyle == 'library' and A.editor.nativeTitle == 'Word Hunter - Word', 'word editor must use native chrome')
local settings = A.CreateSettingsPanel()
settings.refreshPreview()
assert(settings.whwNativeStyle == 'library' and settings.preview.whwNativeStyle == 'reader')
assert(settings.preview.whwReadingBackground.paintedAtlas == A.panel.whwReadingBackground.paintedAtlas,
  'preview and Reader must use the same native parchment')
local word=settings.previewWords[1]
A.SetWordMarking('underline'); settings.refreshPreview()
assert(word.text:GetTextColor() == A.ReaderInk(A.panel)[1], 'preview uses Reader ink')
assert(word.underline:IsShown(), 'preview shows the same underline mode')
A.SetWordMarking('color'); settings.refreshPreview()
assert(not word.underline:IsShown(), 'color-only mode must still work')
for _, style in ipairs({'tooltip','dialog','solid','midnight'}) do
  A.SetBackgroundStyle(style)
  settings.refreshPreview()
  local body=A.panel.whwReadingBackground.paintedColor
  local mock=settings.preview.whwReadingBackground.paintedColor
  assert(body and mock and body[1]==mock[1] and body[2]==mock[2] and body[3]==mock[3],
    'legacy background must match its preview: '..style)
end
WordHunterWoWDB.settings.background='midnight'
A.ApplyBackground(A.panel)
assert(A.ReaderInk(A.panel)==A.COLORS.text, 'dark preference restores readable light text')
C_Texture=nil
local fallback=A.CreateNativeWindow('FallbackNativeTest','reader','Fallback')
assert(not rawget(fallback,'whwNativeStyle'), 'missing native assets must retain fallback')
assert(A.CreateSearchBox(fallback), 'legacy search remains available')
print('native-ui: Reader, ink/status, title clearance, library, words, scrollbar, dark preference and fallback: ok')