-- The settings window (/whw settings), and the short page in Options > AddOns
-- that opens it.
--
-- Window layout adapted from DoesItDie by Joe Greive (MIT): a movable window of
-- the addon's own with a live preview on the left, tabs on the right, controls
-- built by hand from plain CheckButton, Slider and Button frames, one shared
-- menu for the choices, and a Reset button per tab.
--
-- Why a window of its own rather than a page in Blizzard's options canvas:
--
--   * the canvas is protected on Retail, so /whw settings could not open it in
--     combat, and Settings.OpenToCategory had already been handed a string
--     once and opened nothing;
--   * Blizzard's dropdown menus are the best-known taint carrier on Retail, and
--     the slider and tick box templates are not guaranteed to behave the same
--     on Forever. Nothing here uses any of the three;
--   * one long scrolling page had grown to nineteen settings, and a preview of
--     what they do is worth more than a paragraph about each.
--
-- What did not change: every stored key, every default, every getter and setter
-- and every slash command. The controls call the same setters the slash
-- commands call, so a setting behaves exactly as it did from the old page.
--
-- Sizing. The window is never SetScale'd. At 200% an 860 x 580 window is 1160
-- units tall, which does not fit on the screen at the default UI scale, and the
-- slider that sets the size would move under the cursor while it was dragged.
-- So the window does what the quest panel does: letters come from
-- Addon.FONT_ROLES at the "Quest panel text" size, the buttons from
-- Addon.RoleButtonHeight, and every vertical measure is multiplied by the same
-- number, so a letter that grows pushes the row below it down rather than
-- landing on it. Horizontal offsets stay where they are and long lines wrap.

local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
local addonName = (...) or "WordHunterWoW"

-- The window's own strings. English only, like every other label here: the
-- quest text is in the language being learned, the buttons are not.
LABELS.tabAppearance = "Appearance"
LABELS.tabSizes = "Sizes"
LABELS.tabPanel = "Quest panel"
LABELS.tabLearning = "Learning"
LABELS.tabCollecting = "Collecting"
LABELS.tabController = "Controller"
LABELS.tabAbout = "About"
LABELS.resetTab = "Reset this tab"
LABELS.previewTitle = "Preview"
LABELS.previewEnglishOff = "The English opens in its own window while the integrated quest window is off."
LABELS.backgroundNote = "Choose a frame style. Text stays on an opaque reading surface in every theme."
LABELS.languageNote = "Required — words are stored separately per language. English US/GB both export as 'en'."
LABELS.resetLayoutButton = "Reset window positions"
LABELS.resetLayoutNote = "Puts every window back where it started, this one included. The same as /whw reset."
LABELS.harvestClear = "Clear collected text"
LABELS.harvestClearBody = "This throws away every passage and word collected so far that has not been exported. It cannot be undone."
LABELS.harvestClearAction = "Clear"
LABELS.gamepadWindowNote = "In this window: LB/RB switch tabs · B closes it."
LABELS.optionsPageText = "Settings have their own window with a live preview. You can also type /whw settings."
LABELS.optionsPageButton = "Open WordHunterWoW settings"
LABELS.aboutVersion = "WordHunterWoW %s  ·  game: %s  ·  client %s (%s)"
LABELS.aboutWords = "Learning %s: %d of your words in this language, %d across all languages."
LABELS.aboutCommandsHeading = "Slash commands"
LABELS.aboutCommands = "/whw — open or close the quest panel\n"
  .. "/whw words  ·  /whw stats — the word list and the statistics\n"
  .. "/whw settings [tab] — this window\n"
  .. "/whw lang <locale>  ·  /whw bg <style>  ·  /whw opacity <0-100>\n"
  .. "/whw read — reading mode\n"
  .. "/whw recall on|off  ·  /whw difficult [export]\n"
  .. "/whw harvest [on|off|export|clear]\n"
  .. "/whw reset — put every window back\n"
  .. "/whw diag — diagnostics in chat"
LABELS.aboutDiagnostics = "Print diagnostics to chat"
LABELS.recallBadge = "1–5"

local WHITE = "Interface\\Buttons\\WHITE8X8"
local WINDOW_W, WINDOW_H = 860, 580
local PREVIEW_W = 300
local MARGIN = 10
local SCROLLBAR = 28
-- The width a tab's rows are laid out in: the window less the preview, the
-- margins and the scroll bar. A constant because the window is not resizable
-- and no size setting may widen it -- the letters grow downwards, not across.
local CONTENT_W = WINDOW_W - PREVIEW_W - 3 * MARGIN - SCROLLBAR - 6
local ROW_W = CONTENT_W - 16
-- Measures at 100%, multiplied by the text size wherever they are used.
local ROW_GAP = 10
local CHECK = 24
local BAR = 16
local CHOICE_H = 22
local CHOICE_W = 260
local ACTION_W = 200
local RESET_W = 150
local FOOT = 16
local DISABLED_ALPHA = 0.35
local READING_DIM = 0.55
-- Above the quest panel (20), the word list and statistics (22), the editor
-- (30) and the quest log's button (40), all in this strata, and above the
-- reading dimmer, which is a strata below. At DIALOG, as in DoesItDie, it would
-- open behind the panel. The copy and confirm dialogs are at TOOLTIP, so the
-- ones this window opens still come up over it.
local WINDOW_LEVEL = 50
local MENU_LEVEL = 100

-- The size the window's contents follow: "Quest panel text". The window has no
-- size of its own to set, and a sixth size slider for the settings would be a
-- new setting invented to answer a layout question.
local function pageScale()
  local scale = Addon.GetTextScale and Addon.GetTextScale()
  if type(scale) ~= "number" or scale <= 0 then return 1 end
  return scale
end

local function lineHeight(role, scale)
  return Addon.RoleSize(role, scale) * 1.3
end

-- The room an action button's row takes. Unrounded, unlike RoleButtonHeight,
-- so that every offset on a tab is the same multiple of the text size; the gap
-- under the row absorbs the half pixel the button itself is rounded by.
local function buttonRowHeight(scale)
  return Addon.RoleSize("body", scale) * 13 / 6
end

local function setColor(texture, r, g, b, a)
  if texture.SetColorTexture then
    texture:SetColorTexture(r, g, b, a)
  else
    -- Classic Era's name for the same call.
    texture:SetTexture(r, g, b, a)
  end
end

local function db()
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  return WordHunterWoWDB.settings
end

local function refreshQuestPanel()
  if Addon.refreshPanel and Addon.panel and Addon.panel:IsShown() then Addon.refreshPanel() end
end

