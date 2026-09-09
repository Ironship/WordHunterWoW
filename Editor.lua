local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local STATUS_LABELS = Addon.STATUS_LABELS
local LABELS = Addon.LABELS
local unpack = unpack or table.unpack

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
  -- The recall summary rides on the first line, which has room; the second
  -- already carries the Ready-for-Known hint and is held to two lines.
  local recall = Addon.RecallSummary and selected.key and Addon.RecallSummary(selected.key)
  local history = string.format(
    "First added: %s  •  Last seen: %s%s\n%d quests  •  Status changed: %s",
    date("%Y-%m-%d", selected.firstSeenAt),
    date("%Y-%m-%d", selected.lastSeenAt or selected.firstSeenAt),
    recall and ("  •  " .. recall) or "",
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
  editor.history:SetTextColor(unpack(ready and COLORS.known or COLORS.muted))
end

-- The recall cover: what stands in for the meaning and note boxes while the
-- word is asking to be rated. The boxes themselves are hidden, not painted
-- over -- a frame in front of a box can be seen through at the wrong opacity,
-- scrolled under, or drawn below the box's own scroll bar, and a hidden box
-- has none of those. The cover is a frame of its own so it can take the
-- number keys without sharing the editor's OnKeyDown, which the Escape hook
-- already owns.
-- Save goes with them: with the boxes empty there is nothing to save, and a
-- Save that read the empty boxes would write them over the meaning.
local FIELD_WIDGETS = { "meaningLabel", "translation", "noteLabel", "noteScroll", "statusLabel", "save" }

local function showFields(shown)
  for _, name in ipairs(FIELD_WIDGETS) do
    local widget = editor[name]
    if widget then
      if shown then widget:Show() else widget:Hide() end
    end
  end
  for _, button in pairs(editor.statusButtons or {}) do
    if shown then button:Show() else button:Hide() end
  end
  if editor.cover then
    if shown then
      editor.cover:Hide()
    else
      -- No keys at all in combat. The cover decides per key whether the game
      -- sees it, and that call is refused in combat, so a cover that took
      -- keys then would either swallow Escape and the movement keys or let a
      -- digit both rate the word and fire the action bar. The buttons still
      -- work; EnableKeyboard is not protected.
      editor.cover:EnableKeyboard(not (InCombatLockdown and InCombatLockdown()))
      editor.cover:Show()
    end
    -- At rest, let everything through. A digit that rated the word left the
    -- flag at "keep", and a flag is a frame attribute that outlives the
    -- keystroke; shown again from that state the cover would eat every key.
    if Addon.SafePropagate then Addon.SafePropagate(editor.cover, true) end
  end
end

-- Takes the cover down and fills the boxes. The texts were held back rather
-- than written into hidden boxes: a hidden box still answers GetText, and the
-- meaning must not be anywhere in the editor until it is meant to be seen.
local function reveal(fromKey)
  local selected = Addon.selected
  if not selected then return end
  selected.recallPending = false
  editor.translation:SetText(selected.translationText or "")
  editor.note:SetText(selected.noteText or "")
  showFields(true)
  Addon.updateResetDictionary()
  updateEditorHistory()
  if fromKey then
    -- The digit that gave the verdict is still being handled. Focus the box
    -- now and the same keystroke's character lands in it -- over the meaning,
    -- which HighlightText has just selected -- and Enter would save "3" as the
    -- translation. Focus once the keystroke is over.
    C_Timer.After(0, function()
      if editor:IsShown() and Addon.selected and not Addon.selected.recallPending then
        editor.translation:SetFocus()
        editor.translation:HighlightText()
      end
    end)
  else
    editor.translation:SetFocus()
    editor.translation:HighlightText()
  end
  if Addon.RevealSelectedHighlight then Addon.RevealSelectedHighlight() end
end

-- For the setting being switched off under an open cover: the quest panel
-- reads the setting live and would light the English word beside an editor
-- still asking for a verdict.
function Addon.RevealRecall()
  if editor and editor:IsShown() and Addon.selected and Addon.selected.recallPending then reveal() end
end

-- Written the moment it is given. Save is not involved: cancelling the editor
-- is the natural end of "I only wanted to check", and a verdict that needed
-- Save would be lost on most of them. Guarded against a cover left up by a
-- quest window closing under it -- the rating is for the word the editor is
-- showing, or nobody.
local function rate(score, fromKey)
  local selected = Addon.selected
  if not selected or not selected.recallPending or not editor:IsShown() then return end
  local now = time()
  if Addon.RecordRating then Addon.RecordRating(selected.key, score, now) end
  if Addon.RecordExample then
    Addon.RecordExample(selected.key, selected.context, selected.questId, selected.questTitle, now)
  end
  reveal(fromKey)
end

-- `opts.origin` says where the click came from. Only the quest panel passes
-- "panel": a word met in a quest is the moment to ask whether it is known,
-- and the word list -- which shows the meaning beside the word -- is not.
function Addon.openEditor(word, context, questId, questTitle, opts)
  local key = Addon.wordKey(word)
  if key == "" then return end
  local entry = Addon.GetEffectiveWord(key)
  local dictionaryEntry = Addon.GetDictionaryEntry(key)
  local fromPanel = type(opts) == "table" and opts.origin == "panel"
  local now = time()
  -- The sentence a Learning word was met in is worth keeping whether or not
  -- the word is asked about today. Only for a word of the player's own: a
  -- dictionary word has no entry, and making one here would put it in the
  -- export and freeze the pack's wording, which is what Save avoids.
  if fromPanel and Addon.RecordExample then
    local own = Addon.GetWordsTable()[key]
    if own and Addon.EffectiveStatus(own) == "learning" then
      Addon.RecordExample(key, context, questId, questTitle, now)
    end
  end
  local gated = false
  if fromPanel and Addon.RecallGated then gated = Addon.RecallGated(key, now) end
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
    recallPending = gated,
    translationText = entry and entry.translation or "",
    noteText = entry and entry.note or "",
  }
  local selected = Addon.selected
  editor.word:SetText(selected.word)
  editor.context:SetText(context)
  updateStatusButtons()
  if gated then
    -- Nothing of the meaning reaches a box, and no box has focus: a focused
    -- box would take the number keys as typing.
    editor.translation:SetText("")
    editor.note:SetText("")
    -- Whatever holds the keyboard, not only these two: a click on a quest
    -- word does not take focus from the word list's search box, and a digit
    -- typed there is a filter, not a verdict.
    local focus = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if focus and focus.ClearFocus then focus:ClearFocus() end
    editor.translation:ClearFocus()
    editor.note:ClearFocus()
    showFields(false)
    Addon.updateResetDictionary()
    updateEditorHistory()
    if editor.cover and editor.cover.soFar then
      local mean, count
      if Addon.RecallSummary then
        local _
        _, mean, count = Addon.RecallSummary(key)
      end
      editor.cover.soFar:SetText(count and count > 0 and string.format(LABELS.recallSoFar, count, mean) or "")
    end
  else
    editor.translation:SetText(selected.translationText)
    editor.note:SetText(selected.noteText)
    showFields(true)
    Addon.updateResetDictionary()
    updateEditorHistory()
    editor.translation:SetFocus()
    editor.translation:HighlightText()
  end
  Addon.PlaceFrame(editor, "editor")
  editor:Show()
  editor:Raise()
