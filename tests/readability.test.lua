-- lua tests/readability.test.lua -- no game, packages or test framework needed.
strlower = string.lower
strtrim = function(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
time = os.time
GetLocale = function() return 'deDE' end
local unpack = unpack or table.unpack
local function frame()
  local f = { textures = 0 }
  function f:SetBackdrop(value) self.backdrop = value end
  function f:SetBackdropColor(...) self.background = {...} end
  function f:SetBackdropBorderColor(...) self.border = {...} end
  function f:SetToplevel() end
  function f:CreateTexture(_, layer, _, sublevel)
    self.textures = self.textures + 1
    local t = { layer = layer, sublevel = sublevel }
    function t:ClearAllPoints() self.points = {} end
    function t:SetPoint(...) self.points[#self.points + 1] = {...} end
    function t:SetColorTexture(...) self.color = {...} end
    return t
  end
  return f
end
CreateFrame = function() return { RegisterEvent = function() end, SetScript = function() end } end
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
local Addon = WordHunterWoW_Addon
local function luminance(c)
  local function linear(v) return v <= 0.04045 and v / 12.92 or ((v + 0.055) / 1.055)^2.4 end
  return linear(c[1]) * 0.2126 + linear(c[2]) * 0.7152 + linear(c[3]) * 0.0722
end
local function contrast(a, b)
  local x, y = luminance(a), luminance(b)
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05)
end
local function over(foreground, background)
  local a = foreground[4]
  return { foreground[1]*a + background[1]*(1-a), foreground[2]*a + background[2]*(1-a),
    foreground[3]*a + background[3]*(1-a) }
end
local minimum = 100
for _, client in ipairs({'retail', 'classic', 'sod'}) do
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = client == 'retail' and 1 or 2, 1
  Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
  C_Seasons = { GetActiveSeason = function() return client == 'sod' and 2 or 0 end }
  Addon.Compat.Refresh()
  WordHunterWoWDB = { settings = {} }
  assert(Addon.GetBackgroundStyle() == (client == 'retail' and 'midnight' or 'tooltip'))
  assert(Addon.Compat.GameFlavor() == client)
  local window = frame()
  Addon.panel, Addon.confirmDialog = window, frame()
  for _, theme in ipairs(Addon.BACKGROUND_ORDER) do
    for _, opacity in ipairs({0, 0.5, 1}) do
      WordHunterWoWDB.settings.opacity = opacity
      Addon.SetBackgroundStyle(theme)
      assert(window.backdrop.edgeFile == Addon.BACKGROUNDS[theme].edgeFile, 'theme border was replaced')
      assert(window.background[4] == opacity, 'frame opacity preference was discarded')
      local surface = window.whwReadingBackground
      assert(surface.color[4] == 1, 'text background became transparent')
      assert(surface.layer == 'BACKGROUND' and surface.sublevel == 1, 'surface covers text or sits under backdrop')
      assert(Addon.confirmDialog.whwReadingBackground.color[1] == surface.color[1], 'confirmation theme did not refresh')
      local bg = surface.color
      local selected = over(Addon.COLORS.enHighlightBackground, bg)
      local hover = over({0.30, 0.42, 0.55, 0.20}, bg)
      -- The status four are in this list because "Text colour only" and
      -- "Underline and text colour" put them on the quest text itself. Offering
      -- that choice is only honest while every one of them stays legible on
      -- every theme, selected and hovered.
      for _, key in ipairs({'text', 'muted', 'caveat', 'enHighlight', 'enWordHighlight',
                            'new', 'learning', 'known', 'ignored'}) do
        for _, background in ipairs({bg, selected, hover}) do
          local ratio = contrast(Addon.COLORS[key], background)
          minimum = math.min(minimum, ratio)
          assert(ratio >= 4.5, theme .. '/' .. key .. ': contrast ' .. ratio)
        end
      end
    end
  end
  assert(window.textures == 1, 'theme changes leak textures')
end
local button = frame()
button.label = { SetTextColor = function(self, ...) self.color = {...} end }
for _, status in ipairs({'new', 'learning', 'known', 'ignored'}) do
  for _, active in ipairs({true, false}) do
    Addon.styleFlatButton(button, Addon.COLORS[status], active)
    assert(contrast(button.label.color, button.background) >= 4.5, 'unreadable status button')
  end
end
Addon.panel, Addon.confirmDialog = nil, nil
WordHunterWoWDB = { version = 11, settings = { targetLocale = 'deDE' } }
Addon.initializeDatabase()
-- Provider tables remain read-only overlays; palettes never leak into data.
for _, locale in ipairs({'deDE', 'frFR', 'esES', 'itIT', 'ptBR'}) do
  local words = { test = { word = 'Test', translation = 'meaning', status = 'known' } }
  assert(Addon.RegisterDictionaryProvider(locale, 'pack', words))
  Addon.SetTargetLocale(locale)
  assert(Addon.GetEffectiveWord('test').translation == 'meaning')
  assert(next(Addon.GetWordsTable()) == nil, 'dictionary copied into user data')
  Addon.GetWordsTable().test = { word = 'Test', translation = 'my meaning', status = 'learning' }
  Addon.SetBackgroundStyle('dialog')
  assert(Addon.GetEffectiveWord('test').translation == 'my meaning', 'theme overwrote user entry')
  assert(words.test.translation == 'meaning' and words.test.status == 'known', 'theme changed dictionary')
end
print(string.format('readability: 4 themes x 3 clients x 3 opacity levels; minimum text contrast %.2f:1', minimum))
