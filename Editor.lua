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
    and (selected.encounterCount or 0) >= (Addon.GetReadyAfter and Addon.GetReadyAfter() or 5)
    and time() - learningSince >= 14 * 24 * 60 * 60
  editor.history:SetText(ready and (history .. "  •  " .. LABELS.readyForKnown) or history)
  editor.history:SetTextColor(unpack(ready and COLORS.known or COLORS.muted))
end

-- The recall strip: the 1-5 rating, under the meaning rather than in front of
-- it.
--
-- It used to cover the boxes and ask first, which is how every flashcard
-- program works and is wrong here. A flashcard shows the front, you try to
-- recall, you turn it over, and only then do you say how it went -- the
-- rating comes after the answer in Anki too. Covering the meaning and asking
-- first asks something else: how confident are you, with no way to find out
-- whether the confidence was earned. The owner put it plainly -- I cannot be
-- sure whether I know it well or badly.
--
-- So the meaning is there the moment the word is clicked, the way it is for
-- every word that is not being asked about, and the question sits underneath
-- it. The editor grows by the height of the strip while it is up, so nothing
-- above it moves and the answer does not jump under the reader's eye.
--
-- A frame of its own so it can take the number keys without sharing the
-- editor's OnKeyDown, which the Escape hook already owns.
-- The strip takes the status row's space rather than making the window taller.
-- Growing the editor looked simpler and is not: Addon.PlaceFrame restores the
-- size on every open, so the added height is overwritten the moment it is set,
-- and forcing it back afterwards would make SaveFramePosition store the taller
-- shape the next time the player dragged the window -- a window that grows by
-- sixty pixels every session.
local STRIP_TOP = -252

-- Whether the question is up. The boxes are no longer part of this: the
-- meaning shows for every word, asked about or not, and only the strip and the
-- editor's height change.
local function showStrip(shown)
  if not editor.cover then return end
  if shown then
    -- No keys at all in combat. The strip decides per key whether the game
    -- sees it, and that call is refused in combat, so a strip that took keys
    -- then would either swallow Escape and the movement keys or let a digit
    -- both rate the word and fire the action bar. The buttons still work;
    -- EnableKeyboard is not protected.
    editor.cover:EnableKeyboard(not (InCombatLockdown and InCombatLockdown()))
    editor.cover:Show()
  else
    editor.cover:Hide()
  end
  -- At rest, let everything through. A digit that rated the word left the flag
  -- at "keep", and a flag is a frame attribute that outlives the keystroke;
  -- shown again from that state the strip would eat every key.
  if Addon.SafePropagate then Addon.SafePropagate(editor.cover, true) end
end

-- The boxes the old cover used to hide. They are shown unconditionally now,
-- and the list is kept because "shown" has to be stated rather than assumed:
-- an editor that has been through an older build, or a frame the client has
-- never been told to show, is hidden until something says otherwise.
-- Always on screen, whether the word is being asked about or not. Stated
-- rather than assumed: a frame the client has never been told to show is
-- hidden, and an editor carried over from a build where these were hidden
-- stays that way until something says otherwise.
local FIELD_WIDGETS = { "meaningLabel", "translation", "noteLabel", "noteScroll", "save" }

-- The row the strip stands in. Hidden while the question is up, which is what
-- makes room for it without touching the window's size. Losing the status
-- buttons for the few seconds the question is up costs nothing: changing a
-- word's status is not what the click was for, and they come back the moment
-- it is answered.
local STATUS_WIDGETS = { "statusLabel", "resetDictionary" }

