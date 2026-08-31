local Addon = WordHunterWoW_Addon or {}
WordHunterWoW_Addon = Addon

Addon.COLORS = {
  new = { 0.35, 0.68, 1.00 },
  learning = { 1.00, 0.66, 0.18 },
  known = { 0.30, 0.88, 0.48 },
  ignored = { 0.55, 0.59, 0.66 },
  neutral = { 0.45, 0.55, 0.70 },
  -- The "no English for this passage" notice. Red so it reads as a warning about
  -- the text below it rather than as part of the quest.
  caveat = { 1.00, 0.42, 0.42 },
}

Addon.STATUS_LABELS = {
  new = "New",
  learning = "Learning",
  known = "Known",
  ignored = "Ignored",
}

Addon.SUPPORTED_LOCALES = {
  enUS = "English (US)",
  enGB = "English (GB)",
  deDE = "German",
  frFR = "French",
  esES = "Spanish (EU)",
  esMX = "Spanish (MX)",
  itIT = "Italian",
  ptBR = "Portuguese (BR)",
}
Addon.SUPPORTED_LOCALE_LIST = { "enUS", "enGB", "deDE", "frFR", "esES", "esMX", "itIT", "ptBR" }
Addon.WH_LANGUAGE_MAP = {
  enUS = "en",
  enGB = "en",
  deDE = "de",
  frFR = "fr",
  esES = "es",
  esMX = "es",
  itIT = "it",
  ptBR = "pt",
}

Addon.LABELS = {
  meaning = "Meaning / translation",
  note = "Note",
  copyWord = "Copy word",
  copyQuest = "Copy quest",
  copyHint = "Press Ctrl+C to copy",
  save = "Save",
  cancel = "Cancel",
  status = "Status",
  empty = "Open a quest to mark words.",
  german = "For %s quest text, set the WoW text language to %s.",
  saved = "%d saved",
  readyForKnown = "Ready for Known",
  listTitle = "WORD LIST",
  search = "Search",
  all = "All",
  hideIgnored = "Hide Ignored",
  wordsButton = "Words",
  statsButton = "Stats",
  statsTitle = "STATISTICS",
  statsSummary = "%d words",
  added7 = "Added (7 days)",
  added30 = "Added (30 days)",
  mostEncountered = "Most encountered",
  settingsTitle = "WordHunterWoW Settings",
  backgroundLabel = "Background style",
  opacityLabel = "Opacity",
  languageLabel = "Target (learned and in game) language",
  resetDictionary = "Reset to dictionary",
  confirmAction = "Reset",
  confirmCancel = "Cancel",
  -- Shown before the reset happens. Someone checking whether they still have
  -- their own edit needs to see what the dictionary would put back, not find
  -- out afterwards.
  resetConfirmBody = "This replaces what you have written with the dictionary's own version.\n\n"
    .. "|cff8ab4f8Meaning|r\n%s\n\n|cff8ab4f8Note|r\n%s",
  resetNothing = "|cff888888(empty)|r",
  harvestExport = "Export collected text",
  -- The file only reaches disk when the game writes its saved variables, which
  -- it does on reload or logout and at no other time. Someone who exports and
  -- then goes looking finds yesterday's file and reasonably concludes it broke.
  harvestExportBody = "%d passages and %d words are ready to send.\n\n"
    .. "|cffffcc66The file is only written when you reload or log out.|r "
    .. "Do that first, then find it here:",
  harvestExportEmpty = "Nothing has been collected yet.\n\n"
    .. "Switch on the box above and read a few quests, then come back.",
  harvestExportReload = "Reload now",
  integratedLabel = "Integrated quest window",
  harvestLabel = "Collect quest and NPC text for the dictionary project",
  harvestNote = "Off by default. Records objectives, progress and hand-in text plus NPC dialogue you actually see — the passages Blizzard's quest API does not publish. Stored locally; %d passages and %d words no dictionary covers. /whw harvest",
  englishHeader = "English",
  enOfferOnly = "[Blizzard publishes no English text for this part of a quest. Showing the quest's opening text instead.]",
  -- Classic quest records carry a title and an objective and no opening text at
  -- all. Without this the objective sits alone under a paragraph of German and
  -- reads as a translation that was cut short.
  enNoOffer = "[No English opening text exists for this quest. Showing its objective.]",
}

