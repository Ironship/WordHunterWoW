-- Run from the addon root:  lua tests/settings-window.test.lua
--
-- The settings window as a whole, added with it in 1.20: that every stored
-- setting has exactly one control, that each control writes its setting and
-- the window catches up, that the preview follows what the controls change,
-- that each tab's Reset puts back what a fresh profile has and leaves alone
-- what it must, and that the window opens above the windows it governs.
--
-- settings-panel and settings-scale hold the controls' details and sizing;
-- issues holds the Options page's registration on clients with and without the
-- Settings API.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("Gamepad.lua")
dofile("Recall.lua")
dofile("UICommon.lua")
dofile("Editor.lua")
dofile("QuestPanel.lua")
dofile("WordList.lua")
dofile("Harvest.lua")
dofile("Settings.lua")
local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
Addon.createEditor()

-- The tick, modelled on every check box the window builds: unmodelled it
-- answers with a manufactured frame, which is truthy, and every box would read
-- ticked whatever the addon did.
local realCreateFrame = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = realCreateFrame(kind, name, parent, template)
  if kind == "CheckButton" then
    function f:SetChecked(value) self.checked = not not value end
    function f:GetChecked() return self.checked and true or false end
  end
  return f
end

-- Which frames the backdrop painter was handed, so a repaint can be seen.
local painted = {}
local realApply = Addon.ApplyBackground
Addon.ApplyBackground = function(frame, ...)
  painted[frame] = (painted[frame] or 0) + 1
  return realApply(frame, ...)
end

local window = Addon.CreateSettingsPanel()
CreateFrame = realCreateFrame
local preview = window.preview

-- ---------------------------------------------------------------------------
-- Every setting placed once.
local SETTINGS = Addon.SETTINGS
local byKey, tabIds = {}, {}
for _, tab in ipairs(window.tabs) do tabIds[tab.id] = true end
for _, spec in ipairs(SETTINGS) do
  assert(not byKey[spec.key], spec.key .. " is listed twice")
  byKey[spec.key] = spec
  assert(spec.tab or spec.where, spec.key .. " has neither a tab nor a place of its own")
  if spec.tab then assert(tabIds[spec.tab], spec.key .. " names a tab the window does not have: " .. spec.tab) end
end
local rowsFor = {}
for _, row in ipairs(window.rows) do
  if row.key then
    assert(byKey[row.key], "a row names " .. row.key .. ", which is not a setting")
    rowsFor[row.key] = rowsFor[row.key] or {}
    table.insert(rowsFor[row.key], row)
  end
