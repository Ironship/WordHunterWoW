local Addon = WordHunterWoW_Addon
local COLORS = Addon.COLORS
local LABELS = Addon.LABELS
local unpack = unpack or table.unpack

-- Everything the player reads comes out of Addon.LABELS -- one table, so a
-- translator has one place to work through and nothing that draws a string has
-- to go looking elsewhere for it. The quest log's three join it from here
-- rather than being written where they are used, because the button, its
-- tooltip and the switch that governs it are one feature, and wording them
-- apart is how a control and its setting end up calling the same thing by two
-- different names.
LABELS.questLogButton = "WordHunterWoW - Reader"
LABELS.questLogButtonTip = "Show this quest's text side by side."
LABELS.questLogAutoLabel = "Open the quest panel automatically from the quest log"
-- Its two neighbours, enOfferOnly and enNoOffer, each name the passage that is
-- being shown in place of the one asked for. This one is for the record that
-- holds no passage at all -- a title and nothing else -- so it names nothing
-- and promises nothing. It joins the table from here rather than from Core so
-- that the branch that raises it and the words it raises stay in one file.
LABELS.enNoText = "[No English text exists for this quest beyond its title.]"

local panel
local wordButtons = {}
local enBits = {}
-- The row height the layout is built on, before the player's text size is
-- applied. Both the font and the row have to scale together: scaling the letters
-- alone makes them collide with the line below.
local BASE_TOKEN_H = 18
local BASE_TOKEN_STEP = 18

local function tokenMetrics(scale)
  scale = scale or (Addon.GetTextScale and Addon.GetTextScale() or 1)
  return BASE_TOKEN_H * scale, BASE_TOKEN_STEP * scale
end

-- Each column has its own size. The right one is the language being learned and
-- follows "Quest panel text"; the left one is the English and follows "English
-- text", the same setting as the separate English window -- because with the
-- integrated layout on, which is the default, that column *is* the English
-- panel as far as the reader is concerned. Tying it to the other slider left
-- the English one apparently doing nothing at all.
--
-- Left and right as ApplyIntegratedLayout anchors them: enScroll from the
-- panel's left edge to its centre, scroll from the centre to the right edge.
-- The width the words may use, which is the width of the pane they are shown
-- in and not a guess at it.
--
-- Both numbers above are struck from the panel's own width less an inset
-- written out by hand, and the pane they have to fit is anchored with a
-- different pair of insets somewhere else. They disagreed. In the single-column
-- layout the pane is 50px narrower than the panel and the content was 48, so
-- the last two pixels of every full line were cut off -- present, laid out,
-- clipped. Worse below 480px wide, where the max() floor stops the content
-- shrinking while the pane keeps going: two columns at the 400px resize
-- minimum gave a 200px content in a 160px pane, and forty pixels of every line
-- were simply not there.
--
-- Clamping rather than replacing the formula. Where the guess already fits it
-- is left alone, so nothing moves at the widths anyone actually uses, and the
-- pane only ever takes width away. A pane that cannot say how wide it is yet --
-- the first render, before the panel has been laid out -- keeps the guess,
-- which is what it had before.
local function fitToPane(scroll, width)
  local pane = scroll and scroll.GetWidth and scroll:GetWidth()
  if not pane or pane <= 0 then return width end
  return math.min(width, pane)
end

-- How one word is marked: its colour and its underline, from its status and
-- the player's marking choice. `status` is nil for a word nothing knows, which
-- is drawn plain. Shared with the settings window's preview, so the picture of
-- the panel there cannot drift from the panel itself.
function Addon.StyleWordButton(button, status, marking, underlineHeight, textColor)
  button.text:SetTextColor(unpack(textColor or COLORS.text))
  if not status then
    button.underline:Hide()
    return
  end
  -- The surface picks the palette. `textColor` arriving is the caller saying
  -- it has already resolved the ink for this frame, so it is the right place
  -- to ask which of the two the frame is wearing -- and the answer needs the
  -- theme as well, because a native window keeps its chrome when the player
  -- switches to a dark theme and must then wear the dark palette.
  --
  -- This used to be the right colour multiplied by 0.45, which was a guess
  -- that worked out: the result was dark enough on the parchment but its
  -- contrast was never measured, and the same multiplication made the status
  -- indistinguishable from the body ink. Addon.COLORS_ON_LIGHT is the measured
  -- answer, and tests/readability.test.lua holds it to the same floor as
  -- everything else.
  local palette = Addon.PaletteFor(textColor ~= nil and Addon.GetBackgroundStyle() == "native")
  local color = palette[status] or palette.new
  if marking ~= "underline" then
    button.text:SetTextColor(color[1], color[2], color[3])
  end
  if marking ~= "color" then
    -- Opaque, and thick enough to survive the player's text size. Drawn
    -- faint and one pixel high, the mark was there without being legible,
    -- which is the worst of both.
    button.underline:SetHeight(underlineHeight)
    button.underline:SetColorTexture(color[1], color[2], color[3], 1)
    button.underline:Show()
  else
    button.underline:Hide()
  end
end

local function tokenFont(fs, scale, surface)
  -- GameFontHighlight for the family and the white; the body role for the
  -- size. They are the same number here -- body is anchored to this very
  -- object -- which is exactly why the word list's rows and the editor's boxes
  -- were moved onto it rather than the panel being moved off it.
  local path, _, flags = GameFontHighlight:GetFont()
  scale = scale or (Addon.GetTextScale and Addon.GetTextScale() or 1)
  local size = Addon.RoleSize("body", scale)
  if path then fs:SetFont(path, size or (12 * scale), flags) end
  -- `surface` is the window the words are drawn on, because it decides the
  -- shadow as it decides the colour. On the dark themes the letters are light
  -- over a translucent panel with the game showing through, and the drop
  -- shadow is what separates them from it. On the parchment the letters are
  -- dark ink on light, and the same shadow only smears them: this used to set
  -- the shadow off and then immediately set it back on again in the next line,
  -- so the parchment words kept the dark themes' shadow and the intention in
  -- the `if` never happened.
  if surface and Addon.UsesLightSurface(surface) then
    fs:SetShadowColor(0, 0, 0, 0)
    fs:SetShadowOffset(0, 0)
  else
    fs:SetShadowColor(0, 0, 0, 0.9)
    fs:SetShadowOffset(1, -1)
  end
end
-- The settings preview draws its sample words with this too.
Addon.TokenFont = tokenFont

-- The panel's own furniture -- the title, the progress line, the legend under
-- the text and the buttons beside it -- measured at 100%. Every one of these is
-- multiplied by the same scale the words are, for the reason BASE_TOKEN_H is
-- shared with them: a font that grows inside a box that does not is a clipped
-- font, and an offset that stays where it was while the thing above it grows is
-- an overlap. These were fixed numbers written into the constructor and never
-- touched again, so at 200% the quest text was twice its size inside furniture
-- that had not moved at all, and the panel read as two windows stuck together.
--
-- Nothing here is a horizontal margin, and that is deliberate. This window is
-- sized to sit beside the game's own quest window and the point of it is how
-- much text fits across it, so spending its width on wider margins is the one
-- thing the size setting must not do. Height is the opposite case: the text
-- scrolls, so a taller heading costs scrolling rather than words.
local CHROME_BASE = {
  topPad = 12,        -- above the title
  titleH = 21,
  titleGap = 3,       -- title down to whatever is under it
  metaH = 14,
  metaGap = 8,        -- progress line down to the quest text
  dividerGap = 16,    -- column headings down to the rule between the columns
  footPad = 8,        -- under the buttons
  buttonH = 26,
  buttonGap = 6,      -- between two buttons
  metaFootY = 15,     -- progress line's own baseline when it sits in the footer
  legendGap = 16,     -- buttons up to the legend
  legendRowH = 12,
  legendRowGap = 4,
  legendStep = 96,    -- the floor on one legend entry's width, not the width
  legendItemGap = 24, -- a legend label to the next dot
  dotSize = 7,
  dotGap = 5,         -- a dot to its own label
  footerGap = 5,      -- legend up to the rule above it
  contentGap = 5,     -- that rule up to the bottom of the text
}

local function chromeMetrics(scale)
  scale = scale or (Addon.GetTextScale and Addon.GetTextScale() or 1)
  local m = { scale = scale }
  for key, base in pairs(CHROME_BASE) do m[key] = base * scale end
  local hints = Addon.PanelInputHintHeight and Addon.PanelInputHintHeight(panel) or 0
  m.footPad = m.footPad + hints
  m.metaFootY = m.metaFootY + hints
  if panel and rawget(panel, 'whwNativeStyle') then m.topPad = m.topPad + 28 end
  -- Where the heading block ends, which is where the text under it starts in
  -- the two-column layout and where the progress line goes in the one-column
  -- one.
  m.headBottom = m.topPad + m.titleH + m.titleGap
  if panel and rawget(panel, 'whwNativeStyle') then m.headBottom = m.headBottom + 12 end
  m.metaBottom = m.headBottom + m.metaH + m.metaGap
  m.legendBottom = m.footPad + m.buttonH + m.legendGap
  return m
end

-- Re-fonts one of the panel's own strings off the font object it was built
-- with, the way tokenFont does for the quest words. The size is read back from
-- the object rather than written down here so that a player who has turned the
-- game's own font up keeps that: the setting is a multiple of whatever the
-- client draws with, never a replacement for it.
-- The object still supplies the family and, with it, the colour the string was
-- built to wear; the role supplies the size. Splitting the two is what lets
-- every surface share one set of sizes without a single string changing
-- colour, which is what re-basing them onto shared font objects would have
-- done silently.
local function chromeFont(fs, objectName, role, scale)
  local object = _G[objectName]
  if not (fs and fs.SetFont and object and object.GetFont) then return end
  local path, size, flags = object:GetFont()
  size = Addon.RoleSize(role, scale) or (size or 12) * scale
  if path then fs:SetFont(path, size, flags) end
end

-- The four status colours and their names along the bottom of the panel.
-- Measured rather than stepped at a flat 96px: four labels at twice the size no
-- longer fit that step, and on a panel dragged down to its minimum width they
-- no longer fit the row at all, so a row that would overrun the panel wraps
-- instead of running off the edge. The old step survives as a floor, which is
-- what keeps every dot at 100% exactly where it has always been.
--
-- Returns how many rows it took, because the band under the text has to be tall
-- enough to hold them.
local function layoutLegend(m)
  local margin = 18
  local available = math.max(1, (panel:GetWidth() or 0) - margin * 2)
  local offsets, rowOf, rows, x = {}, {}, 1, 0
  for index, item in ipairs(panel.legend) do
    chromeFont(item.text, "GameFontNormalSmall", "label", m.scale)
    local width = m.dotSize + m.dotGap + math.ceil(item.text:GetStringWidth() or 0)
    if x > 0 and x + width > available then
      x = 0
      rows = rows + 1
    end
    offsets[index], rowOf[index] = x, rows
    x = x + math.max(m.legendStep, width + m.legendItemGap)
  end
  for index, item in ipairs(panel.legend) do
    -- Row 1 is the top one, so it is the furthest from the bottom edge the
    -- whole band is measured from.
    local y = m.legendBottom + (rows - rowOf[index]) * (m.legendRowH + m.legendRowGap)
    item.dot:ClearAllPoints()
    item.dot:SetSize(m.dotSize, m.dotSize)
    item.dot:SetPoint("BOTTOMLEFT", margin + offsets[index], y)
    item.text:ClearAllPoints()
    item.text:SetPoint("LEFT", item.dot, "RIGHT", m.dotGap, 0)
  end
  return rows
end

