local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local STATUS_LABELS = Addon.STATUS_LABELS
local LABELS = Addon.LABELS

local editor

local function updateStatusButtons()
  for status, button in pairs(editor.statusButtons) do
    local color = COLORS[status]
    Addon.styleFlatButton(button, color, Addon.selected.status == status)
  end
end

local function updateEditorHistory()
  if not editor or not Addon.selected or not Addon.selected.firstSeenAt then
    if editor and editor.history then editor.history:SetText("") end
    return
  end
  local selected = Addon.selected
  local history = string.format(
    "First added: %s  •  Last seen: %s\n%d quests  •  Status changed: %s",
    date("%Y-%m-%d", selected.firstSeenAt),
    date("%Y-%m-%d", selected.lastSeenAt or selected.firstSeenAt),
    selected.encounterCount or 0,
    date("%Y-%m-%d", selected.statusChangedAt or selected.firstSeenAt)
  )
  local learningSince = selected.status == selected.originalStatus
    and (selected.statusChangedAt or selected.firstSeenAt)
    or time()
  local ready = selected.status == "learning"
    and (selected.encounterCount or 0) >= 5
    and time() - learningSince >= 14 * 24 * 60 * 60
  editor.history:SetText(ready and (history .. "  •  " .. LABELS.readyForKnown) or history)
  if ready then editor.history:SetTextColor(0.30, 0.88, 0.48) else editor.history:SetTextColor(0.62, 0.66, 0.72) end
end

function Addon.openEditor(word, context, questId, questTitle)
  local key = Addon.wordKey(word)
  if key == "" then return end
  local entry = Addon.GetEffectiveWord(key)
  local dictionaryEntry = Addon.GetDictionaryEntry(key)
  Addon.selected = {
    key = key,
    word = entry and entry.word or word,
    status = entry and entry.status or "learning",
    context = context,
    questId = tostring(questId or ""),
    questTitle = questTitle or "",
    firstSeenAt = entry and (entry.firstSeenAt or entry.updatedAt),
    lastSeenAt = entry and (entry.lastSeenAt or entry.updatedAt),
    encounterCount = entry and entry.encounterCount or 0,
    statusChangedAt = entry and (entry.statusChangedAt or entry.updatedAt),
    originalStatus = entry and entry.status or "learning",
    dictionaryEntry = dictionaryEntry,
  }
  local selected = Addon.selected
  editor.word:SetText(selected.word)
  editor.context:SetText(context)
  editor.translation:SetText(entry and entry.translation or "")
  editor.note:SetText(entry and entry.note or "")
  Addon.updateResetDictionary()
  updateEditorHistory()
  editor.translation:SetFocus()
  editor.translation:HighlightText()
  updateStatusButtons()
  Addon.PlaceFrame(editor, "editor")
  editor:Show()
  editor:Raise()
end

local function saveSelected()
  if not Addon.selected then return end
  local now = time()
  local selected = Addon.selected
  local key = selected.key
  local entry = Addon.GetWordsTable()[key]
  if not entry then
    entry = { word = selected.word }
    Addon.GetWordsTable()[key] = entry
  end
  local statusChangedAt = entry.statusChangedAt or now
  if entry.status ~= selected.status then statusChangedAt = now end
  local note = Addon.trim(editor.note:GetText())
  local noteUpdatedAt = entry.noteUpdatedAt or 0
  if note ~= (entry.note or "") then noteUpdatedAt = now end
  entry.status = selected.status
  entry.statusChangedAt = statusChangedAt
  entry.translation = Addon.trim(editor.translation:GetText())
  entry.note = note
  entry.noteUpdatedAt = noteUpdatedAt
  entry.context = selected.context
  entry.questId = selected.questId
  entry.questTitle = selected.questTitle
  entry.updatedAt = now
  Addon.ensureHeadwordDefaults(entry, now)
  Addon.recordEncounter(entry, selected.questId, selected.questTitle, now)
  Addon.rebuildExport()
  editor:Hide()
  Addon.refreshPanel()
  Addon.refreshWordList()
end

