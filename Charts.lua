local Addon = WordHunterWoW_Addon

-- A small bar and line chart, drawn with textures, for the statistics window.
--
-- One widget rather than a drawing routine per chart, because the window has
-- half a dozen of them and every one needs the same things: a scale that lands
-- on a round number, bars that follow the window when it is resized, and a
-- tooltip per column. Bars and their segments are pooled and only moved, so
-- redrawing after a resize or a tab switch allocates nothing.
--
-- There is one vertical scale and no second axis: a bar and a line on the same
-- chart are counts of the same thing, so they can share it. Two measures of
-- different size belong in two charts.
--
-- Data, as given to SetData:
--   bars      list of { segments = { { value, color, label, alpha } ... },
--                       title = "tooltip heading", lines = { "extra tooltip line" ... } }
--             segments stack from the bottom up, in the order given. A column
--             with no segments is still a column to hover, which is how a pure
--             line chart gets its tooltip.
--   xLabels   { [barIndex] = "text" } under the bars the caller wants named
--   lines     list of { values = { [barIndex] = number }, color, label,
--                       texts = { [barIndex] = "shown in the tooltip" },
--                       from = last index of what happened (later points are
--                       an estimate and are drawn fainter),
--                       marks = { barIndex ... } points that get a dot and a figure }
--   yFit      scale the chart to the lines instead of from nothing: a running
--             total that starts high is flat against a scale from zero
--   yMax      a ceiling for the bars, when one bar is allowed to run off the top
--   shadeFrom optional bar index; bars from there on sit on a lighter ground,
--             which is how a projection is told apart from what happened
--   shadeLabel, caption   small text inside the plot (top of the shade / top left,
--             or top right with captionRight, for a chart whose bars crowd the left)
--   emptyText shown instead of the plot when there is nothing to draw

local LEFT_PAD, RIGHT_PAD, TOP_PAD = 34, 8, 6
local BOTTOM_PAD = 15
local STEPS = { 1, 2, 4, 6, 8, 10 }