-- The buttons along the bottom, laid right to left from the corner. Their
-- captions come from UIPanelButtonTemplate's own font object, which is fixed,
-- so the box has to be resized along with the letters or the caption grows out
-- of the button it is in. Wrap instead of widening a reader the player sized.
local function layoutActions(m)
  if Addon.RefreshQuestAudioButton then Addon.RefreshQuestAudioButton() end
  local available = math.max(1, panel:GetWidth() - 36)
  local previous, used, rows = nil, 0, 1
  local actions = Addon.lastQuest and Addon.lastQuest.catalog and panel.catalogActions or panel.actions
  -- The Play button joins the row only when it is up, so a player without the
  -- Spoken addon sees the row exactly as it has always been. Laid out anyway
  -- it left a hole the width of a button and pushed everything beside it.
  local playBtn = panel.questAudioButton
  local row = actions
  if playBtn and rawget(playBtn, "whwOptional") and playBtn:IsShown() then
    row = {}
    for index, action in ipairs(actions) do row[index] = action end
    row[#row + 1] = playBtn
  end
  for _, action in ipairs(row) do
    if action.GetFontString then
      chromeFont(action:GetFontString(), "GameFontNormal", "body", m.scale)
    end
    local width = action.baseWidth * m.scale
    action:SetSize(width, m.buttonH)
    action:ClearAllPoints()
    if previous and used + m.buttonGap + width > available then
      previous, used, rows = nil, 0, rows + 1
    end
    if previous then
      action:SetPoint("RIGHT", previous, "LEFT", -m.buttonGap, 0)
    else
      action:SetPoint("BOTTOMRIGHT", -18, m.footPad + (rows - 1) * (m.buttonH + m.buttonGap))
    end
    used = used + width + (previous and m.buttonGap or 0)
    previous = action
  end
  m.legendBottom = m.legendBottom + (rows - 1) * (m.buttonH + m.buttonGap)
  return rows, available - used, previous
end

-- The one place that knows the panel's vertical stack, in either arrangement.
-- It was spread between the constructor and ApplyIntegratedLayout as literal
-- offsets, which is why growing the title's font would have clipped it and
-- dropped it onto the progress line: the -36 the line sits at knew nothing
-- about the 21px box above it.
--
-- Called from ApplyIntegratedLayout, which settles which arrangement is on, and
-- again from every render -- so dragging the size slider moves the whole panel
-- at once instead of the words now and the title on the next quest.
local function layoutChrome()
  if not panel or not panel.legend then return end
  local m = chromeMetrics()
  -- The English column's heading follows the English size, the same setting the
  -- column under it follows -- see tokenFont above. A heading at one size over a
  -- column at another is the fault this whole function exists to end, and it
  -- would simply have moved one column across.
  local en = chromeMetrics(Addon.GetEnPanelTextScale and Addon.GetEnPanelTextScale() or 1)
  if panel.sourceNote then
    local note = Addon.lastQuest and Addon.lastQuest.referenceNote
    if note then
      chromeFont(panel.sourceNote, "GameFontDisableSmall", "label", m.scale)
      panel.sourceNote:SetWidth(math.max(1, panel:GetWidth() - 36))
      panel.sourceNote:SetText(note)
      local top = math.max(m.headBottom, en.headBottom)
      local height = math.max(m.metaH, panel.sourceNote:GetStringHeight())
      panel.sourceNote:ClearAllPoints()
      panel.sourceNote:SetPoint("TOPLEFT", 18, -top)
      panel.sourceNote:SetHeight(height)
      panel.sourceNote:Show()
      local extra = height + m.titleGap
      m.headBottom, en.headBottom = top + extra, top + extra
      m.metaBottom = m.headBottom + m.metaH + m.metaGap
    else panel.sourceNote:Hide() end
  end

  chromeFont(panel.title, rawget(panel, "whwNativeStyle") and "QuestTitleFont" or "GameFontNormalLarge", "heading", m.scale)
  panel.title:SetHeight(m.titleH)
  panel.title:ClearAllPoints()
  chromeFont(panel.meta, "GameFontDisableSmall", "meta", m.scale)
  panel.meta:SetHeight(m.metaH)
  panel.meta:ClearAllPoints()
  chromeFont(panel.enTitle, "GameFontNormalLarge", "heading", en.scale)
  panel.enTitle:SetHeight(en.titleH)
  if rawget(panel, 'whwNativeStyle') then
    local ink = Addon.ReaderInk(panel)
    -- The palette the surface is wearing, which is not the palette the legend
    -- dots were built with if the theme has changed since. Recoloured here
    -- rather than at construction for that reason: the swatches have to follow
    -- the theme, the same as the words above them and the figures in the
    -- progress line.
    local palette = Addon.PaletteFor(Addon.UsesLightSurface(panel))
    for _, text in ipairs({ panel.title, panel.enTitle, panel.meta, panel.sourceNote }) do
      text:SetTextColor(unpack(ink)); text:SetShadowColor(0, 0, 0, 0)
    end
    for _, item in ipairs(panel.legend) do
      item.text:SetTextColor(unpack(ink))
      local dot = palette[item.status] or palette.new
      item.dot:SetColorTexture(dot[1], dot[2], dot[3], 1)
    end
    panel.divider:SetColorTexture(ink[1], ink[2], ink[3], .25)
    panel.footerLine:SetColorTexture(ink[1], ink[2], ink[3], .25)
    panel.headingRule:ClearAllPoints()
    panel.headingRule:SetPoint('TOPLEFT', panel, 'TOPLEFT', 18, -(math.max(m.headBottom, en.headBottom) - 10))
    panel.headingRule:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', -24, -(math.max(m.headBottom, en.headBottom) - 10))
  end
  panel.enTitle:ClearAllPoints()
  panel.enTitle:SetPoint("TOPLEFT", 18, -en.topPad)
  panel.enTitle:SetPoint("RIGHT", panel, "CENTER", -12, 0)
  panel.scroll:ClearAllPoints()
  panel.enScroll:ClearAllPoints()
  local actionRows, freeWidth, lastAction = layoutActions(m)
  -- A narrow footer needs a separate progress row; never reverse its anchors
  -- or put the progress line under the wrapped buttons.
  local progressRow = panel.integratedLayout and (actionRows > 1 or freeWidth <= 8)
  if progressRow then
    m.metaFootY = m.footPad + actionRows * (m.buttonH + m.buttonGap)
    m.legendBottom = m.metaFootY + m.metaH + m.legendGap
  end
  local rows = layoutLegend(m)
  local legendTop = m.legendBottom + rows * m.legendRowH + (rows - 1) * m.legendRowGap
  local footerY = legendTop + m.footerGap
  -- Everything from here down belongs to the footer, so this is where the text
  -- above it has to stop.
  local bandTop = footerY + m.contentGap
  panel.footerLine:ClearAllPoints()
  panel.footerLine:SetPoint("BOTTOMLEFT", 18, footerY)
  panel.footerLine:SetPoint("BOTTOMRIGHT", -18, footerY)

  if panel.integratedLayout then
    panel.title:SetPoint("TOPLEFT", panel, "TOP", 12, -m.topPad)
    panel.title:SetPoint("TOPRIGHT", -40, -m.topPad)
    panel.meta:SetPoint("BOTTOMLEFT", 18, m.metaFootY)
    -- Bounded on the right by the buttons it shares the footer with. Left
    -- unbounded, as it was, a long progress line at a large size runs straight
    -- under them.
    --
    -- Offset back to the same height its left-hand corner is at. The buttons sit
    -- lower than this line does, and two bottom anchors that disagree about
    -- where the bottom is are not a layout the game can resolve.
    if progressRow then
      panel.meta:SetPoint("BOTTOMRIGHT", -18, m.metaFootY)
    else
      panel.meta:SetPoint("BOTTOMRIGHT", lastAction, "BOTTOMLEFT",
        -8, m.metaFootY - m.footPad)
    end
    panel.scroll:SetPoint("TOPLEFT", panel, "TOP", 8, -m.headBottom)
    panel.scroll:SetPoint("BOTTOMRIGHT", -32, bandTop)
    panel.enScroll:SetPoint("TOPLEFT", 18, -en.headBottom)
    panel.enScroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOM", -20, bandTop)
    -- The rule between the columns starts below the deeper of the two headings.
    -- They are sized by different settings, so either can be the deeper one.
    panel.divider:ClearAllPoints()
    panel.divider:SetPoint("TOP", panel, "TOP", 0,
      -(math.max(m.headBottom, en.headBottom) + m.dividerGap))
    panel.divider:SetPoint("BOTTOM", panel, "BOTTOM", 0, bandTop)
    panel.chromeHeight = math.max(m.headBottom, en.headBottom) + bandTop
  else
    panel.title:SetPoint("TOPLEFT", 18, -m.topPad)
    panel.title:SetPoint("TOPRIGHT", -40, -m.topPad)
    panel.meta:SetPoint("TOPLEFT", 18, -m.headBottom)
    panel.meta:SetPoint("TOPRIGHT", Addon.lastQuest and Addon.lastQuest.readOnly and -18 or -140, -m.headBottom)
    panel.scroll:SetPoint("TOPLEFT", 18, -m.metaBottom)
    panel.scroll:SetPoint("BOTTOMRIGHT", -32, bandTop)
    panel.chromeHeight = m.metaBottom + bandTop
  end

  -- The corner may no longer be dragged down over the furniture. 230 was the
  -- floor while the furniture was a fixed 130-odd tall; at 200% it is twice
  -- that, and a window shorter than its own chrome has the legend sitting on
  -- the quest text.
  --
  -- Only when the floor has actually moved. This runs on every render, and
  -- rebounding a frame that is being dragged can clamp it, which is another
  -- size change, which is another render.
  local _, step = tokenMetrics(m.scale)
  local minHeight = math.max(230, panel.chromeHeight + step * 3)
  if panel.chromeMinHeight ~= minHeight then
    panel.chromeMinHeight = minHeight
    Addon.MakeResizable(panel, "panel", 400, minHeight, 1200, 800)
  end
end

local lastHighlightWord
local lastHighlightIndex
local lastHighlightOccurrence
local lastHighlightSentenceOnly
local selectedHighlight

-- Whether the English word beside this one has to stay dark. With the recall
-- check on, a word that is about to ask for a rating must not have its
-- translation lit in the next column -- on hover, and on the click that opens
-- the question. Read live rather than decided at render time, so a rating
-- given a moment ago counts at once and the panel is not redrawn for it. nil
-- rather than false when it does not apply, which is what every caller
-- passed before this existed.
local function recallGated(button)
  if not Addon.RecallGated or not button.key then return nil end
  return Addon.RecallGated(button.key, time(), button.wordLocale) or nil
end

local function sentenceForWord(text, word)
  local _, sentence = Addon.SentenceContaining(text, word)
  return sentence or Addon.trim(text)
end

local function paintEnglishHighlight(sentenceIndex, wordTokens)
  local hl, wordHl, bg = Addon.EnglishHighlightColors(panel)
  local first
  for _, bit in ipairs(enBits) do
    if bit:IsShown() then
      if bit.caveat then
        local color = rawget(panel, "whwNativeStyle") and Addon.ReaderInk(panel) or COLORS.caveat
        bit.text:SetTextColor(color[1], color[2], color[3])
        if bit.glow then bit.glow:Hide() end
      elseif sentenceIndex and bit.sentenceIndex == sentenceIndex then
        local isWord = wordTokens and bit.sentenceToken and wordTokens[bit.sentenceToken]
        local color = isWord and wordHl or hl
        bit.text:SetTextColor(color[1], color[2], color[3])
        if not bit.glow then
          bit.glow = bit:CreateTexture(nil, "BACKGROUND")
          bit.glow:SetAllPoints()
        end
        bit.glow:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
        bit.glow:Show()
        if not first then first = bit end
      else
        bit.text:SetTextColor(unpack(Addon.ReaderInk(panel)))
        if bit.glow then bit.glow:Hide() end
      end
    end
  end
  if first and panel.enScroll and panel.enScroll:IsShown() and type(first.topY) == "number" then
    local view = panel.enScroll:GetHeight() or 0
    local contentH = panel.enContent:GetHeight() or 0
    local maxScroll = math.max(0, contentH - view)
    local current = panel.enScroll:GetVerticalScroll()
    local top = -first.topY
    if top < current or top + first:GetHeight() > current + view then
      panel.enScroll:SetVerticalScroll(math.max(0, math.min(maxScroll, top - 8)))
    end
  end
end

function Addon.HighlightEnglishForWord(word, deSentenceIndex, wordOccurrence, sentenceOnly)
  if not panel or not Addon.lastQuest then return end
  lastHighlightWord = word
  lastHighlightIndex = deSentenceIndex
  lastHighlightOccurrence = wordOccurrence
  lastHighlightSentenceOnly = sentenceOnly
  local enText = panel.enPlain or ""
  local index, sentence
  -- A word, or a sentence number on its own. The second is how the German
  -- voiceover asks: it knows which sentence it is speaking and nobody has
  -- clicked anything. Requiring a word meant the column beside the German text
  -- -- the arrangement almost everyone reads in -- stayed dark for the whole
  -- passage, while the separate English window, which relaxed the same guard,
  -- followed along. MatchEnglishSentence has taken an index without a word
  -- since the voiceover was written, so nothing below needs to change with it.
  if (word or deSentenceIndex) and panel.enCanHighlight and enText ~= ""
    and Addon.MatchEnglishSentence then
    index, sentence = Addon.MatchEnglishSentence(Addon.lastQuest.text, enText, word, deSentenceIndex, Addon.lastQuest.wordLocale)
  end
  local wordTokens
  if sentence and not sentenceOnly and Addon.MatchEnglishTokenIndexes then
    wordTokens = Addon.MatchEnglishTokenIndexes(sentence, word, wordOccurrence, Addon.lastQuest.wordLocale)
  end
  paintEnglishHighlight(index, wordTokens)
  if Addon.OnHighlightEnglishForWord then
    Addon.OnHighlightEnglishForWord(word, Addon.lastQuest, deSentenceIndex, wordOccurrence, sentenceOnly)
  end
end

-- Once the editor has shown the meaning -- rated, or looked at -- the English
-- word may light up the way it does for any other click.
function Addon.RevealSelectedHighlight()
  if not panel or not selectedHighlight or not selectedHighlight[4] then return end
  selectedHighlight[4] = nil
  Addon.HighlightEnglishForWord(selectedHighlight[1], selectedHighlight[2], selectedHighlight[3])
end

local function refreshPanel()
  -- Shadowed for this render, so every measurement below is already in the
  -- player's chosen size.
  local TOKEN_H, TOKEN_STEP = tokenMetrics()
  if not panel or not Addon.lastQuest then return end
  -- And not into a window nobody can see. Saving a word calls this, and a full
  -- relayout measures every token in both columns and looks each one up in the
  -- dictionary. Editing words from the list with the panel closed paid that on
  -- every Save. Reading the quest again re-renders, so nothing goes stale.
  if not panel:IsShown() then return end
  -- The furniture first, and on every render rather than only when the layout
  -- is switched: the size slider calls straight in here, and a panel that moved
  -- its words now and its title on the next quest is the same complaint in
  -- slower motion. It also settles panel.chromeHeight, which the height below
  -- is measured from.
  if Addon.RefreshCatalogPhaseControl then Addon.RefreshCatalogPhaseControl() end
  layoutChrome()
  local lastQuest = Addon.lastQuest
  local readOnly = lastQuest.readOnly == true
  local wordLocale = lastQuest.wordLocale or Addon.GetTargetLocale()
  if Addon.libraryReturnButton then
    if lastQuest.catalog then Addon.libraryReturnButton:Show() else Addon.libraryReturnButton:Hide() end
  end
  -- Whether this render is a different quest from the last one drawn, which is
  -- what decides if the panes go back to the top.
  local newQuest = panel.renderedQuestKey ~= tostring(lastQuest.id or lastQuest.title or "")
    or panel.renderedText ~= lastQuest.text or panel.renderedPassage ~= lastQuest.passage
    or panel.renderedWordLocale ~= wordLocale or panel.renderedReadOnly ~= readOnly
  panel.renderedQuestKey = tostring(lastQuest.id or lastQuest.title or "")
  panel.renderedText, panel.renderedPassage = lastQuest.text, lastQuest.passage
  panel.renderedWordLocale, panel.renderedReadOnly = wordLocale, readOnly
  if newQuest then
    lastHighlightWord, lastHighlightIndex, lastHighlightOccurrence = nil, nil, nil
    lastHighlightSentenceOnly, selectedHighlight = nil, nil
  end
  panel.title:SetText(lastQuest.title or "Quest")
  for _, button in ipairs(wordButtons) do button:Hide() end

  local integrated = Addon.GetIntegratedLayout and Addon.GetIntegratedLayout() and panel.enScroll and panel.enScroll:IsShown()
  local contentWidth = fitToPane(panel.scroll,
    math.max(200, (integrated and (panel:GetWidth() / 2) or panel:GetWidth()) - 48))
  panel.content:SetWidth(contentWidth)
  if panel.enContent then
    local enWidth = fitToPane(panel.enScroll,
      math.max(180, (integrated and (panel:GetWidth() / 2) or panel:GetWidth()) - 48))
    panel.enContent:SetWidth(enWidth)
    local qid = lastQuest.id
    -- Only ever a record or nil. The `and`/`or` chain this replaces fell
    -- through to `false` whenever the lookup existed and had nothing to
    -- return -- which is every quest the addon has no English for, and every
    -- gossip line, since those arrive with no id at all. `entry ~= nil` then
    -- read "found" for all of them, so hovering a word lit the placeholder
    -- sentence below up as though it were that word's translation.
    local entry
    if qid then
      if Addon.GetEnglishQuestRecord then
        entry = Addon.GetEnglishQuestRecord(qid)
      elseif WordHunterWoW_QuestEN then
        entry = WordHunterWoW_QuestEN[tonumber(qid)]
      end
    end
    if type(entry) ~= "table" then entry = nil end
    local enTitle = LABELS.englishHeader
    -- Kept as separate blocks rather than one joined string. This pane places one
    -- token at a time, so a newline inside a joined string is discarded with the
    -- rest of the whitespace and the caveat runs straight into the quest text.
    -- A caveat of its own, for the reason the other three are: it explains an
    -- absence rather than being English, so it is drawn in the muted colour and
    -- is kept out of enPlain, which is what a hover matches its sentences
    -- against.
    local enBlocks = { { text = lastQuest.referenceKind and lastQuest.referenceKind ~= "quest"
      and "English text is not available for this record." or "English text is not available for this quest.",
      caveat = true } }
    panel.enCanHighlight = entry ~= nil
    if entry then
      enTitle = entry.title or LABELS.englishHeader
      enBlocks = {}
      local hasOffer = entry.description and entry.description ~= ""
      -- The English for the passage the player is actually reading, where the
      -- record has it. Blizzard's quest API publishes neither the progress nor
      -- the hand-in line, so for a long time this pane could only show the
      -- opening text and admit it was the wrong passage.
      local passageText
      if lastQuest.passage == "progress" then
        passageText = entry.progress
      elseif lastQuest.passage == "reward" then
        passageText = entry.completion
      elseif lastQuest.passage == "sourceObjective" then
        passageText = entry.sourceObjective
      elseif lastQuest.passage == "title" then
        passageText = entry.title
      end
      if passageText and passageText ~= "" then
        enBlocks[#enBlocks + 1] = { text = passageText }
      else
        if entry.description and entry.description ~= "" then
          enBlocks[#enBlocks + 1] = { text = entry.description }
        end
        if entry.objectives and entry.objectives ~= "" then
          enBlocks[#enBlocks + 1] = { text = entry.objectives }
        end
      end
      -- The caveat goes last, under the text it is about. Above it, it was the
      -- first thing read on every quest that has one -- a red paragraph standing
      -- between the reader and what they opened the panel for. It explains an
      -- absence, and an explanation of what is missing is only worth reading
      -- after seeing what is there.
      local caveat
      if lastQuest.passage and lastQuest.passage ~= "offer" and not (passageText and passageText ~= "") then
        caveat = LABELS.enOfferOnly
      elseif not hasOffer and not (passageText and passageText ~= "") then
        -- The record itself has no opening text, which is every Classic quest.
        -- Nothing is being withheld here, so say what is actually on screen.
        caveat = LABELS.enNoOffer
      end
      -- Unless the record is a bare title, which 9,770 of the 49,041 shipped
      -- Retail records are. Then neither line above is true: there is no
      -- opening text to offer in place of the passage, and no objective to
      -- point at either, so the panel promised something and showed an empty
      -- column under it. Settled after the two branches rather than before
      -- them, because what decides it is what actually went into enBlocks, not
      -- which passage the player asked for.
      if #enBlocks == 0 then caveat = LABELS.enNoText end
      if caveat then
        enBlocks[#enBlocks + 1] = { text = caveat, caveat = true }
        panel.enCanHighlight = false
      end
    end
    panel.enTitle:SetText(enTitle)
    local enPlainParts = {}
    for _, block in ipairs(enBlocks) do
      if not block.caveat then
        local piece = tostring(block.text or "")
        if piece ~= "" then enPlainParts[#enPlainParts + 1] = piece end
      end
    end
    panel.enPlain = table.concat(enPlainParts, "\n\n")
    for _, bit in ipairs(enBits) do bit:Hide() end
    -- The English column follows the English panel's own size.
    local enScale = Addon.GetEnPanelTextScale and Addon.GetEnPanelTextScale() or 1
    local TOKEN_H, TOKEN_STEP = tokenMetrics(enScale)
    local ex, ey, eused = 0, 0, 0
    local sentenceOffset = 0
    for index, block in ipairs(enBlocks) do
      local color = rawget(panel, "whwNativeStyle") and Addon.ReaderInk(panel) or (block.caveat and COLORS.caveat or COLORS.text)
      local sentenceOfToken = {}
      if not block.caveat then
        for _, si in ipairs(Addon.TokenSentenceIndexes(block.text)) do
          sentenceOfToken[#sentenceOfToken + 1] = sentenceOffset + si
        end
        sentenceOffset = sentenceOffset + #Addon.SplitSentences(block.text)
      end
      local tokenNum = 0
      local sentenceTokenCounts = {}
      if index > 1 then
        ex = 0
        ey = ey - TOKEN_STEP * 1.6
      end
      for _, tokens in ipairs(Addon.TextLines(block.text)) do
        if ex > 0 then
          ex = 0
          ey = ey - TOKEN_STEP
        end
        -- A blank line is a paragraph break, and it is the only thing that
        -- separates a quest's story from what it is asking for.
        if #tokens == 0 then ey = ey - TOKEN_STEP * 0.6 end
        for _, token in ipairs(tokens) do
          eused = eused + 1
          tokenNum = tokenNum + 1
          local bit = enBits[eused]
          if not bit then
            bit = CreateFrame("Frame", nil, panel.enContent)
            bit.text = bit:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            bit.text:SetPoint("CENTER")
            bit.text:SetWordWrap(false)
            enBits[eused] = bit
          end
          -- The font too, for the same pooling reason: a bit built at one size would
          -- keep it forever while the row around it grew.
          tokenFont(bit.text, enScale, panel)
          -- Set on every render: these frames are pooled, so a token the caveat
          -- turned red on an earlier quest would stay red.
          bit.text:SetTextColor(color[1], color[2], color[3])
          bit.text:SetText(token)
          bit.caveat = not not block.caveat
          if bit.glow then bit.glow:Hide() end
          bit.sentenceIndex = sentenceOfToken[tokenNum]
          local si = bit.sentenceIndex
          if si then
            sentenceTokenCounts[si] = (sentenceTokenCounts[si] or 0) + 1
            bit.sentenceToken = sentenceTokenCounts[si]
          else
            bit.sentenceToken = nil
          end
          bit.topY = ey
          local width = math.min(enWidth, math.ceil(bit.text:GetStringWidth()) + 6)
          if ex > 0 and ex + width > enWidth then
            ex = 0
            ey = ey - TOKEN_STEP
            bit.topY = ey
          end
          bit:ClearAllPoints()
          bit:SetPoint("TOPLEFT", ex, ey)
          bit:SetSize(width, TOKEN_H)
          bit:Show()
          ex = ex + width + 2
        end
      end
    end
    -- Down past the bottom of the last row. The rows are TOKEN_H tall and
    -- top-anchored at ey, so the scroll child has to reach that far or the
    -- last line is cut off and cannot be scrolled to. This added a flat 28,
    -- which at 100% is the row plus a 10px pad and at 200% is 8px short of the
    -- row -- so the bottom of every quest was unreachable at exactly the sizes
    -- players raise for reading.
    panel.enContent:SetHeight(math.max(28, -ey + TOKEN_H + 10))
    panel.enScroll:UpdateScrollChildRect()
    Addon.HighlightEnglishForWord(lastHighlightWord, lastHighlightIndex, lastHighlightOccurrence, lastHighlightSentenceOnly)
  end
  -- A strip down the left of the text that words may not use.
  --
  -- Nothing in this addon wants one. It exists because the German voiceover
  -- draws a play button beside each paragraph, and until now there was nowhere
  -- to put one: this loop lays tokens from zero to the full content width, so
  -- every pixel of the column can hold a word. The buttons were hung in the
  -- margin outside the scroll frame instead, which in the two-column layout is
  -- eight pixels wide and shared with the divider -- they sat on the line.
  --
  -- Asked for rather than assumed, and by a function rather than a field, so a
  -- player without the voiceover gets the layout they have always had and the
  -- base addon needs no knowledge of what the strip is for. Reserved from the
  -- text rather than added to the window: the panel is sized to sit beside the
  -- game's own quest window and must not grow to suit an optional extra.
  local gutter = Addon.TextGutter and Addon.TextGutter() or 0
  if gutter > contentWidth / 4 then gutter = 0 end
  local x, y, used = gutter, 0, 0
  local countedWords = {}
  -- Per-quest progress, counted once per distinct word.
  local progress = { known = 0, learning = 0, new = 0 }
  -- Running gmatch("%S+") over the whole text threw away every line break
  -- in it, so the German column ran together as one block while the English
  -- one beside it kept the paragraphs the quest was written with.
  local deSentenceOfToken = Addon.TokenSentenceIndexes(lastQuest.text)
  local deTokenNum = 0
  local wordOccurrenceInSentence = {}
  local marking = Addon.GetWordMarking and Addon.GetWordMarking() or "both"
  local underlineHeight = Addon.UnderlineThickness
    and Addon.UnderlineThickness(Addon.GetTextScale and Addon.GetTextScale() or 1) or 2
  for _, tokens in ipairs(Addon.TextLines(lastQuest.text)) do
    if x > gutter then
      x = gutter
      y = y - TOKEN_STEP
    end
    if #tokens == 0 then y = y - TOKEN_STEP * 0.6 end
    for _, token in ipairs(tokens) do
      used = used + 1
      deTokenNum = deTokenNum + 1
      local button = wordButtons[used]
      if not button then
        button = CreateFrame("Button", nil, panel.content)
        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.text:SetPoint("CENTER")
        button.text:SetWordWrap(false)
        button.underline = button:CreateTexture(nil, "ARTWORK")
        button.underline:SetPoint("BOTTOMLEFT", 1, 1)
        button.underline:SetPoint("BOTTOMRIGHT", -1, 1)
        button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8", "BLEND")
        button:GetHighlightTexture():SetVertexColor(0.30, 0.42, 0.55, 0.20)
        wordButtons[used] = button
      end
      button:SetHeight(TOKEN_H)
      -- Same reason as the English column: pooled frames need the font each time.
      tokenFont(button.text, nil, panel)

      button.text:SetText(token)
      local width = math.min(contentWidth - gutter, math.ceil(button.text:GetStringWidth()) + 6)
      if x > gutter and x + width > contentWidth then
        x = gutter
        y = y - TOKEN_STEP
      end
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", x, y)
      button:SetWidth(width)
      -- Where the word sits in the flow, kept on the button: the controller
      -- moves a cursor by line and by column, and GetPoint is not modelled
      -- where this file is tested.
      button.gridX, button.gridY, button.gridW = x, y, width
      button.gridIndex = used
      x = x + width + 2

      local word = Addon.cleanWord(token)
      local key = Addon.wordKey(word)
      local entry
      if not readOnly then entry = Addon.GetEffectiveWord(key, wordLocale) end
      -- Scored once per distinct word, whether or not anything knows it yet.
      -- A word no dictionary covers is still a word in this quest the player
      -- does not know, so it belongs in the total rather than outside it.
      if word ~= "" and not countedWords[key] then
        countedWords[key] = true
        local status = entry and Addon.EffectiveStatus(entry) or "new"
        if progress[status] ~= nil then progress[status] = progress[status] + 1 end
      end
      Addon.StyleWordButton(button, entry and (entry.status or "new") or nil, marking, underlineHeight,
        rawget(panel, 'whwNativeStyle') and Addon.ReaderInk(panel) or nil)
      if not readOnly and not entry then
        -- Nothing knows this word: no dictionary entry and the player has not
        -- saved it. That is the 5% a new patch brings, and the only vocabulary
        -- the project cannot already gloss, so it is worth collecting.
        if Addon.HarvestUnknownWord and word ~= "" then
          Addon.HarvestUnknownWord(word, lastQuest.id, wordLocale)
        end
      end
      button.word = word
      button.key = key
      button.wordLocale = wordLocale
      button.sentenceIndex = deSentenceOfToken[deTokenNum]
      local occKey = tostring(button.sentenceIndex or 0) .. "\0" .. key
      wordOccurrenceInSentence[occKey] = (wordOccurrenceInSentence[occKey] or 0) + 1
      button.wordOccurrence = wordOccurrenceInSentence[occKey]
      button:SetScript("OnEnter", function(self)
        if not readOnly and self.word and self.word ~= "" then
          Addon.HighlightEnglishForWord(self.word, self.sentenceIndex, self.wordOccurrence, recallGated(self))
        end
      end)
      button:SetScript("OnLeave", function()
        local selected = selectedHighlight or {}
        Addon.HighlightEnglishForWord(selected[1], selected[2], selected[3], true)
      end)
      button:SetScript("OnClick", function(self)
        if readOnly then return end
        local gated = recallGated(self)
        selectedHighlight = { self.word, self.sentenceIndex, self.wordOccurrence, gated }
        Addon.HighlightEnglishForWord(self.word, self.sentenceIndex, self.wordOccurrence, gated)
        local deSentences = Addon.SplitSentences(lastQuest.text)
        local context = (self.sentenceIndex and deSentences[self.sentenceIndex])
          or sentenceForWord(lastQuest.text, self.word)
        Addon.lastOpened = { index = self.gridIndex, serial = panel.layoutSerial, key = self.key }
        Addon.openEditor(self.word, context, lastQuest.id, lastQuest.title, { origin = "panel", locale = wordLocale })
      end)
      button:SetEnabled(not readOnly and word ~= "")
      button:Show()
    end
  end
  -- Same as the English column above: the scroll child reaches the bottom of
  -- the last row plus the 10px pad the flat 28 stood for at 100%, and scales
  -- with the text instead of being cut off by it.
  local contentHeight = math.max(28, -y + TOKEN_H + 10)
  panel.content:SetHeight(contentHeight)
  panel.scroll:UpdateScrollChildRect()
  panel.meta:SetText(readOnly and "English database text – read only" or Addon.FormatProgress(progress, Addon.UsesLightSurface(panel)))
  for _, item in ipairs(panel.legend) do
    if readOnly then item.dot:Hide() item.text:Hide() else item.dot:Show() item.text:Show() end
  end
  -- The panel grows to fit the quest unless the player has sized it themselves.
  -- This used to look under the bare key "panel", but sizes are saved per
  -- layout context, so the lookup never found anything and the height was reset
  -- on every refresh -- including the one that lands a moment after a drag
  -- ends, which is the window jumping just after you let go of the corner.
  local frames = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.frames
  local saved = frames and frames[Addon.LayoutKey("panel")]
  if not (saved and saved.userSized) then
    -- The room the text needs plus the room the furniture takes, asked for
    -- rather than assumed. This was a flat 136 -- one figure for two
    -- arrangements that have never been the same height, and wrong for both the
    -- moment the text size could move it. The floor and the ceiling are screen
    -- sizes and stay where they are, except that the floor gives way once the
    -- furniture alone wants more than it.
    local chromeHeight = panel.chromeHeight or 136
    panel:SetHeight(math.min(560,
      math.max(230, chromeHeight + TOKEN_STEP * 3, contentHeight + chromeHeight)))
  end
  -- Both panes start at the top on a new quest. Leaving the scroll where it was
  -- opened the next quest part-way down its text. The old rule only reset the
  -- German pane, and only below a raw 410px, which stopped applying once the
  -- text size could be raised.
  if newQuest then
    panel.scroll:SetVerticalScroll(0)
    if panel.enScroll then panel.enScroll:SetVerticalScroll(0) end
  end
  -- The buttons in reading order and how many of them this layout used, for
  -- the controller (Gamepad.lua), which walks them. The serial says which
  -- layout they belong to: the pool is reused, so an index remembered across a
  -- re-flow would name whatever word landed there.
  panel.wordButtons, panel.wordCount = wordButtons, used
  panel.layoutSerial = (type(panel.layoutSerial) == "number" and panel.layoutSerial or 0) + 1
  -- The editor's Previous and Next read this pool; a new layout is a new answer.
  if Addon.RefreshWordArrows then Addon.RefreshWordArrows() end
  -- Anything that draws on top of the laid-out text gets its turn here, once the
  -- tokens are where they are going to be. The German voiceover uses it to put a
  -- play button beside each paragraph it has a recording for; nothing else
  -- listens, and when nothing listens this costs a comparison.
  --
  -- A callback rather than a hook on Addon.refreshPanel, because this file calls
  -- its own local copy -- so a wrapper on the public name would miss every
  -- refresh that actually matters.
  if Addon.OnQuestPanelRendered then
    Addon.OnQuestPanelRendered(lastQuest, panel)
  end
end
Addon.refreshPanel = refreshPanel

local function trackQuestEncounters(quest)
  local now = time()
  local seen = {}
  local changed = false
  for token in tostring(quest.text or ""):gmatch("%S+") do
    local key = Addon.wordKey(token)
    local item = Addon.GetWordsTable()[key]
    if item and not seen[key] then
      seen[key] = true
      -- Only when the encounter was actually new. Before, any saved word merely
      -- appearing in the quest rebuilt the whole export -- and that means every
      -- click in the quest log sorted the entire word table and ran five gsubs
      -- per word. With a few thousand words saved, that is what quest browsing
      -- costs.
      if Addon.recordEncounter(item, quest.id, quest.title, now) then
        changed = true
      end
    end
  end
  if changed then Addon.rebuildExport() end
end

-- Whether looking at a quest in the quest log puts this panel on screen by
-- itself.
--
-- Off, and off is the new behaviour. On a live realm the quest log is a pane of
-- the world map, and this window is FULLSCREEN_DIALOG at frame level 20 with
-- SetToplevel -- so a click meant to read a quest's objectives, or to abandon
-- it, dropped the panel over the very row it was aimed at, and the quest could
-- not be reached again without closing the panel first. A quest giver's window
-- is the opposite case and is left exactly as it was: its text is the whole
-- reason that window opened.
--
-- A setting rather than a plain change, because someone working through their
-- log to study the vocabulary wants precisely the old behaviour. Nothing seeds
-- this key, so every profile -- not just a fresh one -- reads nil here and gets
-- the new rule, which is the point: the fault was on all of them.
function Addon.GetQuestLogAutoOpen()
  local v = WordHunterWoWDB and WordHunterWoWDB.settings and WordHunterWoWDB.settings.questLogAutoOpen
  if v == nil then return false end
  return v and true or false
end

function Addon.SetQuestLogAutoOpen(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.questLogAutoOpen = not not value
  if Addon.RefreshSettingsWindow then Addon.RefreshSettingsWindow() end
end

function Addon.GetQuestVoiceAutoPlay()
  local settings = WordHunterWoWDB and WordHunterWoWDB.settings
  return settings and settings.questVoiceAutoPlay == true or false
end

function Addon.GetNpcReaderAutoOpen()
  local settings = WordHunterWoWDB and WordHunterWoWDB.settings
  return settings and settings.npcReaderAutoOpen == true or false
end

function Addon.SetNpcReaderAutoOpen(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.npcReaderAutoOpen = not not value
  if Addon.RefreshSettingsWindow then Addon.RefreshSettingsWindow() end
end

function Addon.SetQuestVoiceAutoPlay(value)
  if type(WordHunterWoWDB) ~= "table" then WordHunterWoWDB = {} end
  if type(WordHunterWoWDB.settings) ~= "table" then WordHunterWoWDB.settings = {} end
  WordHunterWoWDB.settings.questVoiceAutoPlay = not not value
  if Addon.RefreshSettingsWindow then Addon.RefreshSettingsWindow() end
end

-- `requested` is the player having pressed the quest log's own button. It is
-- the only thing that opens the panel from the log while the setting above is
-- off, and it is deliberately not inferred from anything: a rule that guessed
-- at intent is what put the panel in the way in the first place.
local function readCurrentQuest(questLogId, requested)
  local questId = GetQuestID and GetQuestID() or 0
  local title = GetTitleText and GetTitleText() or ""
  local description = GetQuestText and GetQuestText() or ""
  local objectives = GetObjectiveText and GetObjectiveText() or ""
  local Compat = Addon.Compat
  local nativeNPC = true
  if questLogId and questLogId > 0 then
    nativeNPC = false
    questId = questLogId
    description, objectives = Compat.QuestLogText(Compat.QuestLogIndexForID(questId))
    title = Compat.TitleForQuestID(questId) or title
  -- QuestInfoFrame is Retail's; Classic shows the same thing in its own quest
  -- log window. The Classic arm is guarded by flavour rather than folded in, so
  -- that opening the world map on Retail keeps behaving exactly as it did.
  elseif not Compat.NpcQuestFrameShown() and ((QuestInfoFrame and QuestInfoFrame.questLog)
      or (Compat.IsClassic() and Compat.QuestLogShown())) then
    nativeNPC = false
    questId = Compat.SelectedQuestID() or questId
    description, objectives = Compat.QuestLogText(Compat.QuestLogIndexForID(questId))
    title = Compat.TitleForQuestID(questId) or title
  end
  local function normalizeQuestText(t)
    t = tostring(t or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    t = t:gsub(">[ \t]*\n[ \t]*(%S)", ">\n\n%1")
    return t
  end
  local desc = normalizeQuestText(description)
  local obj = normalizeQuestText(objectives)
  local offer = Addon.trim(desc .. (desc ~= "" and obj ~= "" and "\n\n" or "") .. obj)
  offer = offer:gsub("\n\n\n+", "\n\n")
  local progressText = Addon.trim(normalizeQuestText(GetProgressText and GetProgressText() or ""))
  local rewardText = Addon.trim(normalizeQuestText(GetRewardText and GetRewardText() or ""))
  -- Events set lastPassage. Anything that skipped them infers from which
  -- Blizzard function answered, the way this used to work -- and only when
  -- there is nothing to go on, which is what "the fallback" has always meant.
  local passage = Addon.lastPassage
  -- Reading out of the log, and the log holds nothing but the opening text:
  -- Blizzard's progress and hand-in lines exist only while an NPC is saying
  -- them. Without this the read inherited whichever passage the last
  -- conversation left behind, and GOSSIP_CLOSED never clears one -- browse the
  -- log after a chat and every quest came up labelled gossip, which raised the
  -- "no English for this part of a quest" caveat over text that was the opening
  -- text all along, and switched highlighting off with it.
  --
  -- Both ways into the log, not only the one that names an id in its argument:
  -- the other arrives through QuestInfoFrame.questLog or the Classic log window
  -- with no id at all, and it is a read of the same log holding the same one
  -- passage.
  if not nativeNPC then passage = "offer" end
  if passage == nil then
    if offer == "" and progressText ~= "" then
      passage = "progress"
    elseif offer == "" and rewardText ~= "" then
      passage = "reward"
    else
      passage = "offer"
    end
  end
  -- The live client still returns the offer during progress and hand-in, so
  -- using "whichever function is non-empty" kept showing the opening paragraph
  -- while the NPC was saying something else. Trust the passage, fall back to
  -- the offer only when that line is missing.
  local text = offer
  if passage == "progress" and progressText ~= "" then
    text = progressText
  elseif passage == "reward" and rewardText ~= "" then
    text = rewardText
  end
  if text == "" then return end
  -- Legacy log helpers may answer the currently selected quest when selection
  -- fails. Only this raw NPC path has verified ID/text provenance here; the
  -- library's separately guarded liveRecord archives safe log observations.
  local observation = { title = title }
  -- Getters can retain another passage's text. Both archives receive only the
  -- selected line, never an offscreen offer, progress or hand-in value.
  if passage == "offer" then observation.description, observation.objectives = desc, obj end
  if passage == "progress" and progressText ~= "" then observation.progress = progressText end
  if passage == "reward" and rewardText ~= "" then observation.completion = rewardText end
  if nativeNPC and Addon.ArchiveNativeQuest then
    Addon.ArchiveNativeQuest(questId, observation, Addon.TextLocale())
  end
  -- Objectives, progress and hand-in text exist only here, never in the quest
  -- API the dictionaries were built from. Record them when the player opts in.
  if Addon.HarvestQuest then
    Addon.HarvestQuest(questId, {
      title = observation.title,
      description = observation.description,
      objectives = observation.objectives,
      progress = observation.progress,
      reward = observation.completion,
    }, Addon.TextLocale(), nativeNPC and passage or nil)
  end
  Addon.lastQuest = { id = questId or 0, title = Addon.trim(title), text = text, passage = passage }
  trackQuestEncounters(Addon.lastQuest)
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  -- Only put the panel on screen while a quest window is actually open.
  -- Blizzard redraws the quest pane while it is tearing it down, and the hook
  -- that redraw fires reaches us through a timer -- after QUEST_FINISHED has
  -- already closed us. Showing then reopened the panel on the quest the player
  -- had just handed in, a moment after they had closed it.
  --
  -- This only ever declines to open the panel; it never closes one. A panel the
  -- player opened by hand stays where it is and keeps being refreshed above.
  --
  -- NPC conversations and the quest log have separate opt-in auto-open settings.
  --
  -- The test is which window the text came from and never which of Blizzard's
  -- functions fired. Showing the map's quest details runs
  -- QuestInfo_ShowDescriptionText as well as QuestMapFrame_ShowQuestDetails, so
  -- a rule written against hook names would have left that second route open
  -- and the panel would have landed on the log through it regardless.
  local Compat = Addon.Compat
  local atQuestGiver = not Compat or Compat.NpcQuestFrameShown()
  if requested or (atQuestGiver and Addon.GetNpcReaderAutoOpen())
      or (not atQuestGiver and Compat and Compat.QuestLogShown() and Addon.GetQuestLogAutoOpen()) then
    panel:Show()
  end
  -- Laid out after the decision to show, never before it. refreshPanel declines
  -- to work on a hidden window -- that is what keeps a closed panel from being
  -- rebuilt on every save -- so rendering first would have drawn this quest into
  -- a window that was still hidden, and left the old one on screen.
  refreshPanel()
end
Addon.readCurrentQuest = readCurrentQuest

-- A readable item: a journal, a letter, a page in a book ----------------------
--
-- Blizzard draws these in its own frame, and this addon still does not draw
-- into it -- the same bargain as the quest log and the gossip window. The page
-- is read through the client's own API and the words come up in the panel,
-- clickable exactly as the words of an NPC's conversation are. Until now a book
-- was the one passage of the language being learned with no way in at all: the
-- player could open Kearnen's Journal and not click a word of it, while the
-- same sentence spoken by an NPC was word for word clickable.
--
-- Named rather than referenced because one frame or the other is nil depending
-- on the client, and nothing in this file indexes a Blizzard global without
-- asking first. ItemTextFrame is the readable-item window -- a scroll of text
-- with page buttons, which is what a journal or a letter opens -- and BookFrame
-- is the two-page book that keeps one page in each of two regions.
local BOOK_WINDOWS = { "ItemTextFrame", "BookFrame" }

-- The buttons that move a book along. A page turn is the only thing that
-- changes a book's text without closing and reopening the window, so it is the
-- one thing the panel has to follow by itself.
local BOOK_PAGE_BUTTONS = {
  "ItemTextPrevPageButton", "ItemTextNextPageButton",
  "BookFramePrevPageButton", "BookFrameNextPageButton",
}

-- A Blizzard global that is a frame, or nil.
local function bookWindow(name)
  local frame = rawget(_G, name)
  if type(frame) == "table" and type(frame.IsShown) == "function" then return frame end
  return nil
end

-- A named region's text, or nil. GetText is probed rather than assumed, and
-- "" is answered as no text rather than as an empty page: a frame the client
-- has not filled in yet must not push a blank page into the panel over the
-- words the player is actually looking at.
local function bookRegionText(frame, name)
  if not frame then return nil end
  local region = rawget(frame, name)
  if type(region) ~= "table" or type(region.GetText) ~= "function" then return nil end
  local ok, text = pcall(region.GetText, region)
  if ok and type(text) == "string" and text ~= "" then return text end
  return nil
end

-- The page as the game has it: its text, and the title to read it under.
--
-- The item-text API is asked first, because it is the page the client has
-- loaded rather than a font string's rendering of it. The regions under it are
-- the answer for the two-page book, which has no API of its own, and the
-- fallback for a client whose API is not there at all.
function Addon.BookText()
  local item, book = bookWindow("ItemTextFrame"), bookWindow("BookFrame")
  -- Which window the text came from decides what it is called. Asked the other
  -- way round -- the item API's name first, whatever the text -- a two-page book
  -- came up titled after whatever readable item the player had last opened.
  local text, source
  if type(ItemTextGetText) == "function" then
    local ok, value = pcall(ItemTextGetText)
    if ok and type(value) == "string" and value ~= "" then text, source = value, "item" end
  end
  if not text then
    text = bookRegionText(item, "ItemTextItemText")
    if text then source = "item" end
  end
  if not text then
    -- One page per region, joined by a blank line -- which is the paragraph
    -- break this panel already reads, so a page turn in the middle of a
    -- paragraph does not run the two halves together.
    local first = bookRegionText(book, "BookPage1")
    local second = bookRegionText(book, "BookPage2")
    if first or second then
      text = (first or "") .. (first and second and "\n\n" or "") .. (second or "")
      source = "book"
    end
  end
  if not text or text == "" then return nil end

  -- The book's own name, which is what its title bar shows and what the player
  -- would call it.
  local title
  if source == "item" then
    if type(ItemTextGetItem) == "function" then
      local ok, name = pcall(ItemTextGetItem)
      if ok and type(name) == "string" and name ~= "" then title = name end
    end
    title = title or bookRegionText(item, "ItemTextTitleText")
  else
    title = bookRegionText(book, "BookTitle")
  end
  return text, title
end

-- What GOSSIP_SHOW does for a conversation, this does for a page: read it and
-- put it in front of the player. A book is not an NPC and has no quest id, so
-- there is nothing to archive and nothing to count -- the words are what the
-- player came for, and they are the same words the panel already knows how to
-- draw, mark and open an editor on.
function Addon.readBook(requested)
  local text, title = Addon.BookText()
  text = Addon.trim(tostring(text or ""))
  if text == "" then return end
  Addon.lastPassage = "book"
  Addon.lastQuest = { id = 0, title = Addon.trim(title or "Book"), text = text, passage = "book" }
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  if not panel then return end
  -- The same switch the NPC conversation uses, for the same reason: reading a
  -- book is being spoken at, and a player who does not want the panel opening
  -- itself while they are talked to does not want it opening itself while they
  -- read either.
  if requested or Addon.GetNpcReaderAutoOpen() then panel:Show() end
  refreshPanel()
end

function Addon.readGossip(requested)
  local text = C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText()
  if (not text or text == "") and GetGossipText then text = GetGossipText() end
  text = Addon.trim(tostring(text or ""))
  if text == "" then return end
  local title = (UnitName and (UnitName("npc") or UnitName("questnpc"))) or "Gossip"
  Addon.lastPassage = "gossip"
  Addon.lastQuest = { id = 0, title = Addon.trim(title), text = text, passage = "gossip" }
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  if not panel then return end
  if requested or Addon.GetNpcReaderAutoOpen() then panel:Show() end
  refreshPanel()
end

-- The quest log's own way in -------------------------------------------------

local logButton
local questsLogButton
local questsLogRoot

-- A Blizzard global can be absent on one game and be something other than a
-- frame on the other, so nothing below indexes one without asking first. Same
-- shape as Compat's own `shown`, for the same reason.
local function usableFrame(frame)
  if type(frame) == "table" and type(frame.IsShown) == "function" then return frame end
  return nil
end

-- Retail/Forever can load the quest list before its details pane.
local function questLogHost()
  local Compat = Addon.Compat
  if not Compat or Compat.IsRetail() or Compat.IsForever() then
    if type(QuestMapFrame) ~= "table" then return nil end
    return usableFrame(rawget(QuestMapFrame, "DetailsFrame"))
      or usableFrame(rawget(QuestMapFrame, "QuestsFrame"))
  end
  return usableFrame(QuestLogFrame)
end
Addon.QuestLogButtonHost = questLogHost

-- Pressing it. A toggle rather than open-only: what put this button here was a
-- panel standing in front of the quest log, so the same press has to be able to
-- send it away again. Picking a quest in the log already refreshes an open
-- panel, so an open panel is always showing the quest this button would have
-- opened -- which is what makes one press meaning "close" unambiguous rather
-- than a guess about which quest was meant.
function Addon.ToggleQuestFromLog()
  if not panel then return end
  if panel:IsShown() then
    panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
    return
  end
  local Compat = Addon.Compat
  local questId = QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
  if (not questId or questId == 0) and Compat then questId = Compat.SelectedQuestID() end
  -- The id is what tells readCurrentQuest to take the text out of the log
  -- rather than out of whatever an NPC last said, so it is worth the two calls
  -- to find one. Without it the button would open the panel on stale text.
  if questId and questId > 0 then
    readCurrentQuest(questId, true)
  else
    print("|cff66ccffWordHunterWoW:|r Select a quest in the quest log to open Reader.")
  end
end

local sideTabStrata = { BACKGROUND=1, LOW=2, MEDIUM=3, HIGH=4, DIALOG=5,
  FULLSCREEN=6, FULLSCREEN_DIALOG=7, TOOLTIP=8 }
local function syncSideTabLayer(button, elapsed)
  if elapsed then
    button.wordHunterLayerElapsed = (rawget(button, 'wordHunterLayerElapsed') or 0) + elapsed
    if button.wordHunterLayerElapsed < .1 then return end
    button.wordHunterLayerElapsed = 0
  end
  local host = rawget(button, "wordHunterLayerHost")
  if not host then return end
  local strata, level = host:GetFrameStrata(), host:GetFrameLevel()
  if Addon.IsSecretValue and (Addon.IsSecretValue(strata) or Addon.IsSecretValue(level)) then return end
  local function include(frame)
    local other, otherLevel = frame:GetFrameStrata(), frame:GetFrameLevel()
    -- Retail 12.1.7 can hide strata; retain the last readable layer instead.
    if not Addon.IsSecretValue or not (Addon.IsSecretValue(other) or Addon.IsSecretValue(otherLevel)) then
      if (sideTabStrata[other] or 0) > (sideTabStrata[strata] or 0) then
        strata, level = other, otherLevel
      elseif other == strata then
        level = math.max(level, otherLevel)
      end
    end
    if type(frame.GetChildren) == "function" then
      for _, child in ipairs({ frame:GetChildren() }) do
        if child:IsShown() then include(child) end
      end
    end
  end
  -- Window artwork may live on children with their own strata and levels.
  include(host)
  -- Spoken docks these to UIParent in Forever's gamepad mode, outside the map tree.
  if host == WorldMapFrame then
    for _, name in ipairs({ "SpokenZonesPanel", "SpokenZonesPanelToggle" }) do
      local dock = usableFrame(_G[name])
      if dock and dock:IsShown() then include(dock) end
    end
  end
  local content = rawget(button, "wordHunterLayerContent")
  if content then include(content) end

  level = level + 1
  local ownStrata, ownLevel = button:GetFrameStrata(), button:GetFrameLevel()
  if (Addon.IsSecretValue and Addon.IsSecretValue(ownStrata)) or ownStrata ~= strata then button:SetFrameStrata(strata) end
  if (Addon.IsSecretValue and Addon.IsSecretValue(ownLevel)) or ownLevel ~= level then button:SetFrameLevel(level) end
end

local function followSideTabHost(button, host, content)
  button.wordHunterLayerHost = host
  button.wordHunterLayerContent = content
  button:SetScript("OnUpdate", syncSideTabLayer)
  syncSideTabLayer(button)
end

local function createQuestSideTab(icon, toggle, parent)
  local b
  parent = parent or UIParent
  Addon.sideTabSerial = (Addon.sideTabSerial or 0) + 1
  local name = "WordHunterWoWSideTab" .. Addon.sideTabSerial
  if type(SidePanelTabButtonMixin) == "table" then
    b = CreateFrame("Frame", name, parent, "LargeSideTabButtonTemplate")
    b.Icon:SetTexture(icon)
    if type(b.SetFillToInterior) == "function" then
      b:SetFillToInterior(true, 24)
    else
      b.Icon:SetTexCoord(0.03125, 0.96875, 0.03125, 0.96875)
      b.Icon:SetSize(24, 24)
    end
    -- Retail's native SetChecked requires atlases; this tab keeps its file texture.
    function b:SetChecked(checked)
      self.SelectedTexture:SetShown(checked)
    end
    b:EnableMouse(true)
    b:SetCustomOnMouseUpHandler(function(_, button, upInside)
      if button == "LeftButton" and upInside then toggle() end
    end)
  else
    b = CreateFrame("CheckButton", name, parent, "SpellBookSkillLineTabTemplate")
    b:SetSize(32, 32)
    b:SetNormalTexture(icon)
    local texture = b:GetNormalTexture()
    texture:ClearAllPoints()
    texture:SetPoint("CENTER")
    texture:SetSize(24, 24)
    b:SetScript("OnClick", toggle)
  end
  -- ConsolePort registers the host as pass-through and navigates its children.
  local target = CreateFrame("Button", name .. "ClickTarget", b)
  b.wordHunterClickTarget = target
  target:SetAllPoints(b)
  target:SetScript("OnClick", toggle)
  for _, event in ipairs({ "OnEnter", "OnLeave" }) do
    target:SetScript(event, function()
      local handler = b:GetScript(event)
      if handler then handler(b) end
    end)
  end
  if parent == UIParent then b:Hide() end
  if Addon.AttachGamePad then Addon.AttachGamePad(b) end
  return b
end
Addon.CreateBookSideTab = createQuestSideTab

local function frameVisible(frame)
  if not frame then return false end
  if type(frame.IsVisible) == "function" then return frame:IsVisible() end
  return frame:IsShown()
end

local npcReaderButton
local npcReaderHosts = {}

local function npcReaderHost()
  if frameVisible(usableFrame(QuestFrame)) then return QuestFrame end
  if frameVisible(usableFrame(GossipFrame)) then return GossipFrame end
  -- A book is spoken at the player in the same sense an NPC is, and gets the
  -- same Reader tab on the window it is read in.
  for _, name in ipairs(BOOK_WINDOWS) do
    local frame = bookWindow(name)
    if frame and frameVisible(frame) then return frame end
  end
end

function Addon.ToggleReaderFromNpc()
  if not panel or not npcReaderHost() then return end
  if panel:IsShown() then
    panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
    return
  end
  -- Which window the words are in decides which reader reads them. One button
  -- serves all of them, so it has to open the one the player is looking at --
  -- a book read through the gossip reader would come up on the last NPC.
  local book = bookWindow("ItemTextFrame") or bookWindow("BookFrame")
  if book and frameVisible(book) then
    Addon.readBook(true)
  elseif frameVisible(usableFrame(QuestFrame)) then
    readCurrentQuest(nil, true)
  else
    Addon.readGossip(true)
  end
end

function Addon.RefreshNpcReaderButton()
  if not npcReaderButton then return end
  local host = npcReaderHost()
  if not host then npcReaderButton:Hide(); return end
  followSideTabHost(npcReaderButton, host)
  npcReaderButton:ClearAllPoints()
  npcReaderButton:SetPoint("TOPLEFT", host, "TOPRIGHT", 2, -110)
  npcReaderButton:SetScale(host:GetEffectiveScale() / UIParent:GetEffectiveScale())
  npcReaderButton:SetChecked(panel and panel:IsShown() or false)
  npcReaderButton:Show()
end

function Addon.ToggleReader()
  if npcReaderHost() then Addon.ToggleReaderFromNpc() else Addon.ToggleQuestFromLog() end
end

function Addon.AttachNpcReaderButton()
  for _, name in ipairs({ "QuestFrame", "GossipFrame" }) do
    local host = usableFrame(_G[name])
    if host and not npcReaderHosts[host] then
      npcReaderHosts[host] = true
      host:HookScript("OnShow", Addon.RefreshNpcReaderButton)
      host:HookScript("OnHide", Addon.RefreshNpcReaderButton)
    end
  end
  -- The book frames too. The tab follows the window it is hung on, so it has
  -- to be told when one of these appears or goes away just as the NPC windows
  -- are.
  for _, name in ipairs(BOOK_WINDOWS) do
    local host = bookWindow(name)
    if host and not npcReaderHosts[host] then
      npcReaderHosts[host] = true
      host:HookScript("OnShow", Addon.RefreshNpcReaderButton)
      host:HookScript("OnHide", Addon.RefreshNpcReaderButton)
    end
  end
  if not npcReaderButton and next(npcReaderHosts) then
    npcReaderButton = createQuestSideTab("Interface\\Icons\\INV_Misc_Book_11", Addon.ToggleReaderFromNpc)
    Addon.npcReaderButton = npcReaderButton
    npcReaderButton:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(LABELS.questLogButton)
      GameTooltip:AddLine(LABELS.questLogButtonTip, 0.8, 0.82, 0.88, true)
      GameTooltip:Show()
    end)
    npcReaderButton:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if Addon.SideTabShortcut then Addon.SideTabShortcut(npcReaderButton, "READER", "PAD3") end
  end
  Addon.RefreshNpcReaderButton()
  return npcReaderButton
end

function Addon.RefreshQuestLogButton()
  Addon.RefreshNpcReaderButton()
  if not logButton then return end
  if not questsLogButton or not questsLogRoot then logButton:Hide(); return end
  followSideTabHost(logButton, questsLogRoot, rawget(questsLogButton, "wordHunterLayerContent"))
  logButton:ClearAllPoints()
  logButton:SetPoint("TOPLEFT", questsLogButton, "BOTTOMLEFT", 0, -8)
  logButton:SetScale(questsLogButton:GetScale())
  logButton:SetChecked(panel and panel:IsShown() or false)
  if (frameVisible(questLogHost()) or frameVisible(Addon.QuestsLogButtonHost()))
      and frameVisible(questsLogRoot) then
    logButton:Show()
  else
    logButton:Hide()
  end
end

function Addon.AttachQuestLogButton()
  if logButton then return logButton end
  local host = questLogHost()
  if not host then return nil end
  local button = createQuestSideTab("Interface\\Icons\\INV_Misc_Book_11", Addon.ToggleQuestFromLog)
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(LABELS.questLogButton)
    GameTooltip:AddLine(LABELS.questLogButtonTip, 0.8, 0.82, 0.88, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  logButton = button
  if Addon.SideTabShortcut then Addon.SideTabShortcut(button, "READER", "PAD3") end
  Addon.questLogButton = button
  host:HookScript("OnShow", Addon.RefreshQuestLogButton)
  host:HookScript("OnHide", Addon.RefreshQuestLogButton)
  Addon.RefreshQuestLogButton()
  return button
end

-- The library follows the quest list, even when no quest is selected.
-- Probe frames because Forever shares the map UI while using a Classic flavor.
local function questsLogHost()
  if type(QuestMapFrame) == "table" then
    local list = rawget(QuestMapFrame, "QuestsFrame")
    local ok = usableFrame(list)
    if ok then return ok end
  end
  return usableFrame(QuestLogFrame)
end
Addon.QuestsLogButtonHost = questsLogHost

-- A side tab outside the outer window. Parenting it to UIParent keeps the
-- quest list's clipped children and border from cutting off the tab's art.
function Addon.RefreshQuestsLogButton()
  local b = questsLogButton
  if not b then return end
  local host = questsLogHost()
  local anchor
  if type(QuestMapFrame) == "table" and host == rawget(QuestMapFrame, "QuestsFrame") then
    for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
      local tab = usableFrame(rawget(QuestMapFrame, key))
      if tab and (not anchor or tab:IsShown()) then anchor = tab end
    end
  end
  followSideTabHost(b, questsLogRoot, anchor or host)
  b:ClearAllPoints()
  if anchor then
    -- Reserve a neighbour at -3, its 32px height, and an 8px gap (Lorever).
    b:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -43)
  else
    b:SetPoint("TOPLEFT", questsLogRoot, "TOPRIGHT", 2, -96)
  end
  if UIParent and type(UIParent.GetEffectiveScale) == "function"
      and type(questsLogRoot.GetEffectiveScale) == "function" then
    b:SetScale(questsLogRoot:GetEffectiveScale() / UIParent:GetEffectiveScale())
  end
  b:SetChecked(Addon.questsFrame and Addon.questsFrame:IsShown() or false)
  if (frameVisible(host) or frameVisible(questLogHost())) and frameVisible(questsLogRoot) then
    b:Show()
  else
    b:Hide()
  end
  Addon.RefreshQuestLogButton()
end

function Addon.AttachQuestsLogButton()
  if questsLogButton then return questsLogButton end
  local host = questsLogHost()
  if not host then return nil end
  local map = type(QuestMapFrame) == "table" and host == rawget(QuestMapFrame, "QuestsFrame")
  questsLogRoot = map and (usableFrame(WorldMapFrame) or usableFrame(QuestMapFrame)) or host
  local function toggle()
    if Addon.toggleQuestBrowser then Addon.toggleQuestBrowser() end
  end
  local b = createQuestSideTab("Interface\\Icons\\INV_Misc_Book_09", toggle)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("WordHunterWoW - " .. (LABELS.questsTitle or "QUESTS"))
    GameTooltip:AddLine(LABELS.questsLogTip or "Open the quest browser.", 0.8, 0.82, 0.88, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  questsLogButton = b
  if Addon.SideTabShortcut then Addon.SideTabShortcut(b, "QUESTS", "PAD4") end
  Addon.questsLogButton = b
  local watched = {}
  local function watch(frame)
    if not frame or watched[frame] then return end
    watched[frame] = true
    frame:HookScript("OnShow", Addon.RefreshQuestsLogButton)
    frame:HookScript("OnHide", Addon.RefreshQuestsLogButton)
  end
  watch(host)
  watch(questLogHost())
  watch(questsLogRoot)
  if map then
    watch(QuestMapFrame)
    for _, key in ipairs({ "QuestsTab", "EventsTab", "MapLegendTab" }) do
      watch(usableFrame(rawget(QuestMapFrame, key)))
    end
  end
  Addon.RefreshQuestsLogButton()
  return b
end

-- Which of Blizzard's functions fired only matters for working out which quest
-- the player is looking at; the reading itself is the same on every game.
function Addon.hookQuestUi()
  local Compat = Addon.Compat
  Addon.AttachNpcReaderButton()
  Addon.AttachQuestLogButton()
  if Addon.AttachQuestsLogButton then Addon.AttachQuestsLogButton() end
  return Compat.HookQuestUi(function(name)
    C_Timer.After(0, function()
      -- Belt and braces for a log that arrived by some route ADDON_LOADED did
      -- not name: by the time one of the log's own functions has run, its
      -- frames certainly exist, so nothing can be too early here.
      Addon.AttachQuestLogButton()
      if Addon.AttachQuestsLogButton then
        Addon.AttachQuestsLogButton()
        Addon.RefreshQuestsLogButton()
      end
      if name == "QuestMapFrame_ShowQuestDetails" then
        local questId = QuestMapFrame_GetDetailQuestID and QuestMapFrame_GetDetailQuestID()
        if not questId or questId == 0 then questId = Compat.SelectedQuestID() end
        if questId and questId > 0 then readCurrentQuest(questId) end
      elseif name == "QuestLog_SetSelection" or name == "QuestLog_UpdateQuestDetails" then
        local questId = Compat.SelectedQuestID()
        if questId and questId > 0 then readCurrentQuest(questId) else readCurrentQuest() end
      else
        readCurrentQuest()
      end
    end)
  end)
end

-- The book frames and what moves them along, hooked once for the session.
--
-- OnShow rather than the event alone, and the event rather than OnShow alone:
-- a book the player reopens shows its frame before the client has the page in
-- it, and a client whose item-text event this build does not know still has a
-- window that shows. Both, so neither is the only thing standing between the
-- player and the words. Page buttons come last, because turning a page is the
-- one thing that changes a book's text in place -- and the panel reading the
-- page the player started on for the rest of the book is exactly the fault
-- this whole section exists to avoid.
-- One hook per frame and per button, tracked on the object rather than in a
-- flag over the whole section: a client can build these windows after this is
-- first called, and the next call has to reach them. Calling it again is how
-- hookQuestUi already works.
function Addon.hookBookUi()
  for _, name in ipairs(BOOK_WINDOWS) do
    local frame = bookWindow(name)
    if frame and not rawget(frame, "whwBookHook") then
      frame.whwBookHook = true
      frame:HookScript("OnShow", function() Addon.readBook() end)
      frame:HookScript("OnHide", function()
        -- The bargain GOSSIP_CLOSED keeps: a panel showing this book goes away
        -- with it, and one the player opened on something else is left alone.
        if Addon.lastQuest and Addon.lastQuest.passage == "book" then
          if panel then panel:Hide() end
          if Addon.editor then Addon.editor:Hide() end
        end
      end)
    end
  end
  for _, buttonName in ipairs(BOOK_PAGE_BUTTONS) do
    local button = bookWindow(buttonName)
    if button and not rawget(button, "whwBookHook") then
      button.whwBookHook = true
      button:HookScript("OnClick", function() Addon.readBook() end)
    end
  end
  Addon.AttachNpcReaderButton()
  return true
end

function Addon.createPanel()
  -- Built once. Nothing in the game calls this twice -- ADDON_LOADED fires once
  -- per addon and Init.lua's branch is guarded by the addon's own name -- but a
  -- second call would silently abandon the frame the player is looking at,
  -- along with the position they dragged it to, and hand back a fresh one. That
  -- has already cost time inside the test suite, where calling it again to get
  -- at the frame reset state the rest of the file depended on.
  --
  -- Checked against the public handle rather than the upvalue, so a test that
  -- clears Addon.panel to start over still gets a new one.
  if Addon.panel then return Addon.panel end
  panel = Addon.CreateNativeWindow("WordHunterWoWFrame", "reader", "WordHunterWoW")
  Addon.panel = panel
  panel:SetFrameStrata("FULLSCREEN_DIALOG")
  panel:SetFrameLevel(20)
  panel:SetToplevel(true)
  panel:SetClampedToScreen(true)
  panel:SetMovable(true)
  panel:EnableMouse(true)
  panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving)
  panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    Addon.SaveFramePosition(self, Addon.LayoutKey("panel"))
  end)
  Addon.setBackdrop(panel)
  Addon.SetupEscapeClose(panel)
  -- The dimmer follows the panel rather than the setting, so it is hung on the
  -- frame's own events. Five places call Show or Hide on this panel and a sixth
  -- will be added the week after anybody patches them one at a time; hooked
  -- once here, every path is covered including the ones not written yet.
  panel:HookScript("OnShow", function()
    if Addon.ApplyReadingDim then Addon.ApplyReadingDim() end
    Addon.RefreshQuestLogButton()
  end)
  panel:HookScript("OnHide", function()
    if Addon.ApplyReadingDim then Addon.ApplyReadingDim() end
    Addon.RefreshQuestLogButton()
  end)
  local panelDef = Addon.LAYOUT_DEFAULTS.npc.panel
  panel:SetSize(panelDef.w, panelDef.h)
  panel:SetPoint("CENTER", UIParent, "CENTER", -200, 0)
  Addon.PlaceFrame(panel, "panel")
  Addon.MakeResizable(panel, "panel", 400, 230, 1200, 800)
  -- Debounced, the way the word list already does it. Relaying the text out
  -- means measuring and repositioning every word on screen, and undebounced that
  -- ran on every frame of a drag -- which is part of what made the corner feel
  -- like it was losing the mouse. The word list settled this a while ago; the
  -- panel had been left behind.
  do
    local debounce
    panel:HookScript("OnSizeChanged", function()
      if debounce then debounce:Cancel() end
      debounce = C_Timer.NewTimer(0.15, function()
        if panel:IsShown() then refreshPanel() end
      end)
    end)
  end
  panel:Hide()

  -- Nothing below is anchored or sized here. Every offset and every height in
  -- this window's furniture moves with the player's text size, and layoutChrome
  -- owns all of them; a second copy written out here would be the one that is
  -- right at 100% and wrong everywhere else. Addon.ApplyIntegratedLayout at the
  -- foot of this function is what puts them all on screen.
  panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.title:SetJustifyH("LEFT")
  panel.title:SetMaxLines(1)
  panel.title:SetWordWrap(false)
  panel.sourceNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.sourceNote:SetJustifyH("LEFT")
  panel.sourceNote:SetWordWrap(true)
  panel.sourceNote:Hide()

  panel.meta = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.meta:SetJustifyH("LEFT")
  panel.meta:SetMaxLines(1)

  local close = Addon.NativeCloseButton(panel)
  close:SetPoint("TOPRIGHT", -2, -2)
  close:SetScript("OnClick", function()
    panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
  end)
  panel.enTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  panel.enTitle:SetJustifyH("LEFT")
  panel.enTitle:SetMaxLines(1)
  panel.enTitle:SetWordWrap(false)
  panel.enTitle:SetText(LABELS.englishHeader)

  panel.enScroll = Addon.CreateStyledScrollFrame(panel)
  panel.enContent = CreateFrame("Frame", nil, panel.enScroll)
  panel.enContent:SetWidth(360)
  panel.enContent:SetHeight(1)
  panel.enScroll:SetScrollChild(panel.enContent)

  panel.divider = panel:CreateTexture(nil, "ARTWORK")
  panel.divider:SetColorTexture(0.20, 0.30, 0.43, 0.55)
  panel.divider:SetWidth(1)

  panel.scroll = Addon.CreateStyledScrollFrame(panel)
  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content:SetWidth(382)
  panel.content:SetHeight(1)
  panel.scroll:SetScrollChild(panel.content)

  panel.footerLine = panel:CreateTexture(nil, "ARTWORK")
  panel.footerLine:SetColorTexture(0.20, 0.30, 0.43, 0.55)
  panel.footerLine:SetHeight(1)
  if rawget(panel, 'whwNativeStyle') then
    panel.headingRule = panel:CreateTexture(nil, 'ARTWORK')
    if Addon.HasUIAtlas('spellbook-divider') then
      panel.headingRule:SetAtlas('spellbook-divider'); panel.headingRule:SetHeight(11)
    else
      panel.headingRule:SetColorTexture(.25, .16, .08, .25); panel.headingRule:SetHeight(1)
    end
  end

  -- Kept as a list rather than four loop locals that fall out of scope: the
  -- dots and their labels have to be re-sized and re-placed every time the text
  -- size moves, and something has to be able to reach them again.
  local statuses = { "new", "learning", "known", "ignored" }
  panel.legend = {}
  for index, status in ipairs(statuses) do
    -- From the surface's own palette, so the swatch in the legend is the same
    -- colour as the words it names and as the figure in the progress line.
    local color = Addon.PaletteFor(Addon.UsesLightSurface(panel))[status]
    local dot = panel:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(color[1], color[2], color[3], 1)
    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetText(Addon.STATUS_LABELS[status])
    legend:SetTextColor(0.78, 0.82, 0.88)
    panel.legend[index] = { dot = dot, text = legend, status = status }
  end

  local copyQuest = Addon.createActionButton(panel, LABELS.copyQuest)
  copyQuest.baseWidth = 118
  copyQuest:SetScript("OnClick", function()
    if Addon.lastQuest then Addon.showCopyText(LABELS.copyQuest, Addon.lastQuest.text, nil, panel) end
  end)

  -- --- the Spoken addon's quest audio ---------------------------------------------
  --
  -- Spoken puts its own Play button on Blizzard's quest log and reads the quest
  -- aloud. It has no public "play this quest id" call -- the button resolves the
  -- line itself and hands a prepared clip to its player -- so this asks the two
  -- objects that button asks and gets the same audio for the same quest. Which
  -- is the QuestAccept line, as it is there: the opening paragraph is the one
  -- the player is reading in this panel.
  --
  -- Everything is probed. A player with no Spoken, or with the Spoken player
  -- but not the Spoken_Quests feature that resolves quest ids, gets no button
  -- at all rather than a button that errors.
  local function spokenQuestVoice()
    local Spoken = rawget(_G, "Spoken")
    local VoiceOver = rawget(_G, "VoiceOver")
    if type(Spoken) ~= "table" or type(Spoken.IsCompatible) ~= "function" then return nil end
    local ok, compatible = pcall(Spoken.IsCompatible, Spoken, 1)
    if not ok or not compatible then return nil end
    if type(VoiceOver) ~= "table" then return nil end
    local Player = VoiceOver.Player
    if type(Player) ~= "table" or type(Player.PlayNow) ~= "function" then return nil end
    local Enums = VoiceOver.Enums
    if type(Enums) ~= "table" or type(Enums.SoundEvent) ~= "table" then return nil end
    return VoiceOver
  end
  Addon.SpokenQuestVoice = spokenQuestVoice

  -- The clip this button started, so a second press can find it. Spoken matches
  -- clips by identity and builds a fresh table every time, so the queue is
  -- walked by quest id and event instead -- the same toggle its own button is.
  local spokenClip

  local function spokenPlaying(VoiceOver, quest)
    if not (VoiceOver and quest and tonumber(quest.id) and tonumber(quest.id) > 0) then return nil end
    local Player = VoiceOver.Player
    local event = VoiceOver.Enums.SoundEvent.QuestAccept
    if spokenClip and type(Player.Contains) == "function" and Player:Contains(spokenClip) then
      return spokenClip
    end
    if type(Player.Queued) == "function" then
      local ok, queue = pcall(Player.Queued, Player)
      if ok and type(queue) == "table" then
        for _, clip in ipairs(queue) do
          if clip.questID == quest.id and clip.event == event then return clip end
        end
      end
    end
    return nil
  end

  function Addon.ToggleQuestAudio()
    local VoiceOver = spokenQuestVoice()
    local quest = Addon.lastQuest
    local function done(playing)
      -- The label follows the state here rather than on the next render: a
      -- button that still says Play after you pressed it is a button that
      -- looks like it did nothing.
      if Addon.RefreshQuestAudioButton then Addon.RefreshQuestAudioButton() end
      return playing
    end
    if not VoiceOver or not (quest and tonumber(quest.id) and tonumber(quest.id) > 0) then return done(false) end
    local event = VoiceOver.Enums.SoundEvent.QuestAccept
    local already = spokenPlaying(VoiceOver, quest)
    if already then
      pcall(VoiceOver.Player.Remove, VoiceOver.Player, already)
      spokenClip = nil
      return done(false)
    end
    spokenClip = {
      event = event,
      questID = quest.id,
      title = quest.title,
      name = quest.title,
      origin = "WordHunterWoW",
    }
    local ok, played = pcall(VoiceOver.Player.PlayNow, VoiceOver.Player, spokenClip)
    -- Falsy is how Spoken says no pack has this line. Nothing to keep, and
    -- nothing to stop on the next press.
    if not ok or not played then spokenClip = nil return done(false) end
    return done(true)
  end

  local playBtn = Addon.createActionButton(panel, "Play")
  playBtn.baseWidth = 60
  rawset(playBtn, "whwOptional", true)
  playBtn:SetScript("OnClick", function() Addon.ToggleQuestAudio() end)
  playBtn:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Play with Spoken")
    GameTooltip:AddLine("Reads this quest aloud, the same audio as the Play button in the quest log.", 0.8, 0.82, 0.88, true)
    GameTooltip:Show()
  end)
  playBtn:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  -- Shown only where it can do something: Spoken has to be installed and the
  -- text on screen has to be a real quest. A book, a journal page and a line
  -- of gossip all come through this panel and none of them has audio.
  local function refreshPlayButton()
    local quest = Addon.lastQuest
    local wanted = spokenQuestVoice() ~= nil
      and quest ~= nil and tonumber(quest.id) and tonumber(quest.id) > 0
    -- Show/Hide rather than SetShown: those are the two the stub actually
    -- models, so a test can see the difference between a button that is up and
    -- one that is not. SetShown on a stub frame is answered by a fabricated
    -- method that does nothing.
    if wanted then playBtn:Show() else playBtn:Hide() end
    playBtn:SetText(spokenPlaying(spokenQuestVoice(), quest) and "Stop" or "Play")
  end
  Addon.RefreshQuestAudioButton = refreshPlayButton

  local wordsBtn = Addon.createActionButton(panel, LABELS.wordsButton)
  if Addon.ButtonShortcut then Addon.ButtonShortcut(wordsBtn, "WORDS", nil, "PAD3") end
  wordsBtn.baseWidth = 52
  wordsBtn:SetScript("OnClick", function()
    if Addon.listFrame and Addon.listFrame:IsShown() then
      Addon.listFrame:Hide()
    else
      Addon.toggleWordList()
    end
  end)

  local statsBtn = Addon.createActionButton(panel, LABELS.statsButton)
  if Addon.ButtonShortcut then Addon.ButtonShortcut(statsBtn, "STATS") end
  statsBtn.baseWidth = 52
  statsBtn:SetScript("OnClick", function()
    if Addon.statsFrame and Addon.statsFrame:IsShown() then
      Addon.statsFrame:Hide()
    else
      Addon.toggleStats()
    end
  end)

  -- In the order they are laid out, which is right to left from the corner. The
  -- last of them is the leftmost, and that is what the progress line stops at.
  local phase = Addon.createActionButton(panel, "Offer")
  phase.baseWidth = 102
  phase:Hide()
  phase:SetScript("OnClick", function()
    local quest = Addon.lastQuest
    if not (quest and quest.catalog and Addon.SetCatalogPhase) then return end
    local phases = quest.catalogPhases or { "offer" }
    for index, value in ipairs(phases) do
      if value == quest.catalogPhase then Addon.SetCatalogPhase(phases[index % #phases + 1]) return end
    end
  end)
  phase:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Switch quest passage")
    GameTooltip:AddLine("Offer, progress and completion text where stored.", 0.8, 0.82, 0.88, true)
    GameTooltip:Show()
  end)
  phase:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  panel.catalogPhaseButton = phase
  -- The Play button is deliberately not in either list. It is the one button
  -- that comes and goes -- with the Spoken addon, and with whether the text on
  -- screen is a real quest at all -- and a button in these lists is a button
  -- that has to be laid out, sized and anchored like the rest. layoutActions
  -- appends it to the row when it is up instead.
  panel.actions = { copyQuest, wordsBtn, statsBtn }
  panel.copyQuestButton = copyQuest
  panel.questAudioButton = playBtn
  panel.catalogActions = { copyQuest, wordsBtn, statsBtn, phase }

  function Addon.ApplyIntegratedLayout()
    if not panel then return end
    local hasEN = type(WordHunterWoW_QuestEN) == "table"
    local quest = Addon.lastQuest
    local singleCatalog = quest and quest.catalog and (quest.sourceLocale == "enUS" or quest.sourceLocale == "enGB")
    local integrated = Addon.GetIntegratedLayout() and hasEN and not (quest and quest.readOnly) and not singleCatalog
    -- nil on the very first call, which counts as a change: a width saved from
    -- a two-column session has to be brought back down once.
    local wasIntegrated = panel.integratedLayout
    panel.integratedLayout = integrated
    -- Which of the two arrangements is on, and nothing about where anything in
    -- it goes: layoutChrome below settles that for both, because every offset
    -- in it moves with the player's text size and one copy of those numbers is
    -- all this window can afford.
    if integrated then
      panel.enScroll:Show()
      panel.enTitle:Show()
      panel.divider:Show()
      Addon.PlaceFrame(panel, "panel")
      if Addon.enPanel then Addon.enPanel:Hide() end
    else
      panel.enScroll:Hide()
      panel.enTitle:Hide()
      panel.divider:Hide()
      -- Only when the second column has just gone away. A window sized for two
      -- columns is far too wide for one, so it is worth bringing back down. But
      -- this used to run on every quest read, so a single-column window the
      -- player had dragged out wide was snapped to the default the next time
      -- they talked to anyone. The first call (wasIntegrated == nil) must
      -- restore the saved position instead: without the English pack the
      -- panel never took the integrated branch, so PlaceFrame never ran.
      -- A catalog reference merely hides the companion column; it is not a
      -- request to compact the reader. Resizing here would overwrite the same
      -- saved geometry used by the normal reader, including a hand-picked size.
      if wasIntegrated == nil then
        Addon.PlaceFrame(panel, "panel")
      elseif not (quest and quest.readOnly) and not singleCatalog
          and wasIntegrated ~= false and panel:GetWidth() > 700 then
        panel:SetSize(430, 240)
      end
    end
    -- After the width is settled, because the legend wraps against it. A
    -- refresh already does this, and this runs on every quest read, so it is
    -- only worth doing here for the panel that is not about to be drawn.
    if panel:IsShown() then refreshPanel() else layoutChrome() end
  end

  if Addon.WatchInputHints then
    panel.inputHint = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    panel.inputHint:SetPoint("BOTTOMLEFT", 18, 4)
    panel.inputHint:SetJustifyH("LEFT")
    panel.inputHint:SetWordWrap(true)
    Addon.WatchInputHints(panel, function()
      if panel.inputHint:GetText() ~= Addon.PanelShortcutText() and Addon.RelayoutPanel then
        Addon.RelayoutPanel()
      end
    end)
  end
  Addon.ApplyIntegratedLayout()
end

-- Lay the panel out again after something outside this file has changed what it
-- should look like. Reading mode is the caller: it moves the panel to a
-- different layout context, and the words inside have to be re-flowed against
-- the new width or they stay wrapped for the old one.
--
-- Both halves of the idiom, because a panel that is not on screen must not be
-- refreshed -- refreshPanel measures the text against a frame with no size yet
-- and lays every token at zero.
function Addon.RelayoutPanel()
  if not panel then return end
  if panel:IsShown() then refreshPanel() else layoutChrome() end
end
