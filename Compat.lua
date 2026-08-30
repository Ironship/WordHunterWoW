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

local RETAIL, CLASSIC, SOD = "retail", "classic", "sod"

local resolved

local function projectFamily()
  -- Retail defines both of these. If we cannot tell what we are on, behave
  -- exactly as the addon did before this file existed.
  if type(WOW_PROJECT_ID) ~= "number" then return RETAIL end
  if type(WOW_PROJECT_MAINLINE) ~= "number" then return RETAIL end
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
function Compat.IsClassic() return Compat.GameFlavor() ~= RETAIL end
function Compat.IsSeasonOfDiscovery() return Compat.GameFlavor() == SOD end

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

-- The window an NPC opens when offering or handing in a quest. Named the same
-- in both games, which is why it is not probed by flavour.
function Compat.NpcQuestFrameShown()
  return shown(QuestFrame) and true or false
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
