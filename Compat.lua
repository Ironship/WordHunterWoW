local ADDON_NAME = ...
local Addon = WordHunterWoW_Addon

-- Retail, Classic Era and Season of Discovery run the same addon, but they do
-- not share Blizzard's quest API or its quest log frames. Everything that
-- touches either goes through this file, so the rest of the addon never has to
-- know which game it is running on.
--
-- Two rules shape what follows.
--
-- The first: the season cannot be read while the TOC's files are still running.
-- C_Seasons answers late, and before the player is in the world it answers
-- wrong. So the flavour is a function that resolves on first use and is
-- refreshed at PLAYER_LOGIN, never a constant computed at load time.
--
-- The second: this was written without a Classic client to try it on. Nothing
-- here assumes a function exists or that it takes the arguments Retail's
-- version takes. Every call is probed, every fallback is reachable, and the
-- places that still want confirmation in game are marked CONFIRM.

local Compat = {}
Addon.Compat = Compat

local RETAIL, CLASSIC, SOD, FOREVER = "retail", "classic", "sod", "forever"

local resolved

-- World of Warcraft: Forever, and why it cannot be recognised the way the
-- others are.
--
-- It is a Classic-line game running on a client built from Retail's code. Asked
-- the usual questions it gives Retail's answers: GetBuildInfo returns a
-- Retail-family interface number, and WOW_PROJECT_ID equals
-- WOW_PROJECT_MAINLINE. Every branch below therefore reached RETAIL, and on
-- 2026-09-18 that was not a theory -- thirteen passages of Forever's own quests
-- came out of the harvester stamped "retail" and were merged into the Retail
-- corpus beside Blizzard's, which is the one thing import_harvest's own comment
-- says must never happen: the same quest id is different text on a different
-- game, and one file holding both corrupts both.
--
-- So it is recognised by the only thing here that does not come from the
-- client: this addon's own manifest. Forever requires interface 16001 and the
-- build for it ships a _Camelot.toc saying so, while the Retail build says
-- 120100 and the Classic one 11509. The question this answers is "which build
-- of this addon am I", which is the honest one -- the Forever build exists for
-- exactly one game, and no other build can be mistaken for it.
local FOREVER_INTERFACE = 16001

local function manifestInterface()
  local get = (type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata)
    or GetAddOnMetadata
  if type(get) ~= "function" then return nil end
  -- Probed, like everything else here: this runs on clients whose oldest
  -- members have neither the namespace nor the global, and a missing manifest
  -- has to read as "not Forever" rather than as an error at load time.
  local ok, value = pcall(get, ADDON_NAME or "WordHunterWoW", "Interface")
  if not ok then return nil end
  -- A single number, or nothing. The Forever bundle ships one manifest that
  -- lists every interface it runs under, and on 2026-09-19 tonumber() of that
  -- list was nil, so the bundle read as Retail with this very check in place.
  -- A list decides nothing here; the client's version below decides for it.
  return tonumber(value)
end

-- The one answer the Forever client gives that is not Retail's: its version.
-- Retail is 12.x, Classic Era 1.15.x, and Forever 1.60.x -- the numbering the
-- CurseForge packager keys its "forever" game type on as well. Read from the
-- first value GetBuildInfo returns, because the fourth, the interface number,
-- came back nil on that client.
local function clientIsForever()
  if type(GetBuildInfo) ~= "function" then return false end
  local ok, version = pcall(GetBuildInfo)
  if not ok or type(version) ~= "string" then return false end
  local major, minor = version:match("^(%d+)%.(%d+)")
  return tonumber(major) == 1 and (tonumber(minor) or 0) >= 60
end

local function projectFamily()
  -- Asked before anything else, because the client's other answers are the
  -- ones that are wrong on Forever.
  if clientIsForever() or manifestInterface() == FOREVER_INTERFACE then return FOREVER end

  -- The interface number first, because it is the only answer that does not
  -- depend on a global existing.
  --
  -- This used to fall straight through to RETAIL when WOW_PROJECT_ID was not a
  -- number, on the reasoning that an addon which cannot tell where it is should
  -- behave as it did before this file existed. That reasoning had the case
  -- backwards. WOW_PROJECT_ID arrived with Classic in 2019, so its absence does
  -- not mean "some client we have not heard of" -- it means a client older than
  -- Classic, which is the one thing it certainly is not: Retail.
  --
  -- It is not hypothetical. A 1.12 build of this addon is running on a Project
  -- Legacy client, and it carries its own copy of this file for exactly this
  -- reason, with the inversion made by hand. The same fault reaches every 3.3.5
  -- client too, which defines neither global either.
  local _, _, _, interface = GetBuildInfo and GetBuildInfo()
  interface = tonumber(interface)
  if interface and interface < 20000 and interface >= 11500 then
    -- Classic Era proper: 11509 and its neighbours. Below that is 1.x.
    return CLASSIC
  end
  if interface and interface < 11500 then return CLASSIC end
  if type(WOW_PROJECT_ID) ~= "number" then return CLASSIC end
  if type(WOW_PROJECT_MAINLINE) ~= "number" then return CLASSIC end
  if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then return RETAIL end
  return CLASSIC
