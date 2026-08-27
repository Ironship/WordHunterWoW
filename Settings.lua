local Addon = WordHunterWoW_Addon

function Addon.CreateSettingsPanel()
  if Addon.settingsPanel then return Addon.settingsPanel end

  local panel = CreateFrame("Frame", "WordHunterWoWSettingsPanel", UIParent, "BackdropTemplate")
  panel.name = "WordHunterWoW"
  Addon.settingsPanel = panel
  Addon.setBackdrop(panel, 1)

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(Addon.LABELS.settingsTitle)

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -36)
  subtitle:SetText("Midnight-ready backgrounds use the new War Within / Midnight dark style.")
  subtitle:SetTextColor(0.7, 0.74, 0.8)

  local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  label:SetPoint("TOPLEFT", 16, -64)
  label:SetText(Addon.LABELS.backgroundLabel)

  local dropdown = CreateFrame("Frame", "WordHunterWoWBackgroundDropdown", panel, "UIDropDownMenuTemplate")
  dropdown:SetPoint("TOPLEFT", 12, -84)
  UIDropDownMenu_SetWidth(dropdown, 220)

  local preview = CreateFrame("Frame", nil, panel, "BackdropTemplate")
  preview:SetSize(460, 86)
  preview:SetPoint("TOPLEFT", 16, -132)
  panel.preview = preview
  local previewLabel = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  previewLabel:SetPoint("TOPLEFT", 12, -10)
  previewLabel:SetText("Preview")
  previewLabel:SetTextColor(0.35, 0.68, 1)
  local previewText = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  previewText:SetPoint("CENTER", 0, -6)
  previewText:SetText("WordHunterWoW  •  Quest text preview  •  Gnom / Gnomen")
  Addon.ApplyBackground(preview)

  local opacityLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  opacityLabel:SetPoint("TOPLEFT", 16, -232)
  opacityLabel:SetText(Addon.LABELS.opacityLabel)

  local slider = CreateFrame("Slider", "WordHunterWoWOpacitySlider", panel, "OptionsSliderTemplate")
  slider:SetPoint("TOPLEFT", 16, -252)
  slider:SetSize(460, 16)
  slider:SetMinMaxValues(0, 1.0)
  slider:SetValueStep(0.05)
  slider:SetObeyStepOnDrag(true)
  slider:SetValue(Addon.GetOpacity())
  _G[slider:GetName() .. "Low"]:SetText("0%")
  _G[slider:GetName() .. "High"]:SetText("100%")
  _G[slider:GetName() .. "Text"]:SetText(Addon.LABELS.opacityLabel .. " (" .. math.floor(Addon.GetOpacity() * 100 + 0.5) .. "%)")
  slider:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value * 20 + 0.5) / 20
    Addon.SetOpacity(value)
    Addon.ApplyBackground(preview)
    _G[self:GetName() .. "Text"]:SetText(Addon.LABELS.opacityLabel .. " (" .. math.floor(value * 100 + 0.5) .. "%)")
  end)

  local langLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  langLabel:SetPoint("TOPLEFT", 16, -285)
  langLabel:SetText(Addon.LABELS.languageLabel)

  local langDropdown = CreateFrame("Frame", "WordHunterWoWLanguageDropdown", panel, "UIDropDownMenuTemplate")
  langDropdown:SetPoint("TOPLEFT", 12, -305)
  UIDropDownMenu_SetWidth(langDropdown, 220)

  local function UpdateLangDropdownText()
    local locale = Addon.GetTargetLocale()
    local name = Addon.SUPPORTED_LOCALES[locale] or locale
    UIDropDownMenu_SetText(langDropdown, name .. " (" .. locale .. ")")
  end

  local function OnLangClick(self, arg1)
    local locale = arg1 or self.arg1 or self.value
    if Addon.SUPPORTED_LOCALES[locale] then
      UIDropDownMenu_SetText(langDropdown, Addon.SUPPORTED_LOCALES[locale] .. " (" .. locale .. ")")
      Addon.SetTargetLocale(locale)
    end
  end

  local function InitializeLang(self, level)
    level = level or 1
    for _, locale in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
      local name = Addon.SUPPORTED_LOCALES[locale]
      local info = UIDropDownMenu_CreateInfo()
      info.text = name .. " (" .. locale .. ")"
      info.arg1 = locale
      info.value = locale
      info.func = OnLangClick
      info.checked = Addon.GetTargetLocale() == locale
      UIDropDownMenu_AddButton(info, level)
    end
  end

  UIDropDownMenu_Initialize(langDropdown, InitializeLang)
  UpdateLangDropdownText()

  local langNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  langNote:SetPoint("TOPLEFT", 16, -342)
  langNote:SetPoint("TOPRIGHT", -16, -342)
  langNote:SetJustifyH("LEFT")
  langNote:SetWordWrap(true)
  langNote:SetText("Required — words are stored separately per language. English US/GB both export as 'en'.")
  langNote:SetTextColor(0.8, 0.82, 0.88)

  local integrated = CreateFrame("CheckButton", "WordHunterWoWIntegratedCheck", panel, "UICheckButtonTemplate")
  integrated:SetPoint("TOPLEFT", 12, -372)
  local integratedText = _G[integrated:GetName() .. "Text"]
  if integratedText then
    integratedText:SetText(Addon.LABELS.integratedLabel)
  end
  integrated:SetChecked(Addon.GetIntegratedLayout())
  integrated:SetScript("OnClick", function(self)
    Addon.SetIntegratedLayout(self:GetChecked())
  end)
  panel.integratedCheck = integrated

  local function UpdateDropdownText()
    local key = Addon.GetBackgroundStyle()
    local style = Addon.BACKGROUNDS[key] or Addon.BACKGROUNDS.tooltip
    UIDropDownMenu_SetText(dropdown, style.name)
  end

  local function OnClick(self, arg1)
    local key = arg1 or self.arg1 or self.value
    local style = Addon.BACKGROUNDS[key] or Addon.BACKGROUNDS.tooltip
    UIDropDownMenu_SetText(dropdown, style.name)
    Addon.SetBackgroundStyle(key)
    Addon.ApplyBackground(preview)
  end

  local function Initialize(self, level)
    level = level or 1
    for _, key in ipairs(Addon.BACKGROUND_ORDER) do
      local style = Addon.BACKGROUNDS[key]
      local info = UIDropDownMenu_CreateInfo()
      info.text = style.name
      info.arg1 = key
      info.value = key
      info.func = OnClick
      info.checked = Addon.GetBackgroundStyle() == key
      UIDropDownMenu_AddButton(info, level)
    end
  end

  UIDropDownMenu_Initialize(dropdown, Initialize)
  UpdateDropdownText()

  panel.refresh = function()
    UpdateDropdownText()
    UIDropDownMenu_Initialize(dropdown, Initialize)
    UpdateLangDropdownText()
    UIDropDownMenu_Initialize(langDropdown, InitializeLang)
    Addon.ApplyBackground(preview)
    local v = Addon.GetOpacity()
    slider:SetValue(v)
    _G[slider:GetName() .. "Text"]:SetText(Addon.LABELS.opacityLabel .. " (" .. math.floor(v * 100 + 0.5) .. "%)")
    if panel.integratedCheck then panel.integratedCheck:SetChecked(Addon.GetIntegratedLayout()) end
  end

  if Settings and Settings.RegisterAddOnCategory then
    if Settings.RegisterCanvasLayoutCategory then
      local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
      category.ID = panel.name
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
    else
      local category, layout = Settings.RegisterVerticalLayoutCategory(panel.name)
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
    end
  elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
  end

  return panel
end

function Addon.OpenSettings()
  if not Addon.settingsPanel then Addon.CreateSettingsPanel() end
  Addon.settingsPanel:Show()
  if Addon.settingsPanel.refresh then Addon.settingsPanel.refresh() end
  if Settings and Settings.OpenToCategory and Addon.settingsCategory then
    local id = Addon.settingsCategory.GetID and Addon.settingsCategory:GetID() or Addon.settingsCategory.ID
    if id then Settings.OpenToCategory(id) end
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(Addon.settingsPanel)
    InterfaceOptionsFrame_OpenToCategory(Addon.settingsPanel)
  end
end