-- What the statistics window draws its own parts in, one set for each of the
-- addon's five background styles. They are not one look in five tints: each has
-- its own rule colour, its own kind of edge (a bevelled double line, a single
-- line, or none and a filled card instead), its own colour for headings and for
-- whatever is lit, and its own shape of tab. The window is dark under all of
-- them, as the frame paints it, so every set is a dark-ground set; what differs
-- is what the ground is made of and what is drawn on it.
--   plot, card, track  grounds of a chart, a figure card, and a bar's empty part
--   edge, bevel        the frame round them, and a faint inner line that makes it a bevel
--   rule, grid         separators and the lines inside a chart
--   shade, shadeEdge   the lighter ground of an estimate and its leading edge
--   ring               the colour round a dot on a line (the ground it sits on)
--   head, accent, dim  heading text, the lit tab and hover, and the unlit tab's label
--   tab                "box", "underline" or "fill": the shape a tab takes
--   kit                "stone" (the game's dark stone, bevelled inner frames, plates and
--                      real tabs), "rim" (the tooltip's rim), or "flat" (coloured grounds
--                      and lines, which is also what any client without the art gets)
--   tint               what stone is tinted with, where it is not left as it is
local THEMES = {
  -- Blizzard's own: black over the dark tiled texture, bronze-gold rules.
  native = {
    plot = { 0, 0, 0, 0.38 }, card = { 0, 0, 0, 0.34 }, track = { 0.18, 0.15, 0.10, 1 },
    edge = { 0.60, 0.49, 0.26, 0.80 }, bevel = { 1.00, 0.85, 0.45, 0.10 },
    rule = { 0.60, 0.49, 0.26, 0.60 }, grid = { 0.70, 0.58, 0.32, 1 },
    shade = { 1.00, 0.82, 0.30, 0.08 }, shadeEdge = { 1.00, 0.82, 0.30, 0.60 }, ring = { 0.07, 0.06, 0.05, 1 },
    head = { 1.00, 0.82, 0.00 }, accent = { 1.00, 0.82, 0.00 }, dim = { 0.82, 0.78, 0.70 }, tab = "box",
    kit = "stone",
  },
  -- The tooltip frame: silver edge with a bevel on blue-black.
  tooltip = {
    plot = { 0, 0.02, 0.06, 0.65 }, card = { 0.06, 0.09, 0.15, 0.90 }, track = { 0.10, 0.14, 0.22, 1 },
    edge = { 0.72, 0.74, 0.80, 0.75 }, bevel = { 1, 1, 1, 0.08 },
    rule = { 0.72, 0.74, 0.80, 0.40 }, grid = { 0.55, 0.60, 0.70, 1 },
    shade = { 0.50, 0.70, 1.00, 0.09 }, shadeEdge = { 0.60, 0.75, 1.00, 0.50 }, ring = { 0.04, 0.06, 0.10, 1 },
    head = { 1.00, 0.82, 0.00 }, accent = { 0.85, 0.92, 1.00 }, dim = { 0.72, 0.78, 0.88 }, tab = "box",
    kit = "rim",
  },
  -- Sepia on brown: the parchment's tan instead of the frame's gold.
  dialog = {
    plot = { 0.18, 0.12, 0.06, 0.55 }, card = { 0.20, 0.14, 0.07, 0.55 }, track = { 0.26, 0.19, 0.10, 1 },
    edge = { 0.78, 0.62, 0.38, 0.65 },
    rule = { 0.78, 0.62, 0.38, 0.50 }, grid = { 0.80, 0.66, 0.42, 1 },
    shade = { 0.95, 0.75, 0.40, 0.09 }, shadeEdge = { 0.90, 0.72, 0.42, 0.55 }, ring = { 0.12, 0.09, 0.05, 1 },
    head = { 0.97, 0.85, 0.60 }, accent = { 0.97, 0.80, 0.52 }, dim = { 0.80, 0.70, 0.55 }, tab = "box",
    kit = "stone", tint = { 1.00, 0.80, 0.58 },
  },
  -- Flat and neutral: no outlines at all, filled cards, a lit tab that is a lighter block.
  solid = {
    plot = { 0.03, 0.035, 0.045, 1 }, card = { 0.14, 0.15, 0.17, 1 }, track = { 0.18, 0.19, 0.22, 1 },
    edge = { 0.50, 0.50, 0.55, 0 },
    rule = { 0.30, 0.32, 0.36, 1 }, grid = { 0.40, 0.42, 0.46, 1 },
    shade = { 0.80, 0.85, 0.95, 0.07 }, shadeEdge = { 0.80, 0.85, 0.95, 0.40 }, ring = { 0.03, 0.035, 0.045, 1 },
    head = { 0.95, 0.95, 0.97 }, accent = { 0.95, 0.95, 0.97 }, dim = { 0.66, 0.68, 0.72 }, tab = "fill",
    kit = "flat",
  },
  -- Modern: navy, a hairline, and an electric blue for what is lit; tabs are underlined.
  midnight = {
    plot = { 0.04, 0.05, 0.09, 0.70 }, card = { 0.10, 0.12, 0.19, 0.95 }, track = { 0.14, 0.16, 0.26, 1 },
    edge = { 0.22, 0.24, 0.34, 0.95 },
    rule = { 0.22, 0.24, 0.34, 0.90 }, grid = { 0.30, 0.34, 0.50, 1 },
    shade = { 0.42, 0.55, 1.00, 0.09 }, shadeEdge = { 0.45, 0.60, 1.00, 0.50 }, ring = { 0.04, 0.05, 0.09, 1 },
    head = { 0.62, 0.76, 1.00 }, accent = { 0.42, 0.62, 1.00 }, dim = { 0.62, 0.66, 0.78 }, tab = "underline",
    kit = "flat",
  },
}

function Addon.ChartTheme()
  local style = Addon.GetBackgroundStyle and Addon.GetBackgroundStyle()
  return THEMES[style] or THEMES.midnight
end

-- The next round number at or above a value, from 1/2/4/6/8/10 times a power of
-- ten. Never under 2, so that the middle gridline is a whole number too.
function Addon.NiceCeiling(value)
  if type(value) ~= "number" or value ~= value or value <= 2 then return 2 end
  local magnitude = 1
  while value > magnitude * 10 do magnitude = magnitude * 10 end
  for _, step in ipairs(STEPS) do
    if value <= step * magnitude then return step * magnitude end
  end
  return 10 * magnitude
end

