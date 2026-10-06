local Addon = WordHunterWoW_Addon

-- Source editions are learning material, never native quest/cache replacements.
local function query(value)
  if type(value) ~= "string" then return end
  local source, kind, id = value:match("^reference:([^:]+):([^:]+):(%d+)$")
  if source then return source, kind, tonumber(id) end
end

local function edition(source, kind)
  if kind == "quest" then
    local data = WordHunterWoW_QuestSources
    local bucket = type(data) == "table" and data[source]
    return bucket and bucket.locales, bucket and bucket.label
  end
  local data = WordHunterWoW_EntityDataBySource
  local bucket = type(data) == "table" and data[source]
  return bucket and bucket.kinds and bucket.kinds[kind], bucket and bucket.sourceLabel
end

local function record(languages, locale, id)
  if locale == "enGB" then locale = "enUS" end
  local rows = languages and languages[locale]
  return type(rows) == "table" and rows[id], locale
end

local function body(row, kind, phase)
  if type(row) ~= "table" then return "" end
  if kind ~= "quest" then
    local name, text = row.name or "", row.text or row.role or ""
    return name .. (name ~= "" and text ~= "" and text ~= name and "\n\n" or "") .. (text ~= name and text or "")
  end
  if phase == "title" then return row.title or "" end
  if phase ~= "offer" then return row[phase] or "" end
  local desc, obj = row.description or "", row.objectives or ""
  return desc .. (desc ~= "" and obj ~= "" and "\n\n" or "") .. obj
end

function Addon.GetReferenceEnglishRecord(value)
  local source, kind, id = query(value)
  if not source then return nil end
  local languages = edition(source, kind)
  local row = record(languages, "enUS", id)
  if not row then return nil end
  if kind == "quest" then return row end
  return { title = row.name, description = body(row, kind, "offer") }
end

