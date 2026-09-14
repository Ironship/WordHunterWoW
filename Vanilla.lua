-- WordHunter on World of Warcraft 1.12.1 (Lua 5.0).
--
-- This file is what the Retail and Classic Era builds do not need. It is loaded
-- before anything else and holds every place where the 1.12 client answers
-- differently from the clients the addon was written for.
--
-- Three kinds of difference live here.
--
-- The first is the language. 1.12 runs Lua 5.0: no `#`, no `%`, and no
-- metatable on strings, so `s:gsub(...)` is a syntax the parser will not read.
-- Those are rewritten in the source itself rather than shimmed -- a shim cannot
-- fix a parse error -- and the only thing needed here is WHW_len.
--
-- The second is the widget API. A handful of methods the addon calls did not
-- exist yet. Each has a helper below, and the source calls the helper, so
-- nothing is added to Blizzard's own widget tables and no other addon on the
-- machine can see that this one is here.
--
-- The third is script handlers. 1.12 hands a handler no arguments at all: the
-- frame is the global `this`, the event name is `event`, and the payload is
-- `arg1`..`arg9`. Rather than rewrite fifty handlers into that shape, every
-- frame this addon creates gets its own SetScript and HookScript, which
-- translate on the way in. The rest of the addon keeps the signature it has on
-- every other client.
--
-- Project Legacy ships ClassicAPI.dll, which back-ports a large part of the
-- modern API onto this client -- string.match, hooksecurefunc, C_Timer, and
-- crucially the quest-id lookups vanilla has never had in Lua. The addon needs
-- it. Everything below still probes rather than assumes, so a client without it
-- degrades instead of erroring, but quest ids will be missing and with them the
-- English panel's ability to find the right record.

if WHW_VANILLA_COMPAT then return end
WHW_VANILLA_COMPAT = 1

-- Globals table --------------------------------------------------------------

-- 1.12 does not put _G in the Lua environment; getfenv(0) is how vanilla addons
-- reach the globals table. ClassicAPI installs _G itself, and every other
-- addon on this client already assumes one, but the addon indexes _G by name in
-- half a dozen places and a nil there is an error rather than a missing feature.
if not _G then _G = getfenv(0) end

-- Length ---------------------------------------------------------------------

-- Stands in for `#`, which 5.0 does not have. One function for both strings and
-- tables, because the call sites it replaces were written for an operator that
-- did not care which it was given.
function WHW_len(value)
  local kind = type(value)
  if kind == "string" then return string.len(value) end
  if kind == "table" then return table.getn(value) end
  return 0
end

-- Library gaps ---------------------------------------------------------------
--
-- ClassicAPI supplies all of these. The fallbacks exist so that a missing or
-- older DLL shows up as a feature not working rather than as an error on every
-- line of quest text.

if not string.gmatch then string.gmatch = string.gfind end

if not string.match then
  function string.match(s, pattern, init)
    local found = { string.find(s, pattern, init) }
    if found[1] == nil then return nil end
    local n = table.getn(found)
    if n <= 2 then return string.sub(s, found[1], found[2]) end
    if n == 3 then return found[3] end
    if n == 4 then return found[3], found[4] end
    if n == 5 then return found[3], found[4], found[5] end
    return found[3], found[4], found[5], found[6], found[7]
  end
end

if type(strtrim) ~= "function" then
  function strtrim(s)
    return (string.gsub(tostring(s or ""), "^%s*(.-)%s*$", "%1"))
  end
end

if type(strsplit) ~= "function" then
  function strsplit(sep, text)
    local out = {}
    local pattern = "([^" .. sep .. "]*)" .. sep .. "?"
    for piece in string.gmatch(tostring(text or "") .. sep, pattern) do
      out[table.getn(out) + 1] = piece
    end
    -- The trailing separator added above leaves one empty piece behind it.
    table.remove(out)
    return unpack(out)
  end
end

if type(print) ~= "function" then
  function print(message)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage(tostring(message)) end
  end
end