Addon.BACKGROUNDS = {
  tooltip = {
    name = "Tooltip (Classic Dark)",
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 16,
    tile = true,
    tileSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
    bgColor = { 0.04, 0.06, 0.10, 0.94 },
  },
  dialog = {
    name = "Dialog (Parchment)",
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    edgeSize = 32,
    tile = true,
    tileSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
    bgColor = { 1, 1, 1, 1 },
  },
  solid = {
    name = "Solid Dark",
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    tile = false,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
    bgColor = { 0.06, 0.07, 0.09, 0.96 },
  },
  midnight = {
    name = "Midnight (Modern)",
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
    bgColor = { 0.08, 0.09, 0.13, 0.97 },
    borderColor = { 0.22, 0.24, 0.34, 0.95 },
  },
}

Addon.BACKGROUND_ORDER = { "tooltip", "dialog", "solid", "midnight" }

-- What the panel wears before the player has chosen anything. Classic's whole
-- interface is the old tooltip frame, so a panel in the same skin reads as part
-- of the game next to a German quest rather than as something bolted on.
--
-- This is one function because it is needed in two places -- here, and where
-- the database seeds its defaults -- and the two must not drift apart. They did
-- once: the read side learned about Classic while the write side kept stamping
-- "midnight" into the settings on first run, which made this branch unreachable.
function Addon.DefaultBackgroundStyle()
  if Addon.Compat and Addon.Compat.IsClassic() then return "tooltip" end
  return "midnight"
end

function Addon.GetBackgroundStyle()
  local key = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.background
  if key and Addon.BACKGROUNDS[key] then return key end
  return Addon.DefaultBackgroundStyle()
end

function Addon.GetOpacity()
  local v = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.opacity
  if type(v) == "number" and v >= 0 and v <= 1.0 then return v end
  return 1.0
end

function Addon.GetIntegratedLayout()
  local v = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.integratedLayout
  if v == nil then return true end
  return v and true or false
end

function Addon.SetIntegratedLayout(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.integratedLayout = not not value
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  if Addon.OnIntegratedLayoutChanged then Addon.OnIntegratedLayoutChanged(Addon.GetIntegratedLayout()) end
end

function Addon.SetOpacity(value)
  value = tonumber(value)
  if not value then return end
  value = math.max(0, math.min(1.0, value))
  value = math.floor(value * 20 + 0.5) / 20
  WordHunterWoWDB.settings.opacity = value
  Addon.RefreshAllBackdrops()
  if Addon.settingsPanel and Addon.settingsPanel:IsShown() and Addon.settingsPanel.refresh then
    Addon.settingsPanel.refresh()
  end
end

function Addon.GetTargetLocale()
  local v = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.targetLocale
  if v and Addon.SUPPORTED_LOCALES[v] then return v end
  local client = GetLocale and GetLocale() or "deDE"
  if Addon.SUPPORTED_LOCALES[client] then return client end
  return "deDE"
end

function Addon.SetTargetLocale(locale)
  if not Addon.SUPPORTED_LOCALES[locale] then return end
  WordHunterWoWDB.settings.targetLocale = locale
  Addon.GetWordsTable()
  Addon.rebuildExport()
  if Addon.settingsPanel and Addon.settingsPanel.refresh then
    Addon.settingsPanel.refresh()
  end
  if Addon.listFrame and Addon.listFrame:IsShown() then Addon.refreshWordList() end
  if Addon.statsFrame and Addon.statsFrame:IsShown() then Addon.statsFrame:Hide() end
  if Addon.panel and Addon.panel:IsShown() and Addon.lastQuest then Addon.refreshPanel() end
end

function Addon.GetWordsTable()
  local locale = Addon.GetTargetLocale()
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.wordsByLocale) ~= "table" then WordHunterWoWDB.wordsByLocale = {} end
  if type(WordHunterWoWDB.wordsByLocale[locale]) ~= "table" then WordHunterWoWDB.wordsByLocale[locale] = {} end
  WordHunterWoWDB.words = WordHunterWoWDB.wordsByLocale[locale]
  return WordHunterWoWDB.wordsByLocale[locale]
