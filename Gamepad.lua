local Addon = WordHunterWoW_Addon

-- A controller drives the panel the way the mouse does, through the scripts
-- the mouse fires. The D-pad moves a cursor from word to word; the word under
-- it gets the OnEnter a hover would give it, so the English lights up; the
-- confirm button gives it the OnClick, so the editor opens -- and the
-- voiceover, which hooks the editor rather than the panel, says the word
-- without knowing a controller was involved. Nothing here knows how to open an
-- editor or highlight a translation. It knows which button is under the cursor.
--
-- The client delivers OnGamePadButtonDown to the top-most shown frame that has
-- asked for it (Frame:EnableGamePadButton), and only while the game's own
-- controller support is on -- GamePadEnable, the option under Controls. Which
-- of this addon's frames receives the press does not decide the answer; what is
-- open does: the editor's question strip first, then the editor, then a window
-- lying over the panel, then the panel. So every frame that takes Escape
-- (SetupEscapeClose) takes the pad too, and hands the press to one dispatcher.
--
-- Buttons are named by position, not by glyph. PAD1 is the bottom face button
-- (A on an Xbox pad, Cross on a PlayStation one), PAD2 the right one (B, Circle),
-- PAD3 the left (X, Square), PAD4 the top (Y, Triangle).
--
--   quest panel    D-pad: move between words       PAD1: open the word
--                  PAD2: close                     PAD3: word list
--                  PAD4: reading mode              shoulders: scroll a page
--   editor         D-pad left/right: status        PAD1: save    PAD2: cancel
--                  shoulders: previous / next word
--   the question   D-pad left/right: rating 1-5    PAD1: rate    PAD2: later
--
-- Only presses this file answers are kept from the game; every other one is let
-- through, under the same combat rule the keyboard has (SafePropagate). The
-- sticks are never taken, so walking and looking around keep working with the
-- panel open.

local STATUS_ORDER = { "new", "learning", "known", "ignored" }

-- On by default. A controller that is on in the game and never reaches the
-- panel would be the surprise, not the other way round. The setting is for a
-- player who keeps the pad on for the game and wants the panel to leave its
-- buttons alone.
function Addon.GetGamePadEnabled()
  local settings = WordHunterWoWDB and WordHunterWoWDB.settings
  if settings and settings.gamepad ~= nil then return settings.gamepad and true or false end
  return true
end

function Addon.SetGamePadEnabled(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.gamepad = not not value
  if Addon.settingsPanel and Addon.settingsPanel.refresh then Addon.settingsPanel.refresh() end
end

-- Whether this client has the handler at all. Retail since 9.0, Classic Era
-- since 1.15; a 1.12 client has no controller and no method, and gets nothing
-- attached rather than an error.
function Addon.AttachGamePad(frame)
  if not frame or not frame.EnableGamePadButton then return false end
  frame:EnableGamePadButton(true)
  frame:SetScript("OnGamePadButtonDown", function(self, button)
    Addon.GamePadButton(self, button)
  end)
  return true
end

-- --- the cursor ---------------------------------------------------------------

-- One texture per host, made when first needed and moved rather than remade:
-- the panel's lives on the scroll child with the words, the question strip's
-- on the strip. A translucent box behind the button, the hover highlight's own
-- colour but stronger, since there is no pointer to say where the player is.
--
-- Kept here, keyed by the host, and not as a field on the host: where this
-- file is tested a frame answers any field it was never given with a fresh
-- table, so "not yet made" would read as "made" and no texture would ever be.
local cursors = setmetatable({}, { __mode = "k" })

function Addon.GamePadCursor(host)
  return cursors[host]
end

local function cursorTo(host, button)
  local cursor = cursors[host]
  if not cursor then
    cursor = host:CreateTexture(nil, "BACKGROUND")
    cursor:SetColorTexture(0.30, 0.42, 0.55, 0.45)
    cursors[host] = cursor
  end
  cursor:ClearAllPoints()
  cursor:SetPoint("TOPLEFT", button, "TOPLEFT", -2, 2)
  cursor:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -2)
  cursor.target = button
  cursor:Show()
end

local function hideCursor(host)
  local cursor = host and cursors[host]
  if cursor then
    cursor.target = nil
    cursor:Hide()
  end
end

-- --- the quest panel ----------------------------------------------------------

