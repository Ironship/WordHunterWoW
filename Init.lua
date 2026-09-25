local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
local addonName = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_FINISHED")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("GOSSIP_CLOSED")
events:SetScript("OnEvent", function(_, event, loadedAddon)
  if event == "ADDON_LOADED" then
    if loadedAddon == addonName then
      -- What the saved variables held the instant this addon was told it had
      -- loaded, recorded before anything here has had a chance to touch them.
      --
      -- On the Forever client words marked in one session are gone after a
      -- reload, and the file on disk is provably correct at the moment it is
      -- written: seven entries, the right keys, status "known". Feeding that
      -- same file through this addon's real load path outside the game keeps
      -- all seven. So the question is no longer what the code does with the
      -- table -- it is whether the table is there at all when the code runs,
      -- and that is a thing only the client can answer. /whw diag reads it back.
      Addon.loadSnapshot = {
        dbType = type(WordHunterWoWDB),
        words = 0,
        locales = {},
        version = type(WordHunterWoWDB) == "table" and WordHunterWoWDB.version or nil,
      }
      if type(WordHunterWoWDB) == "table" and type(WordHunterWoWDB.wordsByLocale) == "table" then
        for locale, words in pairs(WordHunterWoWDB.wordsByLocale) do
          local n = 0
          if type(words) == "table" then for _ in pairs(words) do n = n + 1 end end
          Addon.loadSnapshot.locales[locale] = n
          Addon.loadSnapshot.words = Addon.loadSnapshot.words + n
        end
      end
      Addon.initializeDatabase()
      Addon.createPanel()
      Addon.createEditor()
      Addon.hookQuestUi()
      if Addon.CreateSettingsPanel then Addon.CreateSettingsPanel() end
      local target = Addon.GetTargetLocale()
      local client = Addon.TextLocale()
      if client ~= target then
        local name = Addon.SUPPORTED_LOCALES[target] or target
        print(string.format("|cff66ccffWordHunterWoW:|r " .. LABELS.german, name, name))
      end
    elseif loadedAddon == "Blizzard_UIPanels_Game" or loadedAddon == "Blizzard_WorldMap"
        or loadedAddon == "Blizzard_QuestLog" then
      -- Classic's quest log is a load-on-demand addon of its own, so the names
      -- worth hooking may not exist until the player first opens it.
      Addon.hookQuestUi()
    end
  elseif event == "PLAYER_LOGIN" then
    -- The season only answers reliably once the player is in the world, and
    -- Classic's quest log may have loaded since ADDON_LOADED.
    Addon.Compat.Refresh()
    Addon.hookQuestUi()
    -- Remembered now, while the client is sure to answer it, so the collector
    -- still has it at a later moment that answers nothing or a secret value.
    if Addon.PlayerName then Addon.PlayerName() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    -- Its own branch: the last one below treats any event it is handed as a
    -- quest window opening.
    if Addon.PlayerName then Addon.PlayerName() end
  elseif event == "GOSSIP_SHOW" then
    Addon.lastPassage = "gossip"
    if Addon.HarvestGossip then Addon.HarvestGossip() end
    if Addon.readGossip then Addon.readGossip() end
  elseif event == "GOSSIP_CLOSED" then
    if Addon.lastQuest and Addon.lastQuest.passage == "gossip" then
      if Addon.panel then Addon.panel:Hide() end
      if Addon.editor then Addon.editor:Hide() end
    end
  elseif event == "QUEST_FINISHED" then
    Addon.lastPassage = "offer"
    if Addon.panel then Addon.panel:Hide() end
    if Addon.editor then Addon.editor:Hide() end
  else
    if event == "QUEST_PROGRESS" then
      Addon.lastPassage = "progress"
    elseif event == "QUEST_COMPLETE" then
      Addon.lastPassage = "reward"
    else
      Addon.lastPassage = "offer"
    end
    C_Timer.After(0, Addon.readCurrentQuest)
  end
end)