end
for _, spec in ipairs(SETTINGS) do
  local found = rowsFor[spec.key] or {}
  if spec.tab then
    assert(#found == 1, spec.key .. " has " .. #found .. " controls in the window, not one")
    assert(found[1].tab == spec.tab, spec.key .. " is on the " .. found[1].tab .. " tab, not " .. spec.tab)
  else
    assert(#found == 0, spec.key .. " is set " .. spec.where .. ", and has a control here as well")
  end
end
for _, group in ipairs(Addon.SIZE_GROUPS) do
  for _, entry in ipairs(group.entries) do
    local row = rowsFor[entry.key] and rowsFor[entry.key][1]
    assert(row and row.kind == "slider" and row.tab == "sizes", entry.key .. " has no slider on the Sizes tab")
  end
end

-- And no stored key escapes the list. Every setter the addon has is run, and
-- whatever lands in the saved settings has to be a key the list knows -- or it
-- is a setting nobody can reach from this window.
Addon.SetBackgroundStyle("solid")
Addon.SetOpacity(0.5)
Addon.SetWordMarking("color")
for _, key in ipairs(Addon.TEXT_SCALE_KEYS) do Addon["Set" .. key:sub(1, 1):upper() .. key:sub(2)](1.1) end
Addon.SetIntegratedLayout(false)
Addon.SetQuestLogAutoOpen(true)
Addon.SetReadingMode(true)
Addon.SetTargetLocale("frFR")
Addon.SetRecallCheck(false)
Addon.SetReadyAfter(9)
Addon.SetDifficultMinRatings(9)
Addon.SetHarvestEnabled(true)
Addon.SetGamePadEnabled(false)
Addon.toggleWordList()
Addon.listFrame.hideIgnored:GetScript("OnClick")(Addon.listFrame.hideIgnored)
Addon.toggleWordList()
for key in pairs(WordHunterWoWDB.settings) do
  assert(byKey[key], "the saved settings hold " .. key .. ", which the settings list does not know")
end
print("  every setting has exactly one control, on one tab")

-- Back to a fresh profile for what follows.
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
Addon.initializeDatabase()
window.refresh()

-- ---------------------------------------------------------------------------
-- Each control writes its setting, and the window catches up: the preview is
-- redrawn on every change, which is the part of the window a player watches.
local previewDraws = 0
local realRefreshPreview = window.refreshPreview
window.refreshPreview = function(...)
  previewDraws = previewDraws + 1
  return realRefreshPreview(...)
end

local GET = {
  background = Addon.GetBackgroundStyle, opacity = Addon.GetOpacity, wordMarking = Addon.GetWordMarking,
  textScale = Addon.GetTextScale, enPanelTextScale = Addon.GetEnPanelTextScale,
  editorScale = Addon.GetEditorScale, listScale = Addon.GetListScale, statsScale = Addon.GetStatsScale,
  integratedLayout = Addon.GetIntegratedLayout, questLogAutoOpen = Addon.GetQuestLogAutoOpen,
  readingMode = Addon.GetReadingMode, targetLocale = Addon.GetTargetLocale,
  recallCheck = Addon.GetRecallCheck, readyAfter = Addon.GetReadyAfter,
  difficultMinRatings = Addon.GetDifficultMinRatings, harvestCorpus = Addon.GetHarvestEnabled,
  gamepad = Addon.GetGamePadEnabled,
}
local SLIDE_TO = {
  opacity = 0.6, textScale = 1.25, enPanelTextScale = 1.3, editorScale = 1.4, listScale = 1.45,
  statsScale = 1.55, readyAfter = 17, difficultMinRatings = 23,
}
local driven = 0
for _, row in ipairs(window.rows) do
  if row.key then
    assert(GET[row.key], "this test has no getter for " .. row.key)
    local control = row.control
    local before = previewDraws
    if row.kind == "check" then
      local was = GET[row.key]()
      control:SetChecked(not was)
      control:GetScript("OnClick")(control)
      assert(GET[row.key]() == not was, row.key .. ": the box did not store its tick")
      assert(control:GetChecked() == not was, row.key .. ": and the box did not keep it")
    elseif row.kind == "slider" then
      local want = SLIDE_TO[row.key]
      assert(want, "this test has no value to drag " .. row.key .. " to")
      control:GetScript("OnValueChanged")(control, want)
      assert(math.abs(GET[row.key]() - want) < 1e-9, row.key .. ": the slider stored " .. tostring(GET[row.key]()))
    elseif row.kind == "choice" then
      control:GetScript("OnClick")(control)
      local menu = Addon.settingsMenu
      local pick
      for index, entry in ipairs(rawget(menu, "entries")) do
        if entry.value ~= GET[row.key]() then pick = menu.buttons[index] end
      end
      assert(pick, row.key .. ": the menu offered nothing but the current value")
      pick:GetScript("OnClick")(pick)
      assert(GET[row.key]() == pick.value, row.key .. ": picking " .. tostring(pick.value) .. " did not store it")
      assert(_G[control:GetName() .. "Text"]:GetText() ~= nil, row.key .. ": the choice shows nothing")
    else
      error("a " .. row.kind .. " row carries a setting, and this test does not know how to drive one")
    end
    assert(previewDraws > before, row.key .. ": changing it did not redraw the preview")
    driven = driven + 1
  end
end
assert(driven == 17, "drove " .. driven .. " controls, expected 17")
print("  every control writes its setting and redraws the preview")

-- ---------------------------------------------------------------------------
-- Reset, tab by tab, back to what a fresh profile has.
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
Addon.initializeDatabase()
local FRESH = {}
for key, get in pairs(GET) do FRESH[key] = get() end
local freshStored = {}
for key, value in pairs(WordHunterWoWDB.settings) do freshStored[key] = value end

local function changeEverything()
  Addon.SetBackgroundStyle("midnight")
  Addon.SetOpacity(0.35)
  Addon.SetWordMarking("underline")
  for _, key in ipairs(Addon.TEXT_SCALE_KEYS) do Addon["Set" .. key:sub(1, 1):upper() .. key:sub(2)](1.7) end
  Addon.SetIntegratedLayout(false)
  Addon.SetQuestLogAutoOpen(true)
  Addon.SetReadingMode(true)
  Addon.SetTargetLocale("itIT")
  Addon.SetRecallCheck(false)
  Addon.SetReadyAfter(30)
  Addon.SetDifficultMinRatings(31)
  Addon.SetHarvestEnabled(true)
  Addon.SetGamePadEnabled(false)
end

local resetButton = window.resetButton
for _, tab in ipairs(window.tabs) do
  changeEverything()
  local before = {}
  for key, get in pairs(GET) do before[key] = get() end
  window.selectTab(tab.id)
  local resets = false
  for _, spec in ipairs(SETTINGS) do
    if spec.tab == tab.id and spec.reset then resets = true end
  end
  assert(resetButton:IsShown() == resets,
    tab.id .. (resets and ": has settings to reset and no Reset button" or ": has nothing to reset and shows Reset"))
  if resets then
    local repaints = painted[preview] or 0
    resetButton:GetScript("OnClick")(resetButton)
    for _, spec in ipairs(SETTINGS) do
      if spec.tab == tab.id and spec.reset then
        assert(GET[spec.key]() == FRESH[spec.key],
          ("%s: Reset left %s at %s, a fresh profile has %s"):format(tab.id, spec.key,
            tostring(GET[spec.key]()), tostring(FRESH[spec.key])))
        -- The stored form too. A key nothing seeds has to go back to nil, not
        -- to the value nil reads as: recallCheck and gamepad treat a stored
        -- true and "never chosen" as different things.
        assert(WordHunterWoWDB.settings[spec.key] == freshStored[spec.key],
          ("%s: Reset stored %s = %s, a fresh profile has %s"):format(tab.id, spec.key,
            tostring(WordHunterWoWDB.settings[spec.key]), tostring(freshStored[spec.key])))
      elseif spec.tab ~= tab.id and GET[spec.key] then
        assert(GET[spec.key]() == before[spec.key],
          ("%s: Reset also moved %s, which is on the %s tab"):format(tab.id, spec.key, tostring(spec.tab)))
      end
    end
    -- The two it must never touch.
    assert(Addon.GetTargetLocale() == "itIT", tab.id .. ": Reset switched the language being learned")
    assert(Addon.GetReadingMode() == true, tab.id .. ": Reset switched reading mode off")
    if tab.id == "appearance" then
      assert((painted[preview] or 0) > repaints, "resetting the opacity did not repaint the preview")
    end
  end
end
print("  each tab's Reset restores a fresh profile's values and nothing else")

-- ---------------------------------------------------------------------------
-- The preview, with the window open: every setter redraws an open window,
-- which is how a slash command reaches it. A closed one catches up on show.
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.OpenSettings("appearance")
assert(window:IsShown(), "the window did not open")
local words = window.previewWords
-- rawget: a word nothing knows has no status, and the stub would manufacture
-- one for the asking.
local function wordWith(status)
  for _, word in ipairs(words) do
    if word:IsShown() and rawget(word, "status") == status then return word end
  end
end
local learning, plain = wordWith("learning"), wordWith(nil)
assert(learning and plain, "the sample has no learning word, or no word nothing knows")
assert(wordWith("new") and wordWith("known") and wordWith("ignored"), "the sample is missing a status")

local function colour(fs) local r, g, b = fs:GetTextColor() return { r, g, b } end
local function same(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

-- The marking, chosen the way a player chooses it.
local markingChoice = _G.WordHunterWoWWordMarkingDropdown
local function chooseMarking(key)
  markingChoice:GetScript("OnClick")(markingChoice)
  for index, entry in ipairs(rawget(Addon.settingsMenu, "entries")) do
    if entry.value == key then
      local button = Addon.settingsMenu.buttons[index]
      button:GetScript("OnClick")(button)
      return
    end
  end
  error("no menu entry for " .. key)
end
chooseMarking("color")
assert(same(colour(learning.text), Addon.COLORS.learning), "with colour marking the learning word is not in its colour")
assert(not learning.underline:IsShown(), "and colour only means no underline")
chooseMarking("underline")
assert(same(colour(learning.text), Addon.COLORS.text), "with underline only the word keeps the text colour")
assert(learning.underline:IsShown(), "and gets its underline")
chooseMarking("both")
assert(same(colour(learning.text), Addon.COLORS.learning) and learning.underline:IsShown(), "both means both")
assert(same(colour(plain.text), Addon.COLORS.text) and not plain.underline:IsShown(),
  "a word nothing knows is drawn plain, as the panel draws it")

-- The theme and the opacity repaint it.
local before = painted[preview] or 0
Addon.SetBackgroundStyle("tooltip")
assert((painted[preview] or 0) > before, "a new theme did not repaint the preview")
before = painted[preview]
Addon.SetOpacity(0.4)
assert(painted[preview] > before, "a new opacity did not repaint the preview")

-- The text sizes, each on its own column.
Addon.SetTextScale(1.5)
assert(learning.text:GetFontSize() == Addon.RoleSize("body", 1.5), "the sample words do not follow the quest text size")
assert(window.previewTitle:GetFontSize() == Addon.RoleSize("heading", 1.5), "nor does the sample title")
Addon.SetEnPanelTextScale(1.8)
assert(window.previewEnglish:GetFontSize() == Addon.RoleSize("body", 1.8), "the English does not follow the English size")
assert(learning.text:GetFontSize() == Addon.RoleSize("body", 1.5), "and the English size moved the other column")

-- The English goes where the integrated layout puts it, and nowhere when it is off.
assert(window.previewEnglish:IsShown() and not window.previewEnglishOff:IsShown(), "the integrated layout shows the English")
window.integratedCheck:SetChecked(false)
window.integratedCheck:GetScript("OnClick")(window.integratedCheck)
assert(not window.previewEnglish:IsShown() and window.previewEnglishOff:IsShown(),
  "with the integrated layout off the English column is still in the preview")
Addon.SetIntegratedLayout(true)
assert(window.previewEnglish:IsShown(), "and it comes back")

-- Pointing at a word lights up the English word it matches.
local hund = words[5]
assert(rawget(hund, "status") == "learning" and rawget(hund, "en") == 5, "the fifth sample word is the learning one")
hund:GetScript("OnEnter")(hund)
assert(window.previewEnglish:GetText():find(Addon.ColorHex("enWordHighlight") .. "pieces", 1, true),
  "hovering a word did not light up its English: " .. tostring(window.previewEnglish:GetText()))
words[1]:GetScript("OnEnter")(words[1])
assert(window.previewEnglish:GetText():find(Addon.ColorHex("enWordHighlight") .. "Bring", 1, true),
  "and another word lights up another")

-- The sample is in the language being learned.
Addon.SetTargetLocale("frFR")
assert(window.previewTitle:GetText() == "Viande de loup coriace", "the sample did not follow the language")
assert(words[1].text:GetText() == "Apportez", "the sample words did not follow the language")
Addon.SetTargetLocale("deDE")
assert(words[1].text:GetText() == "Bringt", "and back")

-- The rating question's cue, and reading mode's dimmer.
assert(window.previewBadge:IsShown(), "with the recall check on the learning word carries its cue")
Addon.SetRecallCheck(false)
assert(not window.previewBadge:IsShown(), "and not with it off")
Addon.SetRecallCheck(true)
assert(not window.previewWash:IsShown(), "no dimmer with reading mode off")
Addon.SetReadingMode(true)
assert(window.previewWash:IsShown(), "reading mode dims the preview's pane")
Addon.SetReadingMode(false)
print("  the preview follows the theme, the marking, both sizes, the layout and the language")

-- ---------------------------------------------------------------------------
-- Opening, stacking, closing.
assert(window:GetFrameStrata() == "FULLSCREEN_DIALOG", "the window is at " .. window:GetFrameStrata())
local questLevel, editorLevel = Addon.panel:GetFrameLevel(), Addon.editor:GetFrameLevel()
assert(Addon.panel:GetFrameStrata() == "FULLSCREEN_DIALOG" and Addon.editor:GetFrameStrata() == "FULLSCREEN_DIALOG",
  "the panel and the editor moved strata; this comparison needs redoing")
assert(window:GetFrameLevel() > questLevel and window:GetFrameLevel() > editorLevel,
  ("the window (%d) opens behind the quest panel (%d) or the editor (%d)"):format(
    window:GetFrameLevel(), questLevel, editorLevel))
assert(Addon.settingsMenu:GetFrameLevel() > window:GetFrameLevel(), "the choice menu opens behind the window")
assert(tContains(UISpecialFrames, "WordHunterWoWSettingsWindow"), "Escape does not close the window")
-- The keyboard is never taken: a window with the keyboard can swallow keys in
-- combat. The stub manufactures a method on first touch, so an untouched name
-- is one the addon never called.
assert(rawget(window, "EnableKeyboard") == nil, "the window takes the keyboard")

window:Hide()
Addon.OpenSettings()
assert(window:IsShown(), "OpenSettings did not open the window")
Addon.OpenSettings()
assert(not window:IsShown(), "a second /whw settings closes it, as a toggle")
assert(Addon.OpenSettings("coll") == "collecting" and window:IsShown(), "a prefix opens its tab")
assert(Addon.OpenSettings("coll") == "collecting" and window:IsShown(), "and asking for a tab never closes the window")
assert(Addon.OpenSettings("nonsense") == nil, "a name that is no tab opens nothing")
Addon.CloseAll()
assert(not window:IsShown(), "CloseAll leaves the settings window open")
-- /whw reset brings the window back too: a window dragged off the screen
-- cannot be dragged back.
window:ClearAllPoints()
window:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 9000, 9000)
window:SetSize(100, 100)
local realPrint = print
print = function() end
Addon.ResetLayout()
print = realPrint
assert(WordHunterWoWDB.settings.frames and next(WordHunterWoWDB.settings.frames) == nil, "the reset kept a saved position")
local cx, cy = window:GetAnchor("CENTER")
assert(cx == 0 and cy == 0 and window:GetAnchor("TOPLEFT") == nil, "the reset left the window where it was dragged")
assert(window:GetWidth() == 860 and window:GetHeight() == 580, "and at the size it was left at")
print("  the window opens above the panel and the editor, toggles, and closes with everything else")

-- ---------------------------------------------------------------------------
-- The controller.
local propagated = {}
Addon.SafePropagate = function(_, v) propagated[#propagated + 1] = v end
local press = window:GetScript("OnGamePadButtonDown")
assert(press, "the window never asked for pad buttons")
Addon.panel:Show()
Addon.OpenSettings("appearance")
press(window, "PADRSHOULDER")
assert(window.activeTab.id == "sizes", "RB did not step to the next tab")
press(window, "PADLSHOULDER")
press(window, "PADLSHOULDER")
assert(window.activeTab.id == "about", "LB did not step back round the end")
assert(propagated[#propagated] == false, "a press the window took was let through to the game")

markingChoice:GetScript("OnClick")(markingChoice)
assert(Addon.settingsMenu:IsShown(), "the menu did not open")
press(window, "PAD2")
assert(not Addon.settingsMenu:IsShown() and window:IsShown(), "B closes an open choice before the window")

-- A dialog the window opened takes B before the window behind it.
Addon.showCopyText("t", "v", nil, window)
press(window, "PAD2")
assert(not Addon.copyDialog:IsShown() and window:IsShown(), "B closed the window behind the copy box")
press(window, "PAD2")
assert(not window:IsShown(), "B did not close the window")
assert(Addon.panel:IsShown(), "and closing the settings took the quest panel with it")

-- Switched off, nothing is taken.
Addon.OpenSettings("about")
Addon.SetGamePadEnabled(false)
press(window, "PAD2")
assert(window:IsShown(), "with the controller off, B still closed the window")
assert(propagated[#propagated] == true, "and the press was not handed back to the game")
press(window, "PADRSHOULDER")
assert(window.activeTab.id == "about", "with the controller off, RB still changed the tab")
Addon.SetGamePadEnabled(true)
print("  the pad closes a choice, a dialog and the window in that order, and steps the tabs")

print("settings-window: ok")