end

-- Season of Discovery runs on the Classic Era client, so the project id cannot
-- tell them apart. The season id is deliberately not written down here: it is
-- read from Enum.SeasonID by name. A client without C_Seasons, without the
-- enum, or reporting a season we cannot name is treated as Era, which is the
-- safe answer -- Era data on Era is right, and Era data on SoD is merely
-- incomplete, while the reverse would show text from a game the player is not
-- in.
local function seasonIsDiscovery()
  if type(C_Seasons) ~= "table" or type(C_Seasons.GetActiveSeason) ~= "function" then
    return false
  end
  local ok, active = pcall(C_Seasons.GetActiveSeason)
  if not ok or type(active) ~= "number" then return false end
  local ids = type(Enum) == "table" and Enum.SeasonID or nil
  if type(ids) ~= "table" then return false end
  local discovery = ids.SeasonOfDiscovery
  if type(discovery) ~= "number" then return false end
  return active == discovery
end

function Compat.Refresh()
  local family = projectFamily()
  if family == RETAIL then
    resolved = RETAIL
  elseif family == FOREVER then
    -- Not put through the season check: C_Seasons exists on this client and
    -- answers for a season Forever is not in, and a Forever corpus filed as
    -- Season of Discovery is the same mistake as filing it as Retail, one
    -- folder further along.
    resolved = FOREVER
  elseif seasonIsDiscovery() then
    resolved = SOD
  else
    resolved = CLASSIC
  end
  return resolved
end

function Compat.GameFlavor()
  if not resolved then Compat.Refresh() end
  return resolved
end

function Compat.IsRetail() return Compat.GameFlavor() == RETAIL end
-- Everything that is not Retail, Forever included. That is deliberate and not
-- an oversight of the new value: Forever is a Classic-line game and wants the
-- Classic quest log calls, the Classic frame names and the Classic defaults.
-- What it must not share is the corpus, and that is keyed on GameFlavor.
function Compat.IsClassic() return Compat.GameFlavor() ~= RETAIL end
function Compat.IsSeasonOfDiscovery() return Compat.GameFlavor() == SOD end
function Compat.IsForever() return Compat.GameFlavor() == FOREVER end

-- Recorded alongside harvested text so a corpus built on one game is never
-- mistaken for one built on another.
function Compat.BuildInfo()
  if type(GetBuildInfo) ~= "function" then return nil, nil end
  local version, build = GetBuildInfo()
  return version, build
end

-- Quest log ------------------------------------------------------------------

function Compat.QuestLogIndexForID(questId)
  if not questId or questId <= 0 then return nil end
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetLogIndexForQuestID) == "function" then
    local index = C_QuestLog.GetLogIndexForQuestID(questId)
    if index and index > 0 then return index end
  end
  -- CONFIRM: the Classic Era name for the same lookup.
  if type(GetQuestLogIndexByID) == "function" then
    local index = GetQuestLogIndexByID(questId)
    if index and index > 0 then return index end
  end
  return nil
end

local function idThatMapsBack(index, ...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    -- Classic returns the quest id among GetQuestLogTitle's later results and
    -- its position has moved between builds. Rather than counting commas, try
    -- every number it returned and keep the one that maps back to the index we
    -- started from. A level or a group size will not.
    if type(value) == "number" and value > 0 and Compat.QuestLogIndexForID(value) == index then
      return value
    end
  end
  return nil
end

function Compat.QuestIDForLogIndex(index)
  if not index or index <= 0 then return nil end
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetQuestIDForLogIndex) == "function" then
    local questId = C_QuestLog.GetQuestIDForLogIndex(index)
    if questId and questId > 0 then return questId end
  end
  if type(GetQuestLogTitle) == "function" then
    return idThatMapsBack(index, GetQuestLogTitle(index))
  end
  return nil
end

function Compat.SelectedQuestID()
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetSelectedQuest) == "function" then
    local questId = C_QuestLog.GetSelectedQuest()
    if questId and questId > 0 then return questId end
  end
  if type(GetQuestLogSelection) == "function" then
    local index = GetQuestLogSelection()
    if index and index > 0 then return Compat.QuestIDForLogIndex(index) end
  end
  return nil
end

function Compat.TitleForQuestID(questId)
  if not questId or questId <= 0 then return nil end
  if type(C_QuestLog) == "table" and type(C_QuestLog.GetTitleForQuestID) == "function" then
    local title = C_QuestLog.GetTitleForQuestID(questId)
    if title and title ~= "" then return title end
  end
  if type(GetQuestLogTitle) == "function" then
    local index = Compat.QuestLogIndexForID(questId)
    if index then
      local title = GetQuestLogTitle(index)
      if type(title) == "string" and title ~= "" then return title end
    end
  end
  return nil
