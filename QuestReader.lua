local Addon = WordHunterWoW_Addon

-- The library reuses the real reader; it never selects an offline quest in
-- Blizzard's log. A source language travels with the text so an English
-- fallback cannot be stored as German vocabulary or sent to the German voice.
local function plain(value)
  if type(value) ~= "string" then return "" end
  local check = Addon.IsSecretValue or issecretvalue
  if type(check) == "function" then
    local ok, secret = pcall(check, value)
    if not ok or secret then return "" end
  end
  return Addon.trim(value:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

local function idFor(value)
  if type(value) ~= "number" and type(value) ~= "string" then return nil end
  local id = tonumber(value)
  if not id or id <= 0 or id == math.huge or id ~= math.floor(id) then return nil end
  return id
end

local function playerName()
  if Addon.PlayerName then
    local ok, value = pcall(Addon.PlayerName)
    if ok and plain(value) ~= "" then return plain(value) end
  end
  if type(UnitName) == "function" then
    local ok, value = pcall(UnitName, "player")
    if ok and plain(value) ~= "" then return plain(value):match("^[^%-]+") end
  end
  return nil
end

local function personalize(text, locale)
  local name = playerName()
  local function fill(token, pattern, value)
    if not value or value == "" then return end
    for _, mark in ipairs({ "{" .. token .. "}", "<" .. token .. ">", pattern }) do
      text = text:gsub(mark, function() return value end)
    end
  end
  fill("name", "%$[nN]", name)
  for _, unit in ipairs({ { "class", "%$[cC]", UnitClass }, { "race", "%$[rR]", UnitRace } }) do
    if type(unit[3]) == "function" then
      local ok, localized, englishName = pcall(unit[3], "player")
      local value
      if ok and locale == Addon.TextLocale() then value = plain(localized)
      elseif ok and (locale == "enUS" or locale == "enGB") then
        value = plain(englishName)
        if unit[1] == "class" then
          value = ({ DEATHKNIGHT = "Death Knight", DEMONHUNTER = "Demon Hunter" })[value]
            or (value:sub(1, 1):upper() .. value:sub(2):lower())
        else value = value == "Scourge" and "Undead" or value:gsub("(%l)(%u)", "%1 %2") end
      end
      fill(unit[1], unit[2], value)
    end
  end
  local ok, sex = false, nil
  if type(UnitSex) == "function" then ok, sex = pcall(UnitSex, "player") end
  local check = Addon.IsSecretValue or issecretvalue
  if ok and type(check) == "function" then
    local checked, secret = pcall(check, sex)
    if not checked or secret then ok = false end
  end
  text = text:gsub("%$[gG]([^:;]*):([^;]*);", function(male, female) return ok and sex == 3 and female or male end)
  return text
end

local PHASES = { "offer", "progress", "completion" }
Addon.PersonalizeQuestText = personalize
local FIELDS = { "title", "description", "objectives", "progress", "completion" }
local function passage(record, phase)
  if type(record) ~= "table" then return "" end
  if phase == "title" then return plain(record.title) end
  if phase == "progress" or phase == "completion" then return plain(record[phase]) end
  local desc, obj = plain(record.description), plain(record.objectives)
  return desc .. (desc ~= "" and obj ~= "" and "\n\n" or "") .. obj
end

local function hasText(record)
  for _, phase in ipairs(PHASES) do if passage(record, phase) ~= "" then return true end end
  return false
end

local function recordFor(data, id)
  if type(data) ~= "table" then return nil end
  return data[id] or data[tostring(id)]
end

local function collectedPhaseVerified(entry, kind)
  if kind == "progress" then return entry.kind == kind and entry.observedPassage == "progress" end
  if kind == "reward" or kind == "completion" then
    return (entry.kind == "reward" or entry.kind == "completion")
      and (entry.observedPassage == "reward" or entry.observedPassage == "completion")
  end
  return true
end

local function corpusRecord(id, locale)
  local corpus = WordHunterWoWCorpus
  local buckets = type(corpus) == "table" and corpus.byLocale
  local bucket = type(buckets) == "table" and buckets[locale]
  if type(bucket) ~= "table" then return nil end
  local flavor = Addon.Compat and Addon.Compat.GameFlavor() or "retail"
  local record = {}
  local prefix = flavor == "retail" and "" or flavor .. ":"
  for _, kind in ipairs({ "title", "description", "objectives", "progress", "completion", "reward" }) do
    local entry = bucket[prefix .. kind .. ":" .. id]
    if type(entry) == "table" and idFor(entry.id) == id
        and collectedPhaseVerified(entry, kind)
        and (entry.flavor == flavor or (entry.flavor == nil and flavor == "retail")) then
      local field = kind == "reward" and "completion" or kind
      if plain(record[field]) == "" then record[field] = plain(entry.text) end
    end
  end
  -- Older/imported corpora need not use Harvest's keys. Sort the keys first
  -- so duplicate records cannot randomly change between openings.
  local keys = {}
  for key in pairs(bucket) do if type(key) == "string" then keys[#keys + 1] = key end end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local entry = bucket[key]
    if type(entry) == "table" and idFor(entry.id) == id
        and collectedPhaseVerified(entry, entry.kind)
        and (entry.flavor == flavor or (entry.flavor == nil and flavor == "retail"))
        and (entry.kind == "title" or entry.kind == "description" or entry.kind == "objectives"
          or entry.kind == "progress" or entry.kind == "completion" or entry.kind == "reward") then
      local field = entry.kind == "reward" and "completion" or entry.kind
      if plain(record[field]) == "" then record[field] = plain(entry.text) end
    end
  end
  return record
end

local function liveRecord(id, locale)
  if Addon.TextLocale() ~= locale then return nil end
  local Compat = Addon.Compat
  if not Compat or type(GetQuestLogQuestText) ~= "function" then return nil end
  local okIndex, index = pcall(Compat.QuestLogIndexForID, id)
  if not okIndex or type(index) ~= "number" or index <= 0 then return nil end
  local ok, desc, obj
  if Compat.QuestLogTextIsIndexed and Compat.QuestLogTextIsIndexed() then
    ok, desc, obj = pcall(GetQuestLogQuestText, index)
  else
    -- Legacy reads the selected quest. Do not move that selection even briefly.
    local okSelected, selected = pcall(Compat.SelectedQuestID)
    if not okSelected or selected ~= id then return nil end
    ok, desc, obj = pcall(GetQuestLogQuestText)
  end
  if not ok then return nil end
  local okTitle, title = pcall(Compat.TitleForQuestID, id)
  return { title = okTitle and plain(title) or "", description = plain(desc), objectives = plain(obj) }
end

local function english(locale) return locale == "enUS" or locale == "enGB" end

function Addon.GetCatalogLocale()
  return Addon.SUPPORTED_LOCALES[Addon.catalogLocale] and Addon.catalogLocale or Addon.GetTargetLocale()
end

-- A qualified game bucket is authoritative, including IDs it does not contain.
-- Legacy locale-flat packs remain readable when no qualified game pack exists.
-- A publisher can explicitly share Classic records with Forever by providing
-- its Forever bucket and sourceFlavor="classic"; no alias is inferred here.
function Addon.GetQuestDatabase(locale)
  locale = locale or Addon.GetCatalogLocale()
  local flavor = Addon.Compat and Addon.Compat.GameFlavor() or "retail"
  local games = WordHunterWoW_QuestDataByFlavor
  local game = type(games) == "table" and games[flavor]
  local all = WordHunterWoW_QuestData
  local data = type(game) == "table" and game or (type(all) == "table" and all or {})
  local sourceLocale = locale
  local bucket = data[locale]
  if type(bucket) ~= "table" and english(locale) then
    sourceLocale = locale == "enGB" and "enUS" or "enGB"
    bucket = data[sourceLocale]
  end
  if type(bucket) ~= "table" and type(game) ~= "table" and english(locale)
      and type(WordHunterWoW_QuestEN) == "table" then
    bucket, sourceLocale = WordHunterWoW_QuestEN, "enUS"
  end
  return type(bucket) == "table" and bucket or {},
    type(game) == "table" and (game.sourceFlavor or flavor) or "legacy",
    type(game) == "table", sourceLocale
end

local function databaseRecord(record, sourceFlavor, locale)
  if type(record) ~= "table" then return nil end
  local flavor = Addon.Compat and Addon.Compat.GameFlavor() or "retail"
  local declared = record.sourceFlavor or record.flavor
  if declared and declared ~= flavor and declared ~= sourceFlavor then return nil end
  local declaredLocale = record.sourceLocale or record.locale
  if declaredLocale and declaredLocale ~= locale
      and not (english(declaredLocale) and english(locale)) then return nil end
  if flavor ~= "retail" and type(record.descriptionSource) == "string"
      and record.descriptionSource:lower():find("^retail") then
    local copy = {}
    for key, value in pairs(record) do copy[key] = value end
    copy.description = "" -- The objectives may still be authentic Classic data.
    return copy
  end
  return record
end

local function incomplete(record)
  if type(record) ~= "table" then return true end
  for _, field in ipairs(FIELDS) do if plain(record[field]) == "" then return true end end
  return false
end

-- Supplement an observation without changing the native archive or the static
-- database. Callers supply only records already qualified for this game/language.
local function fillMissing(record, fallback, source)
  if type(record) ~= "table" or type(fallback) ~= "table" then return record end
  local result = record
  for _, field in ipairs(FIELDS) do
    if plain(record[field]) == "" and plain(fallback[field]) ~= "" then
      if result == record then
        result = {}
        for key, value in pairs(record) do result[key] = value end
      end
      result[field] = fallback[field]
      result[field .. "Source"] = fallback[field .. "Source"] or fallback.source or source
      result[field .. "SourceFlavor"] = fallback[field .. "SourceFlavor"] or fallback.sourceFlavor or fallback.flavor
    end
  end
  return result
end

function Addon.GetEnglishQuestRecord(value)
  if type(value) == "string" and value:find("^reference:") then
    return Addon.GetReferenceEnglishRecord and Addon.GetReferenceEnglishRecord(value)
  end
  local id = idFor(value)
  if not id then return nil end
  local currentFlavor = Addon.Compat and Addon.Compat.GameFlavor() or "retail"
  local data, flavor, qualified, locale = Addon.GetQuestDatabase("enUS")
  local record = recordFor(data, id)
  if not record and not qualified then
    record, locale = recordFor(WordHunterWoW_QuestEN, id), "enUS"
  end
  record = databaseRecord(record, flavor, locale)
  if Addon.GetLibraryQuestSourceRecord then
    local imported, label = Addon.GetLibraryQuestSourceRecord(id, "enUS")
    if type(record) ~= "table" then record = imported else record = fillMissing(record, imported, label) end
  end
  for _, nativeLocale in ipairs({ "enUS", "enGB" }) do
    local observed = Addon.GetObservedQuestTexts and Addon.GetObservedQuestTexts(nativeLocale)
    local native = recordFor(observed, id)
    if hasText(native) then
      if incomplete(native) then native = fillMissing(native, corpusRecord(id, nativeLocale), "collected text") end
      return fillMissing(native, record, "database"), currentFlavor, nativeLocale, "observed text"
    end
    native = corpusRecord(id, nativeLocale)
    if hasText(native) then return fillMissing(native, record, "database"), currentFlavor, nativeLocale, "collected text" end
  end
  return record, record and (record.sourceFlavor or record.flavor) or flavor, locale, "database"
end

function Addon.ResolveCatalogQuest(value, locale, phase)
  if type(value) == "string" and value:find("^reference:") then
    return Addon.ResolveReferenceQuest and Addon.ResolveReferenceQuest(value, locale, phase)
  end
  local id = idFor(value)
  if not id then return nil end
  locale = locale or Addon.GetCatalogLocale()
  if not Addon.SUPPORTED_LOCALES[locale] then return nil end
  if phase == "reward" then phase = "completion" end
  if phase and phase ~= "offer" and phase ~= "progress" and phase ~= "completion" and phase ~= "title" then return nil end
  local flavor = Addon.Compat and Addon.Compat.GameFlavor() or "retail"
  local localized, databaseFlavor, _, databaseLocale = Addon.GetQuestDatabase(locale)
  local sourceFlavor, sourceLocale = flavor, locale
  local record, source = liveRecord(id, locale), "quest log"
  if passage(record) ~= "" and Addon.ArchiveNativeQuest then Addon.ArchiveNativeQuest(id, record, locale) end
  if incomplete(record) then
    local observed = Addon.GetObservedQuestTexts and Addon.GetObservedQuestTexts(locale)
    local native = recordFor(observed, id)
    if not hasText(record) then record, source = native, "observed text"
    else record = fillMissing(record, native, "observed text") end
  end
  if incomplete(record) then
    local collected = corpusRecord(id, locale)
    if not hasText(record) then
      record, source = collected, "collected text"
      sourceFlavor, sourceLocale = flavor, locale
    else record = fillMissing(record, collected, "collected text") end
  end
  local combined = false
  if passage(record) == "" then
    local last = Addon.lastQuest
    if type(last) == "table" and not last.catalog and not last.readOnly and idFor(last.id) == id
        and (not last.sourceFlavor or last.sourceFlavor == flavor)
        and last.passage == "offer" and Addon.TextLocale() == locale and plain(last.text) ~= "" then
      local fresh = { title = last.title, description = last.text }
      record, source = hasText(record) and fillMissing(fresh, record, source) or fresh, "quest log"
      combined = true -- last.text already combines the description and objectives.
      sourceFlavor, sourceLocale = flavor, locale
    end
  end
  local database = databaseRecord(recordFor(localized, id), databaseFlavor, locale)
  if not hasText(record) then
    record, source = database, "database"
    sourceFlavor, sourceLocale = record and (record.sourceFlavor or record.flavor) or databaseFlavor, databaseLocale
  elseif not combined then
    record = fillMissing(record, database, "database")
  else
    -- Fresh text already contains its objectives; only supplement dialogue.
    record = fillMissing(record, database and { progress = database.progress, completion = database.completion,
      progressSource = database.progressSource, completionSource = database.completionSource,
      progressSourceFlavor = database.progressSourceFlavor, completionSourceFlavor = database.completionSourceFlavor }, "database")
  end
  local importedLabel
  if Addon.GetLibraryQuestSourceRecord and incomplete(record) then
    local imported, label = Addon.GetLibraryQuestSourceRecord(id, locale)
    local supplemented = fillMissing(record or {}, imported, label)
    if supplemented ~= record and (hasText(imported) or passage(imported, "title") ~= "") then importedLabel = label end
    if not hasText(record) and (hasText(imported) or passage(imported, "title") ~= "") then
      record, source, sourceFlavor, sourceLocale = supplemented, label, flavor, locale
    elseif supplemented ~= record then
      record = supplemented
    end
  end
  local englishRecord, englishFlavor, englishLocale, englishSource = Addon.GetEnglishQuestRecord(id)
  local available = {}
  for _, candidate in ipairs(PHASES) do
    if passage(record, candidate) ~= "" or passage(englishRecord, candidate) ~= "" then available[#available + 1] = candidate end
  end
  local titleOnly = not hasText(record) and passage(record, "title") ~= ""
    or not hasText(englishRecord) and passage(englishRecord, "title") ~= ""
  if titleOnly then table.insert(available, 1, "title") end
  if not phase then
    for _, candidate in ipairs(PHASES) do
      if passage(record, candidate) ~= "" then phase = candidate break end
    end
    phase = phase or available[1]
  end
  if not phase then return nil end
  if phase == "title" and not titleOnly then return nil end
  if passage(record, phase) == "" then
    record, sourceFlavor, sourceLocale, source = englishRecord, englishFlavor, englishLocale, englishSource
  end
  local text = passage(record, phase)
  if text == "" then return nil end
  local englishTarget = english(locale)
  local readOnly = sourceLocale ~= locale and not (english(sourceLocale) and englishTarget)
  local title = plain(record.title)
  if title == "" then title = "Quest " .. id end
  local phaseSource = phase ~= "offer" and (record[phase .. "Source"] or source)
    or record.descriptionSource or record.objectivesSource or source
  local importedPassage = importedLabel and (phaseSource == importedLabel
    or (phase == "offer" and record.objectivesSource == importedLabel))
  local referenceNote = importedPassage and (importedLabel .. ": stored quest text.") or nil
  if phase == "title" then referenceNote = "Title-only study: no quest dialogue is stored in this language." end
  if phase ~= "offer" then sourceFlavor = record[phase .. "SourceFlavor"] or sourceFlavor end
  -- A reference is deliberately not a voice-pack passage. Existing optional
  -- voice hooks still get their cleanup callback, but have no clip to attach.
  return { id = id, title = personalize(title, sourceLocale), text = personalize(text, sourceLocale),
    passage = readOnly and "reference" or phase == "completion" and "reward" or phase,
    catalogPhase = phase, catalogPhases = available, phaseSource = phaseSource,
    catalog = true, requestedLocale = locale, sourceLocale = sourceLocale, sourceFlavor = sourceFlavor,
    wordLocale = not readOnly and locale or nil, source = source, readOnly = readOnly,
    descriptionSource = record.descriptionSource or source, objectivesSource = record.objectivesSource or source,
    originFlavor = record.originFlavor or sourceFlavor, sourceBuild = record.sourceBuild,
    referenceNote = referenceNote,
    voiceUnavailable = readOnly or sourceLocale ~= "deDE" or phase == "title"
      or not not importedPassage
      or (type(phaseSource) == "string" and phaseSource:find("MultiLanguage", 1, true) ~= nil) }
end

local function libraryNavigation()
  if Addon.libraryReturnButton then return end
  local button = Addon.CreateBookSideTab("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up", function()
    Addon.panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
    -- Show, don't toggle: the library may already be open under the reader,
    -- and a toggle would close exactly the window the button promises.
    if Addon.questsFrame and Addon.questsFrame:IsShown() then
      Addon.questsFrame:Show()
    elseif Addon.toggleQuestBrowser then
      Addon.toggleQuestBrowser()
    end
  end, Addon.panel)
  button:SetPoint("BOTTOMLEFT", Addon.panel, "BOTTOMRIGHT", -6, 12)
  button:SetFrameLevel(Addon.panel:GetFrameLevel() + 2)
  button:SetChecked(false)
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Back to quest library")
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  Addon.libraryReturnButton = button
end

function Addon.RefreshCatalogPhaseControl()
  local button = Addon.panel and Addon.panel.catalogPhaseButton
  if not button then return end
  local quest = Addon.lastQuest
  if Addon.panel.copyQuestButton then
    Addon.panel.copyQuestButton:SetText(quest and quest.referenceKind and quest.referenceKind ~= "quest" and "Copy text" or "Copy quest")
  end
  if not (quest and quest.catalog) then button:Hide() return end
  local phases = quest.catalogPhases or { "offer" }
  button:SetText((quest.referenceKind and quest.referenceKind ~= "quest" and "Text"
    or ({ offer = "Offer", progress = "Progress", completion = "Completion", sourceObjective = "Source field", title = "Title" })[quest.catalogPhase or "offer"])
    .. (#phases > 1 and " >" or ""))
  if button.SetEnabled then button:SetEnabled(#phases > 1) end
  button:Show()
end

function Addon.SetCatalogPhase(phase)
  local quest = Addon.lastQuest
  if not (quest and quest.catalog) then return false end
  return Addon.OpenCatalogQuest(quest.id, quest.requestedLocale, phase)
end

function Addon.OpenCatalogQuest(value, locale, phase)
  local quest = Addon.ResolveCatalogQuest(value, locale, phase)
  if not quest then return false end
  if locale and Addon.catalogLocale ~= quest.requestedLocale then
    Addon.catalogLocale = quest.requestedLocale
    if Addon.refreshQuestBrowser then Addon.refreshQuestBrowser() end
  end
  if not Addon.panel then Addon.createPanel() end
  libraryNavigation()
  Addon.libraryReturnButton:Show()
  if Addon.editor then Addon.editor:Hide() end
  if Addon.confirmDialog then Addon.confirmDialog:Hide() end
  Addon.selected = nil
  Addon.lastQuest = quest
  Addon.RefreshCatalogPhaseControl()
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  Addon.panel:Show()
  Addon.refreshPanel()
  return true
end

function Addon.SetCatalogLocale(locale)
  if not Addon.SUPPORTED_LOCALES[locale] then return false end
  Addon.catalogLocale = locale
  if Addon.editor then Addon.editor:Hide() end
  if Addon.confirmDialog then Addon.confirmDialog:Hide() end
  Addon.selected = nil
  if Addon.refreshQuestBrowser then Addon.refreshQuestBrowser() end
  local quest = Addon.lastQuest
  if quest and quest.catalog and Addon.panel and Addon.panel:IsShown() then
    if not Addon.OpenCatalogQuest(quest.id, locale, quest.catalogPhase) then
      Addon.panel:Hide()
      if Addon.questsFrame then Addon.questsFrame:Show() end
      return false
    end
  end
  return true
end