-- Three round steps that hold a run of values with some room above them, for a
-- scale that does not start at nothing. Returns the bottom and the top.
function Addon.FitRange(low, high)
  local span = math.max(high - low, 1)
  local half = Addon.NiceCeiling(math.ceil(span * 1.25 / 2))
  -- Rounded down to a figure with few digits, so the labels read as such.
  local unit = 1
  while unit * 10 <= half do unit = unit * 10 end
  local bottom = math.max(0, math.floor((low - (2 * half - span) / 3) / unit) * unit)
  while bottom + 2 * half < high do half = Addon.NiceCeiling(half + 1) end
  return bottom, bottom + 2 * half
end

-- A one pixel frame round a frame, in the theme's edge colour, and inside it a
-- second faint line where the theme calls for a bevel. `scale` fades the edge
-- further; Addon.RecolorOutlines puts every one right after a theme change.
local outlines = {}

function Addon.RecolorOutline(edges)
  local theme = Addon.ChartTheme()
  local c, bevel = theme.edge, theme.bevel
  -- The game's own border where the theme calls for it and the client has it;
  -- the flat lines below are drawn only when it is not.
  local mode = theme.kit == "stone" and "inset" or (theme.kit == "rim" and "rim" or nil)
  local drawn = Addon.Kit and Addon.Kit.SetBorder(edges.frame, mode, c)
  for index = 1, 4 do
    edges[index]:SetColorTexture(c[1], c[2], c[3], drawn and 0 or c[4] * (edges.scale or 1))
    if bevel and not drawn then
      edges.inner[index]:SetColorTexture(bevel[1], bevel[2], bevel[3], bevel[4])
    else
      edges.inner[index]:SetColorTexture(0, 0, 0, 0)
    end
  end
end

function Addon.RecolorOutlines()
  for _, edges in ipairs(outlines) do Addon.RecolorOutline(edges) end
end