SLASH_WORDHUNTERWOW1 = "/whw"
SlashCmdList.WORDHUNTERWOW = function(message)
  local raw = strtrim(tostring(message or ""))
  local command = strlower(raw)
  if command == "reload" or command == "export" then
    Addon.rebuildExport()
    print("|cff66ccffWordHunterWoW:|r /reload writes the import file to SavedVariables.")
  elseif command:match("^harvest") then
    local arg = strtrim(command:match("^%S+%s*(.*)$") or "")
    if arg == "on" or arg == "off" then
      Addon.SetHarvestEnabled(arg == "on")
      print("|cff66ccffWordHunterWoW:|r Text collection " .. arg .. ".")
    elseif arg == "clear" then
      Addon.ClearHarvest()
      print("|cff66ccffWordHunterWoW:|r Collected text cleared.")
    elseif arg == "export" then
      Addon.rebuildHarvestExport()
      local blob = WordHunterWoWCorpusExport
      if Addon.showCopyText and type(blob) == "string" and blob ~= "" then
        Addon.showCopyText(Addon.LABELS.harvestExport, blob, Addon.LABELS.harvestExportHint)
      else
        print("|cff66ccffWordHunterWoW:|r Nothing to copy.")
      end
    else
      print(string.format("|cff66ccffWordHunterWoW:|r Text collection %s, %d passages and %d unglossed words for %s.  •  /whw harvest <on|off|export|clear>",
        Addon.GetHarvestEnabled() and "on" or "off", Addon.HarvestCount() - Addon.HarvestWordCount(),
        Addon.HarvestWordCount(), Addon.GetTargetLocale()))
    end
  elseif command:match("^difficult") then
    local arg = strtrim(command:match("^%S+%s*(.*)$") or "")
    if arg == "export" then
      local text = Addon.BuildDifficultExport and Addon.BuildDifficultExport() or ""
      if Addon.showCopyText and type(text) == "string" and text ~= "" then
        Addon.showCopyText(Addon.LABELS.difficultExport, text, Addon.LABELS.difficultExportHint)
      else
        print("|cff66ccffWordHunterWoW:|r Nothing to copy.")
      end
    else
      print(string.format("|cff66ccffWordHunterWoW:|r Recall check %s, %d difficult words for %s.  •  /whw difficult export  •  /whw recall <on|off>",
        Addon.GetRecallCheck and Addon.GetRecallCheck() and "on" or "off",
        Addon.CountDifficult and Addon.CountDifficult() or 0, Addon.GetTargetLocale()))
    end
  elseif command:match("^recall") then
    local arg = strtrim(command:match("^%S+%s*(.*)$") or "")
    if (arg == "on" or arg == "off") and Addon.SetRecallCheck then
      Addon.SetRecallCheck(arg == "on")
      print("|cff66ccffWordHunterWoW:|r Recall check " .. arg .. ".")
    else
      print(string.format("|cff66ccffWordHunterWoW:|r Recall check %s.  •  /whw recall <on|off>",
        Addon.GetRecallCheck and Addon.GetRecallCheck() and "on" or "off"))
    end
  elseif command == "reset" or command == "resetlayout" then
    -- A way back from a window dragged off the screen or shrunk to nothing.
    -- Without one the only remedy is deleting the saved file, which takes the
    -- player's whole word list with it.
    Addon.ResetLayout()
  elseif command == "words" then
    Addon.toggleWordList()
  elseif command == "stats" then
    Addon.toggleStats()
  -- Three numbers that together say where a word went: what the client handed
  -- over at load, what the table holds now, and what the addon can reach
  -- through the locale it is actually using. A word that is on disk, absent at
  -- load and absent now was never given to the addon; one present at load and
  -- absent now was dropped in this session; one present in the table but not
  -- through GetWordsTable is filed under a locale nobody is reading.
  elseif command == "diag" then
    local snap = Addon.loadSnapshot
    local live, byLocale = 0, {}
    if type(WordHunterWoWDB) == "table" and type(WordHunterWoWDB.wordsByLocale) == "table" then
      for locale, words in pairs(WordHunterWoWDB.wordsByLocale) do
        local n = 0
        if type(words) == "table" then for _ in pairs(words) do n = n + 1 end end
        byLocale[#byLocale + 1] = locale .. "=" .. n
        live = live + n
      end
    end
    local reachable = 0
    for _ in pairs(Addon.GetWordsTable()) do reachable = reachable + 1 end
    print("|cff59aefaWordHunterWoW diag:|r")
    print(string.format("  at load:    %s, %d words%s",
      snap and snap.dbType or "(never fired)",
      snap and snap.words or 0,
      snap and snap.version and (", db v" .. tostring(snap.version)) or ""))
    print(string.format("  now:        %d words  [%s]", live,
      table.concat(byLocale, " ")))
    print(string.format("  reachable:  %d  via locale %s",
      reachable, tostring(Addon.GetTargetLocale())))
    print(string.format("  game:       %s", tostring(Addon.Compat and Addon.Compat.GameFlavor())))
    -- Where the flavour comes from, because on the Forever client it answered
    -- "retail" with this file's own fix installed. The manifest reader is the
    -- half that can fail quietly: a client with neither C_AddOns nor the global
    -- returns nothing, and a name that is not the folder's returns nothing
    -- either, and both look identical from outside.
    local reader = (type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata and "C_AddOns")
      or (type(GetAddOnMetadata) == "function" and "global") or "NONE"
    local get = (type(C_AddOns) == "table" and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local iface, title
    if type(get) == "function" then
      local ok1, v1 = pcall(get, addonName, "Interface")
      local ok2, v2 = pcall(get, addonName, "Title")
      iface = ok1 and tostring(v1) or ("pcall failed: " .. tostring(v1))
      title = ok2 and tostring(v2) or "?"
    end
    print(string.format("  manifest:   reader=%s  name=%s", reader, tostring(addonName)))
    print(string.format("              Interface=%s  Title=%s", tostring(iface), tostring(title)))
    local version, _, _, build = GetBuildInfo and GetBuildInfo()
    print(string.format("              GetBuildInfo=%s (%s)  PROJECT_ID=%s",
      tostring(version), tostring(build), tostring(WOW_PROJECT_ID)))
    -- What the client answers for the player's own name right now, because on
    -- the Forever client the name got past both harvest guards and nobody knows
    -- what UnitName gave them. A secret value is described, never printed or
    -- compared: touching one is what the check is there to avoid.
    local raw, rawType, secret, shown = nil, "no UnitName", "n/a", "-"
    if type(UnitName) == "function" then
      local ok, value = pcall(UnitName, "player")
      if not ok then
        rawType = "error: " .. tostring(value)
      else
        raw = value
        rawType = type(raw)
        if type(issecretvalue) ~= "function" then
          secret = "no issecretvalue"
        else
          secret = Addon.IsSecretValue and Addon.IsSecretValue(raw) and "yes" or "no"
        end
        if secret ~= "yes" and rawType == "string" then shown = "\"" .. raw .. "\"" end
      end
    end
    local cached = Addon.CachedPlayerName and Addon.CachedPlayerName()
    print(string.format("  name:       UnitName type=%s secret=%s value=%s  cached=%s",
      rawType, secret, shown, cached and ("\"" .. cached .. "\"") or "none"))
  -- Reading mode has a slash command as well as a settings box because it is
  -- the one setting here somebody turns on and off inside a single session:
  -- read a quest, take the quest, go back to playing. A trip through the
  -- options panel for that is a trip nobody makes twice.
  elseif command == "read" or command == "reading" then
    if Addon.ToggleReadingMode then
      local on = Addon.ToggleReadingMode()
      if print then
        print("|cff59aefaWordHunterWoW:|r " ..
          (on and Addon.LABELS.readingOn or Addon.LABELS.readingOff))
      end
    end
  elseif command == "settings" or command == "config" or command == "options" then
    if Addon.OpenSettings then Addon.OpenSettings() end
  elseif command:match("^bg%s+") then
    local key = strlower(strtrim(command:match("^bg%s+(.+)$") or ""))
    if Addon.BACKGROUNDS[key] then
      Addon.SetBackgroundStyle(key)
      print("|cff66ccffWordHunterWoW:|r Background: " .. Addon.BACKGROUNDS[key].name)
    else
      print("|cff66ccffWordHunterWoW:|r /whw bg <tooltip|dialog|solid|midnight>  •  /whw settings")
    end
  elseif command:match("^opacity%s*") or command:match("^alpha%s*") then
    local valStr = strtrim(command:match("^%S+%s*(.*)$") or "")
    if valStr == "" then
      print(string.format("|cff66ccffWordHunterWoW:|r Opacity: %d%%  •  /whw opacity <0-100>", math.floor(Addon.GetOpacity() * 100 + 0.5)))
    else
      local val = tonumber(valStr)
      if val and val > 1 and val <= 100 then val = val / 100 end
      if val and val >= 0 and val <= 1.0 then
        Addon.SetOpacity(val)
        print(string.format("|cff66ccffWordHunterWoW:|r Opacity: %d%%", math.floor(val * 100 + 0.5)))
      else
        print("|cff66ccffWordHunterWoW:|r /whw opacity <0-100>  •  e.g. /whw opacity 85")
      end
    end
  elseif command:match("^lang") then
    local arg = strtrim(command:match("^%S+%s*(.*)$") or "")
    if arg == "" then
      local cur = Addon.GetTargetLocale()
      print(string.format("|cff66ccffWordHunterWoW:|r Language: %s (%s)  •  /whw lang <%s>", Addon.SUPPORTED_LOCALES[cur] or cur, cur, table.concat(Addon.SUPPORTED_LOCALE_LIST, "|")))
    else
      local norm = strlower(strtrim(arg))
      local found
      for _, loc in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
        if strlower(loc) == norm then found = loc; break end
      end
      if not found then
        local matches = {}
        for _, loc in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
          if strlower(loc):sub(1, #norm) == norm then matches[#matches + 1] = loc end
        end
        -- "es" matches esES and esMX; only a unique prefix is safe to guess.
        if #matches == 1 then found = matches[1] end
      end
      if found and Addon.SUPPORTED_LOCALES[found] then
        Addon.SetTargetLocale(found)
        print(string.format("|cff66ccffWordHunterWoW:|r Language: %s (%s)", Addon.SUPPORTED_LOCALES[found], found))
      else
        print("|cff66ccffWordHunterWoW:|r /whw lang <" .. table.concat(Addon.SUPPORTED_LOCALE_LIST, "|") .. ">")
      end
    end
  elseif Addon.listFrame and Addon.listFrame:IsShown() then
    Addon.listFrame:Hide()
  elseif Addon.statsFrame and Addon.statsFrame:IsShown() then
    Addon.statsFrame:Hide()
  elseif Addon.panel and Addon.panel:IsShown() then
    Addon.panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
  elseif Addon.panel then
    if Addon.lastQuest then Addon.refreshPanel() else print("|cff66ccffWordHunterWoW:|r " .. LABELS.empty) end
    Addon.panel:Show()
  end
end