if type(hooksecurefunc) ~= "function" then
  -- Nothing on 1.12 is secure, so this is a plain post-hook. Fixed arity rather
  -- than varargs: 5.0 forwards them through the implicit `arg` table and the
  -- functions hooked here take one argument at most.
  function hooksecurefunc(a, b, c)
    local owner, name, post
    if type(a) == "string" then owner, name, post = getfenv(0), a, b
    else owner, name, post = a, b, c end
    local original = owner[name]
    if type(original) ~= "function" or type(post) ~= "function" then return end
    owner[name] = function(a1, a2, a3, a4, a5)
      local r1, r2, r3, r4 = original(a1, a2, a3, a4, a5)
      post(a1, a2, a3, a4, a5)
      return r1, r2, r3, r4
    end
  end
end

if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then
  -- One driver frame for every pending callback, rather than a frame each.
  local pending = {}
  local driver = CreateFrame("Frame")
  driver:SetScript("OnUpdate", function()
    local now = GetTime()
    local i = 1
    while i <= table.getn(pending) do
      local timer = pending[i]
      if timer.cancelled then
        table.remove(pending, i)
      elseif now >= timer.at then
        if timer.every then
          timer.at = now + timer.every
          if timer.left then
            timer.left = timer.left - 1
            if timer.left <= 0 then timer.cancelled = true end
          end
          i = i + 1
        else
          table.remove(pending, i)
        end
        timer.callback()
      else
        i = i + 1
      end
    end
  end)

  local function schedule(delay, callback, every, iterations)
    local timer = {
      at = GetTime() + (tonumber(delay) or 0),
      callback = callback,
      every = every,
      left = iterations,
    }
    function timer:Cancel() self.cancelled = true end
    function timer:IsCancelled() return self.cancelled and true or false end
    pending[table.getn(pending) + 1] = timer
    return timer
  end

  C_Timer = C_Timer or {}
  function C_Timer.After(delay, callback) schedule(delay, callback) end
  function C_Timer.NewTimer(delay, callback) return schedule(delay, callback) end
  function C_Timer.NewTicker(delay, callback, iterations)
    return schedule(delay, callback, tonumber(delay) or 0, iterations)
  end
end

-- Widget methods 1.12 does not have ------------------------------------------

function WHW_SetColorTexture(texture, r, g, b, a)
  if not texture then return end
  if texture.SetColorTexture then return texture:SetColorTexture(r, g, b, a) end
  -- 1.12's SetTexture takes the colour directly; the flat-colour texture the
  -- newer call is named after did not exist as a separate thing yet.
  return texture:SetTexture(r, g, b, a == nil and 1 or a)
end

function WHW_SetWordWrap(fontString, allow)
  if fontString and fontString.SetWordWrap then return fontString:SetWordWrap(allow) end
  -- 1.12 wraps whenever the string has a width to wrap inside and does not
  -- otherwise. Every caller that switches wrapping off here is a single-line
  -- label already held to one line by its height and SetMaxLines.
end

function WHW_SetMaxLines(fontString, lines)
  if fontString and fontString.SetMaxLines then return fontString:SetMaxLines(lines) end
end

function WHW_SetSpacing(fontString, spacing)
  if fontString and fontString.SetSpacing then return fontString:SetSpacing(spacing) end
end

function WHW_SetEnabled(widget, enabled)
  if not widget then return end
  if widget.SetEnabled then return widget:SetEnabled(enabled) end
  if enabled then
    if widget.Enable then widget:Enable() end
  elseif widget.Disable then
    widget:Disable()
  end
end

function WHW_SetShown(widget, shown)
  if not widget then return end
  if widget.SetShown then return widget:SetShown(shown) end
  if shown then widget:Show() else widget:Hide() end
end

function WHW_SetSize(region, width, height)
  if not region then return end
  if region.SetSize then return region:SetSize(width, height) end
  if region.SetWidth then region:SetWidth(width) end
  if region.SetHeight then region:SetHeight(height) end
end

function WHW_GetSize(region)
  if not region then return 0, 0 end
  if region.GetSize then return region:GetSize() end
  return region:GetWidth(), region:GetHeight()
end

function WHW_Raise(frame)
  if frame and frame.Raise then return frame:Raise() end
  -- Without Raise the frame keeps the level it was given, which is already
  -- above the game's own windows. Nothing further to do.
end

function WHW_SetObeyStepOnDrag(slider, obey)
  if slider and slider.SetObeyStepOnDrag then return slider:SetObeyStepOnDrag(obey) end
