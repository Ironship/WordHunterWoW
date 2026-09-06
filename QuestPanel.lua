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
LABELS.questLogButton = "Word Hunter"
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

local function tokenFont(fs, scale)
  local path, size, flags = GameFontHighlight:GetFont()
  scale = scale or (Addon.GetTextScale and Addon.GetTextScale() or 1)
  if path then fs:SetFont(path, (size or 12) * scale, flags) end
  fs:SetShadowColor(0, 0, 0, 0.9)
  fs:SetShadowOffset(1, -1)
end

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
  -- Where the heading block ends, which is where the text under it starts in
  -- the two-column layout and where the progress line goes in the one-column
  -- one.
  m.headBottom = m.topPad + m.titleH + m.titleGap
  m.metaBottom = m.headBottom + m.metaH + m.metaGap
  m.legendBottom = m.footPad + m.buttonH + m.legendGap
  return m
end

-- Re-fonts one of the panel's own strings off the font object it was built
-- with, the way tokenFont does for the quest words. The size is read back from
-- the object rather than written down here so that a player who has turned the
-- game's own font up keeps that: the setting is a multiple of whatever the
-- client draws with, never a replacement for it.
local function chromeFont(fs, objectName, scale)
  local object = _G[objectName]
  if not (fs and fs.SetFont and object and object.GetFont) then return end
  local path, size, flags = object:GetFont()
  if path then fs:SetFont(path, (size or 12) * scale, flags) end
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
    chromeFont(item.text, "GameFontNormalSmall", m.scale)
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
-- of the button it is in.
local function layoutActions(m)
  local previous
  for _, action in ipairs(panel.actions) do
    if action.GetFontString then
      chromeFont(action:GetFontString(), "GameFontNormal", m.scale)
    end
    action:SetSize(action.baseWidth * m.scale, m.buttonH)
    action:ClearAllPoints()
    if previous then
      action:SetPoint("RIGHT", previous, "LEFT", -m.buttonGap, 0)
    else
      action:SetPoint("BOTTOMRIGHT", -18, m.footPad)
    end
    previous = action
  end
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

  chromeFont(panel.title, "GameFontNormalLarge", m.scale)
  panel.title:SetHeight(m.titleH)
  panel.title:ClearAllPoints()
  chromeFont(panel.meta, "GameFontDisableSmall", m.scale)
  panel.meta:SetHeight(m.metaH)
  panel.meta:ClearAllPoints()
  chromeFont(panel.enTitle, "GameFontNormalLarge", en.scale)
  panel.enTitle:SetHeight(en.titleH)
  panel.enTitle:ClearAllPoints()
  panel.enTitle:SetPoint("TOPLEFT", 18, -en.topPad)
  panel.enTitle:SetPoint("RIGHT", panel, "CENTER", -12, 0)
  panel.scroll:ClearAllPoints()
  panel.enScroll:ClearAllPoints()
  layoutActions(m)

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
    panel.meta:SetPoint("BOTTOMRIGHT", panel.actions[#panel.actions], "BOTTOMLEFT",
      -8, m.metaFootY - m.footPad)
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
    panel.title:SetPoint("TOPRIGHT", -18, -m.topPad)
    panel.meta:SetPoint("TOPLEFT", 18, -m.headBottom)
    panel.meta:SetPoint("TOPRIGHT", -140, -m.headBottom)
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

local function sentenceForWord(text, word)
  local _, sentence = Addon.SentenceContaining(text, word)
  return sentence or Addon.trim(text)
end

local function paintEnglishHighlight(sentenceIndex, wordTokens)
  local hl = COLORS.enHighlight
  local wordHl = COLORS.enWordHighlight
  local bg = COLORS.enHighlightBackground
  local first
  for _, bit in ipairs(enBits) do
    if bit:IsShown() then
      if bit.caveat then
        local color = COLORS.caveat
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
        bit.text:SetTextColor(unpack(COLORS.text))
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
    index, sentence = Addon.MatchEnglishSentence(Addon.lastQuest.text, enText, word, deSentenceIndex)
  end
  local wordTokens
  if sentence and not sentenceOnly and Addon.MatchEnglishTokenIndexes then
    wordTokens = Addon.MatchEnglishTokenIndexes(sentence, word, wordOccurrence)
  end
  paintEnglishHighlight(index, wordTokens)
  if Addon.OnHighlightEnglishForWord then
    Addon.OnHighlightEnglishForWord(word, Addon.lastQuest, deSentenceIndex, wordOccurrence, sentenceOnly)
  end
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
  layoutChrome()
  local lastQuest = Addon.lastQuest
  -- Whether this render is a different quest from the last one drawn, which is
  -- what decides if the panes go back to the top.
  local newQuest = panel.renderedQuestKey ~= tostring(lastQuest.id or lastQuest.title or "")
    or panel.renderedText ~= lastQuest.text or panel.renderedPassage ~= lastQuest.passage
  panel.renderedQuestKey = tostring(lastQuest.id or lastQuest.title or "")
  panel.renderedText, panel.renderedPassage = lastQuest.text, lastQuest.passage
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
    local entry = WordHunterWoW_QuestEN and qid and WordHunterWoW_QuestEN[tonumber(qid)]
    local enTitle = LABELS.englishHeader
    -- Kept as separate blocks rather than one joined string. This pane places one
    -- token at a time, so a newline inside a joined string is discarded with the
    -- rest of the whitespace and the caveat runs straight into the quest text.
    local enBlocks = { { text = "English text is not available for this quest." } }
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
      elseif not hasOffer then
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
      local color = block.caveat and COLORS.caveat or COLORS.text
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
          tokenFont(bit.text, enScale)
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
    panel.enContent:SetHeight(math.max(28, -ey + 28))
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
  local savedCount = 0
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
      tokenFont(button.text)

      button.text:SetText(token)
      local width = math.min(contentWidth - gutter, math.ceil(button.text:GetStringWidth()) + 6)
      if x > gutter and x + width > contentWidth then
        x = gutter
        y = y - TOKEN_STEP
      end
      button:ClearAllPoints()
      button:SetPoint("TOPLEFT", x, y)
      button:SetWidth(width)
      x = x + width + 2

      local word = Addon.cleanWord(token)
      local key = Addon.wordKey(word)
      local entry = Addon.GetEffectiveWord(key)
      -- Scored once per distinct word, whether or not anything knows it yet.
      -- A word no dictionary covers is still a word in this quest the player
      -- does not know, so it belongs in the total rather than outside it.
      if word ~= "" and not countedWords[key] then
        countedWords[key] = true
        if entry then savedCount = savedCount + 1 end
        local status = entry and Addon.EffectiveStatus(entry) or "new"
        if progress[status] ~= nil then progress[status] = progress[status] + 1 end
      end
      button.text:SetTextColor(unpack(COLORS.text))
      if entry then
        local color = COLORS[entry.status] or COLORS.new
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
      else
        button.underline:Hide()
        -- Nothing knows this word: no dictionary entry and the player has not
        -- saved it. That is the 5% a new patch brings, and the only vocabulary
        -- the project cannot already gloss, so it is worth collecting.
        if Addon.HarvestUnknownWord and word ~= "" then
          Addon.HarvestUnknownWord(word, lastQuest.id)
        end
      end
      button.word = word
      button.sentenceIndex = deSentenceOfToken[deTokenNum]
      local occKey = tostring(button.sentenceIndex or 0) .. "\0" .. key
      wordOccurrenceInSentence[occKey] = (wordOccurrenceInSentence[occKey] or 0) + 1
      button.wordOccurrence = wordOccurrenceInSentence[occKey]
      button:SetScript("OnEnter", function(self)
        if self.word and self.word ~= "" then
          Addon.HighlightEnglishForWord(self.word, self.sentenceIndex, self.wordOccurrence)
        end
      end)
      button:SetScript("OnLeave", function()
        local selected = selectedHighlight or {}
        Addon.HighlightEnglishForWord(selected[1], selected[2], selected[3], true)
      end)
      button:SetScript("OnClick", function(self)
        selectedHighlight = { self.word, self.sentenceIndex, self.wordOccurrence }
        Addon.HighlightEnglishForWord(self.word, self.sentenceIndex, self.wordOccurrence)
        local deSentences = Addon.SplitSentences(lastQuest.text)
        local context = (self.sentenceIndex and deSentences[self.sentenceIndex])
          or sentenceForWord(lastQuest.text, self.word)
        Addon.openEditor(self.word, context, lastQuest.id, lastQuest.title)
      end)
      button:SetEnabled(word ~= "")
      button:Show()
    end
  end
  local contentHeight = math.max(28, -y + 28)
  panel.content:SetHeight(contentHeight)
  panel.scroll:UpdateScrollChildRect()
  panel.meta:SetText(Addon.FormatProgress(progress))
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
  if questLogId and questLogId > 0 then
    questId = questLogId
    description, objectives = Compat.QuestLogText(Compat.QuestLogIndexForID(questId))
    title = Compat.TitleForQuestID(questId) or title
  -- QuestInfoFrame is Retail's; Classic shows the same thing in its own quest
  -- log window. The Classic arm is guarded by flavour rather than folded in, so
  -- that opening the world map on Retail keeps behaving exactly as it did.
  elseif (QuestInfoFrame and QuestInfoFrame.questLog) or (Compat.IsClassic() and Compat.QuestLogShown()) then
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
  -- Events set lastPassage. Tests and anything that skipped them still infer
  -- from which Blizzard function answered, the way this used to work.
  local passage = Addon.lastPassage
  -- A quest named by log id is being read out of the log, and the log holds
  -- nothing but the opening text -- Blizzard's progress and hand-in lines exist
  -- only while an NPC is saying them. Without this the read inherited whichever
  -- passage the last conversation left behind, and GOSSIP_CLOSED never clears
  -- one: browse the log after a chat and every quest came up labelled gossip,
  -- which raised the "no English for this part of a quest" caveat over text
  -- that was the opening text all along, and switched highlighting off with it.
  if questLogId and questLogId > 0 then passage = "offer" end
  if passage ~= "progress" and passage ~= "reward" and passage ~= "gossip" then
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
  -- Objectives, progress and hand-in text exist only here, never in the quest
  -- API the dictionaries were built from. Record them when the player opts in.
  if Addon.HarvestQuest then
    Addon.HarvestQuest(questId, {
      title = title,
      description = desc,
      objectives = obj,
      progress = progressText ~= "" and progressText or nil,
      reward = rewardText ~= "" and rewardText or nil,
    })
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
  -- The quest giver's window and the quest log are two different cases now. At
  -- an NPC the panel opens with the window, as it always has. From the log it
  -- waits to be asked -- see Addon.GetQuestLogAutoOpen above for what reading
  -- the log used to cost -- unless the player pressed the button hung on the
  -- log, which is what `requested` carries.
  --
  -- The test is which window the text came from and never which of Blizzard's
  -- functions fired. Showing the map's quest details runs
  -- QuestInfo_ShowDescriptionText as well as QuestMapFrame_ShowQuestDetails, so
  -- a rule written against hook names would have left that second route open
  -- and the panel would have landed on the log through it regardless.
  local Compat = Addon.Compat
  local atQuestGiver = not Compat or Compat.NpcQuestFrameShown()
  if atQuestGiver or requested or (Compat.QuestLogShown() and Addon.GetQuestLogAutoOpen()) then
    panel:Show()
  end
  -- Laid out after the decision to show, never before it. refreshPanel declines
  -- to work on a hidden window -- that is what keeps a closed panel from being
  -- rebuilt on every save -- so rendering first would have drawn this quest into
  -- a window that was still hidden, and left the old one on screen.
  refreshPanel()
end
Addon.readCurrentQuest = readCurrentQuest

function Addon.readGossip()
  local text = C_GossipInfo and C_GossipInfo.GetText and C_GossipInfo.GetText()
  if (not text or text == "") and GetGossipText then text = GetGossipText() end
  text = Addon.trim(tostring(text or ""))
  if text == "" then return end
  local title = (UnitName and (UnitName("npc") or UnitName("questnpc"))) or "Gossip"
  Addon.lastPassage = "gossip"
  Addon.lastQuest = { id = 0, title = Addon.trim(title), text = text, passage = "gossip" }
  if Addon.ApplyIntegratedLayout then Addon.ApplyIntegratedLayout() end
  if not panel then return end
  panel:Show()
  refreshPanel()
end

-- The quest log's own way in -------------------------------------------------

local logButton

-- A Blizzard global can be absent on one game and be something other than a
-- frame on the other, so nothing below indexes one without asking first. Same
-- shape as Compat's own `shown`, for the same reason.
local function usableFrame(frame)
  if type(frame) == "table" and type(frame.IsShown) == "function" then return frame end
  return nil
end

-- What the button hangs on. Retail keeps the quest log inside the world map and
-- swaps in a details pane once a quest is picked; Classic Era has a window of
-- its own. Both are frames this suite already trusts in the live game --
-- Compat.QuestLogFrame and the English panel between them watch every one.
--
-- Asked by flavour rather than by probing both, unlike Compat.QuestLogFrame,
-- which wants whichever of them is open at this instant. This picks a parent
-- once and never rehomes the button, so a leftover global of the other game's
-- name would capture it for the whole session and the button would sit on a
-- window that never opens.
--
-- Retail's details pane is preferred over the map around it because it is on
-- screen exactly while a quest is being read: hung there, the button comes and
-- goes with the thing it acts on and needs no showing or hiding of its own.
--
-- Published because which frame this picks is the whole of the Classic half of
-- the feature, and it cannot be read back off the button afterwards.
local function questLogHost()
  local Compat = Addon.Compat
  if not Compat or Compat.IsRetail() then
    if type(QuestMapFrame) ~= "table" then return nil end
    return usableFrame(QuestMapFrame.DetailsFrame)
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
    readCurrentQuest(nil, true)
  end
end

-- Idempotent, and called again at every moment the log could have arrived:
-- Retail builds the map's quest log in Blizzard_WorldMap and Classic keeps its
-- own in Blizzard_QuestLog, both load-on-demand, so at the addon's own
-- ADDON_LOADED there is usually nothing here yet to hang anything on.
function Addon.AttachQuestLogButton()
  if logButton then return logButton end
  local host = questLogHost()
  if not host then return nil end
  local button = Addon.createActionButton(host, LABELS.questLogButton)
  button:SetSize(104, 22)
  -- Just outside the log's top-right corner, not in among Blizzard's own
  -- buttons. Which children the quest log has, and where it has room for
  -- another, differs between the two games -- Retail's details pane ends in
  -- Abandon/Share/Track, Classic's window carries its close button in that
  -- corner -- and both have moved between patches. The outer edge is the one
  -- part of the frame Blizzard never draws on, so it is the only anchor that
  -- can be got right for both without a client of each to try it on. The
  -- English panel already sits beside the log at this offset, which is where
  -- the 4 comes from.
  button:SetPoint("TOPLEFT", host, "TOPRIGHT", 4, -8)
  -- Above this addon's own quest panel, which is the only thing that covers it.
  --
  -- The panel is FULLSCREEN_DIALOG at level 20 with SetToplevel; the quest log
  -- lives in the world map, which sits lower, so a button hung off the map is
  -- drawn under the panel. On a live realm the panel opens right beside the log
  -- -- that is the whole point of it -- and it left this button as a red sliver
  -- with two letters of its name showing.
  --
  -- Raising it is right rather than merely convenient: this button's one job is
  -- to toggle that panel, so it is the one control that has to stay reachable
  -- while the panel is up. It is raised within FULLSCREEN_DIALOG rather than
  -- put in a strata above it, so it still goes behind a true modal -- a
  -- confirmation, or the game's own menus.
  button:SetFrameStrata("FULLSCREEN_DIALOG")
  button:SetFrameLevel(40)
  button:SetScript("OnClick", Addon.ToggleQuestFromLog)
  button:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- Written to, never read back. Text taken off one of the game's own frames
    -- can be a secret value on current Retail, and touching one taints the
    -- addon and stops everything else it does, nowhere near this line.
    GameTooltip:SetText(LABELS.questLogButton)
    GameTooltip:AddLine(LABELS.questLogButtonTip, 0.8, 0.82, 0.88, true)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function()
    if GameTooltip then GameTooltip:Hide() end
  end)
  logButton = button
  Addon.questLogButton = button
  return button