function Addon.AddOutline(frame, scale)
  local edges = { scale = scale or 1, inner = {}, frame = frame }
  outlines[#outlines + 1] = edges
  for index = 1, 4 do
    edges[index] = frame:CreateTexture(nil, "BORDER")
    edges.inner[index] = frame:CreateTexture(nil, "BORDER")
  end
  edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(1)
  edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(1)
  edges[3]:SetPoint("TOPLEFT"); edges[3]:SetPoint("BOTTOMLEFT"); edges[3]:SetWidth(1)
  edges[4]:SetPoint("TOPRIGHT"); edges[4]:SetPoint("BOTTOMRIGHT"); edges[4]:SetWidth(1)
  local inner = edges.inner
  inner[1]:SetPoint("TOPLEFT", 1, -1); inner[1]:SetPoint("TOPRIGHT", -1, -1); inner[1]:SetHeight(1)
  inner[2]:SetPoint("BOTTOMLEFT", 1, 1); inner[2]:SetPoint("BOTTOMRIGHT", -1, 1); inner[2]:SetHeight(1)
  inner[3]:SetPoint("TOPLEFT", 1, -1); inner[3]:SetPoint("BOTTOMLEFT", 1, 1); inner[3]:SetWidth(1)
  inner[4]:SetPoint("TOPRIGHT", -1, -1); inner[4]:SetPoint("BOTTOMRIGHT", -1, 1); inner[4]:SetWidth(1)
  Addon.RecolorOutline(edges)
  return edges
end

local function number(value)
  return tostring(math.floor((tonumber(value) or 0) + 0.5))
end

local function barTotal(bar)
  local total = 0
  for _, segment in ipairs(bar.segments or {}) do total = total + (tonumber(segment.value) or 0) end
  return total
end

local function showTip(barFrame)
  local chart = barFrame.chart
  local data = chart.data
  local bar = data and data.bars[barFrame.index]
  if not bar then return end
  GameTooltip:SetOwner(barFrame, "ANCHOR_TOP")
  GameTooltip:SetText(bar.title or "", 1, 1, 1)
  local shown = 0
  for _, segment in ipairs(bar.segments or {}) do
    local value = tonumber(segment.value) or 0
    if value > 0 and segment.label then
      local c = segment.color or Addon.COLORS.text
      GameTooltip:AddDoubleLine(segment.label, segment.text or number(value), c[1], c[2], c[3], 1, 1, 1)
      shown = shown + 1
    end
  end
  if shown > 1 then
    local total = barTotal(bar)
    GameTooltip:AddDoubleLine(chart.totalLabel or "Total", bar.totalText or number(total), 0.8, 0.8, 0.8, 1, 1, 1)
  end
  for _, series in ipairs(data.lines or {}) do
    local value = series.values[barFrame.index]
    if value then
      local c = series.color or Addon.COLORS.text
      GameTooltip:AddDoubleLine(series.label or "", series.texts and series.texts[barFrame.index] or number(value),
        c[1], c[2], c[3], 1, 1, 1)
    end
  end
  for _, text in ipairs(bar.lines or {}) do GameTooltip:AddLine(text, 0.78, 0.82, 0.88, true) end
  GameTooltip:Show()
end

local function leaveBar(barFrame)
  barFrame.highlight:Hide()
  GameTooltip:Hide()
end

local function enterBar(barFrame)
  barFrame.highlight:Show()
  showTip(barFrame)
end

local function newBar(chart, index)
  local frame = CreateFrame("Frame", nil, chart.clip)
  frame:EnableMouse(true)
  frame.chart = chart
  frame.index = index
  frame.segments = {}
  frame.highlight = frame:CreateTexture(nil, "OVERLAY")
  frame.highlight:SetAllPoints()
  frame.highlight:SetColorTexture(1, 1, 1, 0.10)
  frame.highlight:Hide()
  frame:SetScript("OnEnter", enterBar)
  frame:SetScript("OnLeave", leaveBar)
  return frame
end

local function segmentTexture(frame, slot)
  local texture = frame.segments[slot]
  if not texture then
    texture = frame:CreateTexture(nil, "ARTWORK")
    frame.segments[slot] = texture
    -- What is laid on the colour: the stone's grain, a lit edge along the top, a
    -- shaded one down the right, and for an estimate an outline.
    texture.grain = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    texture.lip = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    texture.shade = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    texture.outline = {}
    for index = 1, 3 do texture.outline[index] = frame:CreateTexture(nil, "ARTWORK", nil, 2) end
  end
  return texture
end

local function hideSegment(texture)
  texture:Hide()
  texture.grain:Hide(); texture.lip:Hide(); texture.shade:Hide()
  for _, edge in ipairs(texture.outline) do edge:Hide() end
end

-- One segment of a column: a toned colour with the stone's grain over it, a lit
-- edge along the top and a shaded one down the right. An estimate (anything
-- drawn at less than full strength) is the same slab in a paler colour, so it
-- reads as "not yet" and is every bit as solid as the rest. The flat styles
-- draw plain colour, and fade an estimate as they always have.
local function paintSegment(frame, slot, c, alpha, theme, width, height, bottom)
  local texture = segmentTexture(frame, slot)
  local flat = theme.kit == "flat"
  local estimate = (alpha or 1) < 1 and not flat
  local r, g, b = Addon.Kit.Tone(c, theme)
  if estimate then r, g, b = Addon.Kit.Pale(r, g, b) end
  texture:ClearAllPoints()
  texture:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, bottom)
  texture:SetSize(width, height)
  texture:SetColorTexture(r, g, b, flat and (alpha or 1) or 1)
  texture:Show()
  for _, part in ipairs({ texture.grain, texture.lip, texture.shade }) do
    part:ClearAllPoints()
    part:Hide()
  end
  for _, edge in ipairs(texture.outline) do edge:ClearAllPoints(); edge:Hide() end
  if flat then return end
  if Addon.Kit.Grain(texture.grain, theme, Addon.Kit.GRAIN) then
    texture.grain:SetAllPoints(texture)
  end
  texture.lip:SetColorTexture(1, 0.95, 0.8, 0.30)
  texture.lip:SetPoint("TOPLEFT", texture, "TOPLEFT"); texture.lip:SetPoint("TOPRIGHT", texture, "TOPRIGHT")
  texture.lip:SetHeight(1)
  texture.lip:Show()
  if width >= 6 then
    texture.shade:SetColorTexture(0, 0, 0, 0.28)
    texture.shade:SetPoint("TOPRIGHT", texture, "TOPRIGHT"); texture.shade:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT")
    texture.shade:SetWidth(1)
    texture.shade:Show()
  end