end

-- Script handlers ------------------------------------------------------------

-- How many of the `arg1`..`argN` globals each script carries on 1.12. Anything
-- not named here carries none, and its handler is called with the frame alone.
local SCRIPT_ARGS = {
  OnUpdate = 1,               -- elapsed
  OnClick = 1,                -- mouse button
  OnMouseDown = 1,
  OnMouseUp = 1,
  OnMouseWheel = 1,
  OnDragStart = 1,
  OnKeyDown = 1,
  OnKeyUp = 1,
  OnChar = 1,
  OnVerticalScroll = 1,
  OnHorizontalScroll = 1,
  OnSizeChanged = 2,          -- width, height
  OnScrollRangeChanged = 2,
}

local function wrapHandler(script, handler)
  if type(handler) ~= "function" then return handler end
  if script == "OnEvent" then
    -- The event name is a global of its own on 1.12, not the first payload slot.
    return function()
      return handler(this, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
    end
  end
  if script == "OnValueChanged" then
    -- 1.12 does not pass the new value; the slider is asked for it instead.
    return function()
      local value
      if this and this.GetValue then value = this:GetValue() end
      return handler(this, value)
    end
  end
  local count = SCRIPT_ARGS[script]
  if count == 1 then return function() return handler(this, arg1) end end
  if count == 2 then return function() return handler(this, arg1, arg2) end end
  return function() return handler(this) end
end
WHW_WrapHandler = wrapHandler

local function installScriptShim(frame)
  if type(frame) ~= "table" then return frame end
  local setScript, hookScript = frame.SetScript, frame.HookScript
  if setScript then
    frame.SetScript = function(self, script, handler)
      return setScript(self, script, wrapHandler(script, handler))
    end
  end
  if hookScript then
    frame.HookScript = function(self, script, handler)
      return hookScript(self, script, wrapHandler(script, handler))
    end
  end
  return frame
end

-- Frames ---------------------------------------------------------------------

-- Templates this client does not have. BackdropTemplate exists on Retail only
-- because backdrops were taken off frames there; on 1.12 every frame still has
-- SetBackdrop, so dropping the template is the whole of the port.
local TEMPLATE_UNAVAILABLE = {
  BackdropTemplate = true,
  InputScrollFrameTemplate = true,
}

local anonymous = 0

function WHW_CreateFrame(frameType, name, parent, template)
  if template and TEMPLATE_UNAVAILABLE[template] then template = nil end
  -- A 1.12 template names its own children "$parentSomething", and $parent
  -- resolves to nothing when the frame itself has no name. Give every templated
  -- frame a name rather than find out which templates mind.
  if template and not name then
    anonymous = anonymous + 1
    name = "WordHunterWoWAnon" .. anonymous
  end
  local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
  if not ok and template then
    -- Naming a template this client does not have is an error, not a nil, and
    -- it would take the rest of the addon down with it. Asking and finding out
    -- beats asking the client whether the template exists: the answer to that
    -- can be wrong in the direction that silently costs a scroll bar.
    ok, frame = pcall(CreateFrame, frameType, name, parent)
  end
  if not ok then error(frame, 2) end
  return installScriptShim(frame)
end

-- The multi-line box InputScrollFrameTemplate would have given us, built from
-- the pieces 1.12 does have. A multi-line EditBox grows its own height to fit
-- its text, so the scroll frame only has to be told the width.
function WHW_MultilineEditBox(parent)
  local scroll = WHW_CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local box = WHW_CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(false)
  box:SetFontObject("ChatFontNormal")
  box:SetJustifyH("LEFT")
  box:SetWidth(200)
  box:SetHeight(32)
  scroll:SetScrollChild(box)
  scroll.EditBox = box

  local function fit()
    local width = scroll:GetWidth()
    if width and width > 24 then box:SetWidth(width - 4) end
    scroll:UpdateScrollChildRect()
  end
  scroll:SetScript("OnSizeChanged", fit)
  scroll:SetScript("OnShow", fit)
  box:SetScript("OnTextChanged", function() scroll:UpdateScrollChildRect() end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll.Fit = fit
  return scroll
end

-- Dropdowns ------------------------------------------------------------------
--
-- 1.12 takes the value first and the dropdown second; every later client
-- reversed it. Rather than decide from a version number, try the order this
-- client is expected to want and fall back to the other.

function WHW_DD_SetWidth(dropdown, width)
  if type(UIDropDownMenu_SetWidth) ~= "function" then return end
  if not pcall(UIDropDownMenu_SetWidth, width, dropdown) then
    pcall(UIDropDownMenu_SetWidth, dropdown, width)
  end
end

function WHW_DD_SetText(dropdown, text)
  if type(UIDropDownMenu_SetText) ~= "function" then return end
  if not pcall(UIDropDownMenu_SetText, text, dropdown) then
    pcall(UIDropDownMenu_SetText, dropdown, text)
  end
end

function WHW_DD_CreateInfo()
  if type(UIDropDownMenu_CreateInfo) == "function" then return UIDropDownMenu_CreateInfo() end
  return {}
end

-- Translated quest text ------------------------------------------------------

-- Some 1.12 servers translate quest text by rewriting the quest frames' own
-- font strings, and leave the API answering in the client's language. Project
-- Legacy is one of them: the quest log shows German while GetQuestLogQuestText
-- still returns English, so the addon was marking English words against a
-- German dictionary -- every word in the paragraph the player was not reading.
--
-- This addon exists to work on the words actually on screen, so the frame is
-- asked first and the API is what it falls back to. Nothing changes on a client
-- that translates nothing: the frame and the API then say the same thing.

local function fontStringText(name)
  local region = _G[name]
  if type(region) ~= "table" or type(region.GetText) ~= "function" then return nil end
  if type(region.IsShown) == "function" and not region:IsShown() then return nil end
  local text = region:GetText()
  if type(text) ~= "string" or strtrim(text) == "" then return nil end
  return text
end

-- `where` is "log" for the quest log's own window, anything else for the frame
-- an NPC opens. Returns description, objectives -- either may be nil, meaning
-- "nothing on screen, use what the API said".
function WHW_OnScreenQuestText(where)
  if where == "log" then
    return fontStringText("QuestLogQuestDescription"), fontStringText("QuestLogObjectivesText")
  end
  return fontStringText("QuestDescription"), fontStringText("QuestObjectiveText")
end

function WHW_OnScreenPassage(which)
  if which == "progress" then return fontStringText("QuestProgressText") end
  if which == "reward" then return fontStringText("QuestRewardText") end
  return nil
end

-- Quest ids ------------------------------------------------------------------

-- Vanilla has no quest ids in Lua at all: GetQuestLogTitle returns a title and a
-- level, and the NPC frames return text and nothing else. ClassicAPI adds the
-- log lookups, which covers the quest log.

function WHW_SelectedQuestId()
  if type(GetQuestLogSelection) ~= "function" then return nil end
  local index = GetQuestLogSelection()
  if not index or index <= 0 then return nil end
  if type(GetQuestIDForLogIndex) == "function" then
    local id = GetQuestIDForLogIndex(index)
    if id and id > 0 then return id end
  end
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestIDForLogIndex) == "function" then
    local id = C_QuestLog.GetQuestIDForLogIndex(index)
    if id and id > 0 then return id end
  end
  return nil
end

-- The NPC quest frames publish no id on any 1.12 client, with or without
-- ClassicAPI. What they do publish is the title, and the English quest records
-- are keyed by id and carry the title -- so the title is the handle. Built once,
-- on first use, from whatever record table is loaded.
--
-- A title two quests share identifies neither, so it is dropped rather than
-- resolved to whichever was seen first: showing the wrong quest's English text
-- is worse than showing none.
local titleIndex

function WHW_QuestIdByTitle(title)
  if type(title) ~= "string" or title == "" then return nil end
  if type(WordHunterWoW_QuestEN) ~= "table" then return nil end
  if not titleIndex then
    titleIndex = {}
    for id, entry in pairs(WordHunterWoW_QuestEN) do
      local recorded = type(entry) == "table" and entry.title or nil
      if type(recorded) == "string" and recorded ~= "" then
        local key = string.lower(recorded)
        if titleIndex[key] == nil then
          titleIndex[key] = id
        else
          titleIndex[key] = false
        end
      end
    end
  end
  local hit = titleIndex[string.lower(title)]
  if hit then return hit end
  return nil
end
