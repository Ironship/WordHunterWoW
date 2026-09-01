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

  local scaleLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  scaleLabel:SetPoint("TOPLEFT", 16, -285)
  scaleLabel:SetText(Addon.LABELS.textScaleLabel)

  local scale = CreateFrame("Slider", "WordHunterWoWTextScaleSlider", panel, "OptionsSliderTemplate")
  scale:SetPoint("TOPLEFT", 16, -305)
  scale:SetSize(460, 16)
  scale:SetMinMaxValues(Addon.TEXT_SCALE_MIN, Addon.TEXT_SCALE_MAX)
  scale:SetValueStep(0.05)
  scale:SetObeyStepOnDrag(true)
  scale:SetValue(Addon.GetTextScale())
  _G[scale:GetName() .. "Low"]:SetText(string.format("%d%%", Addon.TEXT_SCALE_MIN * 100))
  _G[scale:GetName() .. "High"]:SetText(string.format("%d%%", Addon.TEXT_SCALE_MAX * 100))
  local function scaleText(v)
    return Addon.LABELS.textScaleLabel .. string.format(" (%d%%)", v * 100 + 0.5)
  end
  _G[scale:GetName() .. "Text"]:SetText(scaleText(Addon.GetTextScale()))
  scale:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value * 20 + 0.5) / 20
    Addon.SetTextScale(value)
    _G[self:GetName() .. "Text"]:SetText(scaleText(value))
  end)
  panel.textScaleSlider = scale

  -- One slider per surface rather than one for everything: the quest panel can
  -- grow its rows to match, while the editor and the list sit on frames with
  -- fixed heights and have less room before the text collides. A single slider
  -- would have to be set for the tightest of them.
  local function sizeSlider(name, y, label, get, set)
    local caption = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    caption:SetPoint("TOPLEFT", 16, y)
    caption:SetText(label)
    local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 16, y - 20)
    s:SetSize(460, 16)
    s:SetMinMaxValues(Addon.TEXT_SCALE_MIN, Addon.TEXT_SCALE_MAX)
    s:SetValueStep(0.05)
    s:SetObeyStepOnDrag(true)
    s:SetValue(get())
    _G[s:GetName() .. "Low"]:SetText(string.format("%d%%", Addon.TEXT_SCALE_MIN * 100))
    _G[s:GetName() .. "High"]:SetText(string.format("%d%%", Addon.TEXT_SCALE_MAX * 100))
    local function caption_for(v) return label .. string.format(" (%d%%)", v * 100 + 0.5) end
    _G[s:GetName() .. "Text"]:SetText(caption_for(get()))
    s:SetScript("OnValueChanged", function(self, value)
      value = math.floor(value * 20 + 0.5) / 20
      set(value)
      _G[self:GetName() .. "Text"]:SetText(caption_for(value))
    end)
    return s
  end

  -- One slider per window, generated from the same table the scaling reads, so
  -- adding a window in one place cannot leave it without a control here.
  panel.windowSliders = {}
  local y = -338
  for _, w in ipairs(Addon.SCALED_WINDOWS) do
    local name = "WordHunterWoW" .. w.key:sub(1, 1):upper() .. w.key:sub(2) .. "Slider"
    local getter = Addon["Get" .. w.key:sub(1, 1):upper() .. w.key:sub(2)]
    local setter = Addon["Set" .. w.key:sub(1, 1):upper() .. w.key:sub(2)]
    panel.windowSliders[w.key] = sizeSlider(name, y, Addon.LABELS[w.label], getter, setter)
    y = y - 53
  end

  local langLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  langLabel:SetPoint("TOPLEFT", 16, -550)
  langLabel:SetText(Addon.LABELS.languageLabel)

  local langDropdown = CreateFrame("Frame", "WordHunterWoWLanguageDropdown", panel, "UIDropDownMenuTemplate")
  langDropdown:SetPoint("TOPLEFT", 12, -570)
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
  langNote:SetPoint("TOPLEFT", 16, -607)
  langNote:SetPoint("TOPRIGHT", -16, -607)
  langNote:SetJustifyH("LEFT")
  langNote:SetWordWrap(true)
  langNote:SetText("Required — words are stored separately per language. English US/GB both export as 'en'.")
  langNote:SetTextColor(0.8, 0.82, 0.88)

  local integrated = CreateFrame("CheckButton", "WordHunterWoWIntegratedCheck", panel, "UICheckButtonTemplate")
  integrated:SetPoint("TOPLEFT", 12, -637)
  local integratedText = _G[integrated:GetName() .. "Text"]
  if integratedText then
    integratedText:SetText(Addon.LABELS.integratedLabel)
  end
  integrated:SetChecked(Addon.GetIntegratedLayout())
  integrated:SetScript("OnClick", function(self)
    Addon.SetIntegratedLayout(self:GetChecked())
  end)
  panel.integratedCheck = integrated

  local harvest = CreateFrame("CheckButton", "WordHunterWoWHarvestCheck", panel, "UICheckButtonTemplate")
  harvest:SetPoint("TOPLEFT", 12, -665)
  local harvestText = _G[harvest:GetName() .. "Text"]
  if harvestText then
    harvestText:SetText(Addon.LABELS.harvestLabel)
  end
  harvest:SetChecked(Addon.GetHarvestEnabled())
  harvest:SetScript("OnClick", function(self)
    Addon.SetHarvestEnabled(self:GetChecked())
  end)
  panel.harvestCheck = harvest

  local harvestNote = panel:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  harvestNote:SetPoint("TOPLEFT", 16, -689)
  harvestNote:SetPoint("TOPRIGHT", -16, -689)
  harvestNote:SetJustifyH("LEFT")
  harvestNote:SetWordWrap(true)
  harvestNote:SetTextColor(0.8, 0.82, 0.88)
  panel.harvestNote = harvestNote

  -- The slash command did this already, but only someone who read the addon's
  -- description knew it existed. Anyone who switches the box on can now find
  -- the way to get the text back out without being told.
  local harvestExport = Addon.createActionButton(panel, Addon.LABELS.harvestExport)
  harvestExport:SetSize(180, 24)
  -- Anchored under the note rather than at a fixed offset, so it follows however
  -- many lines the note wraps to.
  harvestExport:SetPoint("TOPLEFT", harvestNote, "BOTTOMLEFT", 0, -8)
  harvestExport:SetScript("OnClick", function()
    local written = Addon.rebuildHarvestExport and Addon.rebuildHarvestExport() or 0
    if written <= 0 then
      Addon.showConfirm(Addon.LABELS.harvestExport, Addon.LABELS.harvestExportEmpty,
        Addon.LABELS.confirmCancel, nil)
      return
    end
    local words = Addon.HarvestWordCount and Addon.HarvestWordCount() or 0
    Addon.showConfirm(Addon.LABELS.harvestExport,
      string.format(Addon.LABELS.harvestExportBody, written - words, words),
      Addon.LABELS.harvestExportReload,
      function() if ReloadUI then ReloadUI() end end,
      Addon.HarvestExportPath and Addon.HarvestExportPath() or nil)
  end)
  panel.harvestExport = harvestExport

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
    if panel.harvestCheck then panel.harvestCheck:SetChecked(Addon.GetHarvestEnabled()) end
    if panel.harvestNote then
      local passages = Addon.HarvestCount and (Addon.HarvestCount() - Addon.HarvestWordCount()) or 0
      panel.harvestNote:SetText(string.format(Addon.LABELS.harvestNote, passages, Addon.HarvestWordCount and Addon.HarvestWordCount() or 0))
    end
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