-- ---------------------------------------------------------------------------
-- Every stored setting, the tab it lives on, and what that tab's Reset does
-- with it. The window's rows name their key, and a test holds the two lists
-- together: a key with no row, or on two tabs, is the fault that list exists
-- to catch.
--
-- reset:
--   "default"  the setter is called with the default, so its side effects run
--              -- a repaint, a rescale, a relayout. Used for the keys a fresh
--              profile is seeded with.
--   "clear"    the key is written back to nil. For the keys nothing seeds,
--              where nil is a state of its own: recallCheck and gamepad read
--              nil as on and only an explicit false as off, and a Reset that
--              wrote true would stop being the "never chosen" a fresh profile
--              has. `after` runs whatever the setter would have done besides.
--   nil        never reset. The language selects which word list is live, so a
--              Reset must not switch it; reading mode is a session toggle.
--
-- `where` marks a key that is set somewhere other than a row of this window.
-- ---------------------------------------------------------------------------
Addon.SETTINGS = {
  { key = "background", tab = "appearance", reset = "default",
    default = function() return Addon.DefaultBackgroundStyle() end, set = "SetBackgroundStyle" },
  { key = "opacity", tab = "appearance", reset = "default", default = 1.0, set = "SetOpacity" },
  { key = "wordMarking", tab = "appearance", reset = "clear", after = refreshQuestPanel },
  { key = "textScale", tab = "sizes", reset = "default", default = 1.0, set = "SetTextScale" },
  { key = "enPanelTextScale", tab = "sizes", reset = "default", default = 1.0, set = "SetEnPanelTextScale" },
  { key = "editorScale", tab = "sizes", reset = "default", default = 1.0, set = "SetEditorScale" },
  { key = "listScale", tab = "sizes", reset = "default", default = 1.0, set = "SetListScale" },
  { key = "statsScale", tab = "sizes", reset = "default", default = 1.0, set = "SetStatsScale" },
  { key = "integratedLayout", tab = "panel", reset = "default", default = true, set = "SetIntegratedLayout" },
  { key = "questLogAutoOpen", tab = "panel", reset = "clear" },
  { key = "readingMode", tab = "panel" },
  { key = "targetLocale", tab = "learning" },
  { key = "recallCheck", tab = "learning", reset = "clear" },
  { key = "readyAfter", tab = "learning", reset = "clear" },
  { key = "difficultMinRatings", tab = "learning", reset = "clear" },
  { key = "harvestCorpus", tab = "collecting", reset = "clear" },
  { key = "gamepad", tab = "controller", reset = "clear" },
  { key = "hideIgnored", where = "the word list window, beside the list it filters" },
  { key = "frames", where = "dragging and resizing; Reset window positions on the Sizes tab" },
}

local TABS = {
  { id = "appearance", label = "tabAppearance" },
  { id = "sizes", label = "tabSizes" },
  { id = "panel", label = "tabPanel" },
  { id = "learning", label = "tabLearning" },
  { id = "collecting", label = "tabCollecting" },
  { id = "controller", label = "tabController" },
  { id = "about", label = "tabAbout" },
}
Addon.SETTINGS_TABS = TABS

local function tabResets(id)
  for _, spec in ipairs(Addon.SETTINGS) do
    if spec.tab == id and spec.reset then return true end
  end
  return false
end