local function showFields(asking)
  for _, name in ipairs(FIELD_WIDGETS) do
    local widget = editor[name]
    if widget and widget.Show then widget:Show() end
  end
  for _, name in ipairs(STATUS_WIDGETS) do
    local widget = editor[name]
    if widget then
      if asking then widget:Hide() else widget:Show() end
    end
  end
  for _, button in pairs(editor.statusButtons or {}) do
    if asking then button:Hide() else button:Show() end
  end
  showStrip(asking)
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
  showFields(false)
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
  -- Previous and Next step through the quest the word was clicked in. A word
  -- opened from the list has no quest around it, so the click the panel
  -- recorded is forgotten: Next then starts the panel's quest from its first
  -- word, rather than walking on from a word the editor is no longer showing.
  if not fromPanel then Addon.lastOpened = nil end
  if Addon.RefreshWordArrows then Addon.RefreshWordArrows() end
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
    -- The meaning goes in like any other word's. It used to be held back here
    -- and written only on reveal, because the cover in front of it could be
    -- read through; there is nothing in front of it now.
    editor.translation:SetText(selected.translationText or "")
    editor.note:SetText(selected.noteText or "")
    showFields(true)
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
    showFields(false)
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
  editor:SetSize(420, 400)
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
  -- The arrow keys are Previous and Next while no box holds the keyboard; with
  -- a box focused they move its caret and never reach this frame. Kept from
  -- the game whether or not there was a word to go to: an arrow pressed at the
  -- end of a quest is still meant for the editor, not for turning the player.
  local function arrowKeys(self, key)
    if key ~= "LEFT" and key ~= "RIGHT" then return false end
    if GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus() then return false end
    if Addon.OpenNeighbourWord then Addon.OpenNeighbourWord(key == "LEFT" and -1 or 1) end
    return true
  end
  Addon.SetupEscapeClose(editor, arrowKeys)
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
  save:SetSize(94, Addon.RoleButtonHeight())
  save:SetPoint("BOTTOMRIGHT", -20, 20)
  save:SetScript("OnClick", saveSelected)
  editor.save = save
  local cancel = Addon.createActionButton(editor, LABELS.cancel)
  cancel:SetSize(94, Addon.RoleButtonHeight())
  cancel:SetPoint("RIGHT", save, "LEFT", -8, 0)
  cancel:SetScript("OnClick", function() editor:Hide() end)
  editor.cancel = cancel

  -- Previous and Next, on the bottom row with Cancel and Save and at their
  -- height: the reading controls belong in this window, where the word is.
  -- Four buttons across the row is what made Cancel and Save 94 wide and sent
  -- Copy word up beside Reset to dictionary; at the editor's narrowest, 420,
  -- the row has two pixels to spare.
  editor.prevWord = Addon.createActionButton(editor, LABELS.prevWord)
  editor.prevWord:SetSize(88, Addon.RoleButtonHeight())
  editor.prevWord:SetPoint("BOTTOMLEFT", 20, 20)
  editor.prevWord:SetScript("OnClick", function()
    if Addon.OpenNeighbourWord then Addon.OpenNeighbourWord(-1) end
  end)
  editor.nextWord = Addon.createActionButton(editor, LABELS.nextWord)
  editor.nextWord:SetSize(88, Addon.RoleButtonHeight())
  editor.nextWord:SetPoint("LEFT", editor.prevWord, "RIGHT", 6, 0)
  editor.nextWord:SetScript("OnClick", function()
    if Addon.OpenNeighbourWord then Addon.OpenNeighbourWord(1) end
  end)

  local copyWord = Addon.createActionButton(editor, LABELS.copyWord)
  copyWord:SetSize(110, Addon.RoleButtonHeight())
  copyWord:SetScript("OnClick", function()
    if Addon.selected then Addon.showCopyText(LABELS.copyWord, Addon.selected.word, nil, editor) end
  end)

  editor.resetDictionary = Addon.createActionButton(editor, LABELS.resetDictionary)
  editor.resetDictionary:SetSize(145, Addon.RoleButtonHeight())
  editor.resetDictionary:SetPoint("BOTTOMLEFT", editor.prevWord, "TOPLEFT", 0, 6)
  copyWord:SetPoint("LEFT", editor.resetDictionary, "RIGHT", 8, 0)
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

  -- Under the status buttons, in the space the extra height opens up, so the
  -- meaning and the note keep the positions they have when nothing is being
  -- asked. Not mouse-enabled itself, so a drag on it moves the editor as a
  -- drag anywhere else does; the buttons on it take their own clicks.
  local cover = CreateFrame("Frame", nil, editor)
  cover:SetPoint("TOPLEFT", 0, STRIP_TOP)
  cover:SetPoint("BOTTOMRIGHT", 0, 84)
  cover:Hide()
  editor.cover = cover

  cover.prompt = cover:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  cover.prompt:SetPoint("TOPLEFT", 20, -2)
  cover.prompt:SetPoint("TOPRIGHT", -20, -2)
  cover.prompt:SetJustifyH("LEFT")
  cover.prompt:SetText(LABELS.recallPrompt)

  cover.scale = cover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cover.scale:SetTextColor(unpack(COLORS.muted))
  cover.scale:SetPoint("TOPLEFT", 20, -20)
  cover.scale:SetPoint("TOPRIGHT", -20, -20)
  cover.scale:SetJustifyH("LEFT")
  cover.scale:SetText(LABELS.recallScale)

  -- Coloured as the verdict reads: not knowing a word is what New looks like,
  -- knowing it is what Known looks like, and the middle is Learning.
  local scoreColors = { COLORS.new, COLORS.new, COLORS.learning, COLORS.known, COLORS.known }
  cover.buttons = {}
  for score = 1, 5 do
    local button = Addon.createFlatButton(cover, tostring(score), scoreColors[score])
    button:SetSize(70, Addon.RoleButtonHeight())
    button:SetPoint("TOPLEFT", 20 + (score - 1) * 76, -36)
    button.score = score
    button:SetScript("OnClick", function(self) rate(self.score) end)
    cover.buttons[score] = button
  end

  cover.soFar = cover:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  cover.soFar:SetTextColor(unpack(COLORS.muted))
  cover.soFar:SetPoint("TOPRIGHT", -20, -20)
  cover.soFar:SetJustifyH("RIGHT")

  -- Declining the question. Not a rating of any kind: sometimes a word is
  -- clicked to check a spelling, and that says nothing about knowing it. It
  -- used to be "Show meaning", which was the only way past the cover; with the
  -- meaning already on screen what is left is to put the question away.
  cover.show = Addon.createActionButton(cover, LABELS.recallLater)
  cover.show:SetSize(90, Addon.RoleButtonHeight())
  cover.show:SetPoint("TOPLEFT", 20 + 5 * 76 + 10, -36)
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

-- Previous and Next go grey at the ends of the quest, and both go grey with no
-- quest on the panel. The walk lives with the controller (Gamepad.lua), which
-- is loaded before this file; asked for rather than assumed, so an editor built
-- without it -- as several tests build one -- has grey buttons and no error.
function Addon.RefreshWordArrows()
  if not editor or not editor.prevWord then return end
  local available = Addon.NeighbourWordAvailable
  editor.prevWord:SetEnabled(available ~= nil and available(-1) or false)
  editor.nextWord:SetEnabled(available ~= nil and available(1) or false)
end
