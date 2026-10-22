local Addon = WordHunterWoW_Addon
local PREFIX = "WORDHUNTERWOW_"
local actions = {
  READER = "Toggle quest reader", QUESTS = "Toggle quest library",
  WORDS = "Toggle word list", STATS = "Toggle statistics",
  READING = "Toggle reading mode", SETTINGS = "Open settings",
  PREVIOUS = "Previous word", NEXT = "Next word", SAVE = "Save word", CLOSE = "Close window",
}
BINDING_HEADER_WORDHUNTERWOW = "WordHunterWoW"
for action, label in pairs(actions) do _G["BINDING_NAME_" .. PREFIX .. action] = label end

function Addon.GamePadHintsEnabled()
  if not (Addon.GetGamePadEnabled and Addon.GetGamePadEnabled()) then return false end
  if C_GamePad and C_GamePad.IsEnabled then return C_GamePad.IsEnabled() end
  if GetCVarBool then return GetCVarBool("GamePadEnable") end
  return false
end

local function padKey(key)
  if type(key) ~= "string" then return false end
  if IsBindingForGamePad then return IsBindingForGamePad(key) end
  return key:match("^PAD[%w]+$") ~= nil or key:match("%-PAD[%w]+$") ~= nil
end

function Addon.InputKeyText(key)
  if Addon.GamePadUI and padKey(key) then return Addon.GamePadUI.Key(key) end
  local text = GetBindingText and GetBindingText(key, 1)
  if type(text) == "string" and text ~= "" then return text end
  return _G["KEY_" .. key] or key
end

function Addon.SideTabShortcut(button, action, pad)
  local hint = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("RIGHT", button, "LEFT", -3, 0)
  hint:SetJustifyH("RIGHT")
  hint:SetShadowColor(0, 0, 0, 1)
  hint:SetShadowOffset(1, -1)
  Addon.ButtonShortcut(button, action)
  Addon.WatchInputHints(button, function()
    local cursor = Addon.GamePadUI and Addon.GamePadUI.ConsolePortActive()
    hint:SetText(Addon.ShortcutHint(action, nil, not cursor and pad or nil))
  end)
end

local function chord(key)
  if IsShiftKeyDown and IsShiftKeyDown() then key = "SHIFT-" .. key end
  if IsControlKeyDown and IsControlKeyDown() then key = "CTRL-" .. key end
  if IsAltKeyDown and IsAltKeyDown() then key = "ALT-" .. key end
  return key
end

function Addon.ShortcutAction(key)
  local binding = GetBindingAction and GetBindingAction(chord(key), true)
  local action = type(binding) == "string" and binding:match("^WORDHUNTERWOW_(.+)$")
  return actions[action] and action or nil
end

local function click(button)
  local handler = button and button:GetScript("OnClick")
  if handler then handler(button) end
end

function Addon.RunShortcut(action)
  local editor = Addon.editor
  if action == "SAVE" then
    if editor and editor:IsShown() then click(editor.save) end
  elseif action == "PREVIOUS" or action == "NEXT" then
    if editor and editor:IsShown() and Addon.OpenNeighbourWord then
      Addon.OpenNeighbourWord(action == "PREVIOUS" and -1 or 1)
    end
  elseif action == "CLOSE" then Addon.CloseAll()
  elseif action == "READER" then Addon.ToggleReader()
  elseif action == "QUESTS" then Addon.toggleQuestBrowser()
  elseif action == "WORDS" then
    if Addon.listFrame and Addon.listFrame:IsShown() then Addon.listFrame:Hide()
    else Addon.toggleWordList() end
  elseif action == "STATS" then
    if Addon.statsFrame and Addon.statsFrame:IsShown() then Addon.statsFrame:Hide()
    else Addon.toggleStats() end
  elseif action == "READING" then Addon.ToggleReadingMode()
  elseif action == "SETTINGS" then Addon.OpenSettings()
  end
end

function Addon.HandleShortcutKey(key)
  if InCombatLockdown and InCombatLockdown() then return false end
  if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return false end
  local action = Addon.ShortcutAction(key)
  if not action then return false end
  Addon.RunShortcut(action)
  return true
end

-- Frame-local pad controls take priority over ordinary game bindings. Only an
-- explicit WordHunter binding replaces one of those controls.
function Addon.ShortcutHint(action, keyboard, pad)
  local usingPad = Addon.GamePadHintsEnabled()
  if type(pad) == "function" then pad = pad() end
  local keys, seen = {}, {}
  local function add(key)
    if not key or seen[key] or padKey(key) ~= usingPad then return end
    seen[key] = true
    keys[#keys + 1] = Addon.InputKeyText(key)
  end
  local typing = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
  if action and GetBindingKey and (usingPad or not typing) then
    for _, key in ipairs({ GetBindingKey(PREFIX .. action) }) do add(key) end
  end
  if not usingPad and action == "SAVE" and Addon.editor and typing == Addon.editor.translation then
    add("ENTER")
  end
  local fallback = usingPad and pad or keyboard
  if usingPad and Addon.GamePadUI and Addon.GamePadUI.ConsolePortActive() then fallback = nil end
  if fallback then
    local bound = Addon.ShortcutAction(fallback)
    if not bound or bound == action then
      if usingPad or fallback == "ESCAPE" or (not (InCombatLockdown and InCombatLockdown())
          and not (GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus())) then add(fallback) end
    end
  end
  return table.concat(keys, " / ")
end

local watchers = setmetatable({}, { __mode = "k" })
function Addon.WatchInputHints(frame, refresh)
  watchers[frame] = refresh
  frame:HookScript("OnShow", refresh)
  refresh()
end

function Addon.RefreshInputHints()
  for _, refresh in pairs(watchers) do refresh() end
end

function Addon.WindowInputHint(frame)
  local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 2)
  hint:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, 2)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(true)
  Addon.WatchInputHints(frame, function()
    hint:SetText(Addon.GamePadHintsEnabled() and Addon.GamePadUI and Addon.GamePadUI.Hint() or "")
  end)
  return hint