function Addon.createEditor()
  editor = CreateFrame("Frame", "WordHunterWoWEditor", UIParent, "BackdropTemplate")
  Addon.editor = editor
  editor:SetSize(420, 380)
  editor:SetFrameStrata("FULLSCREEN_DIALOG")
  editor:SetFrameLevel(30)
  editor:SetClampedToScreen(true)
  editor:EnableMouse(true)
  editor:SetMovable(true)
  editor:RegisterForDrag("LeftButton")
  editor:SetScript("OnDragStart", editor.StartMoving)
  editor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Addon.SaveFramePosition(self, Addon.LayoutKey("editor"))
  end)
  Addon.setBackdrop(editor, 1)
  Addon.SetupEscapeClose(editor)
  Addon.MakeResizable(editor, "editor", 420, 380, 650, 750)
  Addon.PlaceFrame(editor, "editor")
  editor:Hide()

  editor.word = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  editor.word:SetPoint("TOPLEFT", 20, -40)
  editor.word:SetPoint("TOPRIGHT", -20, -40)
  editor.word:SetHeight(22)
  editor.word:SetJustifyH("LEFT")

  editor.context = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  editor.context:SetPoint("TOPLEFT", 20, -66)
  editor.context:SetPoint("TOPRIGHT", -20, -66)
  editor.context:SetHeight(26)
  editor.context:SetJustifyH("LEFT")
  editor.context:SetJustifyV("TOP")
  editor.context:SetWordWrap(true)
  editor.context:SetMaxLines(2)

  editor.history = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  editor.history:SetPoint("TOPLEFT", 20, -96)
  editor.history:SetPoint("TOPRIGHT", -20, -96)
  editor.history:SetHeight(30)
  editor.history:SetJustifyH("LEFT")
  editor.history:SetJustifyV("TOP")
  editor.history:SetWordWrap(true)
  editor.history:SetMaxLines(2)

  local meaning = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  meaning:SetPoint("TOPLEFT", 20, -132)
  meaning:SetText(LABELS.meaning)
  editor.translation = Addon.createEditBox(editor)
  editor.translation:SetPoint("TOPLEFT", 20, -148)
  editor.translation:SetPoint("TOPRIGHT", -20, -148)
  editor.translation:SetScript("OnEnterPressed", saveSelected)
  editor.translation:SetScript("OnEscapePressed", function() Addon.CloseAll() end)

  local note = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  note:SetPoint("TOPLEFT", 20, -182)
  note:SetText(LABELS.note)
  editor.noteScroll = CreateFrame("ScrollFrame", nil, editor, "InputScrollFrameTemplate")
  editor.noteScroll:SetPoint("TOPLEFT", 20, -198)
  editor.noteScroll:SetPoint("TOPRIGHT", -20, -198)
  editor.noteScroll:SetHeight(48)
  editor.noteScroll.hideCharCount = true
  InputScrollFrame_OnLoad(editor.noteScroll)
  editor.note = editor.noteScroll.EditBox
  editor.note:SetFontObject("ChatFontNormal")
  editor.note:SetAutoFocus(false)
  editor.note:SetMultiLine(true)
  editor.note:SetMaxLetters(1000)
  editor.note:SetScript("OnEscapePressed", function() Addon.CloseAll() end)

  local statusLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusLabel:SetPoint("TOPLEFT", 20, -262)
  statusLabel:SetText(LABELS.status)
  editor.statusButtons = {}
  local statuses = { "new", "learning", "known", "ignored" }
  for index, status in ipairs(statuses) do
    local button = Addon.createFlatButton(editor, STATUS_LABELS[status], COLORS[status])
    button:SetSize(89, 26)
    button:SetPoint("TOPLEFT", 20 + (index - 1) * 95, -278)
    button.status = status
    button:SetScript("OnClick", function(self)
      Addon.selected.status = self.status
      updateStatusButtons()
      updateEditorHistory()
    end)
    editor.statusButtons[status] = button
  end

  local save = Addon.createActionButton(editor, LABELS.save)
  save:SetSize(112, 30)
  save:SetPoint("BOTTOMRIGHT", -20, 20)
  save:SetScript("OnClick", saveSelected)
  local cancel = Addon.createActionButton(editor, LABELS.cancel)
  cancel:SetSize(112, 30)
  cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function() editor:Hide() end)
  local copyWord = Addon.createActionButton(editor, LABELS.copyWord)
  copyWord:SetSize(110, 30)
  copyWord:SetPoint("BOTTOMLEFT", 20, 20)
  copyWord:SetScript("OnClick", function()
    if Addon.selected then Addon.showCopyText(LABELS.copyWord, Addon.selected.word) end
  end)

  editor.resetDictionary = Addon.createActionButton(editor, LABELS.resetDictionary)
  editor.resetDictionary:SetSize(145, 24)
  editor.resetDictionary:SetPoint("BOTTOMLEFT", copyWord, "TOPLEFT", 0, 6)
  editor.resetDictionary:SetScript("OnClick", function()
    local dict = Addon.selected and Addon.selected.dictionaryEntry
    if not dict or not Addon.editorDiffersFromDictionary() then return end
    local function shown(value)
      value = Addon.trim(tostring(value or ""))
      return value ~= "" and value or LABELS.resetNothing
    end
    Addon.showConfirm(LABELS.resetDictionary,
      string.format(LABELS.resetConfirmBody, shown(dict.translation), shown(dict.note)),
      LABELS.confirmAction,
      function()
        editor.translation:SetText(dict.translation or "")
        editor.note:SetText(dict.note or "")
        Addon.updateResetDictionary()
      end)
  end)
  editor.resetDictionary:Hide()

  -- Typing back to what the dictionary says is a way of undoing an edit, so the
  -- button has to follow the boxes rather than only the moment the word opened.
  -- Hooked rather than set: the note's scroll frame has its own handler.
  editor.translation:HookScript("OnTextChanged", Addon.updateResetDictionary)
  editor.note:HookScript("OnTextChanged", Addon.updateResetDictionary)
end

-- Whether what is in the boxes is the player's own wording or the dictionary's.
-- Compared trimmed: a trailing space is not an edit worth offering to undo.
function Addon.editorDiffersFromDictionary()
  local dict = Addon.selected and Addon.selected.dictionaryEntry
  if not dict or not editor then return false end
  return Addon.trim(editor.translation:GetText() or "") ~= Addon.trim(dict.translation or "")
      or Addon.trim(editor.note:GetText() or "") ~= Addon.trim(dict.note or "")
end

-- Hidden when the word is not in a dictionary at all -- there is nothing to
-- reset to. Present but greyed when the boxes already hold the dictionary's own
-- wording, so the button itself answers "have I changed this?" without the
-- player having to press it and find out.
function Addon.updateResetDictionary()
  if not editor or not editor.resetDictionary then return end
  local dict = Addon.selected and Addon.selected.dictionaryEntry
  editor.resetDictionary:SetShown(dict ~= nil)
  if not dict then return end
  if Addon.editorDiffersFromDictionary() then
    editor.resetDictionary:Enable()
  else
    editor.resetDictionary:Disable()
  end
end
