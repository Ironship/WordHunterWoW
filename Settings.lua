local Addon = WordHunterWoW_Addon

function Addon.CreateSettingsPanel()
  if Addon.settingsPanel then return Addon.settingsPanel end

  -- The frame Blizzard parents into the Options canvas. It must be this one —
  -- wrapping it in another host left the canvas blank on Retail.
  local panel = CreateFrame("Frame", "WordHunterWoWSettingsPanel")
  panel.name = "WordHunterWoW"
  Addon.settingsPanel = panel

  local scroll = CreateFrame("ScrollFrame", "WordHunterWoWSettingsScroll", panel, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -26, 4)

  local box = CreateFrame("Frame", "WordHunterWoWSettingsContent", scroll)
  box:SetSize(600, 1060)
  scroll:SetScrollChild(box)

  local title = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText(Addon.LABELS.settingsTitle)

  local subtitle = box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", 16, -36)
  subtitle:SetText("Choose a frame style. Text stays on an opaque reading surface in every theme.")
  subtitle:SetTextColor(0.7, 0.74, 0.8)

  -- Gold, like every other caption on this page, but pulled to the label
  -- role: this was the only surface drawing its captions at 12 where the
  -- other five draw them at 10. The page itself is never scaled, so this
  -- is the whole of what it had to answer for.
  local label = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  Addon.ApplyFontRole(label, "label")
  label:SetPoint("TOPLEFT", 16, -64)
  label:SetText(Addon.LABELS.backgroundLabel)

  local dropdown = CreateFrame("Frame", "WordHunterWoWBackgroundDropdown", box, "UIDropDownMenuTemplate")
  dropdown:SetPoint("TOPLEFT", 12, -84)
  UIDropDownMenu_SetWidth(dropdown, 220)

  local preview = CreateFrame("Frame", nil, box, "BackdropTemplate")
  preview:SetSize(460, 86)
  preview:SetPoint("TOPLEFT", 16, -132)
  panel.preview = preview
  local previewLabel = preview:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  previewLabel:SetPoint("TOPLEFT", 12, -10)
  previewLabel:SetText("Preview")
  previewLabel:SetTextColor(0.35, 0.68, 1)
  local previewText = preview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  previewText:SetPoint("CENTER", 0, -6)
  previewText:SetText(Addon.ColorHex("text") .. "Quest text  •  " .. Addon.ColorHex("enHighlight")
    .. "Matching sentence  •  " .. Addon.ColorHex("enWordHighlight") .. "Word|r")
  Addon.ApplyBackground(preview)

  local opacityLabel = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  Addon.ApplyFontRole(opacityLabel, "label")
  opacityLabel:SetPoint("TOPLEFT", 16, -232)
  opacityLabel:SetText(Addon.LABELS.opacityLabel)

  local slider = CreateFrame("Slider", "WordHunterWoWOpacitySlider", box, "OptionsSliderTemplate")
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

  local markLabel = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  Addon.ApplyFontRole(markLabel, "label")
  markLabel:SetPoint("TOPLEFT", 16, -285)
  markLabel:SetText(Addon.LABELS.wordMarkingLabel)

  local markDropdown = CreateFrame("Frame", "WordHunterWoWWordMarkingDropdown", box, "UIDropDownMenuTemplate")
  markDropdown:SetPoint("TOPLEFT", 12, -305)
  UIDropDownMenu_SetWidth(markDropdown, 220)

  local function UpdateMarkText()
    local mark = Addon.WORD_MARKINGS[Addon.GetWordMarking()]
    UIDropDownMenu_SetText(markDropdown, mark and mark.name or "")
  end

  local function OnMarkClick(self, arg1)
    local key = arg1 or self.arg1 or self.value
    if not Addon.WORD_MARKINGS[key] then return end
    UIDropDownMenu_SetText(markDropdown, Addon.WORD_MARKINGS[key].name)
    Addon.SetWordMarking(key)
  end

  local function InitializeMark(self, level)
    level = level or 1
    for _, key in ipairs(Addon.WORD_MARKING_ORDER) do
      local info = UIDropDownMenu_CreateInfo()
      info.text = Addon.WORD_MARKINGS[key].name
      info.arg1 = key
      info.value = key
      info.func = OnMarkClick
      info.checked = Addon.GetWordMarking() == key
      UIDropDownMenu_AddButton(info, level)
    end
  end

  UIDropDownMenu_Initialize(markDropdown, InitializeMark)
  UpdateMarkText()

  -- A wrapped line of small print under a control. Anchored on both sides so it
  -- wraps to the panel rather than running off it.
  local function note(y, text)
    local fs = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    fs:SetPoint("TOPLEFT", 16, y)
    fs:SetPoint("TOPRIGHT", -16, y)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(true)
    fs:SetTextColor(0.8, 0.82, 0.88)
    fs:SetText(text)
    return fs
  end

  -- The unit belongs to the group, not the slider, and it is the whole point of
  -- the split: a text size reads "18pt" and a window size reads "150%", so the
  -- two cannot be read as the same promise about what the screen will look
  -- like. Addon.SIZE_GROUPS carries the argument.
  local function sizeSlider(name, y, label, unit, get, set)
    local caption = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    Addon.ApplyFontRole(caption, "label")
    caption:SetPoint("TOPLEFT", 16, y)
    caption:SetText(label)
    local s = CreateFrame("Slider", name, box, "OptionsSliderTemplate")
    s:SetPoint("TOPLEFT", 16, y - 20)
    s:SetSize(460, 16)
    s:SetMinMaxValues(Addon.TEXT_SCALE_MIN, Addon.TEXT_SCALE_MAX)
    s:SetValueStep(0.05)
    s:SetObeyStepOnDrag(true)
    s:SetValue(get())
    _G[s:GetName() .. "Low"]:SetText(Addon.FormatSizeValue(unit, Addon.TEXT_SCALE_MIN))
    _G[s:GetName() .. "High"]:SetText(Addon.FormatSizeValue(unit, Addon.TEXT_SCALE_MAX))
    -- Kept on the slider so refresh can redraw the figure too. SetValue only
    -- fires OnValueChanged when the value actually moves, so a panel reopened
    -- on an unchanged setting was showing the caption it was built with.
    function s.captionFor(v) return label .. " (" .. Addon.FormatSizeValue(unit, v) .. ")" end
    _G[s:GetName() .. "Text"]:SetText(s.captionFor(get()))
    s:SetScript("OnValueChanged", function(self, value)
      value = math.floor(value * 20 + 0.5) / 20
      set(value)
      _G[self:GetName() .. "Text"]:SetText(self.captionFor(value))
    end)
    return s
  end

  -- Every size slider, generated from the same table that says which family a
  -- key belongs to, so a window cannot be added to the addon and left without a
  -- control -- and so it cannot land in the wrong group either.
  --
  -- Laid out by carrying an offset down the section rather than at hand-written
  -- ones: this block changes length whenever a window or a note is added, and
  -- everything below it used to have to be renumbered by hand to match.
  panel.sizeSliders = {}
  local y = -348
  for _, group in ipairs(Addon.SIZE_GROUPS) do
    -- Larger than the slider captions under it. A heading in the same font as
    -- the things it governs is not a heading, and the split only works if the
    -- eye takes in "these are two lists" before it reads any number.
    local heading = box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    heading:SetPoint("TOPLEFT", 16, y)
    heading:SetText(Addon.LABELS[group.heading])
    note(y - 22, Addon.LABELS[group.note])
    y = y - 58
    for _, entry in ipairs(group.entries) do
      local suffix = entry.key:sub(1, 1):upper() .. entry.key:sub(2)
      panel.sizeSliders[entry.key] = sizeSlider("WordHunterWoW" .. suffix .. "Slider",
        y, Addon.LABELS[entry.label], group.unit, Addon["Get" .. suffix], Addon["Set" .. suffix])
      y = y - 53
      if entry.note then
        note(y, Addon.LABELS[entry.note])
        y = y - 28
      end
    end
    y = y - 14
  end

  local langLabel = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  Addon.ApplyFontRole(langLabel, "label")
  langLabel:SetPoint("TOPLEFT", 16, y)
  langLabel:SetText(Addon.LABELS.languageLabel)

  local langDropdown = CreateFrame("Frame", "WordHunterWoWLanguageDropdown", box, "UIDropDownMenuTemplate")
  langDropdown:SetPoint("TOPLEFT", 12, y - 20)
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

  note(y - 57, "Required — words are stored separately per language. English US/GB both export as 'en'.")

  local integrated = CreateFrame("CheckButton", "WordHunterWoWIntegratedCheck", box, "UICheckButtonTemplate")
  integrated:SetPoint("TOPLEFT", 12, y - 87)
  local integratedText = _G[integrated:GetName() .. "Text"]
  if integratedText then
    integratedText:SetText(Addon.LABELS.integratedLabel)
  end
  integrated:SetChecked(Addon.GetIntegratedLayout())
  integrated:SetScript("OnClick", function(self)
    Addon.SetIntegratedLayout(self:GetChecked())
  end)
  panel.integratedCheck = integrated

  -- Next to the layout box rather than down among the sliders: both are about
  -- how the panel behaves rather than what it looks like. This one is off out
  -- of the box, which is the change it exists to undo -- the panel opening
  -- itself from the quest log put it over the quest that had just been clicked.
  local questLogAuto = CreateFrame("CheckButton", "WordHunterWoWQuestLogAutoCheck", box, "UICheckButtonTemplate")
  questLogAuto:SetPoint("TOPLEFT", 12, y - 115)
  local questLogAutoText = _G[questLogAuto:GetName() .. "Text"]
  if questLogAutoText then
    questLogAutoText:SetText(Addon.LABELS.questLogAutoLabel)
  end
  questLogAuto:SetChecked(Addon.GetQuestLogAutoOpen())
  questLogAuto:SetScript("OnClick", function(self)
    Addon.SetQuestLogAutoOpen(self:GetChecked())
  end)
  panel.questLogAutoCheck = questLogAuto

  local harvest = CreateFrame("CheckButton", "WordHunterWoWHarvestCheck", box, "UICheckButtonTemplate")
  harvest:SetPoint("TOPLEFT", 12, y - 143)
  local harvestText = _G[harvest:GetName() .. "Text"]
  if harvestText then
    harvestText:SetText(Addon.LABELS.harvestLabel)
  end
  harvest:SetChecked(Addon.GetHarvestEnabled())
  harvest:SetScript("OnClick", function(self)
    Addon.SetHarvestEnabled(self:GetChecked())
  end)
  panel.harvestCheck = harvest

  local harvestNote = note(y - 167, "")
  panel.harvestNote = harvestNote

  -- The slash command did this already, but only someone who read the addon's
  -- description knew it existed. Anyone who switches the box on can now find
  -- the way to get the text back out without being told.
  local harvestExport = Addon.createActionButton(box, Addon.LABELS.harvestExport)
  harvestExport:SetSize(180, 24)
  -- Anchored under the note rather than at a fixed offset, so it follows however
  -- many lines the note wraps to.
  harvestExport:SetPoint("TOPLEFT", harvestNote, "BOTTOMLEFT", 0, -8)
  harvestExport:SetScript("OnClick", function()
    if Addon.rebuildHarvestExport then Addon.rebuildHarvestExport() end
    local blob = WordHunterWoWCorpusExport
    -- A previous export this session already moved the live table into the blob.
    -- Showing "nothing collected" would lie; offer the blob again.
    if type(blob) ~= "string" or blob == "" then
      -- Nothing to confirm, so no action text: showConfirm drops its action
      -- button and the dialog closes on Cancel alone.
      Addon.showConfirm(Addon.LABELS.harvestExport, Addon.LABELS.harvestExportEmpty, nil, nil, panel)
      return
    end
    Addon.showCopyText(Addon.LABELS.harvestExport, blob, Addon.LABELS.harvestExportHint, panel)
    if panel.refresh then panel.refresh() end
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
    for key, slider in pairs(panel.sizeSliders or {}) do
      local get = Addon["Get" .. key:sub(1, 1):upper() .. key:sub(2)]
      if get then
        slider:SetValue(get())
        -- And the figure, which SetValue does not touch when the value it is
        -- given is the one the slider already holds.
        _G[slider:GetName() .. "Text"]:SetText(slider.captionFor(get()))
      end
    end
    UpdateDropdownText()
    UIDropDownMenu_Initialize(dropdown, Initialize)
    UpdateMarkText()
    UIDropDownMenu_Initialize(markDropdown, InitializeMark)
    UpdateLangDropdownText()
    UIDropDownMenu_Initialize(langDropdown, InitializeLang)
    Addon.ApplyBackground(preview)
    local v = Addon.GetOpacity()
    slider:SetValue(v)
    _G[slider:GetName() .. "Text"]:SetText(Addon.LABELS.opacityLabel .. " (" .. math.floor(v * 100 + 0.5) .. "%)")
    if panel.integratedCheck then panel.integratedCheck:SetChecked(Addon.GetIntegratedLayout()) end
    if panel.questLogAutoCheck then panel.questLogAutoCheck:SetChecked(Addon.GetQuestLogAutoOpen()) end
    if panel.harvestCheck then panel.harvestCheck:SetChecked(Addon.GetHarvestEnabled()) end
    if panel.harvestNote then
      local passages = Addon.HarvestCount and (Addon.HarvestCount() - Addon.HarvestWordCount()) or 0
      panel.harvestNote:SetText(string.format(Addon.LABELS.harvestNote, passages, Addon.HarvestWordCount and Addon.HarvestWordCount() or 0))
    end
  end

  -- Blizzard's own route into this panel -- Esc, Options, AddOns -- never calls
  -- OpenSettings, so nothing refreshed the controls and they showed whatever
  -- was true the last time the addon opened it itself.
  panel:HookScript("OnShow", function(self)
    if self.refresh then self.refresh() end
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
  end)

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