-- The index of the focused word button, and the layout it was focused under.
-- The panel numbers its layouts; a new quest, or the same one re-flowed at
-- another size, reuses the same pooled buttons for different words, so an index
-- remembered across a layout would point at whatever word landed there.
local focus, focusSerial

local function wordsOf(panel)
  local list, count = panel.wordButtons, panel.wordCount
  if type(list) ~= "table" or type(count) ~= "number" then return {}, 0 end
  return list, count
end

local function usable(button)
  return button ~= nil and button.word ~= nil and button.word ~= "" and button:IsShown()
end

local function currentFocus(panel)
  local list = wordsOf(panel)
  if focus and focusSerial == panel.layoutSerial and usable(list[focus]) then return focus end
  hideCursor(panel.content)
  return nil
end

-- Brings the focused word into the scroll frame's window. Measured, not
-- assumed: a frame that cannot say how tall it is, or where it is scrolled to,
-- is left where it is rather than scrolled by a guess.
local function scrollIntoView(panel, button)
  local scroll = panel.scroll
  if not scroll or type(button.gridY) ~= "number" then return end
  local view = scroll.GetHeight and scroll:GetHeight()
  local top = scroll.GetVerticalScroll and scroll:GetVerticalScroll()
  if type(view) ~= "number" or type(top) ~= "number" or view <= 0 then return end
  local height = button.GetHeight and button:GetHeight()
  if type(height) ~= "number" then height = 18 end
  local wordTop, wordBottom = -button.gridY, -button.gridY + height
  if wordTop < top then
    scroll:SetVerticalScroll(math.max(0, wordTop - 4))
  elseif wordBottom > top + view then
    -- A little below the word, but never past its top: in a window shorter
    -- than the word and the margin together, the top is the part to keep.
    scroll:SetVerticalScroll(math.max(0, math.min(wordTop, wordBottom - view + 4)))
  end
end

local function setFocus(panel, index)
  local list = wordsOf(panel)
  local button = list[index]
  if not usable(button) then return false end
  focus, focusSerial = index, panel.layoutSerial
  cursorTo(panel.content, button)
  local onEnter = button:GetScript("OnEnter")
  if onEnter then onEnter(button) end
  scrollIntoView(panel, button)
  return true
end

local function firstWord(panel)
  local list, count = wordsOf(panel)
  for index = 1, count do
    if usable(list[index]) then return setFocus(panel, index) end
  end
  return false
end

-- One word along the reading order, over punctuation-only tokens the panel
-- disabled. At either end the press is kept -- it was meant for the panel --
-- and nothing moves.
local function step(panel, direction)
  local list, count = wordsOf(panel)
  local index = currentFocus(panel)
  if not index then return firstWord(panel) end
  local next = index + direction
  while next >= 1 and next <= count do
    if usable(list[next]) then return setFocus(panel, next) end
    next = next + direction
  end
  return true
end

local function centre(button)
  return (button.gridX or 0) + (button.gridW or 0) / 2
end

-- The word on the nearest line above (+1) or below (-1) whose centre is
-- closest to this one's. Lines are the panel's own y offsets, recorded when it
-- laid the words out, so the answer is what the eye would pick.
local function line(panel, direction)
  local list, count = wordsOf(panel)
  local index = currentFocus(panel)
  if not index then return firstWord(panel) end
  local from = list[index]
  if type(from.gridY) ~= "number" then return true end
  local nearest, nearestGap
  for other = 1, count do
    local button = list[other]
    if not usable(button) or type(button.gridY) ~= "number" then button = nil end
    if button and (button.gridY - from.gridY) * direction > 0 then
      local gap = math.abs(button.gridY - from.gridY)
      if not nearestGap or gap < nearestGap then nearest, nearestGap = button.gridY, gap end
    end
  end
  if not nearest then return true end
  local best, bestDistance
  for other = 1, count do
    local button = list[other]
    if usable(button) and button.gridY == nearest then
      local distance = math.abs(centre(button) - centre(from))
      if not bestDistance or distance < bestDistance then best, bestDistance = other, distance end
    end
  end
  if not best then return true end
  return setFocus(panel, best)
end