function Addon.ResolveReferenceQuest(value, locale, phase)
  local source, kind, id = query(value)
  if not source then return nil end
  local languages, label = edition(source, kind)
  if not languages then return nil end
  locale = locale or Addon.GetCatalogLocale()
  if not Addon.SUPPORTED_LOCALES[locale] then return nil end
  if phase == "reward" then phase = "completion" end
  local localized, sourceLocale = record(languages, locale, id)
  local english = record(languages, "enUS", id)
  local phases, candidates = {}, kind == "quest" and { "offer", "progress", "completion", "sourceObjective" } or { "offer" }
  if kind == "quest" then
    for _, row in ipairs({ localized or {}, english or {} }) do
      if (row.title or "") ~= "" and body(row, kind, "offer") == ""
        and body(row, kind, "progress") == "" and body(row, kind, "completion") == ""
        and body(row, kind, "sourceObjective") == "" then
        table.insert(candidates, 1, "title")
        break
      end
    end
  end
  for _, candidate in ipairs(candidates) do
    if body(localized, kind, candidate) ~= "" or body(english, kind, candidate) ~= "" then
      phases[#phases + 1] = candidate
      if not phase and candidate ~= "title" and body(localized, kind, candidate) ~= "" then phase = candidate end
    end
  end
  if not phase and kind == "quest" and body(localized, kind, "title") ~= "" then
    for _, candidate in ipairs(phases) do if candidate == "title" then phase = candidate end end
  end
  phase = phase or phases[1]
  local valid = false
  for _, candidate in ipairs(phases) do if candidate == phase then valid = true end end
  if not valid then return nil end
  local selected = localized
  if body(selected, kind, phase) == "" then selected, sourceLocale = english, "enUS" end
  local text = body(selected, kind, phase)
  if text == "" then return nil end
  local readOnly = sourceLocale ~= locale and not (sourceLocale == "enUS" and locale == "enGB")
  local title = selected.title or selected.name or (kind .. " #" .. id)
  if Addon.PersonalizeQuestText then
    title, text = Addon.PersonalizeQuestText(title, sourceLocale), Addon.PersonalizeQuestText(text, sourceLocale)
  end
  return { id = value, sourceId = id, title = title,
    text = text, passage = readOnly and "reference" or phase == "completion" and "reward" or phase,
    catalog = true, catalogPhase = phase, catalogPhases = phases, requestedLocale = locale,
    sourceLocale = sourceLocale, wordLocale = not readOnly and locale or nil, readOnly = readOnly,
    referenceSource = source, referenceKind = kind, source = label, phaseSource = label,
    sourceFlavor = source, voiceUnavailable = true,
    referenceNote = (label or source) .. ": static source; versions and DE/EN text may differ."
      .. (phase == "title" and " Title-only study; this view contains no quest dialogue." or "") }
end

function Addon.GetLibraryViews()
  local views = {}
  local labels = { ["multilanguage-classic-master"] = "ML Classic", ["multilanguage-classic"] = "ML Classic",
    ["multilanguage-tbc"] = "ML TBC", ["multilanguage-retail"] = "ML Retail",
    ["multilanguage-wrath"] = "ML Wrath", ["multilanguage-cata"] = "ML Cata",
    ["multilanguage-mop-classic"] = "ML Pandaria", ["multilanguage-forever"] = "ML Forever" }
  local order, suffix = { quest = 1, item = 2, spell = 3, npc = 4 },
    { quest = "quests", item = "items", spell = "spells", npc = "NPCs" }
  local function append(source, kind, bucket)
    if type(source) ~= "string" or source:find(":", 1, true) or type(bucket) ~= "table" then return end
    local languages = edition(source, kind)
    if type(languages) ~= "table" then return end
    local de, en = languages.deDE, languages.enUS
    if not (type(de) == "table" and next(de) or type(en) == "table" and next(en)) then return end
    local label = bucket.viewLabel or labels[source] or bucket.sourceLabel or bucket.label or source
    if type(label) ~= "string" or label == "" then label = source end
    views[#views + 1] = { key = source .. ":" .. kind, source = source, kind = kind,
      label = label .. " " .. suffix[kind] }
  end
  for source, bucket in pairs(WordHunterWoW_QuestSources or {}) do append(source, "quest", bucket) end
  for source, bucket in pairs(WordHunterWoW_EntityDataBySource or {}) do
    for _, kind in ipairs({ "item", "spell", "npc" }) do append(source, kind, bucket) end
  end
  table.sort(views, function(a, b)
    if a.kind ~= b.kind then return order[a.kind] < order[b.kind] end
    if a.label ~= b.label then return a.label < b.label end
    return a.key < b.key
  end)
  table.insert(views, 1, { key = "game", label = "Game quests" })
  return views
end

function Addon.GetLibraryView()
  for _, view in ipairs(Addon.GetLibraryViews()) do if view.key == Addon.libraryView then return view end end
  return Addon.GetLibraryViews()[1]
end

function Addon.SetLibraryView(key)
  for _, view in ipairs(Addon.GetLibraryViews()) do
    if view.key == key then
      Addon.libraryView = key
      if Addon.questsFrame then Addon.questsFrame.page, Addon.questsFrame.filter = 1, "database" end
      if Addon.refreshQuestBrowser then Addon.refreshQuestBrowser() end
      return true
    end
  end
  return false
end

function Addon.CollectReferenceCatalog()
  local view = Addon.GetLibraryView()
  if not view.source then return nil end
  local languages = edition(view.source, view.kind)
  local locale = Addon.GetCatalogLocale()
  local actualLocale = locale == "enGB" and "enUS" or locale
  local rows, out = {}, {}
  for id, row in pairs(languages.enUS or {}) do rows[id] = { row = row, locale = "enUS" } end
  for id, row in pairs(languages[actualLocale] or {}) do rows[id] = { row = row, locale = actualLocale } end
  for id, item in pairs(rows) do
    local title = item.row.title or item.row.name or (view.kind .. " #" .. id)
    out[#out + 1] = { id = "reference:" .. view.source .. ":" .. view.kind .. ":" .. id,
      idStr = tostring(id), sourceId = id, title = title, titleLocale = item.locale,
      titleSource = "source reference", sortKey = Addon.utf8Lower(title), reference = true }
  end
  table.sort(out, function(a, b) if a.sortKey == b.sortKey then return a.sourceId < b.sourceId end return a.sortKey < b.sortKey end)
  return out
end