end

local function labelString(chart, pool, index)
  local label = pool[index]
  if not label then
    label = chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pool[index] = label
  end
  return label
end

local function markPool(chart, index)
  local mark = chart.marks[index]
  if not mark then
    mark = {}
    mark.ring = chart.overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    mark.ring:SetSize(9, 9)
    mark.ring:SetColorTexture(0.05, 0.07, 0.10, 1)
    mark.dot = chart.overlay:CreateTexture(nil, "OVERLAY", nil, 2)
    mark.dot:SetSize(5, 5)
    mark.text = chart.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    chart.marks[index] = mark
  end
  return mark
end

local function layout(chart)
  local data = chart.data
  if not data then return end
  local width = (chart:GetWidth() or 0) - LEFT_PAD - RIGHT_PAD
  local height = (chart:GetHeight() or 0) - TOP_PAD - chart.bottomPad
  if width < 8 or height < 8 then return end
  local plot = chart.plot
  local count = #data.bars

  local theme = Addon.ChartTheme()
  Addon.Kit.Ground(chart.ground, theme, "plot")
  chart.shade:SetColorTexture(theme.shade[1], theme.shade[2], theme.shade[3], theme.shade[4])
  chart.shadeEdge:SetColorTexture(theme.shadeEdge[1], theme.shadeEdge[2], theme.shadeEdge[3], theme.shadeEdge[4])
  Addon.RecolorOutline(chart.outline)

  -- The columns are cut off at the border's inner edge. The game's borders are
  -- drawn a few pixels inside the frame they are put round, so a column that
  -- starts at the plot's edge, or reaches its top, was poking out past the line
  -- that is supposed to hold it. A one pixel line (the flat styles) has no such
  -- margin and needs none.
  local pad = theme.kit == "stone" and 3 or (theme.kit == "rim" and 4 or 0)
  chart.clip:ClearAllPoints()
  chart.clip:SetPoint("TOPLEFT", plot, "TOPLEFT", pad, -pad)
  chart.clip:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", -pad, 0)
  if chart.clip.SetClipsChildren then chart.clip:SetClipsChildren(pad > 0) end

  local top, low, high = 0, math.huge, 0
  for _, bar in ipairs(data.bars) do top = math.max(top, barTotal(bar)) end
  for _, series in ipairs(data.lines or {}) do
    for _, value in pairs(series.values) do
      value = tonumber(value) or 0
      low, high = math.min(low, value), math.max(high, value)
    end
  end
  local empty = top <= 0 and high <= 0
  local yMin, yMax = 0, nil
  if data.yFit and low < math.huge then
    yMin, yMax = Addon.FitRange(low, high)
  else
    yMax = Addon.NiceCeiling(data.yMax or math.max(top, high))
  end
  local function reach(value)
    return math.floor(math.max(0, math.min((value - yMin) / (yMax - yMin), 1)) * height + 0.5)
  end

  chart.emptyLabel:SetText(data.emptyText or "")
  chart.emptyLabel:SetShown(empty and (data.emptyText ~= nil))
  chart.caption:SetText(data.caption or "")
  chart.caption:ClearAllPoints()
  if data.captionRight then
    chart.caption:SetPoint("TOPRIGHT", plot, "TOPRIGHT", -5, -3)
  else
    chart.caption:SetPoint("TOPLEFT", plot, "TOPLEFT", 5, -3)
  end

  -- Gridlines at the bottom, half and full scale, named on the left.
  for step = 0, 2 do
    local y = math.floor(height * step / 2 + 0.5)
    local grid = chart.grid[step + 1]
    grid:ClearAllPoints()
    grid:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, y)
    grid:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, y)
    -- With nothing to draw only the floor stays, so the words in the middle
    -- are not struck through by a rule.
    grid:SetColorTexture(theme.grid[1], theme.grid[2], theme.grid[3], 1)
    grid:SetAlpha(step == 0 and 0.55 or (empty and 0 or 0.24))
    local left = chart.yLabels[step + 1]
    left:ClearAllPoints()
    left:SetPoint("RIGHT", plot, "BOTTOMLEFT", -4, y)
    left:SetText(empty and (step == 0 and "0" or "") or number(yMin + (yMax - yMin) * step / 2))
  end

  local slot = width / math.max(count, 1)
  local gap = slot >= 8 and 2 or (slot >= 4.5 and 1 or 0)
  for index = 1, count do
    local bar = data.bars[index]
    local frame = chart.barFrames[index]
    if not frame then
      frame = newBar(chart, index)
      chart.barFrames[index] = frame
    end
    local x = math.floor((index - 1) * slot + 0.5)
    local nextX = math.floor(index * slot + 0.5)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, 0)
    frame:SetSize(math.max(nextX - x, 1), height)
    frame:Show()
    local inner = math.max(nextX - x - gap, 1)
    local cumulative, drawn = 0, 0
    local used = 0
    for _, segment in ipairs(bar.segments or {}) do
      local value = tonumber(segment.value) or 0
      if value > 0 then
        used = used + 1
        cumulative = cumulative + value
        local edge = reach(cumulative)
        paintSegment(frame, used, segment.color or Addon.COLORS.text, segment.alpha, theme,
          inner, math.max(edge - drawn, 1), drawn)
        drawn = math.max(edge, drawn + 1)
      end
    end
    for slotIndex = used + 1, #frame.segments do hideSegment(frame.segments[slotIndex]) end
    frame.highlight:Hide()
  end
  for index = count + 1, #chart.barFrames do chart.barFrames[index]:Hide() end

  -- The figure over a column, for a chart of a few columns: the height says how
  -- much, the figure says exactly. A column that runs off the top has its figure
  -- elsewhere (the caller names it), and an empty one has none.
  for index = 1, math.max(count, #chart.valueLabels) do
    local label = chart.valueLabels[index]
    local total = index <= count and barTotal(data.bars[index]) or 0
    if chart.showValues and index <= count and total > 0 and total <= yMax then
      if not label then
        label = chart.overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        chart.valueLabels[index] = label
      end
      label:ClearAllPoints()
      local y = reach(total)
      if y + 16 <= height then
        label:SetPoint("BOTTOM", plot, "BOTTOMLEFT", math.floor((index - 0.5) * slot + 0.5), y + 2)
      else
        label:SetPoint("TOP", plot, "BOTTOMLEFT", math.floor((index - 0.5) * slot + 0.5), y - 3)
      end
      label:SetText(number(total))
      label:Show()
    elseif label then
      label:Hide()
    end
  end

  for index = 1, count do
    local text = data.xLabels and data.xLabels[index]
    if text then
      local label = labelString(chart, chart.xLabels, index)
      label:ClearAllPoints()
      label:SetPoint("TOP", plot, "BOTTOMLEFT", math.floor((index - 0.5) * slot + 0.5), -2)
      label:SetText(text)
      label:Show()
    elseif chart.xLabels[index] then
      chart.xLabels[index]:Hide()
    end
  end
  -- Pooled by bar index with gaps, so the leftovers are found by walking it.
  for index, label in pairs(chart.xLabels) do
    if index > count then label:Hide() end
  end

  if data.shadeFrom and data.shadeFrom <= count then
    local x = math.floor((data.shadeFrom - 1) * slot + 0.5)
    chart.shade:ClearAllPoints()
    chart.shade:SetPoint("TOPLEFT", plot, "TOPLEFT", x, 0)
    chart.shade:SetPoint("BOTTOMRIGHT", plot, "BOTTOMRIGHT", 0, 0)
    chart.shade:Show()
    chart.shadeEdge:ClearAllPoints()
    chart.shadeEdge:SetPoint("TOPLEFT", plot, "TOPLEFT", x, 0)
    chart.shadeEdge:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", x, 0)
    chart.shadeEdge:Show()
    chart.shadeText:ClearAllPoints()
    chart.shadeText:SetPoint("TOPLEFT", plot, "TOPLEFT", x + 5, -3)
    chart.shadeText:SetText(data.shadeLabel or "")
  else
    chart.shade:Hide()
    chart.shadeEdge:Hide()
    chart.shadeText:SetText("")
  end

  -- The lines, joined column centre to column centre, an estimate fainter than
  -- what happened. Where the client has no Line object the bars alone are drawn,
  -- which loses a trend and nothing else. The dots and figures do not need one.
  local drawnLines, drawnMarks = 0, 0
  for _, series in ipairs(data.lines or {}) do
    local c = series.color or Addon.COLORS.text
    local previousX, previousY
    for index = 1, count do
      local value = tonumber(series.values[index])
      if value then
        local px = (index - 0.5) * slot
        local py = reach(value)
        if previousX and chart.overlay.CreateLine then
          drawnLines = drawnLines + 1
          local line = chart.lines[drawnLines]
          if not line then
            line = chart.overlay:CreateLine(nil, "OVERLAY")
            chart.lines[drawnLines] = line
          end
          local estimate = series.from and index > series.from
          line:SetThickness(estimate and 1.4 or 1.8)
          line:SetColorTexture(c[1], c[2], c[3], estimate and 0.6 or 0.95)
          line:SetStartPoint("BOTTOMLEFT", plot, previousX, previousY)
          line:SetEndPoint("BOTTOMLEFT", plot, px, py)
          line:Show()
        end
        previousX, previousY = px, py
      else
        previousX, previousY = nil, nil
      end
    end
    for _, index in ipairs(series.marks or {}) do
      local value = tonumber(series.values[index])
      if value then
        drawnMarks = drawnMarks + 1
        local mark = markPool(chart, drawnMarks)
        local px, py = (index - 0.5) * slot, reach(value)
        mark.ring:SetColorTexture(theme.ring[1], theme.ring[2], theme.ring[3], 1)
        mark.ring:ClearAllPoints()
        mark.ring:SetPoint("CENTER", plot, "BOTTOMLEFT", px, py)
        mark.ring:Show()
        mark.dot:ClearAllPoints()
        mark.dot:SetPoint("CENTER", plot, "BOTTOMLEFT", px, py)
        mark.dot:SetColorTexture(c[1], c[2], c[3], 1)
        mark.dot:Show()
        -- Above the point, centred; tucked to its left at the right-hand edge
        -- and beneath it when it is up against the top.
        mark.text:ClearAllPoints()
        local near = px > width - 26
        local above = py + 20 <= height
        if above then
          mark.text:SetPoint(near and "BOTTOMRIGHT" or "BOTTOM", plot, "BOTTOMLEFT", px + (near and 6 or 0), py + 6)
        else
          mark.text:SetPoint(near and "TOPRIGHT" or "TOP", plot, "BOTTOMLEFT", px + (near and 6 or 0), py - 6)
        end
        mark.text:SetText(series.texts and series.texts[index] or number(value))
        mark.text:Show()
      end
    end
  end
  for index = drawnLines + 1, #chart.lines do chart.lines[index]:Hide() end
  for index = drawnMarks + 1, #chart.marks do
    local mark = chart.marks[index]
    mark.ring:Hide()
    mark.dot:Hide()
    mark.text:Hide()
  end
end

function Addon.CreateBarChart(parent, options)
  options = options or {}
  local chart = CreateFrame("Frame", nil, parent)
  if options.height then chart:SetHeight(options.height) end
  chart.bottomPad = options.bottomPad or BOTTOM_PAD
  chart.totalLabel = options.totalLabel
  chart.barFrames, chart.xLabels, chart.lines, chart.marks = {}, {}, {}, {}
  chart.valueLabels = {}
  chart.showValues = options.values == true

  local plot = CreateFrame("Frame", nil, chart)
  plot:SetPoint("TOPLEFT", chart, "TOPLEFT", LEFT_PAD, -TOP_PAD)
  plot:SetPoint("BOTTOMRIGHT", chart, "BOTTOMRIGHT", -RIGHT_PAD, chart.bottomPad)
  chart.plot = plot
  -- What the columns are drawn in; sized to the plot by layout().
  chart.clip = CreateFrame("Frame", nil, plot)
  chart.clip:SetAllPoints(plot)
  chart.clip:EnableMouse(false)

  chart.ground = plot:CreateTexture(nil, "BACKGROUND")
  chart.ground:SetAllPoints()
  chart.outline = Addon.AddOutline(plot, 1)
  chart.shade = plot:CreateTexture(nil, "BACKGROUND", nil, 1)
  chart.shade:Hide()
  chart.shadeEdge = plot:CreateTexture(nil, "BACKGROUND", nil, 2)
  chart.shadeEdge:SetWidth(1)
  chart.shadeEdge:Hide()

  chart.grid, chart.yLabels = {}, {}
  for step = 1, 3 do
    local grid = plot:CreateTexture(nil, "BACKGROUND", nil, 3)
    grid:SetHeight(1)
    chart.grid[step] = grid
    local left = chart:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    left:SetJustifyH("RIGHT")
    chart.yLabels[step] = left
  end

  -- Above every bar, so the line and the small texts are not painted over by
  -- the columns they cross. It takes no mouse: the bars underneath still get
  -- the tooltip.
  chart.overlay = CreateFrame("Frame", nil, plot)
  chart.overlay:SetAllPoints()
  chart.overlay:SetFrameLevel(plot:GetFrameLevel() + 6)
  chart.overlay:EnableMouse(false)

  chart.shadeText = chart.overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chart.shadeText:SetJustifyH("LEFT")
  chart.caption = chart.overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chart.caption:SetPoint("TOPLEFT", plot, "TOPLEFT", 5, -3)
  chart.emptyLabel = chart.overlay:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  chart.emptyLabel:SetPoint("CENTER", plot, "CENTER")
  chart.emptyLabel:Hide()

  chart:SetScript("OnSizeChanged", layout)
  chart:SetScript("OnShow", layout)

  function chart:SetData(data)
    self.data = data
    layout(self)
  end

  return chart
end

-- A row of colour swatches with a name each, for under a chart's title.
--   legend:SetEntries({ { color = COLORS.known, text = "Known" }, ... })
-- An entry with `line = true` is a short rule rather than a square, which is
-- what a line on the chart looks like.
function Addon.CreateChartLegend(parent)
  local legend = CreateFrame("Frame", nil, parent)
  legend:SetHeight(14)
  legend.items = {}
  function legend:SetEntries(entries)
    -- Kept, because the colours are drawn from these and a change of palette or
    -- style has to draw them again: a legend painted once, when the window was
    -- built, went on showing the old colour beside bars in the new one.
    self.entries = entries
    local x = 0
    for index, entry in ipairs(entries) do
      local item = self.items[index]
      if not item then
        item = {}
        item.swatch = self:CreateTexture(nil, "ARTWORK")
        item.edge = {}
        for side = 1, 4 do item.edge[side] = self:CreateTexture(nil, "ARTWORK", nil, 1) end
        item.text = self:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        self.items[index] = item
      end
      local c = entry.color or Addon.COLORS.text
      local swatchWidth = entry.line and 12 or 8
      item.swatch:SetSize(swatchWidth, entry.line and 2 or 8)
      -- Painted as the columns are, so the key matches what it names.
      local theme = Addon.ChartTheme()
      local estimate = not entry.line and (entry.alpha or 1) < 1 and theme.kit ~= "flat"
      local r, g, b = c[1], c[2], c[3]
      if not entry.line then r, g, b = Addon.Kit.Tone(c, theme) end
      if estimate then r, g, b = Addon.Kit.Pale(r, g, b) end
      item.swatch:SetColorTexture(r, g, b, (estimate and 1) or (entry.alpha or 1))
      item.swatch:Show()
      if entry.line then
        local grain = rawget(item.swatch, "whwGrain")
        if grain then grain:Hide() end
      else
        Addon.Kit.Speckle(item.swatch, theme)
      end
      for _, edge in ipairs(item.edge) do edge:Hide() end
      item.swatch:ClearAllPoints()
      item.swatch:SetPoint("LEFT", self, "LEFT", x, 0)
      item.text:ClearAllPoints()
      item.text:SetPoint("LEFT", item.swatch, "RIGHT", 4, 0)
      item.text:SetText(entry.text)
      item.swatch:Show()
      item.text:Show()
      x = x + swatchWidth + 4 + math.ceil(item.text:GetStringWidth() or 40) + 12
    end
    for index = #entries + 1, #self.items do
      self.items[index].swatch:Hide()
      local grain = rawget(self.items[index].swatch, "whwGrain")
      if grain then grain:Hide() end
      for _, edge in ipairs(self.items[index].edge) do edge:Hide() end
      self.items[index].text:Hide()
    end
  end
  Addon.Kit.OnRefresh(function()
    local entries = rawget(legend, "entries")
    if entries then legend:SetEntries(entries) end
  end)
  return legend
end