end

-- Retail's GetQuestLogQuestText takes the log index. Classic's takes nothing
-- and reads whichever entry is currently selected, so the entry has to be
-- selected first -- and the player's own selection put back, or the quest log
-- jumps under their hands.
function Compat.QuestLogText(questLogIndex)
  if type(GetQuestLogQuestText) ~= "function" then return "", "" end
  if Compat.IsRetail() then
    if questLogIndex then return GetQuestLogQuestText(questLogIndex) end
    return GetQuestLogQuestText()
  end
  if not questLogIndex then return GetQuestLogQuestText() end
  if type(SelectQuestLogEntry) ~= "function" then return GetQuestLogQuestText() end
  local previous = type(GetQuestLogSelection) == "function" and GetQuestLogSelection() or nil
  local moved = previous ~= questLogIndex
  if moved then SelectQuestLogEntry(questLogIndex) end
  local description, objectives = GetQuestLogQuestText()
  if moved and previous and previous > 0 then SelectQuestLogEntry(previous) end
  return description, objectives
end

-- Frames ---------------------------------------------------------------------

local function shown(frame)
  return type(frame) == "table" and type(frame.IsShown) == "function" and frame:IsShown()
end

-- Addons that replace the quest dialogue with a window of their own. Each one
-- leaves Blizzard's QuestFrame hidden for the rest of the session, so a panel
-- that waits for QuestFrame to appear waits forever once any of them is
-- installed. They are listed by the global each publishes; `child` is for the
-- ones whose window serves gossip as well and says which field is the quest
-- half. The windows are built on first use, so they are looked up on every
-- call rather than remembered.
local DIALOGUE_REPLACEMENTS = {
  { global = "DUIQuestFrame" },                        -- DialogueUI, Peterodox
  { global = "LWDialogFrame", child = "QuestFrame" },  -- Lorewalker, AdaptiveX
}

-- The replacement window standing in for the quest dialogue right now, if any.
function Compat.ReplacementQuestFrame()
  for _, entry in ipairs(DIALOGUE_REPLACEMENTS) do
    local frame = _G[entry.global]
    if shown(frame) and (not entry.child or shown(frame[entry.child])) then
      return frame
    end
  end
  return nil
end

-- A replacement window is built the first time somebody speaks to an NPC, and
-- it may go up a frame later than the quest event that caused it -- in which
-- case asking "is it shown?" on that event answers no and the panel stays
-- closed. Hooking the window's own OnShow asks again once it is really up, so
-- the order of the two stops mattering. A hook cannot be undone, hence the
-- once-per-window guard.
local dialogueHooked = {}

function Compat.HookReplacementDialogue(handler)
  local any = false
  for _, entry in ipairs(DIALOGUE_REPLACEMENTS) do
    local frame = _G[entry.global]
    if type(frame) == "table" and type(frame.HookScript) == "function" then
      if not dialogueHooked[entry.global] then
        dialogueHooked[entry.global] = true
        frame:HookScript("OnShow", handler)
      end
      any = true
    end
  end
  return any
end

-- The window an NPC opens when offering or handing in a quest. Named the same
-- in both games, which is why it is not probed by flavour.
function Compat.NpcQuestFrameShown()
  if shown(QuestFrame) then return true end
  return Compat.ReplacementQuestFrame() ~= nil
end

-- Retail keeps the quest log inside the world map; Classic has its own window.
function Compat.QuestLogFrame()
  if shown(QuestLogFrame) then return QuestLogFrame end
  if shown(QuestMapFrame) then return QuestMapFrame end
  if shown(WorldMapFrame) then return WorldMapFrame end
  return nil
end

function Compat.QuestLogShown()
  return Compat.QuestLogFrame() ~= nil
end

-- Hooks ----------------------------------------------------------------------

-- Every name that means "the quest text on screen just changed". The first two
-- are Retail's, the last two Classic's; a name that does not exist on this
-- client is skipped rather than assumed. Hooking happens once per name for the
-- lifetime of the session -- hooksecurefunc cannot be undone, so hooking twice
-- would fire the handler twice.
local QUEST_TEXT_HOOKS = {
  "QuestInfo_ShowDescriptionText",
  "QuestMapFrame_ShowQuestDetails",
  "QuestLog_UpdateQuestDetails",
  "QuestLog_SetSelection",
}

local hooked = {}

function Compat.HookQuestUi(handler)
  local installed = 0
  for _, name in ipairs(QUEST_TEXT_HOOKS) do
    if not hooked[name] and type(_G[name]) == "function" then
      hooked[name] = true
      hooksecurefunc(name, function(...) handler(name, ...) end)
      installed = installed + 1
    end
  end
  return installed
end