end

local function saveSelected()
  if not Addon.selected then return end
  -- The boxes are empty while the cover is up. Its button is hidden, but Enter
  -- in a box or a test can still reach this: answer by showing the meaning,
  -- never by saving nothing over it.
  if Addon.selected.recallPending then
    reveal()
    return
  end
  local now = time()
  local selected = Addon.selected
  local key = selected.key
  local translation = Addon.trim(editor.translation:GetText())
  local note = Addon.trim(editor.note:GetText())
  -- The sentence goes with the word from the moment it is marked Learning,
  -- whichever branch below the entry itself takes.
  if selected.status == "learning" and Addon.RecordExample then
    Addon.RecordExample(key, selected.context, selected.questId, selected.questTitle, now)
  end
  local dict = selected.dictionaryEntry or Addon.GetDictionaryEntry(key)
  local dictStatus = dict and ((dict.status == "ignored" or dict.status == "known" or dict.status == "learning" or dict.status == "new") and dict.status or "new") or nil
  -- Matching the dictionary exactly means there is nothing of the player's to
  -- keep. Writing an overlay would freeze this wording against later pack updates.
  if dict and translation == Addon.trim(dict.translation or "")
      and note == Addon.trim(dict.note or "")
      and selected.status == dictStatus then
    Addon.GetWordsTable()[key] = nil
    Addon.rebuildExport()
    editor:Hide()
    Addon.refreshPanel()
    Addon.refreshWordList()
    return
  end
  local entry = Addon.GetWordsTable()[key]
  if not entry then
    entry = { word = selected.word }
    Addon.GetWordsTable()[key] = entry
  end
  local statusChangedAt = entry.statusChangedAt or now
  if entry.status ~= selected.status then statusChangedAt = now end
  local noteUpdatedAt = entry.noteUpdatedAt or 0
  if note ~= (entry.note or "") then noteUpdatedAt = now end
  entry.status = selected.status
  entry.statusChangedAt = statusChangedAt
  entry.translation = translation
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
  -- Built once. Nothing in the game calls this twice -- ADDON_LOADED fires once
  -- per addon and Init.lua's branch is guarded by the addon's own name -- but a
  -- second call would silently abandon the frame the player is looking at,
  -- along with the position they dragged it to, and hand back a fresh one. That
  -- has already cost time inside the test suite, where calling it again to get
  -- at the frame reset state the rest of the file depended on.
  --
  -- Checked against the public handle rather than the upvalue, so a test that
  -- clears Addon.editor to start over still gets a new one.
  if Addon.editor then return Addon.editor end
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
  Addon.ApplyWindowScale("editorScale")
  editor:Hide()

  editor.word = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  editor.word:SetPoint("TOPLEFT", 20, -40)
  editor.word:SetPoint("TOPRIGHT", -20, -40)
  editor.word:SetHeight(22)
  editor.word:SetJustifyH("LEFT")

  editor.context = editor:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  editor.context:SetTextColor(unpack(COLORS.muted))
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
  editor.meaningLabel = meaning
  editor.translation = Addon.createEditBox(editor)
  editor.translation:SetPoint("TOPLEFT", 20, -148)
  editor.translation:SetPoint("TOPRIGHT", -20, -148)
  editor.translation:SetScript("OnEnterPressed", saveSelected)
  editor.translation:SetScript("OnEscapePressed", function() Addon.CloseAll() end)

  local note = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  note:SetPoint("TOPLEFT", 20, -182)
  note:SetText(LABELS.note)
  editor.noteLabel = note
  editor.noteScroll = CreateFrame("ScrollFrame", nil, editor, "InputScrollFrameTemplate")
  editor.noteScroll:SetPoint("TOPLEFT", 20, -198)
  editor.noteScroll:SetPoint("TOPRIGHT", -20, -198)
  editor.noteScroll:SetHeight(48)
  editor.noteScroll.hideCharCount = true
  InputScrollFrame_OnLoad(editor.noteScroll)
  editor.note = editor.noteScroll.EditBox
  editor.note:SetFontObject("ChatFontNormal")
  -- The note box is built here rather than by createEditBox, so it needs the
  -- same correction: chat font for the family, body role for the size.
  Addon.ApplyFontRole(editor.note, "body")
  editor.note:SetAutoFocus(false)
  editor.note:SetMultiLine(true)
  editor.note:SetMaxLetters(1000)
  editor.note:SetScript("OnEscapePressed", function() Addon.CloseAll() end)

  local statusLabel = editor:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusLabel:SetPoint("TOPLEFT", 20, -262)
  statusLabel:SetText(LABELS.status)
  editor.statusLabel = statusLabel
  editor.statusButtons = {}
  local statuses = { "new", "learning", "known", "ignored" }
  for index, status in ipairs(statuses) do
    local button = Addon.createFlatButton(editor, STATUS_LABELS[status], COLORS[status])
    button:SetSize(89, Addon.RoleButtonHeight())
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
  save:SetSize(112, Addon.RoleButtonHeight())
  save:SetPoint("BOTTOMRIGHT", -20, 20)
  save:SetScript("OnClick", saveSelected)
  editor.save = save
  local cancel = Addon.createActionButton(editor, LABELS.cancel)
  cancel:SetSize(112, Addon.RoleButtonHeight())
  cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function() editor:Hide() end)
  editor.cancel = cancel
  local copyWord = Addon.createActionButton(editor, LABELS.copyWord)
  copyWord:SetSize(110, Addon.RoleButtonHeight())
  copyWord:SetPoint("BOTTOMLEFT", 20, 20)
  copyWord:SetScript("OnClick", function()
    if Addon.selected then Addon.showCopyText(LABELS.copyWord, Addon.selected.word, nil, editor) end
  end)

  editor.resetDictionary = Addon.createActionButton(editor, LABELS.resetDictionary)
  editor.resetDictionary:SetSize(145, Addon.RoleButtonHeight())
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
      end,
      editor)
  end)
  editor.resetDictionary:Hide()

  -- Typing back to what the dictionary says is a way of undoing an edit, so the
  -- button has to follow the boxes rather than only the moment the word opened.
  -- Hooked rather than set: the note's scroll frame has its own handler.
  editor.translation:HookScript("OnTextChanged", Addon.updateResetDictionary)
  editor.note:HookScript("OnTextChanged", Addon.updateResetDictionary)

  -- The cover, over the same area the boxes occupy: from under the history
  -- line to above the bottom row of buttons, so Cancel and Copy word stay
  -- reachable and the resize corner stays uncovered. Not mouse-enabled
  -- itself, so a drag on it moves the editor as a drag anywhere else does;
  -- the buttons on it take their own clicks.
  local cover = CreateFrame("Frame", nil, editor)
  cover:SetPoint("TOPLEFT", 0, -128)
  cover:SetPoint("BOTTOMRIGHT", 0, 84)
  cover:Hide()
  editor.cover = cover

  cover.prompt = cover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cover.prompt:SetPoint("TOPLEFT", 20, -8)
  cover.prompt:SetPoint("TOPRIGHT", -20, -8)
  cover.prompt:SetJustifyH("LEFT")
  cover.prompt:SetText(LABELS.recallPrompt)

  cover.scale = cover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cover.scale:SetTextColor(unpack(COLORS.muted))
  cover.scale:SetPoint("TOPLEFT", 20, -30)
  cover.scale:SetPoint("TOPRIGHT", -20, -30)
  cover.scale:SetJustifyH("LEFT")
  cover.scale:SetText(LABELS.recallScale)

  -- Coloured as the verdict reads: not knowing a word is what New looks like,
  -- knowing it is what Known looks like, and the middle is Learning.
  local scoreColors = { COLORS.new, COLORS.new, COLORS.learning, COLORS.known, COLORS.known }
  cover.buttons = {}
  for score = 1, 5 do
    local button = Addon.createFlatButton(cover, tostring(score), scoreColors[score])
    button:SetSize(70, Addon.RoleButtonHeight())
    button:SetPoint("TOPLEFT", 20 + (score - 1) * 76, -52)
    button.score = score
    button:SetScript("OnClick", function(self) rate(self.score) end)
    cover.buttons[score] = button
  end

  cover.soFar = cover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cover.soFar:SetTextColor(unpack(COLORS.muted))
  cover.soFar:SetPoint("TOPLEFT", 20, -88)
  cover.soFar:SetPoint("TOPRIGHT", -20, -88)
  cover.soFar:SetJustifyH("LEFT")

  -- Looking without answering. Not a rating of any kind: sometimes a word is
  -- clicked to check a spelling, and that says nothing about knowing it.
  cover.show = Addon.createActionButton(cover, LABELS.recallShow)
  cover.show:SetSize(140, Addon.RoleButtonHeight())
  cover.show:SetPoint("TOPLEFT", 20, -108)
  cover.show:SetScript("OnClick", function() reveal() end)

  -- The number keys, on the cover's own frame. The keys 1 to 5 are the action
  -- bar's by default, so the ones this takes are kept and every other key --
  -- Escape above all -- is let through, with the same combat rule the editor
  -- itself has to follow.
  local KEY_SCORES = {
    ["1"] = 1, ["2"] = 2, ["3"] = 3, ["4"] = 4, ["5"] = 5,
    NUMPAD1 = 1, NUMPAD2 = 2, NUMPAD3 = 3, NUMPAD4 = 4, NUMPAD5 = 5,
  }
  cover:EnableKeyboard(true)
  if Addon.SafePropagate then Addon.SafePropagate(cover, true) end
  cover:SetScript("OnKeyDown", function(self, key)
    local score = KEY_SCORES[key]
    if score and Addon.selected and Addon.selected.recallPending
        and not (InCombatLockdown and InCombatLockdown()) then
      if Addon.SafePropagate then Addon.SafePropagate(self, false) end
      rate(score, true)
    else
      if Addon.SafePropagate then Addon.SafePropagate(self, true) end
    end
  end)
  -- Combat starting or ending while the cover is up: showFields decided the
  -- keyboard once, at show time, and this keeps the decision current.
  cover:RegisterEvent("PLAYER_REGEN_DISABLED")
  cover:RegisterEvent("PLAYER_REGEN_ENABLED")
  cover:SetScript("OnEvent", function(self, event)
    local out = event == "PLAYER_REGEN_ENABLED"
    self:EnableKeyboard(out)
    if out and Addon.SafePropagate then Addon.SafePropagate(self, true) end
  end)
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
  -- And not while the word is still asking to be rated: the confirmation this
  -- button opens prints the dictionary's meaning, which is the one thing the
  -- cover exists to hold back.
  local pending = Addon.selected and Addon.selected.recallPending
  editor.resetDictionary:SetShown(dict ~= nil and not pending)
  if not dict then return end
  if Addon.editorDiffersFromDictionary() then
    editor.resetDictionary:Enable()
  else
    editor.resetDictionary:Disable()
  end
end