end

Addon.DictionaryProviders = Addon.DictionaryProviders or {}
Addon.DictionaryProviderOrder = Addon.DictionaryProviderOrder or {}

function Addon.RegisterDictionaryProvider(locale, providerId, entries)
  if not Addon.SUPPORTED_LOCALES[locale] or type(providerId) ~= "string" or type(entries) ~= "table" then return false end
  if type(Addon.DictionaryProviders[locale]) ~= "table" then Addon.DictionaryProviders[locale] = {} end
  if type(Addon.DictionaryProviderOrder[locale]) ~= "table" then Addon.DictionaryProviderOrder[locale] = {} end
  if not Addon.DictionaryProviders[locale][providerId] then
    Addon.DictionaryProviderOrder[locale][#Addon.DictionaryProviderOrder[locale] + 1] = providerId
  end
  Addon.DictionaryProviders[locale][providerId] = entries
  if Addon.listFrame and Addon.listFrame:IsShown() and Addon.refreshWordList then Addon.refreshWordList() end
  if Addon.panel and Addon.panel:IsShown() and Addon.lastQuest and Addon.refreshPanel then Addon.refreshPanel() end
  return true
end

function Addon.GetDictionaryEntry(key, locale)
  locale = locale or Addon.GetTargetLocale()
  local providers = Addon.DictionaryProviders[locale]
  local order = Addon.DictionaryProviderOrder[locale]
  if not providers or not order then return nil end
  for i = #order, 1, -1 do
    local providerId = order[i]
    local entry = providers[providerId] and providers[providerId][key]
    if entry then return entry, providerId end
  end
end

function Addon.GetEffectiveWord(key)
  local user = Addon.GetWordsTable()[key]
  if user then return user, false end
  local dict, providerId = Addon.GetDictionaryEntry(key)
  if not dict then return nil, false end
  return {
    word = dict.word or key,
    status = (dict.status == "ignored" or dict.status == "known" or dict.status == "learning" or dict.status == "new") and dict.status or "new",
    translation = dict.translation or "",
    note = dict.note or "",
    dictionaryProvider = providerId,
    builtInDictionary = true,
  }, true
end

local VALID_STATUS = { new = true, learning = true, known = true, ignored = true }

function Addon.EffectiveStatus(entry)
  local status = entry and entry.status
  if VALID_STATUS[status] then return status end
  return "new"
end

-- Walks the player's words plus every dictionary entry without building a merged
-- copy first. A locale pack ships ~74k entries, so materialising the merge — as
-- GetEffectiveWords has to — allocates a table per entry every call, and the word
-- list calls it on each keystroke in the search box.
-- The callback gets the entry as stored; read its status through EffectiveStatus.
function Addon.ForEachEffectiveWord(fn)
  local locale = Addon.GetTargetLocale()
  local providers = Addon.DictionaryProviders[locale] or {}
  local order = Addon.DictionaryProviderOrder[locale] or {}
  local user = Addon.GetWordsTable()
  -- Later providers win, so walk backwards and keep the first hit. With a single
  -- provider — the normal case — no bookkeeping table is needed at all.
  local emitted = (#order > 1) and {} or nil
  for index = #order, 1, -1 do
    local providerId = order[index]
    for key, entry in pairs(providers[providerId] or {}) do
      if user[key] == nil and (emitted == nil or emitted[key] == nil) then
        if emitted then emitted[key] = true end
        fn(key, entry, true, providerId)
      end
    end
  end
  for key, entry in pairs(user) do fn(key, entry, false) end
end

function Addon.GetEffectiveWords()
  local result = {}
  Addon.ForEachEffectiveWord(function(key, entry, isDictionary, providerId)
    if isDictionary then
      result[key] = {
        word = entry.word or key,
        status = Addon.EffectiveStatus(entry),
        translation = entry.translation or "",
        note = entry.note or "",
        dictionaryProvider = providerId,
        builtInDictionary = true,
      }
    else
      result[key] = entry
    end
  end)
  return result
end

function Addon.ApplyBackground(frame, alphaOverride)
  if not frame or not frame.SetBackdrop then return end
  local style = Addon.BACKGROUNDS[Addon.GetBackgroundStyle()] or Addon.BACKGROUNDS.midnight
  frame:SetBackdrop({
    bgFile = style.bgFile,
    edgeFile = style.edgeFile,
    edgeSize = style.edgeSize,
    tile = style.tile,
    tileSize = style.tileSize,
    insets = style.insets,
  })
  local c = style.bgColor
  local alpha = alphaOverride or Addon.GetOpacity()
  frame:SetBackdropColor(c[1], c[2], c[3], alpha)
  if style.borderColor then
    local b = style.borderColor
    frame:SetBackdropBorderColor(b[1], b[2], b[3], alpha)
  end
  frame:SetToplevel(true)
end

function Addon.SetBackgroundStyle(key)
  if not Addon.BACKGROUNDS[key] then return end
  WordHunterWoWDB.settings.background = key
  Addon.RefreshAllBackdrops()
end

function Addon.RefreshAllBackdrops()
  for _, f in ipairs({ Addon.panel, Addon.editor, Addon.listFrame, Addon.statsFrame, Addon.copyDialog, Addon.enPanel, Addon.settingsPanel and Addon.settingsPanel.preview }) do
    if f and f.SetBackdrop then Addon.ApplyBackground(f) end
  end
end

function Addon.trim(value)
  return strtrim(tostring(value or ""))
end

local function stripMark(value, mark)
  while value:sub(1, #mark) == mark do value = value:sub(#mark + 1) end
  while value:sub(-#mark) == mark do value = value:sub(1, -#mark - 1) end
  return value
end

-- Quest text arrives with its paragraphs in it. Both columns of the panel have
-- to walk it the same way -- line by line, then word by word -- or the German
-- and the English stop lining up with each other, which is the whole point of
-- showing them side by side. Returned as a list of lines, each a list of words,
-- so the walk can be checked on its own rather than only through the layout.
function Addon.TextLines(text)
  local body = tostring(text or "")
  -- A trailing break ends the last line rather than starting an empty one
  -- after it, which would leave a gap hanging under the text.
  if body:sub(-1) ~= "\n" then body = body .. "\n" end
  local lines = {}
  for line in body:gmatch("([^\n]*)\n") do
    local tokens = {}
    for token in line:gmatch("%S+") do tokens[#tokens + 1] = token end
    lines[#lines + 1] = tokens
  end
  return lines
end

function Addon.cleanWord(token)
  local word = Addon.trim(token):gsub("^[%p]+", ""):gsub("[%p]+$", "")
  for _, mark in ipairs({ "„", "“", "”", "‚", "‘", "’", "«", "»", "…", "–", "—" }) do
    word = stripMark(word, mark)
  end
  return Addon.trim(word)
end

-- strlower only knows ASCII, so it leaves À Ä É Ñ Ü and the rest of the accented
-- capitals untouched. Dictionary keys are folded with full Unicode rules, so an
-- unfolded capital never matches and the word also gets its own list entry.
-- Latin-1 Supplement capitals are C3 80..9E and lowercase to the same byte + 0x20;
-- C3 97 in that range is the multiplication sign, not a letter.
local LATIN_EXTRA_LOWER = {
  ["Œ"] = "œ", ["Ÿ"] = "ÿ", ["Š"] = "š", ["Ž"] = "ž", ["Đ"] = "đ",
}

function Addon.utf8Lower(text)
  text = tostring(text or "")
  text = text:gsub("\195([\128-\158])", function(byte)
    local code = string.byte(byte)
    if code == 0x97 then return "\195" .. byte end
    return "\195" .. string.char(code + 0x20)
  end)
  for upper, lower in pairs(LATIN_EXTRA_LOWER) do
    text = text:gsub(upper, lower)
  end
  return strlower(text)
end

function Addon.wordKey(word)
  local cleaned = Addon.cleanWord(word):gsub("ẞ", "ss"):gsub("ß", "ss")
  return Addon.utf8Lower(cleaned)
end

local function encode(value)
  -- Parenthesised: gsub also returns a replacement count, and an unparenthesised
  -- call in the last slot of a table constructor would append it as a field.
  return (tostring(value or ""):gsub("([^A-Za-z0-9_.~%-])", function(byte)
    return string.format("%%%02X", string.byte(byte))
  end))
end

function Addon.ensureHeadwordDefaults(entry, now)
  if entry.status == nil then entry.status = "learning" end
  if entry.statusChangedAt == nil then entry.statusChangedAt = entry.updatedAt or now end
  if entry.translation == nil then entry.translation = "" end
  if entry.note == nil then entry.note = "" end
  if entry.noteUpdatedAt == nil then entry.noteUpdatedAt = 0 end
  if entry.encounteredQuests == nil then entry.encounteredQuests = {} end
  if entry.encounterCount == nil then entry.encounterCount = 0 end
  if entry.firstSeenAt == nil then entry.firstSeenAt = entry.updatedAt or now end
end

function Addon.rebuildExport()
  local words = Addon.GetWordsTable()
  local keys = {}
  for key in pairs(words) do keys[#keys + 1] = key end
  table.sort(keys)
  local rows = {}
  for _, key in ipairs(keys) do
    local item = words[key]
    rows[#rows + 1] = table.concat({
      encode(item.word),
      item.status or "new",
      tostring(item.statusChangedAt or item.updatedAt or 0),
      tostring(item.updatedAt or 0),
      encode(item.translation),
      encode(item.note),
      tostring(item.noteUpdatedAt or item.updatedAt or 0),
      encode(item.context),
      encode(item.questId),
      encode(item.questTitle),
      tostring(item.firstSeenAt or item.updatedAt or 0),
      tostring(item.lastSeenAt or item.updatedAt or 0),
      tostring(item.encounterCount or 0),
    }, ",")
  end
  WordHunterWoWExport = "WHW3|" .. table.concat(rows, ";")
  local target = Addon.GetTargetLocale()
  WordHunterWoWLanguage = Addon.WH_LANGUAGE_MAP[target] or target
end

function Addon.initializeDatabase()
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.words) ~= "table" then WordHunterWoWDB.words = {} end
  if type(WordHunterWoWDB.wordsByLocale) ~= "table" then WordHunterWoWDB.wordsByLocale = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  if type(WordHunterWoWDB.settings.frames) ~= "table" then WordHunterWoWDB.settings.frames = {} end
  if not Addon.BACKGROUNDS[WordHunterWoWDB.settings.background] then
    WordHunterWoWDB.settings.background = Addon.DefaultBackgroundStyle()
  end
  if type(WordHunterWoWDB.settings.opacity) ~= "number" or WordHunterWoWDB.settings.opacity < 0 or WordHunterWoWDB.settings.opacity > 1.0 then
    WordHunterWoWDB.settings.opacity = 1.0
  end
  if WordHunterWoWDB.settings.integratedLayout == nil then
    WordHunterWoWDB.settings.integratedLayout = true
  end
  if not Addon.SUPPORTED_LOCALES[WordHunterWoWDB.settings.targetLocale] then
    local client = GetLocale and GetLocale() or "deDE"
    if Addon.SUPPORTED_LOCALES[client] then
      WordHunterWoWDB.settings.targetLocale = client
    else
      WordHunterWoWDB.settings.targetLocale = "deDE"
    end
  end
  if (WordHunterWoWDB.version or 0) < 8 then
    local hasPartitioned = false
    for _, tbl in pairs(WordHunterWoWDB.wordsByLocale) do
      if next(tbl) ~= nil then hasPartitioned = true; break end
    end
    if not hasPartitioned and next(WordHunterWoWDB.words) ~= nil then
      local target = WordHunterWoWDB.settings.targetLocale
      if not WordHunterWoWDB.wordsByLocale[target] then WordHunterWoWDB.wordsByLocale[target] = {} end
      for k, v in pairs(WordHunterWoWDB.words) do
        if type(v) == "table" and v.word then
          WordHunterWoWDB.wordsByLocale[target][k] = v
        end
      end
    end
  end
  if (WordHunterWoWDB.version or 0) < 9 then
    local words = WordHunterWoWDB.wordsByLocale.deDE
    if type(words) == "table" then
      local migrations = {}
      for key, entry in pairs(words) do
        local normalized = strlower(tostring(key)):gsub("ẞ", "SS"):gsub("ß", "ss")
        if normalized ~= key then migrations[#migrations + 1] = { key, normalized, entry } end
      end
      for _, migration in ipairs(migrations) do
        local oldKey, newKey, entry = migration[1], migration[2], migration[3]
        if not words[newKey] then words[newKey] = entry end
        words[oldKey] = nil
      end
    end
  end
  if (WordHunterWoWDB.version or 0) < 10 then
    -- Keys written before the Unicode fold kept their accented capitals, so
    -- "Überfall" and "überfall" were two entries and only the second matched the
    -- dictionary. Re-key every locale and merge the pairs back together.
    for _, words in pairs(WordHunterWoWDB.wordsByLocale) do
      if type(words) == "table" then
        local migrations = {}
        for key, entry in pairs(words) do
          local normalized = Addon.wordKey(key)
          if normalized ~= "" and normalized ~= key then
            migrations[#migrations + 1] = { key, normalized, entry }
          end
        end
        for _, migration in ipairs(migrations) do
          local oldKey, newKey, entry = migration[1], migration[2], migration[3]
          local existing = words[newKey]
          if not existing then
            words[newKey] = entry
          elseif type(existing) == "table" and type(entry) == "table" then
            -- Keep whichever side the player actually touched.
            if (existing.status == nil or existing.status == "new") and entry.status then
              existing.status = entry.status
            end
            if (existing.note == nil or existing.note == "") and entry.note then
              existing.note = entry.note
            end
            if (existing.translation == nil or existing.translation == "") and entry.translation then
              existing.translation = entry.translation
            end
          end
          words[oldKey] = nil
        end
      end
    end
  end
  if (WordHunterWoWDB.version or 0) < 11 and Addon.Compat and Addon.Compat.IsClassic() then
    -- Earlier builds stamped "midnight" into the settings the first time they
    -- ran, before this addon had a Classic default at all. On a Classic client
    -- that value can only be that stamp and never a choice -- the addon has
    -- never been released for Classic -- so clearing it is safe, and it lets
    -- the Classic default actually reach the player it was written for.
    if WordHunterWoWDB.settings.background == "midnight" then
      WordHunterWoWDB.settings.background = Addon.DefaultBackgroundStyle()
    end
  end
  Addon.GetWordsTable()
  WordHunterWoWDB.version = 11
  Addon.rebuildExport()
end

Addon.LAYOUT_DEFAULTS = {
  npc = {
    panel = { point = "LEFT", relPoint = "LEFT", x = 420, y = 40, w = 720, h = 500 },
    list = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -16, y = -36, w = 420, h = 520 },
    stats = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -448, y = -36, w = 340, h = 400 },
    editor = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -448, y = -448, w = 430, h = 400 },
  },
  questlog = {
    panel = { point = "RIGHT", relPoint = "RIGHT", x = -20, y = 40, w = 680, h = 500 },
    list = { point = "TOPRIGHT", relPoint = "TOPRIGHT", x = -16, y = -36, w = 420, h = 500 },
    stats = { point = "BOTTOMRIGHT", relPoint = "BOTTOMRIGHT", x = -16, y = 90, w = 340, h = 400 },
    editor = { point = "CENTER", relPoint = "CENTER", x = 180, y = 50, w = 430, h = 400 },
  },
}

function Addon.GetLayoutContext()
  if QuestFrame and QuestFrame:IsShown() then return "npc" end
  if WorldMapFrame and WorldMapFrame:IsShown() then return "questlog" end
  return "npc"
end

function Addon.LayoutKey(base)
  return tostring(base or "panel") .. ":" .. Addon.GetLayoutContext()
end

function Addon.PlaceFrame(frame, baseKey)
  if not frame then return end
  local def = Addon.LAYOUT_DEFAULTS[Addon.GetLayoutContext()][baseKey]
  if not def then return end
  Addon.RestoreFramePosition(frame, Addon.LayoutKey(baseKey), def.point, def.x, def.y, def.w, def.h)
end

function Addon.SaveFramePosition(frame, key)
  if not frame or not key then return end
  if not WordHunterWoWDB or not WordHunterWoWDB.settings then return end
  if not WordHunterWoWDB.settings.frames then WordHunterWoWDB.settings.frames = {} end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  if not point then return end
  local w, h = frame:GetSize()
  -- Updated in place rather than replaced. The entry also carries whether the
  -- player picked this size by hand, and rebuilding the table dropped that
  -- every time the window was moved.
  local entry = WordHunterWoWDB.settings.frames[key]
  if type(entry) ~= "table" then
    entry = {}
    WordHunterWoWDB.settings.frames[key] = entry
  end
  entry.point, entry.relPoint, entry.x, entry.y = point, relPoint, x, y
  entry.w, entry.h = w, h
end

function Addon.RestoreFramePosition(frame, key, defaultPoint, defaultX, defaultY, defaultW, defaultH)
  local data = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.frames and WordHunterWoWDB.settings.frames[key]
  if data and data.point and data.w and data.h then
    frame:ClearAllPoints()
    frame:SetPoint(data.point, UIParent, data.relPoint or data.point, data.x or 0, data.y or 0)
    frame:SetSize(data.w, data.h)
    return true
  end
  if defaultPoint then
    frame:ClearAllPoints()
    frame:SetPoint(defaultPoint, UIParent, defaultPoint, defaultX or 0, defaultY or 0)
  end
  if defaultW and defaultH then
    frame:SetSize(defaultW, defaultH)
  end
  return false
end

function Addon.MakeResizable(frame, key, minW, minH, maxW, maxH)
  if not frame then return end
  frame:SetResizable(true)
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW, maxH)
  else
    -- Classic has no SetResizeBounds; it is the one call that replaced these
    -- two. Guarding it without a fallback left the window with no limits at
    -- all there, so it could be dragged down to nothing or out past the screen
    -- and there was no way back short of resetting the layout. That is what
    -- "hard to resize" turns out to mean.
    if frame.SetMinResize then frame:SetMinResize(minW, minH) end
    if frame.SetMaxResize then frame:SetMaxResize(maxW, maxH) end
  end
  if not frame.resizeHandle then
    local handle = CreateFrame("Button", nil, frame)
    handle:SetSize(16, 16)
    handle:SetPoint("BOTTOMRIGHT", -4, 4)
    handle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    handle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    handle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    -- Drag scripts, not OnMouseDown/OnMouseUp.
    --
    -- The corner stops when the size hits a bound or the frame reaches the edge
    -- of the screen, while the cursor carries on -- so on most real drags the
    -- cursor ends up somewhere off this 16px grip. OnMouseUp is only delivered
    -- to the button the cursor is actually over, so releasing there never
    -- reached StopMovingOrSizing and the frame was left in sizing mode: it went
    -- on following the cursor with the button up, which is the window growing
    -- and shrinking on its own and dropping clicks. OnDragStop is delivered to
    -- the frame that started the drag wherever the cursor has got to.
    handle:RegisterForDrag("LeftButton")
    local dragging = false
    local function stopSizing()
      frame:StopMovingOrSizing()
      Addon.SaveFramePosition(frame, Addon.LayoutKey(key))
      if not dragging then return end
      dragging = false
      -- The player has chosen a size, so nothing should size this frame for
      -- them again. Recorded when it happens rather than worked out later from
      -- a saved size: every frame has a saved size, including ones only ever
      -- moved, and including the ones the addon sized itself.
      local frames = WordHunterWoWDB and WordHunterWoWDB.settings
        and WordHunterWoWDB.settings.frames
      local saved = frames and frames[Addon.LayoutKey(key)]
      if saved then saved.userSized = true end
    end
    handle:SetScript("OnDragStart", function()
      dragging = true
      frame:StartSizing("BOTTOMRIGHT")
    end)
    handle:SetScript("OnDragStop", stopSizing)
    -- Two backstops, neither redundant. A press with no drag never starts
    -- sizing, but stopping costs nothing. And a frame hidden mid-drag -- Escape,
    -- or the quest window closing under it -- would otherwise still be sizing
    -- when it came back.
    handle:SetScript("OnMouseUp", stopSizing)
    frame:HookScript("OnHide", function() stopSizing() end)
    frame:HookScript("OnSizeChanged", function(self)
      if self:IsShown() then
        Addon.SaveFramePosition(self, Addon.LayoutKey(key))
      end
    end)
    frame.resizeHandle = handle
  end
end

local function questEncounterKey(questId, questTitle)
  local id = tostring(questId or "")
  if id ~= "" and id ~= "0" then return "id:" .. id end
  local title = Addon.utf8Lower(Addon.trim(questTitle))
  if title ~= "" then return "title:" .. title end
end

function Addon.recordEncounter(item, questId, questTitle, now)
  item.firstSeenAt = item.firstSeenAt or item.updatedAt or now
  item.lastSeenAt = now
  item.encounterCount = tonumber(item.encounterCount) or 0
  if type(item.encounteredQuests) ~= "table" then item.encounteredQuests = {} end
  local questKey = questEncounterKey(questId, questTitle)
  if questKey and not item.encounteredQuests[questKey] then
    item.encounteredQuests[questKey] = true
    item.encounterCount = item.encounterCount + 1
  end
end

function Addon.CloseAll()
  local closed = false
  for _, key in ipairs({ "panel", "editor", "listFrame", "statsFrame", "copyDialog", "enPanel" }) do
    local frame = Addon[key]
    if frame and frame.IsShown and frame:IsShown() then
      frame:Hide()
      if frame == Addon.editor and frame.ClearFocus then pcall(function() frame:ClearFocus() end) end
      closed = true
    end
  end
  if Addon.settingsPanel and Addon.settingsPanel:IsShown() then
    Addon.settingsPanel:Hide()
    closed = true
  end
  return closed
end

-- Where the collected text ends up. An addon cannot see its own WoW folder or
-- the name of the account directory -- neither is exposed to Lua -- so this is
-- the shape of the path with the one part it does know filled in: which game
-- it is running on.
function Addon.HarvestExportPath()
  local flavour = "_retail_"
  if Addon.Compat and Addon.Compat.IsClassic() then flavour = "_classic_era_" end
  return "World of Warcraft\\" .. flavour
    .. "\\WTF\\Account\\<your account>\\SavedVariables\\WordHunterWoW.lua"
end

function Addon.SetupEscapeClose(frame)
  if not frame or not frame.GetName then return end
  local name = frame:GetName()
  if name and not tContains(UISpecialFrames, name) then
    tinsert(UISpecialFrames, name)
  end
  frame:EnableKeyboard(true)
  frame:SetPropagateKeyboardInput(true)
  frame:HookScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then
      self:SetPropagateKeyboardInput(false)
      Addon.CloseAll()
    else
      self:SetPropagateKeyboardInput(true)
    end
  end)
end