-- A tab by its id or its label, or by a prefix of either that fits only one,
-- the way /whw lang takes "fr" for frFR.
function Addon.FindSettingsTab(name)
  name = strlower(strtrim(tostring(name or "")))
  if name == "" then return nil end
  for _, tab in ipairs(TABS) do
    if tab.id == name or strlower(LABELS[tab.label]) == name then return tab.id end
  end
  local found
  for _, tab in ipairs(TABS) do
    local label = strlower(LABELS[tab.label])
    if tab.id:sub(1, #name) == name or label:sub(1, #name) == name then
      if found and found ~= tab.id then return nil end
      found = tab.id
    end
  end
  return found
end

function Addon.SettingsTabNames()
  local names = {}
  for _, tab in ipairs(TABS) do names[#names + 1] = tab.id end
  return names
end

-- Puts one tab's settings back to what a fresh profile has, through the same
-- setters the controls use.
function Addon.ResetSettings(tabId)
  local settings = db()
  for _, spec in ipairs(Addon.SETTINGS) do
    if spec.tab == tabId and spec.reset == "default" then
      local value = spec.default
      if type(value) == "function" then value = value() end
      Addon[spec.set](value)
    elseif spec.tab == tabId and spec.reset == "clear" then
      settings[spec.key] = nil
      if spec.after then spec.after() end
    end
  end
  if Addon.settingsPanel and Addon.settingsPanel.refresh then Addon.settingsPanel.refresh() end
end

-- ---------------------------------------------------------------------------
-- The preview's sample quest, one per language the addon learns. Each word
-- carries its status by position -- never looked up -- so the preview neither
-- reads the player's word list nor depends on a dictionary being installed. A
-- word with no status is one nothing knows, which the panel draws plain. The
-- third field is the English word it matches, for the hover.
-- ---------------------------------------------------------------------------
local ENGLISH = {
  title = "Tough Wolf Meat",
  words = { "Bring", "Marshal", "Dughan", "eight", "pieces", "of", "tough", "wolf", "meat." },
}
local SAMPLES = {
  de = { title = "Zähes Wolfsfleisch", words = {
    { "Bringt", "known", 1 }, { "Marschall", nil, 2 }, { "Dughan", "ignored", 3 }, { "acht", "new", 4 },
    { "Stücke", "learning", 5 }, { "zähes", nil, 7 }, { "Wolfsfleisch.", nil, 9 } } },
  fr = { title = "Viande de loup coriace", words = {
    { "Apportez", "known", 1 }, { "au" }, { "maréchal", nil, 2 }, { "Dughan", "ignored", 3 }, { "huit", "new", 4 },
    { "morceaux", "learning", 5 }, { "de", nil, 6 }, { "viande", nil, 9 }, { "de" }, { "loup", nil, 8 },
    { "coriace.", nil, 7 } } },
  es = { title = "Carne de lobo dura", words = {
    { "Llevad", "known", 1 }, { "al" }, { "alguacil", nil, 2 }, { "Dughan", "ignored", 3 }, { "ocho", "new", 4 },
    { "trozos", "learning", 5 }, { "de", nil, 6 }, { "carne", nil, 9 }, { "de" }, { "lobo", nil, 8 },
    { "dura.", nil, 7 } } },
  it = { title = "Carne di lupo coriacea", words = {
    { "Portate", "known", 1 }, { "al" }, { "maresciallo", nil, 2 }, { "Dughan", "ignored", 3 }, { "otto", "new", 4 },
    { "pezzi", "learning", 5 }, { "di", nil, 6 }, { "carne", nil, 9 }, { "di" }, { "lupo", nil, 8 },
    { "coriacea.", nil, 7 } } },
  pt = { title = "Carne de lobo dura", words = {
    { "Levem", "known", 1 }, { "ao" }, { "marechal", nil, 2 }, { "Dughan", "ignored", 3 }, { "oito", "new", 4 },
    { "pedaços", "learning", 5 }, { "de", nil, 6 }, { "carne", nil, 9 }, { "de" }, { "lobo", nil, 8 },
    { "dura.", nil, 7 } } },
  en = { title = ENGLISH.title, words = {
    { "Bring", "known", 1 }, { "Marshal", nil, 2 }, { "Dughan", "ignored", 3 }, { "eight", "new", 4 },
    { "pieces", "learning", 5 }, { "of", nil, 6 }, { "tough", nil, 7 }, { "wolf", nil, 8 }, { "meat.", nil, 9 } } },
}
local MAX_SAMPLE_WORDS = 11
local PREVIEW_PAD = 16
-- The mock panel sits inside the pane with a margin, so reading mode's dimmer
-- behind it has somewhere to show.
local MOCK_INSET = 10
local MOCK_W = PREVIEW_W - 2 * MOCK_INSET

local function previewSample()
  local lang = Addon.WH_LANGUAGE_MAP[Addon.GetTargetLocale()]
  return SAMPLES[lang] or SAMPLES.de, lang
end

-- The English line, with the sentence and the word a hover would light up in
-- the panel's own two colours. The sample is one sentence, so the sentence is
-- the whole line.
local function englishLine(lit)
  local parts = {}
  for index, word in ipairs(ENGLISH.words) do
    if index == lit then
      parts[#parts + 1] = Addon.ColorHex("enWordHighlight") .. word .. Addon.ColorHex("enHighlight")
    else
      parts[#parts + 1] = word
    end
  end
  return Addon.ColorHex("enHighlight") .. table.concat(parts, " ") .. "|r"
end

-- ---------------------------------------------------------------------------
-- The shared menu the choice rows open (DoesItDie's openMenu). Above the
-- window, and closed by a click anywhere else where the client has the event
-- for it, or by a second click on the button that opened it everywhere.
-- ---------------------------------------------------------------------------
local menu

local function closeMenu()
  if menu then menu:Hide() end
end

local function openMenu(owner, entries, current, pick)
  if not menu then
    menu = CreateFrame("Frame", "WordHunterWoWSettingsMenu", UIParent, "BackdropTemplate")
    Addon.settingsMenu = menu
    menu:Hide()
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    menu:SetFrameLevel(MENU_LEVEL)
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    menu:SetBackdropColor(0.07, 0.08, 0.1, 0.98)
    menu:SetBackdropBorderColor(0.35, 0.37, 0.42, 1)
    menu.buttons = {}
    -- Registered only while the menu is open: the event fires on every click
    -- anywhere, and a closed menu has nothing to say about any of them.
    menu:SetScript("OnShow", function(self) pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnHide", function(self) pcall(self.UnregisterEvent, self, "GLOBAL_MOUSE_DOWN") end)
    menu:SetScript("OnEvent", function(self)
      if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then self:Hide() end
    end)
  end
  if menu:IsShown() and menu.owner == owner then
    menu:Hide()
    return
  end
  local scale = pageScale()
  local height = lineHeight("body", scale) + 6 * scale
  menu.owner = owner
  menu.entries = entries
  for index, entry in ipairs(entries) do
    local button = menu.buttons[index]
    if not button then
      button = CreateFrame("Button", nil, menu)
      local highlight = button:CreateTexture(nil, "HIGHLIGHT")
      highlight:SetAllPoints()
      setColor(highlight, 1, 1, 1, 0.1)
      button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      button.text:SetPoint("LEFT", 8, 0)
      button.text:SetJustifyH("LEFT")
      menu.buttons[index] = button
    end
    Addon.ApplyFontRole(button.text, "body", scale)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -4 - (index - 1) * height)
    button:SetPoint("RIGHT", menu, "RIGHT", -1, 0)
    button:SetHeight(height)
    button.value = entry.value
    button.current = entry.value == current
    -- The current entry in gold, the way the old dropdown ticked it.
    button.text:SetText(button.current and ("|cffffd100" .. entry.label .. "|r") or entry.label)
    button:SetScript("OnClick", function()
      menu:Hide()
      pick(entry.value)
    end)
    button:Show()
  end
  for index = #entries + 1, #menu.buttons do menu.buttons[index]:Hide() end
  menu:SetSize(owner:GetWidth(), #entries * height + 8)
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
  -- Clicking the window raises it, so a fixed level is not enough to stay on
  -- top of it: the menu is put above whatever level the button has reached.
  menu:SetFrameLevel(math.max(MENU_LEVEL, owner:GetFrameLevel() + 20))
  menu:Show()
  if menu.Raise then menu:Raise() end
end

local function backgroundEntries()
  local list = {}
  for _, key in ipairs(Addon.BACKGROUND_ORDER) do
    list[#list + 1] = { value = key, label = Addon.BACKGROUNDS[key].name }
  end
  return list
end

local function markingEntries()
  local list = {}
  for _, key in ipairs(Addon.WORD_MARKING_ORDER) do
    list[#list + 1] = { value = key, label = Addon.WORD_MARKINGS[key].name }
  end
  return list
end

local function languageEntries()
  local list = {}
  for _, locale in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
    list[#list + 1] = { value = locale, label = Addon.SUPPORTED_LOCALES[locale] .. " (" .. locale .. ")" }
  end
  return list
end

local function addonVersion()
  local get = (type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  if type(get) ~= "function" then return "?" end
  local ok, value = pcall(get, addonName, "Version")
  if ok and type(value) == "string" and value ~= "" then return value end
  return "?"
end

-- Blizzard's own options, closed when the Open button on its page is pressed so
-- the window is not opened behind them. Skipped in combat, and pcall'd; if it
-- cannot be closed the window still opens, in a strata above it.
local function closeBlizzardOptions()
  if InCombatLockdown and InCombatLockdown() then return end
  if type(HideUIPanel) ~= "function" then return end
  for _, frame in ipairs({ SettingsPanel or false, InterfaceOptionsFrame or false }) do
    if frame and frame.IsShown then
      pcall(function()
        if frame:IsShown() then HideUIPanel(frame) end
      end)
    end
  end
end

-- ---------------------------------------------------------------------------
-- The window.
-- ---------------------------------------------------------------------------
function Addon.CreateSettingsPanel()
  if Addon.settingsPanel then return Addon.settingsPanel end

  local window = CreateFrame("Frame", "WordHunterWoWSettingsWindow", UIParent, "BackdropTemplate")
  Addon.settingsPanel = window
  window:Hide()
  window:SetSize(WINDOW_W, WINDOW_H)
  window:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  window:SetFrameStrata("FULLSCREEN_DIALOG")
  window:SetFrameLevel(WINDOW_LEVEL)
  window:SetToplevel(true)
  window:SetClampedToScreen(true)
  window:EnableMouse(true)
  window:SetMovable(true)
  window:RegisterForDrag("LeftButton")
  window:SetScript("OnDragStart", function(self) self:StartMoving() end)
  window:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Addon.SaveFramePosition(self, Addon.LayoutKey("settings"))
  end)
  -- Opaque, like the editor: a window you work in should not show the game
  -- through it. It follows the theme, so it looks like the rest of the addon.
  Addon.ApplyBackground(window, 1)
  -- Escape closes it. The window never takes the keyboard: with no keyboard
  -- of its own it cannot swallow a key during a fight, when the call that
  -- would let the key through is not allowed.
  if not tContains(UISpecialFrames, "WordHunterWoWSettingsWindow") then
    tinsert(UISpecialFrames, "WordHunterWoWSettingsWindow")
  end
  -- The pad: B closes it, the shoulders switch tabs (Gamepad.lua). Built at
  -- load, out of combat, so letting presses through can be set here.
  if Addon.AttachGamePad and Addon.AttachGamePad(window) and Addon.SafePropagate then
    Addon.SafePropagate(window, true)
  end

  local rows, tabs, tabsById = {}, {}, {}
  -- Strings outside the tabs that follow the size too: the title, the tab
  -- names, the preview's caption.
  local chrome = {}
  window.rows, window.tabs, window.tabsById, window.chrome = rows, tabs, tabsById, chrome
  window.sizeSliders = {}

  local title = window:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetText(LABELS.settingsTitle)
  window.title = title
  chrome[#chrome + 1] = { fs = title, role = "heading" }

  local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", window, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function() window:Hide() end)
  window.closeButton = close

  local divider = window:CreateTexture(nil, "ARTWORK")
  setColor(divider, 0.35, 0.37, 0.42, 1)
  divider:SetHeight(1)

  local pane = CreateFrame("Frame", nil, window)
  window.previewPane = pane
  local area = CreateFrame("Frame", nil, window)
  window.area = area

  local reset = Addon.createActionButton(area, LABELS.resetTab)
  reset:SetScript("OnClick", function()
    if window.activeTab then Addon.ResetSettings(window.activeTab.id) end
  end)
  window.resetButton = reset

  -- --- rows ------------------------------------------------------------------
  -- A row is a container frame on a tab's scroll child, the strings in it and
  -- the role each is drawn at, and two functions: Layout, which sizes and
  -- places its own pieces at a scale and answers how tall it came out, and
  -- Refresh, which reads its setting back.
  local function newRow(tab, kind, opts)
    opts = opts or {}
    local row = { kind = kind, tab = tab.id, key = opts.key, strings = {}, sized = {}, enabledIf = opts.enabledIf }
    row.frame = CreateFrame("Frame", nil, tab.content)
    tab.rows[#tab.rows + 1] = row
    rows[#rows + 1] = row
    return row
  end

  local function addString(row, fs, role)
    row.strings[#row.strings + 1] = { fs = fs, role = role }
    return fs
  end

  local function check(tab, name, key, label, get, set)
    local row = newRow(tab, "check", { key = key })
    local box = CreateFrame("CheckButton", name, row.frame)
    box:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    box:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    box:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    box:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    -- Named the way UICheckButtonTemplate named its label, so anything that
    -- looked the label up by name still finds it.
    local text = addString(row, box:CreateFontString(name .. "Text", "ARTWORK", "GameFontHighlight"), "body")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(label)
    box:SetScript("OnClick", function(self)
      set(self:GetChecked() and true or false)
      window.refresh()
    end)
    row.control = box
    box.settingsRow = row
    row.sized[#row.sized + 1] = { frame = box, w = CHECK, h = CHECK }
    function row.Layout(scale)
      local size = CHECK * scale
      box:SetSize(size, size)
      box:ClearAllPoints()
      box:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
      local labelTop = (size - lineHeight("body", scale)) / 2
      text:ClearAllPoints()
      text:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, -labelTop)
      text:SetWidth(ROW_W - size - 8)
      -- The label clicks the box too.
      if box.SetHitRectInsets then box:SetHitRectInsets(0, -(ROW_W - size), 0, 0) end
      return math.max(size, labelTop + (text:GetStringHeight() or 0))
    end
    function row.Refresh() box:SetChecked(get() and true or false) end
    return box, row
  end

  -- `opts`: step, normalize (the stored form of a dragged value), caption (the
  -- line above the bar for a value), low and high (the ends), get, set, after
  -- (anything besides the setter), enabledIf. The range is set by the caller.
  local function slider(tab, name, key, opts)
    local row = newRow(tab, "slider", { key = key, enabledIf = opts.enabledIf })
    local s = CreateFrame("Slider", name, row.frame)
    if s.SetOrientation then s:SetOrientation("HORIZONTAL") end
    s:SetValueStep(opts.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    if s.EnableMouseWheel then s:EnableMouseWheel(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    setColor(track, 0.3, 0.31, 0.34, 1)
    track:SetPoint("LEFT", s, "LEFT", 0, 0)
    track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    -- The template's child names, for the same reason as the check box's.
    local caption = addString(row, s:CreateFontString(name .. "Text", "ARTWORK", "GameFontHighlight"), "body")
    local low = addString(row, s:CreateFontString(name .. "Low", "ARTWORK", "GameFontHighlightSmall"), "meta")
    local high = addString(row, s:CreateFontString(name .. "High", "ARTWORK", "GameFontHighlightSmall"), "meta")
    low:SetText(opts.low)
    high:SetText(opts.high)
    -- Kept on the slider so refresh can redraw the figure too: SetValue fires
    -- OnValueChanged only when the value moves.
    s.captionFor = opts.caption
    -- Held until the first refresh. A new slider sits at 0, and the client
    -- fires OnValueChanged when the range the caller sets next clamps it --
    -- which, let through, would store the bottom of the range as the setting.
    local updating = true
    s:SetScript("OnValueChanged", function(self, value)
      if updating then return end
      opts.set(opts.normalize(value))
      -- The stored figure, not the dragged one: the setter clamps.
      caption:SetText(self.captionFor(opts.get()))
      if opts.after then opts.after() end
      if window.refreshPreview then window.refreshPreview() end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
      self:SetValue(self:GetValue() + delta * opts.step)
    end)
    row.control = s
    s.settingsRow = row
    row.sized[#row.sized + 1] = { frame = s, h = BAR }
    function row.Layout(scale)
      local captionHeight = lineHeight("body", scale)
      caption:ClearAllPoints()
      caption:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4 * scale)
      s:ClearAllPoints()
      s:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 4, -(captionHeight + 4 * scale))
      s:SetSize(ROW_W - 12, BAR * scale)
      track:SetHeight(4 * scale)
      local thumb = s.GetThumbTexture and s:GetThumbTexture()
      if thumb and thumb.SetSize then thumb:SetSize(18 * scale, 24 * scale) end
      low:ClearAllPoints()
      low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, -2 * scale)
      high:ClearAllPoints()
      high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, -2 * scale)
      return captionHeight + 4 * scale + BAR * scale + 2 * scale + lineHeight("meta", scale)
    end
    function row.Refresh()
      local value = opts.get()
      updating = true
      s:SetValue(value)
      updating = false
      caption:SetText(s.captionFor(value))
    end
    return s, row
  end

  local function choice(tab, name, key, label, entries, get, set)
    local row = newRow(tab, "choice", { key = key })
    local caption = addString(row, row.frame:CreateFontString(nil, "ARTWORK", "GameFontNormal"), "label")
    caption:SetText(label)
    local button = CreateFrame("Button", name, row.frame, "BackdropTemplate")
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button:SetBackdropColor(0.1, 0.11, 0.13, 1)
    button:SetBackdropBorderColor(0.35, 0.37, 0.42, 1)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    setColor(highlight, 1, 1, 1, 0.08)
    local text = addString(row, button:CreateFontString(name .. "Text", "OVERLAY", "GameFontHighlight"), "body")
    text:SetJustifyH("LEFT")
    local arrow = addString(row, button:CreateFontString(nil, "OVERLAY", "GameFontNormal"), "body")
    arrow:SetText("v")
    button:SetScript("OnClick", function(self)
      openMenu(self, entries(), get(), function(value)
        set(value)
        window.refresh()
      end)
    end)
    row.control = button
    button.settingsRow = row
    row.sized[#row.sized + 1] = { frame = button, h = CHOICE_H }
    function row.Layout(scale)
      local captionHeight = lineHeight("label", scale)
      caption:ClearAllPoints()
      caption:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, -(captionHeight + 2 * scale))
      button:SetSize(math.min(ROW_W, CHOICE_W * scale), CHOICE_H * scale)
      text:ClearAllPoints()
      text:SetPoint("LEFT", button, "LEFT", 8, 0)
      text:SetPoint("RIGHT", button, "RIGHT", -22 * scale, 0)
      arrow:ClearAllPoints()
      arrow:SetPoint("RIGHT", button, "RIGHT", -8, 0)
      return captionHeight + 2 * scale + CHOICE_H * scale
    end
    function row.Refresh()
      local current = get()
      local shown = tostring(current)
      for _, entry in ipairs(entries()) do
        if entry.value == current then shown = entry.label end
      end
      text:SetText(shown)
    end
    return button, row
  end

  -- A wrapped line of small print, across the row.
  local function note(tab, text, opts)
    local row = newRow(tab, "note", opts)
    local fs = addString(row, row.frame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"), "meta")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetTextColor(0.8, 0.82, 0.88)
    if text then fs:SetText(text) end
    row.control = fs
    fs.settingsRow = row
    function row.Layout(scale)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
      fs:SetWidth(ROW_W)
      return math.max(fs:GetStringHeight() or 0, lineHeight("meta", scale))
    end
    return fs, row
  end

  local function heading(tab, text)
    local row = newRow(tab, "heading")
    local fs = addString(row, row.frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"), "heading")
    fs:SetText(text)
    row.control = fs
    fs.settingsRow = row
    function row.Layout(scale)
      fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
      return lineHeight("heading", scale)
    end
    return fs, row
  end

  -- One of the addon's own buttons, which grows in both directions: a caption
  -- in Blizzard's fixed button font needs the box around it to grow with it.
  local function action(tab, text, onClick)
    local row = newRow(tab, "action")
    local button = Addon.createActionButton(row.frame, text)
    button:SetScript("OnClick", onClick)
    row.button = button
    row.control = button
    button.settingsRow = row
    function row.Layout(scale)
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", row.frame, "TOPLEFT", 0, 0)
      button:SetSize(ACTION_W * scale, Addon.RoleButtonHeight(scale))
      if button.GetFontString then Addon.ApplyFontRole(button:GetFontString(), "body", scale) end
      return buttonRowHeight(scale)
    end
    return button, row
  end

  -- --- tabs --------------------------------------------------------------------
  local function addTab(spec)
    local tab = { id = spec.id, label = LABELS[spec.label], rows = {} }
    local suffix = spec.id:sub(1, 1):upper() .. spec.id:sub(2)
    -- Named, because the scroll frame template names its scroll bar after it.
    tab.scroll = CreateFrame("ScrollFrame", "WordHunterWoWSettings" .. suffix .. "Scroll", area,
      "UIPanelScrollFrameTemplate")
    tab.content = CreateFrame("Frame", "WordHunterWoWSettings" .. suffix .. "Content", tab.scroll)
    tab.scroll:SetScrollChild(tab.content)
    tab.scroll:Hide()
    local button = CreateFrame("Button", "WordHunterWoWSettings" .. suffix .. "Tab", window)
    button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetText(tab.label)
    button.selectedBar = button:CreateTexture(nil, "ARTWORK")
    setColor(button.selectedBar, 1, 0.82, 0, 1)
    button.selectedBar:SetHeight(2)
    button.selectedBar:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 6, 0)
    button.selectedBar:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -6, 0)
    button:SetScript("OnClick", function() window.selectTab(tab.id) end)
    tab.button = button
    chrome[#chrome + 1] = { fs = button.text, role = "label" }
    tabs[#tabs + 1] = tab
    tabsById[tab.id] = tab
    return tab
  end
  for _, spec in ipairs(TABS) do addTab(spec) end

  -- --- 1. Appearance -------------------------------------------------------------
  local appearance = tabsById.appearance
  note(appearance, LABELS.backgroundNote)
  choice(appearance, "WordHunterWoWBackgroundDropdown", "background", LABELS.backgroundLabel,
    backgroundEntries, Addon.GetBackgroundStyle, Addon.SetBackgroundStyle)
  local function opacityCaption(v)
    return LABELS.opacityLabel .. " (" .. math.floor((tonumber(v) or 1) * 100 + 0.5) .. "%)"
  end
  local opacity = slider(appearance, "WordHunterWoWOpacitySlider", "opacity", {
    step = 0.05,
    normalize = function(v) return math.floor((tonumber(v) or 1) * 20 + 0.5) / 20 end,
    caption = opacityCaption, low = "0%", high = "100%",
    get = Addon.GetOpacity, set = Addon.SetOpacity,
  })
  opacity:SetMinMaxValues(0, 1.0)
  window.opacitySlider = opacity
  choice(appearance, "WordHunterWoWWordMarkingDropdown", "wordMarking", Addon.LABELS.wordMarkingLabel,
    markingEntries, Addon.GetWordMarking, Addon.SetWordMarking)

  -- --- 2. Sizes ------------------------------------------------------------------
  -- Every size slider, generated from the table that says which family a key
  -- belongs to, so a window cannot be added to the addon and left without a
  -- control, or land in the wrong group. The unit belongs to the group: a text
  -- size reads "18pt" and a window size "150%" (Addon.SIZE_GROUPS says why).
  local sizes = tabsById.sizes
  for _, group in ipairs(Addon.SIZE_GROUPS) do
    heading(sizes, LABELS[group.heading])
    note(sizes, LABELS[group.note])
    for _, entry in ipairs(group.entries) do
      local suffix = entry.key:sub(1, 1):upper() .. entry.key:sub(2)
      local label, unit = LABELS[entry.label], group.unit
      local s = slider(sizes, "WordHunterWoW" .. suffix .. "Slider", entry.key, {
        step = 0.05,
        normalize = function(v) return math.floor((tonumber(v) or 1) * 20 + 0.5) / 20 end,
        caption = function(v) return label .. " (" .. Addon.FormatSizeValue(unit, v) .. ")" end,
        low = Addon.FormatSizeValue(unit, Addon.TEXT_SCALE_MIN),
        high = Addon.FormatSizeValue(unit, Addon.TEXT_SCALE_MAX),
        get = Addon["Get" .. suffix], set = Addon["Set" .. suffix],
        -- The window is one of the surfaces the text size governs, so it has
        -- to answer while the slider is still under the cursor. Run for all
        -- five: the cost is one pass over a list.
        after = function() if window.layout then window.layout() end end,
      })
      s:SetMinMaxValues(Addon.TEXT_SCALE_MIN, Addon.TEXT_SCALE_MAX)
      window.sizeSliders[entry.key] = s
      if entry.note then note(sizes, LABELS[entry.note]) end
    end
  end
  note(sizes, LABELS.resetLayoutNote)
  action(sizes, LABELS.resetLayoutButton, function() Addon.ResetLayout() end)

  -- --- 3. Quest panel ------------------------------------------------------------
  -- How the panel behaves rather than what it looks like.
  local panelTab = tabsById.panel
  window.integratedCheck = check(panelTab, "WordHunterWoWIntegratedCheck", "integratedLayout",
    LABELS.integratedLabel, Addon.GetIntegratedLayout, Addon.SetIntegratedLayout)
  -- Off out of the box: the panel opening itself from the quest log put it
  -- over the quest that had just been clicked.
  window.questLogAutoCheck = check(panelTab, "WordHunterWoWQuestLogAutoCheck", "questLogAutoOpen",
    LABELS.questLogAutoLabel, Addon.GetQuestLogAutoOpen, Addon.SetQuestLogAutoOpen)
  -- It also has a slash command and a pad button, which are what a player
  -- will actually use; the box is here so somebody who has never read the
  -- command list can find out it exists.
  window.readingCheck = check(panelTab, "WordHunterWoWReadingCheck", "readingMode", LABELS.readingLabel,
    function() return Addon.GetReadingMode and Addon.GetReadingMode() or false end,
    function(v) if Addon.SetReadingMode then Addon.SetReadingMode(v) end end)

  -- --- 4. Learning ---------------------------------------------------------------
  local learning = tabsById.learning
  choice(learning, "WordHunterWoWLanguageDropdown", "targetLocale", LABELS.languageLabel,
    languageEntries, Addon.GetTargetLocale, Addon.SetTargetLocale)
  note(learning, LABELS.languageNote)
  local function recallOn() return Addon.GetRecallCheck and Addon.GetRecallCheck() or false end
  window.recallCheck = check(learning, "WordHunterWoWRecallCheck", "recallCheck", LABELS.recallLabel,
    recallOn, function(v) if Addon.SetRecallCheck then Addon.SetRecallCheck(v) end end)

  -- The two thresholds the rating box feeds, dimmed while it is off. Dimmed and
  -- not locked: a player may set them before switching the question on.
  --
  -- Whole numbers of events, not a scale, so the slider steps by one and the
  -- caption carries the unit: a bare "20" could be read as a percentage.
  local function countSlider(name, key, label, format, get, set, low, high)
    local s = slider(learning, name, key, {
      step = 1,
      normalize = function(v) return math.floor((tonumber(v) or low) + 0.5) end,
      caption = function(v)
        return label .. " " .. string.format(format, math.floor((tonumber(v) or low) + 0.5))
      end,
      low = tostring(low), high = tostring(high),
      get = get, set = set,
      -- The note under these counts difficult words, and the count is exactly
      -- what these change.
      after = function() if window.refreshDifficultNote then window.refreshDifficultNote() end end,
      enabledIf = recallOn,
    })
    s:SetMinMaxValues(low, high)
    return s
  end
  window.readySlider = countSlider("WordHunterWoWReadyAfterSlider", "readyAfter",
    LABELS.readyAfterLabel, LABELS.readyAfterValue,
    function() return Addon.GetReadyAfter and Addon.GetReadyAfter() or 5 end,
    function(v) if Addon.SetReadyAfter then Addon.SetReadyAfter(v) end end,
    Addon.RECALL_READY_MIN or 1, Addon.RECALL_READY_MAX or 40)
  window.difficultSlider = countSlider("WordHunterWoWDifficultMinSlider", "difficultMinRatings",
    LABELS.difficultMinLabel, LABELS.difficultMinValue,
    function() return Addon.GetDifficultMinRatings and Addon.GetDifficultMinRatings() or 5 end,
    function(v) if Addon.SetDifficultMinRatings then Addon.SetDifficultMinRatings(v) end end,
    Addon.RECALL_DIFFICULT_MIN or 3, Addon.RECALL_DIFFICULT_MAX or 40)

  local difficultNote, difficultRow = note(learning, "")
  window.difficultNote = difficultNote
  -- Named so the sliders can redraw just this line.
  window.refreshDifficultNote = function()
    difficultNote:SetText(string.format(LABELS.difficultNote,
      Addon.CountDifficult and Addon.CountDifficult() or 0,
      Addon.GetDifficultMinRatings and Addon.GetDifficultMinRatings() or 5))
  end
  difficultRow.Refresh = window.refreshDifficultNote

  -- The same shape as the harvest export: the list goes into the copy box, and
  -- an empty list says so in a dialog with nothing to confirm.
  window.difficultExport = action(learning, LABELS.difficultExport, function()
    local text = Addon.BuildDifficultExport and Addon.BuildDifficultExport() or ""
    if type(text) ~= "string" or text == "" then
      Addon.showConfirm(LABELS.difficultExport,
        string.format(LABELS.difficultExportEmpty,
          Addon.GetDifficultMinRatings and Addon.GetDifficultMinRatings() or 5),
        nil, nil, window)
      return
    end
    Addon.showCopyText(LABELS.difficultExport, text, LABELS.difficultExportHint, window)
  end)

  -- --- 5. Collecting -------------------------------------------------------------
  local collecting = tabsById.collecting
  window.harvestCheck = check(collecting, "WordHunterWoWHarvestCheck", "harvestCorpus", LABELS.harvestLabel,
    Addon.GetHarvestEnabled, Addon.SetHarvestEnabled)
  local harvestNote, harvestRow = note(collecting, "")
  window.harvestNote = harvestNote
  function harvestRow.Refresh()
    local words = Addon.HarvestWordCount and Addon.HarvestWordCount() or 0
    local passages = Addon.HarvestCount and (Addon.HarvestCount() - words) or 0
    harvestNote:SetText(string.format(LABELS.harvestNote, passages, words))
  end
  window.harvestExport = action(collecting, LABELS.harvestExport, function()
    if Addon.rebuildHarvestExport then Addon.rebuildHarvestExport() end
    local blob = WordHunterWoWCorpusExport
    -- A previous export this session already moved the live table into the
    -- blob. Showing "nothing collected" would lie; offer the blob again.
    if type(blob) ~= "string" or blob == "" then
      -- Nothing to confirm, so no action text: showConfirm drops its action
      -- button and the dialog closes on Cancel alone.
      Addon.showConfirm(LABELS.harvestExport, LABELS.harvestExportEmpty, nil, nil, window)
      return
    end
    Addon.showCopyText(LABELS.harvestExport, blob, LABELS.harvestExportHint, window)
    window.refresh()
  end)
  -- /whw harvest clear, behind a confirmation, because it cannot be undone.
  window.harvestClear = action(collecting, LABELS.harvestClear, function()
    Addon.showConfirm(LABELS.harvestClear, LABELS.harvestClearBody, LABELS.harvestClearAction, function()
      if Addon.ClearHarvest then Addon.ClearHarvest() end
      window.refresh()
    end, window)
  end)

  -- --- 6. Controller -------------------------------------------------------------
  local controller = tabsById.controller
  window.gamepadCheck = check(controller, "WordHunterWoWGamepadCheck", "gamepad", LABELS.gamepadLabel,
    function() return Addon.GetGamePadEnabled and Addon.GetGamePadEnabled() or false end,
    function(v) if Addon.SetGamePadEnabled then Addon.SetGamePadEnabled(v) end end)
  window.gamepadNote = note(controller, LABELS.gamepadNote)
  note(controller, LABELS.gamepadWindowNote)

  -- --- 7. About ------------------------------------------------------------------
  -- Nothing here is read off a game frame. The name probe /whw diag prints
  -- stays in chat and is never drawn here.
  local about = tabsById.about
  local versionLine, versionRow = note(about, "")
  function versionRow.Refresh()
    local build, number = "?", "?"
    if GetBuildInfo then
      local v, b = GetBuildInfo()
      build, number = tostring(v), tostring(b)
    end
    local flavor = Addon.Compat and Addon.Compat.GameFlavor and Addon.Compat.GameFlavor() or "?"
    versionLine:SetText(string.format(LABELS.aboutVersion, addonVersion(), tostring(flavor), build, number))
  end
  local wordsLine, wordsRow = note(about, "")
  function wordsRow.Refresh()
    local here, all = 0, 0
    for _ in pairs(Addon.GetWordsTable()) do here = here + 1 end
    if type(WordHunterWoWDB) == "table" and type(WordHunterWoWDB.wordsByLocale) == "table" then
      for _, words in pairs(WordHunterWoWDB.wordsByLocale) do
        if type(words) == "table" then for _ in pairs(words) do all = all + 1 end end
      end
    end
    local locale = Addon.GetTargetLocale()
    wordsLine:SetText(string.format(LABELS.aboutWords,
      (Addon.SUPPORTED_LOCALES[locale] or locale) .. " (" .. locale .. ")", here, all))
  end
  heading(about, LABELS.aboutCommandsHeading)
  note(about, LABELS.aboutCommands)
  action(about, LABELS.aboutDiagnostics, function()
    if Addon.PrintDiagnostics then Addon.PrintDiagnostics() end
  end)

  -- --- the preview -----------------------------------------------------------------
  -- A miniature quest panel drawn with the panel's own code where it can be
  -- reached: the theme and opacity through ApplyBackground, the letters
  -- through TokenFont, each word's marking through StyleWordButton. It takes
  -- nothing over and reads nothing but this addon's settings.
  local previewCaption = pane:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  previewCaption:SetText(LABELS.previewTitle)
  chrome[#chrome + 1] = { fs = previewCaption, role = "label" }
  -- Reading mode dims the game behind the panel; here, the pane behind the
  -- mock. Never the screen.
  local wash = pane:CreateTexture(nil, "BACKGROUND")
  wash:SetAllPoints(pane)
  setColor(wash, 0, 0, 0, READING_DIM)
  window.previewWash = wash

  local preview = CreateFrame("Frame", "WordHunterWoWSettingsPreview", pane, "BackdropTemplate")
  window.preview = preview
  -- 200% text is cut off at the pane's edge rather than spilling over the tabs.
  if preview.SetClipsChildren then preview:SetClipsChildren(true) end
  Addon.ApplyBackground(preview)

  local previewTitle = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  window.previewTitle = previewTitle
  local words = {}
  window.previewWords = words
  local lit
  for index = 1, MAX_SAMPLE_WORDS do
    -- Built like the panel's own word buttons, so StyleWordButton finds the
    -- same two pieces on them.
    local word = CreateFrame("Button", nil, preview)
    word.text = word:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    word.text:SetPoint("CENTER", word, "CENTER", 0, 0)
    word.text:SetWordWrap(false)
    word.underline = word:CreateTexture(nil, "ARTWORK")
    word.underline:SetPoint("BOTTOMLEFT", word, "BOTTOMLEFT", 1, 1)
    word.underline:SetPoint("BOTTOMRIGHT", word, "BOTTOMRIGHT", -1, 1)
    word:SetHighlightTexture(WHITE, "BLEND")
    local hl = word:GetHighlightTexture()
    if hl and hl.SetVertexColor then hl:SetVertexColor(0.30, 0.42, 0.55, 0.20) end
    -- Pointing at a word lights up its English, as it does in the panel --
    -- through a highlighter of this window's own, never the panel's.
    word:SetScript("OnEnter", function(self)
      if self.en and window.previewEnglish then
        lit = self.en
        window.previewEnglish:SetText(englishLine(lit))
      end
    end)
    word:SetScript("OnLeave", function()
      lit = nil
      if window.refreshPreview then window.refreshPreview() end
    end)
    word:Hide()
    words[index] = word
  end
  local badge = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  badge:SetText(LABELS.recallBadge)
  window.previewBadge = badge
  local progress = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  progress:SetJustifyH("LEFT")
  window.previewProgress = progress
  local ready = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  ready:SetJustifyH("LEFT")
  ready:SetWordWrap(true)
  window.previewReady = ready
  local enHeader = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  enHeader:SetText(LABELS.englishHeader)
  window.previewEnglishHeader = enHeader
  local enText = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  enText:SetJustifyH("LEFT")
  enText:SetWordWrap(true)
  window.previewEnglish = enText
  local enOff = preview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  enOff:SetJustifyH("LEFT")
  enOff:SetWordWrap(true)
  enOff:SetText(LABELS.previewEnglishOff)
  window.previewEnglishOff = enOff

  window.refreshPreview = function()
    local scale = Addon.GetTextScale and Addon.GetTextScale() or 1
    local enScale = Addon.GetEnPanelTextScale and Addon.GetEnPanelTextScale() or 1
    local marking = Addon.GetWordMarking and Addon.GetWordMarking() or "both"
    local sample = previewSample()
    local inner = MOCK_W - 2 * PREVIEW_PAD

    Addon.ApplyBackground(preview)
    if Addon.GetReadingMode and Addon.GetReadingMode() then wash:Show() else wash:Hide() end

    Addon.ApplyFontRole(previewTitle, "heading", scale)
    previewTitle:SetText(sample.title)
    previewTitle:ClearAllPoints()
    previewTitle:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD, -PREVIEW_PAD)
    previewTitle:SetWidth(inner)

    local rowH = 18 * scale
    local x, y = 0, -PREVIEW_PAD - lineHeight("heading", scale) - 6 * scale
    local counts = { known = 0, learning = 0, new = 0 }
    local learningWord
    local thickness = Addon.UnderlineThickness and Addon.UnderlineThickness(scale) or 2
    for index, word in ipairs(words) do
      local entry = sample.words[index]
      if entry then
        if Addon.TokenFont then Addon.TokenFont(word.text, scale) end
        word.text:SetText(entry[1])
        local width = math.min(inner, math.ceil(word.text:GetStringWidth()) + 6)
        if x > 0 and x + width > inner then
          x = 0
          y = y - rowH
        end
        word:ClearAllPoints()
        word:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD + x, y)
        word:SetSize(width, rowH)
        x = x + width + 2
        word.status, word.en = entry[2], entry[3]
        Addon.StyleWordButton(word, entry[2], marking, thickness)
        local status = entry[2] or "new"
        if counts[status] then counts[status] = counts[status] + 1 end
        if entry[2] == "learning" then learningWord = word end
        word:Show()
      else
        word.status, word.en = nil, nil
        word:Hide()
      end
    end
    y = y - rowH - 6 * scale

    -- The rating question's cue, on the word it would ask about.
    Addon.ApplyFontRole(badge, "meta", scale)
    badge:ClearAllPoints()
    if learningWord and Addon.GetRecallCheck and Addon.GetRecallCheck() then
      badge:SetPoint("BOTTOMLEFT", learningWord, "TOPRIGHT", -4, -6 * scale)
      badge:Show()
    else
      badge:Hide()
    end

    Addon.ApplyFontRole(progress, "meta", scale)
    progress:SetText(Addon.FormatProgress(counts))
    progress:ClearAllPoints()
    progress:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD, y)
    progress:SetWidth(inner)
    y = y - lineHeight("meta", scale) - 2 * scale

    Addon.ApplyFontRole(ready, "meta", scale)
    ready:SetText(Addon.ColorHex("known") .. LABELS.readyForKnown .. "|r  " ..
      string.format(LABELS.readyAfterValue, Addon.GetReadyAfter and Addon.GetReadyAfter() or 5))
    ready:ClearAllPoints()
    ready:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD, y)
    ready:SetWidth(inner)
    y = y - math.max(ready:GetStringHeight() or 0, lineHeight("meta", scale)) - 10 * scale

    -- The English, at its own size, where the integrated layout puts it in the
    -- panel. Off, the panel has no English in it at all, so neither has this.
    if Addon.GetIntegratedLayout and Addon.GetIntegratedLayout() then
      Addon.ApplyFontRole(enHeader, "label", enScale)
      enHeader:ClearAllPoints()
      enHeader:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD, y)
      y = y - lineHeight("label", enScale) - 2 * enScale
      Addon.ApplyFontRole(enText, "body", enScale)
      enText:SetText(englishLine(lit or 5))
      enText:ClearAllPoints()
      enText:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD, y)
      enText:SetWidth(inner)
      enHeader:Show()
      enText:Show()
      enOff:Hide()
    else
      Addon.ApplyFontRole(enOff, "meta", scale)
      enOff:ClearAllPoints()
      enOff:SetPoint("TOPLEFT", preview, "TOPLEFT", PREVIEW_PAD, y)
      enOff:SetWidth(inner)
      enHeader:Hide()
      enText:Hide()
      enOff:Show()
    end
  end

  -- --- layout, tabs and refresh --------------------------------------------------
  local function layout()
    local scale = pageScale()
    for _, item in ipairs(chrome) do Addon.ApplyFontRole(item.fs, item.role, scale) end

    local headerHeight = lineHeight("heading", scale) + 20
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", window, "TOPLEFT", 16, -12)
    local tabHeight = lineHeight("label", scale) + 12
    local x = 12
    for _, tab in ipairs(tabs) do
      local width = math.ceil(tab.button.text:GetStringWidth()) + 20
      tab.button:SetSize(width, tabHeight)
      tab.button:ClearAllPoints()
      tab.button:SetPoint("TOPLEFT", window, "TOPLEFT", x, -headerHeight)
      x = x + width + 2
    end
    divider:ClearAllPoints()
    divider:SetPoint("TOPLEFT", window, "TOPLEFT", 12, -(headerHeight + tabHeight))
    divider:SetPoint("TOPRIGHT", window, "TOPRIGHT", -12, -(headerHeight + tabHeight))

    local top = headerHeight + tabHeight + 8
    pane:ClearAllPoints()
    pane:SetPoint("TOPLEFT", window, "TOPLEFT", MARGIN, -top)
    pane:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", MARGIN, MARGIN)
    pane:SetWidth(PREVIEW_W)
    previewCaption:ClearAllPoints()
    previewCaption:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, 0)
    preview:ClearAllPoints()
    preview:SetPoint("TOPLEFT", pane, "TOPLEFT", MOCK_INSET, -(lineHeight("label", scale) + 4 + MOCK_INSET))
    preview:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -MOCK_INSET, MOCK_INSET)
    area:ClearAllPoints()
    area:SetPoint("TOPLEFT", window, "TOPLEFT", PREVIEW_W + 2 * MARGIN, -top)
    area:SetPoint("BOTTOMRIGHT", window, "BOTTOMRIGHT", -MARGIN, MARGIN)

    local buttonHeight = Addon.RoleButtonHeight(scale)
    reset:SetSize(RESET_W * scale, buttonHeight)
    reset:ClearAllPoints()
    reset:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -8, 4)
    if reset.GetFontString then Addon.ApplyFontRole(reset:GetFontString(), "body", scale) end
    local foot = buttonHeight + 12

    for _, tab in ipairs(tabs) do
      tab.scroll:ClearAllPoints()
      tab.scroll:SetPoint("TOPLEFT", area, "TOPLEFT", 0, 0)
      tab.scroll:SetPoint("BOTTOMRIGHT", area, "BOTTOMRIGHT", -SCROLLBAR, foot)
      local y = -8 * scale
      for _, row in ipairs(tab.rows) do
        for _, item in ipairs(row.strings) do Addon.ApplyFontRole(item.fs, item.role, scale) end
        local height = row.Layout(scale)
        row.frame:ClearAllPoints()
        row.frame:SetPoint("TOPLEFT", tab.content, "TOPLEFT", 8, y)
        row.frame:SetSize(ROW_W, height)
        row.y, row.h = y, height
        y = y - height - ROW_GAP * scale
      end
      -- Tall enough to reach the last row, or the last row cannot be scrolled
      -- to. Struck from where the rows landed rather than written down.
      tab.content:SetSize(CONTENT_W, -y + FOOT * scale)
      if tab.scroll.UpdateScrollChildRect then tab.scroll:UpdateScrollChildRect() end
    end
  end
  window.layout = layout

  function window.selectTab(id)
    local tab = tabsById[id] or tabs[1]
    closeMenu()
    window.activeTab = tab
    Addon.lastSettingsTab = tab.id
    for _, other in ipairs(tabs) do
      local on = other == tab
      if on then other.scroll:Show() else other.scroll:Hide() end
      other.button.text:SetTextColor(on and 1 or 0.62, on and 0.82 or 0.64, on and 0 or 0.68)
      if on then other.button.selectedBar:Show() else other.button.selectedBar:Hide() end
    end
    if tabResets(tab.id) then reset:Show() else reset:Hide() end
  end

  -- The shoulder buttons' step, round the ends.
  function window.stepTab(direction)
    local current = 1
    for index, tab in ipairs(tabs) do
      if tab == window.activeTab then current = index end
    end
    local nextIndex = (current - 1 + direction) % #tabs + 1
    window.selectTab(tabs[nextIndex].id)
  end

  -- Every setter this window drives calls this, as do the slash commands'
  -- setters, so a setting changed anywhere shows here at once.
  window.refresh = function()
    for _, row in ipairs(rows) do
      if row.Refresh then row.Refresh() end
      if row.enabledIf then
        local on = row.enabledIf() and true or false
        row.dimmed = not on
        row.frame:SetAlpha(on and 1 or DISABLED_ALPHA)
      end
    end
    -- Last, and from here rather than only from the size sliders: /whw reset
    -- and the slash commands change sizes with the window closed.
    layout()
    window.refreshPreview()
  end

  window:SetScript("OnShow", function(self)
    Addon.PlaceFrame(self, "settings")
    self.refresh()
  end)
  window:SetScript("OnHide", function()
    closeMenu()
  end)

  window.selectTab(TABS[1].id)
  -- Built at whatever size is already stored, not at 100% and corrected on
  -- the first show, and the sliders are released from their build-time hold.
  window.refresh()

  Addon.CreateSettingsOptionsPage()
  return window
end

-- Shows the window, on the named tab or the one last used this session.
local function showWindow(tabId)
  local window = Addon.CreateSettingsPanel()
  window.selectTab(tabId or Addon.lastSettingsTab or TABS[1].id)
  if not window:IsShown() then
    window:Show()
    if window.Raise then window:Raise() end
  end
  window.refresh()
  return window
end
Addon.ShowSettings = showWindow

-- /whw settings. A toggle with no tab named, as DoesItDie's /did is; with one,
-- it opens there. Never Settings.OpenToCategory: the window is the addon's own,
-- so it opens in combat too, and there is no category id to get wrong.
function Addon.OpenSettings(which)
  local tabId
  if which ~= nil then
    tabId = Addon.FindSettingsTab(which)
    if not tabId then return nil end
  end
  local window = Addon.CreateSettingsPanel()
  if not tabId and window:IsShown() then
    window:Hide()
    return nil
  end
  showWindow(tabId)
  return window.activeTab and window.activeTab.id
end

-- ---------------------------------------------------------------------------
-- Options > AddOns > WordHunterWoW: a short page with a button that opens the
-- window. It does not open the window by itself when shown -- browsing the
-- AddOns list should not pop a window over it.
-- ---------------------------------------------------------------------------
function Addon.CreateSettingsOptionsPage()
  if Addon.settingsCategoryPage then return Addon.settingsCategoryPage end
  -- The frame Blizzard parents into the Options canvas. It must be this one:
  -- wrapping it in another host left the canvas blank on Retail.
  local page = CreateFrame("Frame", "WordHunterWoWOptionsPage")
  page.name = "WordHunterWoW"
  Addon.settingsCategoryPage = page

  local title = page:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", page, "TOPLEFT", 16, -16)
  title:SetText("WordHunterWoW")
  local text = page:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  text:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  text:SetWidth(560)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(true)
  text:SetText(LABELS.optionsPageText)
  local open = Addon.createActionButton(page, LABELS.optionsPageButton)
  open:SetSize(260, Addon.RoleButtonHeight(1))
  open:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -14)
  open:SetScript("OnClick", function()
    closeBlizzardOptions()
    showWindow()
  end)
  page.openButton = open

  if Settings and Settings.RegisterAddOnCategory then
    if Settings.RegisterCanvasLayoutCategory then
      -- The category's ID is the client's, and a number. Nothing is written
      -- into the table the client hands back: an earlier build overwrote its
      -- ID with the page's name, which broke Settings.OpenToCategory and
      -- tainted the table besides. The window is opened directly now, so
      -- nothing here needs the ID at all.
      local category = Settings.RegisterCanvasLayoutCategory(page, page.name)
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
      Addon.settingsCategoryName = page.name
    else
      local category = Settings.RegisterVerticalLayoutCategory(page.name)
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
      Addon.settingsCategoryName = page.name
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(page)
  end
  return page
end