end

function Addon.ButtonShortcut(button, action, keyboard, pad, below)
  local hint
  if below then
    hint = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -1)
    hint:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -1)
    hint:SetHeight(16)
    hint:SetWordWrap(false)
    hint:SetMaxLines(1)
    button.shortcutHint = hint
  end
  local function text() return Addon.ShortcutHint(action, keyboard, pad) end
  Addon.WatchInputHints(button, function() if hint then hint:SetText(text()) end end)
  button:HookScript("OnEnter", function(self)
    if not GameTooltip then return end
    if GameTooltip:GetOwner() ~= self then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(actions[action] or "Controls")
    end
    local keys = text()
    GameTooltip:AddLine(keys ~= "" and keys or (NOT_BOUND or "Not bound"), 1, .82, 0, true)
    GameTooltip:Show()
  end)
  button:HookScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

function Addon.PanelShortcutText()
  local parts = {}
  local function add(label, action, keyboard, pad)
    local keys = Addon.ShortcutHint(action, keyboard, pad)
    if keys ~= "" then parts[#parts + 1] = keys .. ": " .. label end
  end
  if Addon.GamePadUI and Addon.GamePadUI.ConsolePortActive() then
    parts[#parts + 1] = Addon.GamePadUI.Hint()
  elseif Addon.GamePadHintsEnabled() then
    local movement = {}
    for _, key in ipairs({ "PADDLEFT", "PADDRIGHT", "PADDUP", "PADDDOWN" }) do
      local text = Addon.ShortcutHint(nil, nil, key)
      if text ~= "" then movement[#movement + 1] = text end
    end
    if #movement > 0 then parts[#parts + 1] = table.concat(movement, "/") .. ": move" end
    add("open word", nil, nil, "PAD1")
    add("scroll up", nil, nil, "PADLSHOULDER")
    add("scroll down", nil, nil, "PADRSHOULDER")
    if WordHunterWoW_VoiceTogglePause then
      add("pause / resume voice", nil, nil, "PADRTRIGGER")
      add("replay voice", nil, nil, "PADLTRIGGER")
    end
  end
  add("close", "CLOSE", "ESCAPE", "PAD2")
  add("words", "WORDS", nil, "PAD3")
  add("stats", "STATS")
  add("reading mode", "READING", nil, "PAD4")
  return table.concat(parts, "  ·  ")
end

function Addon.ControllerHelpText()
  if not Addon.GamePadHintsEnabled() then
    return "Enable controller support in Options → Controls and the switch above to show controller hints. "
      .. "Assign WordHunterWoW shortcuts in the game's Key Bindings settings."
  end
  local key = function(button) return Addon.ShortcutHint(nil, nil, button) end
  return "Needs the game's own controller support (Options → Controls).\n"
    .. "Reader — " .. Addon.PanelShortcutText() .. "\n"
    .. "Editor — " .. key("PADDLEFT") .. "/" .. key("PADDRIGHT") .. ": status or rating; "
    .. Addon.ShortcutHint("SAVE", nil, "PAD1") .. ": save; "
    .. Addon.ShortcutHint("CLOSE", nil, "PAD2") .. ": close; "
    .. Addon.ShortcutHint("PREVIOUS", nil, "PADLSHOULDER") .. "/"
    .. Addon.ShortcutHint("NEXT", nil, "PADRSHOULDER") .. ": previous/next word.\n"
    .. "Recall — " .. key("PAD1") .. ": rate; " .. key("PAD2") .. ": later."
end

function Addon.PanelInputHintHeight(panel)
  if not panel then return 0 end
  local hint = rawget(panel, "inputHint")
  if not hint then return 0 end
  local text = Addon.PanelShortcutText()
  hint:SetText(text)
  hint:SetWidth(math.max(1, panel:GetWidth() - 36))
  hint:SetHeight(0)
  local height = text ~= "" and math.ceil(hint:GetStringHeight()) + 6 or 0
  hint:SetHeight(height)
  return height
end

local events = CreateFrame("Frame")
Addon.inputHintsEvents = events
for _, event in ipairs({ "PLAYER_LOGIN", "UPDATE_BINDINGS", "CVAR_UPDATE",
    "GAME_PAD_ACTIVE_CHANGED", "GAME_PAD_CONFIGS_CHANGED", "GAME_PAD_CONNECTED",
    "GAME_PAD_DISCONNECTED", "MODIFIER_STATE_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  -- Older clients do not know the controller events.
  pcall(events.RegisterEvent, events, event)
end
events:SetScript("OnEvent", function(_, event, name)
  if event == "CVAR_UPDATE" and type(name) == "string" and not name:lower():match("^gamepad") then return end
  Addon.RefreshInputHints()
end)
