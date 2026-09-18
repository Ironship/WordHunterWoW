local Addon = WordHunterWoW_Addon

-- How wide the page draws, and how much room is left under the last control.
-- The width is a constant because the canvas this page lives in is one: no size
-- setting may widen it, so the page's letters grow downwards and never across.
-- The foot is there because the export button hangs off the bottom of a note
-- that wraps, so the deepest offset the layout knows about is not the deepest
-- thing on the page.
local BOX_WIDTH, BOX_FOOT = 600, 108

-- Why this page sizes its contents instead of scaling itself.
--
-- It was the one surface in the addon that no size setting reached. The others
-- are answered two ways -- the quest panel sizes its letters, the editor, list
-- and stats windows are SetScale'd whole -- and this page did neither, so with
-- every slider at the same number it came up at a size of its own.
--
-- Scaling it whole is the obvious move and it is wrong here twice over. The
-- frame is parented into Blizzard's options canvas, so it already carries that
-- canvas's effective scale, and SetScale multiplies with the parent rather than
-- replacing it: SetScale(1.5) would draw at 1.5 times whatever Blizzard is
-- drawing at, so the figure under the slider would mean one thing on this page
-- and another on every other, and it would move again whenever the player
-- touched the game's own UI Scale. Dividing the wanted size by the host's
-- GetEffectiveScale would fix the arithmetic and buy a worse fault: a frame
-- scaled up inside a fixed canvas keeps its screen rectangle, so the same
-- content is measured in smaller local units and the right-hand end of every
-- slider is clipped off the page.
--
-- So the page does what the quest panel does. Letters come from
-- Addon.FONT_ROLES, the one button from Addon.RoleButtonHeight, and every
-- vertical offset is multiplied by the same number -- because an offset that
-- stays where it was while the thing above it grows is an overlap, which is all
-- that sizing the letters on their own would have achieved.
--
-- Blizzard's own composites -- a dropdown, a tick box, a slider -- are drawn
-- from art and children this file does not own, so those are scaled rather than
-- re-fonted. That is safe precisely where scaling the page is not: their parent
-- is this addon's content frame, which is never scaled, so SetScale on one of
-- them is absolute. A slider is given back the width it had so that only its
-- height and its captions grow.
--
-- Which of the five sliders: the text family, "Quest panel text". This page has
-- no window of its own to grow, the two families are deliberately not the same
-- measurement, and a sixth slider for the options page would be a new setting
-- invented to answer a bug.
local function pageScale()
  local scale = Addon.GetTextScale and Addon.GetTextScale()
  if type(scale) ~= "number" or scale <= 0 then return 1 end
  return scale