local function page(panel, direction)
  local scroll = panel.scroll
  local view = scroll and scroll.GetHeight and scroll:GetHeight()
  local top = scroll and scroll.GetVerticalScroll and scroll:GetVerticalScroll()
  if type(view) ~= "number" or type(top) ~= "number" then return true end
  local wanted = math.max(0, top + direction * view * 0.8)
  local range = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()
  if type(range) == "number" then wanted = math.min(wanted, math.max(0, range)) end
  scroll:SetVerticalScroll(wanted)
  return true
end

-- --- the question strip -------------------------------------------------------

-- The rating the D-pad has moved to, 1 to 5, or nil before it has moved. Reset
-- once a verdict is given or the question is put away, so the next word does
-- not start where the last one was rated.
local score

local function markScore(cover, value)
  score = value
  local button = cover.buttons and cover.buttons[value]
  if button then cursorTo(cover, button) end
end

local function askingRating(editor)
  local cover = editor.cover
  return cover ~= nil and cover:IsShown() and Addon.selected ~= nil and Addon.selected.recallPending == true
end

-- Opening a word from the pad lands on the strip with the cursor already on
-- the middle rating, so the first thing on screen says where the player is.
-- Opened with the mouse, the strip waits for the first D-pad press instead.
local function openFocused(panel)
  local list = wordsOf(panel)
  local index = currentFocus(panel)
  if not index then return firstWord(panel) end
  local button = list[index]
  local onClick = button:GetScript("OnClick")
  if onClick then onClick(button) end
  local editor = Addon.editor
  if editor and editor:IsShown() and askingRating(editor) then markScore(editor.cover, 3) end
  return true
end

-- Where a step from the word last opened in this quest would land, or nil.
--
-- The starting point is the word last opened from the panel -- Addon.lastOpened,
-- which the panel's word button records on every click -- while it is still
-- current: the same layout serial, and the same key at that index, because the
-- pool is reused across layouts. Failing that, the controller's own focus,
-- when it is current. With neither -- a fresh quest, or a word opened from the
-- list -- Next starts at the first word and Previous has nowhere to go.
local function neighbourOf(direction)
  local panel = Addon.panel
  if not panel or not panel:IsShown() then return nil end
  local list, count = wordsOf(panel)
  local from
  local last = Addon.lastOpened
  if last and last.serial == panel.layoutSerial then
    local button = list[last.index]
    if button and button.key == last.key then from = last.index end
  end
  if not from then from = currentFocus(panel) end
  if not from then
    if direction < 0 then return nil end
    from = 0
  end
  local index = from + direction
  while index >= 1 and index <= count do
    if usable(list[index]) then return index end
    index = index + direction
  end
  return nil
end

-- Whether Previous or Next has anywhere to go: the panel buttons' enabled state.
function Addon.NeighbourWordAvailable(direction)
  return neighbourOf(direction) ~= nil
end

-- Previous and Next: the word before or after the one last opened, opened
-- the way a click opens it -- the cursor moves there, the button's own OnClick
-- runs, and everything that hangs off a click (the English lighting up, the
-- voiceover, the recall question) follows. Returns whether a word was opened;
-- at either end nothing is, and a key or a pad press is kept anyway.
function Addon.OpenNeighbourWord(direction)
  local index = neighbourOf(direction)
  if not index or not setFocus(Addon.panel, index) then return false end
  openFocused(Addon.panel)
  if Addon.RefreshWordArrows then Addon.RefreshWordArrows() end
  return true
end

local function click(button, ...)
  local handler = button and button:GetScript("OnClick")
  if handler then handler(button, ...) end
  return handler ~= nil
end

local function inQuestion(editor, button)
  local cover = editor.cover
  if button == "PADDLEFT" or button == "PADDRIGHT" then
    local next = (score or 3) + (button == "PADDLEFT" and -1 or 1)
    markScore(cover, math.max(1, math.min(5, next)))
    return true
  elseif button == "PAD1" then
    local chosen = score or 3
    score = nil
    hideCursor(cover)
    click(cover.buttons and cover.buttons[chosen])
    return true
  elseif button == "PAD2" then
    score = nil
    hideCursor(cover)
    click(cover.show)
    return true
  end
  return false
end

-- --- the editor ---------------------------------------------------------------

local function statusIndex(status)
  for index, name in ipairs(STATUS_ORDER) do
    if name == status then return index end
  end
  return 2
end