end

-- Which of Blizzard's functions fired only matters for working out which quest
-- the player is looking at; the reading itself is the same on every game.
function Addon.hookQuestUi()
  local Compat = Addon.Compat
  Addon.AttachQuestLogButton()
  return Compat.HookQuestUi(function(name)
    C_Timer.After(0, function()
      -- Belt and braces for a log that arrived by some route ADDON_LOADED did
      -- not name: by the time one of the log's own functions has run, its
      -- frames certainly exist, so nothing can be too early here.
      Addon.AttachQuestLogButton()
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
  panel = CreateFrame("Frame", "WordHunterWoWFrame", UIParent, "BackdropTemplate")
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

  panel.meta = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  panel.meta:SetJustifyH("LEFT")
  panel.meta:SetMaxLines(1)

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
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

  panel.enScroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.enContent = CreateFrame("Frame", nil, panel.enScroll)
  panel.enContent:SetWidth(360)
  panel.enContent:SetHeight(1)
  panel.enScroll:SetScrollChild(panel.enContent)

  panel.divider = panel:CreateTexture(nil, "ARTWORK")
  panel.divider:SetColorTexture(0.20, 0.30, 0.43, 0.55)
  panel.divider:SetWidth(1)

  panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  panel.content = CreateFrame("Frame", nil, panel.scroll)
  panel.content:SetWidth(382)
  panel.content:SetHeight(1)
  panel.scroll:SetScrollChild(panel.content)

  panel.footerLine = panel:CreateTexture(nil, "ARTWORK")
  panel.footerLine:SetColorTexture(0.20, 0.30, 0.43, 0.55)
  panel.footerLine:SetHeight(1)

  -- Kept as a list rather than four loop locals that fall out of scope: the
  -- dots and their labels have to be re-sized and re-placed every time the text
  -- size moves, and something has to be able to reach them again.
  local statuses = { "new", "learning", "known", "ignored" }
  panel.legend = {}
  for index, status in ipairs(statuses) do
    local color = COLORS[status]
    local dot = panel:CreateTexture(nil, "ARTWORK")
    dot:SetColorTexture(color[1], color[2], color[3], 1)
    local legend = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    legend:SetText(Addon.STATUS_LABELS[status])
    legend:SetTextColor(0.78, 0.82, 0.88)
    panel.legend[index] = { dot = dot, text = legend }
  end

  local copyQuest = Addon.createActionButton(panel, LABELS.copyQuest)
  copyQuest.baseWidth = 118
  copyQuest:SetScript("OnClick", function()
    if Addon.lastQuest then Addon.showCopyText(LABELS.copyQuest, Addon.lastQuest.text) end
  end)

  local wordsBtn = Addon.createActionButton(panel, LABELS.wordsButton)
  wordsBtn.baseWidth = 52
  wordsBtn:SetScript("OnClick", function()
    if Addon.listFrame and Addon.listFrame:IsShown() then
      Addon.listFrame:Hide()
    else
      Addon.toggleWordList()
    end
  end)

  local statsBtn = Addon.createActionButton(panel, LABELS.statsButton)
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
  panel.actions = { copyQuest, wordsBtn, statsBtn }

  function Addon.ApplyIntegratedLayout()
    if not panel then return end
    local hasEN = type(WordHunterWoW_QuestEN) == "table"
    local integrated = Addon.GetIntegratedLayout() and hasEN
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
      if wasIntegrated == nil then
        Addon.PlaceFrame(panel, "panel")
      elseif wasIntegrated ~= false and panel:GetWidth() > 700 then
        panel:SetSize(430, 240)
      end
    end
    -- After the width is settled, because the legend wraps against it. A
    -- refresh already does this, and this runs on every quest read, so it is
    -- only worth doing here for the panel that is not about to be drawn.
    if panel:IsShown() then refreshPanel() else layoutChrome() end
  end

  Addon.ApplyIntegratedLayout()
end