end

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
  scroll:SetScrollChild(box)

  -- Where everything on the page sits at 100%, kept rather than applied once: a
  -- size chosen later has to be able to put the whole page down again, and the
  -- offsets are the half of that a re-font cannot do on its own.
  --
  -- Built as the controls are, so the two cannot drift. The alternative -- a
  -- second list of offsets written out by hand -- is the renumbering hazard the
  -- slider block already carries its own cursor to avoid.
  --
  -- `opts`: role, the font role one of this file's own strings is drawn at;
  -- own, a Blizzard composite that carries its own scale; button, one of this
  -- addon's own buttons, which grows in both directions; w and h, its size at
  -- 100%; wide, anchored to both edges so a line wraps to the page.
  local rows = {}
  panel.rows = rows
  -- Room for the controller box and its note, which layout() anchors under
  -- the harvest export rather than placing from this list.
  local GAMEPAD_DEPTH = 96
  local function place(frame, x, y, opts)
    opts = opts or {}
    opts.frame, opts.x, opts.y = frame, x, y
    rows[#rows + 1] = opts
    return frame
  end

  local layout
  layout = function()
    local scale = pageScale()
    local depth = 0
    for _, row in ipairs(rows) do
      local frame = row.frame
      frame:ClearAllPoints()
      if row.own then
        frame:SetScale(scale)
        -- Given back in the frame's own units, or the scale lands on the
        -- offsets a second time and the page pulls itself apart. x is divided
        -- for the same reason and is not scaled: it comes out where it always
        -- was.
        frame:SetPoint("TOPLEFT", row.x / scale, row.y)
        if row.w then frame:SetSize(row.w / scale, row.h or 0) end
      elseif row.button then
        -- Both directions, unlike the strings below: a caption drawn from
        -- Blizzard's own fixed button font needs the box around it to grow
        -- with the letters, or the words push out through the edges.
        frame:SetSize(180 * scale, Addon.RoleButtonHeight(scale))
        frame:SetPoint("TOPLEFT", row.x, row.y * scale)
        if frame.GetFontString then
          Addon.ApplyFontRole(frame:GetFontString(), "body", scale)
        end
      else
        if row.role then Addon.ApplyFontRole(frame, row.role, scale) end
        -- Horizontal offsets are left alone throughout. The page is as wide as
        -- Blizzard's canvas and nothing the player does can widen it, so
        -- spending that width on bigger margins is the one thing a size setting
        -- here must not do.
        frame:SetPoint("TOPLEFT", row.x, row.y * scale)
        if row.wide then frame:SetPoint("TOPRIGHT", -row.x, row.y * scale) end
        if row.w then frame:SetSize(row.w, (row.h or 0) * scale) end
      end
      depth = math.max(depth, -row.y + (row.h or 0))
    end

    -- The harvest export is anchored under a note that wraps rather than at an
    -- offset of its own, so it is placed here and not in the list above: where
    -- that note ends is not known until it has been drawn at this size. The
    -- difficult-word export is not in the same position -- its note is one line
    -- by construction, so it keeps the fixed offset its own test reads it at,
    -- and scales from the list like everything else there.
    local button = panel.harvestExport
    if button then
      button:SetSize(180 * scale, Addon.RoleButtonHeight(scale))
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", panel.harvestNote, "BOTTOMLEFT", 0, -8 * scale)
      if button.GetFontString then Addon.ApplyFontRole(button:GetFontString(), "body", scale) end
    end
    -- The controller box hangs under that button for the same reason, and its
    -- note under the box. Neither is in the list above, so the depth is told
    -- about them by hand: a box and four lines of small print at 100%.
    local pad = panel.gamepadCheck
    if pad and button then
      pad:SetScale(scale)
      pad:ClearAllPoints()
      pad:SetPoint("TOPLEFT", button, "BOTTOMLEFT", -4 / scale, -10 / scale)
      local padNote = panel.gamepadNote
      if padNote then
        Addon.ApplyFontRole(padNote, "meta", scale)
        padNote:ClearAllPoints()
        padNote:SetPoint("TOPLEFT", pad, "BOTTOMLEFT", 4 * scale, -2 * scale)
        padNote:SetPoint("RIGHT", box, "RIGHT", -16, 0)
      end
      depth = depth + GAMEPAD_DEPTH
    end

    -- The scroll box has to be tall enough to reach the last control or it
    -- cannot be scrolled to. Struck from where the controls actually landed
    -- rather than written down: the page changes length whenever a window or a
    -- note is added, and a literal height has to be corrected by hand every
    -- time -- silently, because nothing on screen says the bottom was cut off.
    box:SetSize(BOX_WIDTH, (depth + BOX_FOOT) * scale)
    if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
  end
  panel.layout = layout

  local title = place(box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"),
    16, -16, { role = "heading" })
  title:SetText(Addon.LABELS.settingsTitle)
  panel.title = title

  local subtitle = place(box:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall"),
    16, -36, { role = "meta" })
  subtitle:SetText("Choose a frame style. Text stays on an opaque reading surface in every theme.")
  subtitle:SetTextColor(0.7, 0.74, 0.8)

  -- Gold, like every other caption on this page, but pulled to the label
  -- role: this was the only surface drawing its captions at 12 where the
  -- other five draw them at 10. The role is applied by the layout above now
  -- rather than once here, so the caption follows the size setting the same
  -- way its neighbours do.
  local label = place(box:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
    16, -64, { role = "label" })
  label:SetText(Addon.LABELS.backgroundLabel)

  local dropdown = place(
    CreateFrame("Frame", "WordHunterWoWBackgroundDropdown", box, "UIDropDownMenuTemplate"),
    12, -84, { own = true })
  UIDropDownMenu_SetWidth(dropdown, 220)

  local preview = place(CreateFrame("Frame", nil, box, "BackdropTemplate"),
    16, -132, { own = true, w = 460, h = 86 })
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

  local opacityLabel = place(box:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
    16, -232, { role = "label" })
  opacityLabel:SetText(Addon.LABELS.opacityLabel)

  local slider = place(CreateFrame("Slider", "WordHunterWoWOpacitySlider", box, "OptionsSliderTemplate"),
    16, -252, { own = true, w = 460, h = 16 })
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

  local markLabel = place(box:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
    16, -285, { role = "label" })
  markLabel:SetText(Addon.LABELS.wordMarkingLabel)

  local markDropdown = place(
    CreateFrame("Frame", "WordHunterWoWWordMarkingDropdown", box, "UIDropDownMenuTemplate"),
    12, -305, { own = true })
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
    local fs = place(box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall"),
      16, y, { role = "meta", wide = true })
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
  -- One caption, the slider's own. There used to be a second FontString of this
  -- file's drawn twenty pixels above the bar as well, which is where the
  -- template already draws its label -- so every one of these read "Quest panel
  -- text" in yellow with "Quest panel text (18pt)" in white across it. The
  -- template's label is the one that has to stay, because it is the one
  -- captionFor and refresh redraw; the other only ever repeated it.
  local function sizeSlider(name, y, label, unit, get, set)
    local s = place(CreateFrame("Slider", name, box, "OptionsSliderTemplate"),
      16, y - 20, { own = true, w = 460, h = 16 })
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
      -- The page is one of the surfaces the text size governs, so it has to
      -- answer while the slider is still under the cursor. Run for all five
      -- rather than only the one that moves this page: the cost is one pass
      -- over a list, and a test for "was it the right slider" is a test of
      -- something nobody can see.
      layout()
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
    local heading = place(box:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge"),
      16, y, { role = "heading" })
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

  local langLabel = place(box:CreateFontString(nil, "ARTWORK", "GameFontNormal"),
    16, y, { role = "label" })
  langLabel:SetText(Addon.LABELS.languageLabel)

  local langDropdown = place(
    CreateFrame("Frame", "WordHunterWoWLanguageDropdown", box, "UIDropDownMenuTemplate"),
    12, y - 20, { own = true })
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

  local integrated = place(
    CreateFrame("CheckButton", "WordHunterWoWIntegratedCheck", box, "UICheckButtonTemplate"),
    12, y - 87, { own = true })
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
  local questLogAuto = place(
    CreateFrame("CheckButton", "WordHunterWoWQuestLogAutoCheck", box, "UICheckButtonTemplate"),
    12, y - 115, { own = true })
  local questLogAutoText = _G[questLogAuto:GetName() .. "Text"]
  if questLogAutoText then
    questLogAutoText:SetText(Addon.LABELS.questLogAutoLabel)
  end
  questLogAuto:SetChecked(Addon.GetQuestLogAutoOpen())
  questLogAuto:SetScript("OnClick", function(self)
    Addon.SetQuestLogAutoOpen(self:GetChecked())
  end)
  panel.questLogAutoCheck = questLogAuto

  -- Reading mode, beside the two boxes above: all three are about how the panel
  -- behaves rather than what it looks like. It also has a slash command, which
  -- is the one a player will actually use -- this box is here so somebody who
  -- has never read the command list can find out it exists.
  local reading = place(
    CreateFrame("CheckButton", "WordHunterWoWReadingCheck", box, "UICheckButtonTemplate"),
    12, y - 143, { own = true })
  local readingText = _G[reading:GetName() .. "Text"]
  if readingText then
    readingText:SetText(Addon.LABELS.readingLabel)
  end
  reading:SetChecked(Addon.GetReadingMode and Addon.GetReadingMode() or false)
  reading:SetScript("OnClick", function(self)
    if Addon.SetReadingMode then Addon.SetReadingMode(self:GetChecked()) end
  end)
  panel.readingCheck = reading

  -- The recall check, above the harvest box: both change what happens as you
  -- read, and this one changes it more visibly. Off out of the box, like the
  -- harvest, and for the same reason -- nobody who has not read about it
  -- should find their meanings behind a question.
  local recall = place(
    CreateFrame("CheckButton", "WordHunterWoWRecallCheck", box, "UICheckButtonTemplate"),
    12, y - 171, { own = true })
  local recallText = _G[recall:GetName() .. "Text"]
  if recallText then
    recallText:SetText(Addon.LABELS.recallLabel)
  end
  recall:SetChecked(Addon.GetRecallCheck and Addon.GetRecallCheck() or false)
  recall:SetScript("OnClick", function(self)
    if Addon.SetRecallCheck then Addon.SetRecallCheck(self:GetChecked()) end
  end)
  panel.recallCheck = recall

  -- The two thresholds the rating box feeds, under the box that switches it on.
  --
  -- Whole numbers of events, not a scale, so the slider steps by one and the
  -- caption carries the unit: a bare "20" beside "Call a word difficult after"
  -- could be read as a percentage, a score or a number of days.
  --
  -- One caption, and it is the slider's own. These first shipped with a second
  -- FontString of this file's above the bar as well, which put "Offer Ready for
  -- Known after" and "Offer Ready for Known after 5 quests" on top of each
  -- other -- OptionsSliderTemplate already draws a label above the bar, and it
  -- is the one that has to carry the figure, because it is the one refresh
  -- redraws. The extra line said the same thing, in a different colour, a few
  -- pixels away.
  local function countSlider(name, y, label, format, get, set, low, high)
    local s = place(CreateFrame("Slider", name, box, "OptionsSliderTemplate"),
      16, y - 20, { own = true, w = 460, h = 16 })
    s:SetMinMaxValues(low, high)
    s:SetValueStep(1)
    s:SetObeyStepOnDrag(true)
    s:SetValue(get())
    _G[s:GetName() .. "Low"]:SetText(tostring(low))
    _G[s:GetName() .. "High"]:SetText(tostring(high))
    -- Kept on the slider so refresh can redraw the figure: SetValue fires
    -- OnValueChanged only when the value moves, so a panel reopened on an
    -- unchanged setting would keep the caption it was built with.
    function s.captionFor(v)
      return label .. " " .. string.format(format, math.floor((tonumber(v) or low) + 0.5))
    end
    _G[s:GetName() .. "Text"]:SetText(s.captionFor(get()))
    s:SetScript("OnValueChanged", function(self, value)
      value = math.floor((tonumber(value) or low) + 0.5)
      set(value)
      _G[self:GetName() .. "Text"]:SetText(self.captionFor(value))
      -- The note under these counts difficult words, and the count is exactly
      -- what this slider changes. Left to the next panel refresh it read as a
      -- stale number for as long as the page stayed open.
      if panel.refreshDifficultNote then panel.refreshDifficultNote() end
    end)
    return s
  end

  panel.readySlider = countSlider("WordHunterWoWReadyAfterSlider", y - 197,
    Addon.LABELS.readyAfterLabel, Addon.LABELS.readyAfterValue,
    function() return Addon.GetReadyAfter and Addon.GetReadyAfter() or 5 end,
    function(v) if Addon.SetReadyAfter then Addon.SetReadyAfter(v) end end,
    Addon.RECALL_READY_MIN or 1, Addon.RECALL_READY_MAX or 40)

  panel.difficultSlider = countSlider("WordHunterWoWDifficultMinSlider", y - 243,
    Addon.LABELS.difficultMinLabel, Addon.LABELS.difficultMinValue,
    function() return Addon.GetDifficultMinRatings and Addon.GetDifficultMinRatings() or 5 end,
    function(v) if Addon.SetDifficultMinRatings then Addon.SetDifficultMinRatings(v) end end,
    Addon.RECALL_DIFFICULT_MIN or 3, Addon.RECALL_DIFFICULT_MAX or 40)

  -- One line, filled in by refresh. note() registers it for the layout, so the
  -- export button below can hang off its bottom edge rather than off an offset
  -- that would stop matching the moment the letters grew.
  local difficultNote = note(y - 289, "")
  panel.difficultNote = difficultNote

  -- Named so the sliders above can redraw just this line without running the
  -- whole page refresh, which would reset every slider under the cursor.
  panel.refreshDifficultNote = function()
    difficultNote:SetText(string.format(Addon.LABELS.difficultNote,
      Addon.CountDifficult and Addon.CountDifficult() or 0,
      Addon.GetDifficultMinRatings and Addon.GetDifficultMinRatings() or 5))
  end

  -- The same shape as the harvest export below: the list goes into the copy
  -- box, and an empty list says so in a dialog with nothing to confirm.
  local difficultExport = place(
    Addon.createActionButton(box, Addon.LABELS.difficultExport),
    16, y - 307, { button = true, h = Addon.RoleButtonHeight(1) })
  difficultExport:SetScript("OnClick", function()
    local text = Addon.BuildDifficultExport and Addon.BuildDifficultExport() or ""
    if type(text) ~= "string" or text == "" then
      Addon.showConfirm(Addon.LABELS.difficultExport,
        string.format(Addon.LABELS.difficultExportEmpty,
          Addon.GetDifficultMinRatings and Addon.GetDifficultMinRatings() or 5),
        nil, nil, panel)
      return
    end
    Addon.showCopyText(Addon.LABELS.difficultExport, text, Addon.LABELS.difficultExportHint, panel)
  end)
  panel.difficultExport = difficultExport

  local harvest = place(
    CreateFrame("CheckButton", "WordHunterWoWHarvestCheck", box, "UICheckButtonTemplate"),
    12, y - 347, { own = true })
  local harvestText = _G[harvest:GetName() .. "Text"]
  if harvestText then
    harvestText:SetText(Addon.LABELS.harvestLabel)
  end
  harvest:SetChecked(Addon.GetHarvestEnabled())
  harvest:SetScript("OnClick", function(self)
    Addon.SetHarvestEnabled(self:GetChecked())
  end)
  panel.harvestCheck = harvest

  local harvestNote = note(y - 371, "")
  panel.harvestNote = harvestNote

  -- The slash command did this already, but only someone who read the addon's
  -- description knew it existed. Anyone who switches the box on can now find
  -- the way to get the text back out without being told.
  -- Sized and anchored by the layout above -- under the note rather than at a
  -- fixed offset, so it follows however many lines the note wraps to. Its
  -- height used to be written here as 24, which is a fourth button height in an
  -- addon that draws one; Addon.RoleButtonHeight is the one.
  local harvestExport = Addon.createActionButton(box, Addon.LABELS.harvestExport)
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

  -- The controller. Anchored in layout() rather than placed at an offset, for
  -- the same reason the export above is: where the export lands depends on how
  -- the harvest note wrapped, and that is not known until it has been drawn.
  local gamepad = CreateFrame("CheckButton", "WordHunterWoWGamepadCheck", box, "UICheckButtonTemplate")
  local gamepadText = _G[gamepad:GetName() .. "Text"]
  if gamepadText then
    gamepadText:SetText(Addon.LABELS.gamepadLabel)
  end
  gamepad:SetChecked(Addon.GetGamePadEnabled and Addon.GetGamePadEnabled() or false)
  gamepad:SetScript("OnClick", function(self)
    if Addon.SetGamePadEnabled then Addon.SetGamePadEnabled(self:GetChecked()) end
  end)
  panel.gamepadCheck = gamepad

  local gamepadNote = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  gamepadNote:SetJustifyH("LEFT")
  gamepadNote:SetWordWrap(true)
  gamepadNote:SetTextColor(0.8, 0.82, 0.88)
  gamepadNote:SetText(Addon.LABELS.gamepadNote)
  panel.gamepadNote = gamepadNote

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
    if panel.gamepadCheck then
      panel.gamepadCheck:SetChecked(Addon.GetGamePadEnabled and Addon.GetGamePadEnabled() or false)
    end
    if panel.recallCheck then panel.recallCheck:SetChecked(Addon.GetRecallCheck and Addon.GetRecallCheck() or false) end
    if panel.readingCheck then panel.readingCheck:SetChecked(Addon.GetReadingMode and Addon.GetReadingMode() or false) end
    for _, s in ipairs({ panel.readySlider, panel.difficultSlider }) do
      local get = s == panel.readySlider and Addon.GetReadyAfter or Addon.GetDifficultMinRatings
      if get then
        s:SetValue(get())
        _G[s:GetName() .. "Text"]:SetText(s.captionFor(get()))
      end
    end
    if panel.refreshDifficultNote then panel.refreshDifficultNote() end
    if panel.harvestNote then
      local passages = Addon.HarvestCount and (Addon.HarvestCount() - Addon.HarvestWordCount()) or 0
      panel.harvestNote:SetText(string.format(Addon.LABELS.harvestNote, passages, Addon.HarvestWordCount and Addon.HarvestWordCount() or 0))
    end
    -- Last, and from here rather than only from the slider: Blizzard's own route
    -- into this page never touches the controls, and /whw reset changes the size
    -- with the page closed. Either way the page has to catch up when it opens.
    layout()
  end

  -- The page is built at whatever size is already stored, not at 100% and
  -- corrected on the first show. A frame that has never been laid out has no
  -- size of its own, so the scroll box would have nothing to measure.
  layout()

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
      -- The category's ID is the client's, and a number. This used to overwrite
      -- it with panel.name so that the read below had something to find -- which
      -- broke the read it was serving: Settings.OpenToCategory takes that
      -- number, a string opens nothing, and /whw options quietly did nothing at
      -- all. Writing into a table Blizzard created taints it as well.
      --
      -- The fallback it was there for is kept, in this addon's own table where
      -- it belongs, for a client whose category answers neither GetID nor ID.
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
      Addon.settingsCategoryName = panel.name
    else
      local category, layout = Settings.RegisterVerticalLayoutCategory(panel.name)
      Settings.RegisterAddOnCategory(category)
      Addon.settingsCategory = category
      Addon.settingsCategoryName = panel.name
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
    local id = Addon.settingsCategory.GetID and Addon.settingsCategory:GetID()
      or Addon.settingsCategory.ID
      or Addon.settingsCategoryName
    if id then Settings.OpenToCategory(id) end
  elseif InterfaceOptionsFrame_OpenToCategory then
    InterfaceOptionsFrame_OpenToCategory(Addon.settingsPanel)
    InterfaceOptionsFrame_OpenToCategory(Addon.settingsPanel)
  end
end