local function inEditor(editor, button)
  if askingRating(editor) then return inQuestion(editor, button) end
  if button == "PADDLEFT" or button == "PADDRIGHT" then
    local current = Addon.selected and Addon.selected.status or "learning"
    local next = statusIndex(current) + (button == "PADDLEFT" and -1 or 1)
    next = math.max(1, math.min(#STATUS_ORDER, next))
    click(editor.statusButtons and editor.statusButtons[STATUS_ORDER[next]])
    return true
  elseif button == "PADLSHOULDER" then
    Addon.OpenNeighbourWord(-1)
    return true
  elseif button == "PADRSHOULDER" then
    Addon.OpenNeighbourWord(1)
    return true
  elseif button == "PAD1" then
    click(editor.save)
    return true
  elseif button == "PAD2" then
    click(editor.cancel)
    return true
  end
  return false
end

-- --- dispatch -----------------------------------------------------------------

local function toggleWordList()
  if Addon.listFrame and Addon.listFrame:IsShown() then
    Addon.listFrame:Hide()
  elseif Addon.toggleWordList then
    Addon.toggleWordList()
  end
  return true
end

local function inPanel(panel, button)
  if button == "PADDLEFT" then return step(panel, -1)
  elseif button == "PADDRIGHT" then return step(panel, 1)
  elseif button == "PADDUP" then return line(panel, 1)
  elseif button == "PADDDOWN" then return line(panel, -1)
  elseif button == "PAD1" then return openFocused(panel)
  elseif button == "PAD2" then return Addon.CloseAll() and true or false
  elseif button == "PAD3" then return toggleWordList()
  elseif button == "PAD4" then
    if Addon.ToggleReadingMode then Addon.ToggleReadingMode() end
    return true
  elseif button == "PADLSHOULDER" then return page(panel, -1)
  elseif button == "PADRSHOULDER" then return page(panel, 1)
  end
  return false
end

-- A window lying over the panel -- the word list, the statistics -- is not
-- driven from the pad; it is put away from it. PAD3 still toggles the list, so
-- the button that opened it closes it.
local function firstShown(keys)
  for _, key in ipairs(keys) do
    local frame = Addon[key]
    if frame and frame.IsShown and frame:IsShown() then return frame end
  end
  return nil
end

local function putAway(over, button)
  if button == "PAD2" then over:Hide() return true end
  if button == "PAD3" then return toggleWordList() end
  return false
end

-- The settings window: B closes an open choice first, then the window; the
-- shoulders step through the tabs. Nothing on a tab is pressed from the pad
-- yet, and Reset is deliberately never bound to a button.
local function inSettings(window, button)
  if button == "PAD2" then
    local menu = Addon.settingsMenu
    if menu and menu:IsShown() then
      menu:Hide()
    else
      window:Hide()
    end
    return true
  elseif button == "PADLSHOULDER" or button == "PADRSHOULDER" then
    if window.stepTab then window.stepTab(button == "PADLSHOULDER" and -1 or 1) end
    return true
  end
  return false
end

local function dispatch(button)
  local editor = Addon.editor
  if editor and editor:IsShown() then return inEditor(editor, button) end
  -- The copy and confirm dialogs before the settings window: the window opens
  -- them, and B has to close the dialog rather than the window behind it.
  local dialog = firstShown({ "copyDialog", "confirmDialog" })
  if dialog then return putAway(dialog, button) end
  local settings = Addon.settingsPanel
  if settings and settings.IsShown and settings:IsShown() then return inSettings(settings, button) end
  local over = firstShown({ "listFrame", "statsFrame" })
  if over then return putAway(over, button) end
  local panel = Addon.panel
  if panel and panel:IsShown() then return inPanel(panel, button) end
  if button == "PAD2" then return Addon.CloseAll() and true or false end
  return false
end

-- The one handler every attached frame runs. Returns whether the press was
-- taken; a press that was not is propagated, so the game still sees it.
function Addon.GamePadButton(frame, button)
  local handled = false
  if Addon.GetGamePadEnabled() then
    handled = dispatch(button) and true or false
  end
  if Addon.SafePropagate then Addon.SafePropagate(frame, not handled) end
  return handled
end

-- For a test: where the cursor is.
function Addon.GamePadFocus()
  local panel = Addon.panel
  if not panel then return nil end
  local index = currentFocus(panel)
  local list = wordsOf(panel)
  return index, index and list[index] or nil
end
