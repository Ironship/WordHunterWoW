-- Run from the addon root:  lua tests/english-sentence.test.lua
--
-- Clicking a German word should light up the English sentence that says the
-- same thing. Blizzard keeps paragraph breaks in lockstep even when a
-- translator merges or splits a sentence, so matching has to start there.

strlower = string.lower
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
time = os.time
GetLocale = function() return "deDE" end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon

local function joined(list)
  local out = {}
  for i, s in ipairs(list) do out[i] = s end
  return table.concat(out, " | ")
end

local sents = Addon.SplitSentences("Eins. Zwei! Drei?\nVier.")
assert(#sents == 4, "expected 4 sentences, got " .. #sents .. ": " .. joined(sents))
assert(sents[1] == "Eins.", "got " .. tostring(sents[1]))
assert(sents[4] == "Vier.", "got " .. tostring(sents[4]))
print("  sentences split on . ! ? and line breaks")

local paras = Addon.SplitParagraphs("eins.\n\nzwei.\n\n")
assert(#paras == 2, "expected 2 paragraphs, got " .. #paras)
assert(paras[1] == "eins." and paras[2] == "zwei.", "got " .. joined(paras))
print("  paragraphs split on blank lines")

local i, s = Addon.SentenceContaining("Der Bär ist tot. Bringt die Tatze.", "Tatze")
assert(i == 2 and s:find("Tatze", 1, true), "should find the second sentence, got " .. tostring(i) .. " " .. tostring(s))
print("  SentenceContaining finds the German sentence")

-- Same sentence count: index is enough, no dictionary needed.
local de = "Der mächtige Hippogryph Scharfkralle wurde getötet.\nSenani Donnerherz wird diese Trophäe sehen wollen."
local en = "The mighty hippogryph Sharptalon has been slain.\nSenani Thunderheart will want to see this trophy."
local index, sentence = Addon.MatchEnglishSentence(de, en, "Trophäe")
assert(index == 2, "aligned sentences should map 2 -> 2, got " .. tostring(index))
assert(sentence:find("trophy", 1, true), "got " .. tostring(sentence))
index = Addon.MatchEnglishSentence(de, en, "Hippogryph")
assert(index == 1, "first sentence should stay first, got " .. tostring(index))
print("  matching sentence counts map by index")

-- Real shape of quest 24448: paragraph counts match, sentence counts do not.
-- English joined two clauses; German split them. The last German sentence of
-- the second paragraph still has to land on the last English one.
de = "Kommandant Molotov hat angeordnet, dass Ihr versetzt werdet.\n\n"
  .. "Wir schicken Truppen in die Ruinen. Molotov möchte, dass Ihr eine anführt. Begebt Euch zum Außenposten."
en = "Commander Molotov sent word that you should be dispatched.\n\n"
  .. "We're preparing to send squads into the ruins, and he would like you to lead one of them. Get to the forward post."
index, sentence = Addon.MatchEnglishSentence(de, en, "Außenposten")
assert(index == 3, "last sentence of the second paragraph should map to the last English one, got "
  .. tostring(index) .. " " .. tostring(sentence))
assert(sentence:find("forward post", 1, true), "got " .. tostring(sentence))
index = Addon.MatchEnglishSentence(de, en, "versetzt")
assert(index == 1, "first paragraph should stay first, got " .. tostring(index))
print("  mismatched sentence counts still follow the paragraph")

-- When a German sentence is two English ones, the dictionary gloss picks the
-- right half. Without it, proportional mapping would send everything to sentence 1.
Addon.RegisterDictionaryProvider("deDE", "test-dict", {
  kopf = { word = "Kopf", translation = "head", note = "" },
  azshara = { word = "Azshara", translation = "Azshara", note = "" },
  zuflucht = { word = "Zuflucht", translation = "refuge; sanctuary; retreat", note = "" },
  weltenwanderer = { word = "Weltenwanderer", translation = "Farstrider", note = "" },
})
de = "Bringt mir seinen Kopf - und Azshara gehört uns!"
en = "Bring me his head. and Azshara is ours!"
index, sentence = Addon.MatchEnglishSentence(de, en, "Kopf")
assert(sentence:find("head", 1, true), "Kopf should light 'head', got " .. tostring(sentence))
index, sentence = Addon.MatchEnglishSentence(de, en, "Azshara")
assert(sentence:find("Azshara is ours", 1, true), "Azshara should light the second English sentence, got " .. tostring(sentence))
print("  a merged German sentence splits via the gloss")

-- The click is a token in a specific sentence. Searching the quest for the word
-- would light the first repeat -- Zuflucht in paragraph 2 -- even when the
-- player clicked the one in paragraph 3.
de = "Ihr habt uns geholfen.\n\nHaltet nach der Zuflucht der Weltenwanderer.\n\nMeldet Euch bei der Zuflucht der Weltenwanderer."
en = "Your help has been invaluable.\n\nLook for the Farstrider Retreat.\n\nReport to the Farstrider Retreat."
local indexes = Addon.TokenSentenceIndexes(de)
assert(indexes[#indexes] == 3, "last German token should sit in sentence 3, got " .. tostring(indexes[#indexes]))
index, sentence = Addon.MatchEnglishSentence(de, en, "Zuflucht", 3)
assert(index == 3, "the third German sentence must map to the third English one, got "
  .. tostring(index) .. " " .. tostring(sentence))
assert(sentence:find("Report", 1, true), "got " .. tostring(sentence))
index, sentence = Addon.MatchEnglishSentence(de, en, "Zuflucht", 2)
assert(index == 2 and sentence:find("Look for", 1, true), "sentence 2 should stay 2, got " .. tostring(sentence))
print("  a repeated word lights the sentence that was clicked")

local function marked(sentence, word, occ)
  local hits = Addon.MatchEnglishTokenIndexes(sentence, word, occ)
  local tokens = Addon.FlattenTokens(sentence)
  local out = {}
  for i, tok in ipairs(tokens) do
    if hits[i] then out[#out + 1] = Addon.wordKey(tok) end
  end
  return table.concat(out, " ")
end

assert(marked("Look for the Farstrider Retreat.", "Zuflucht", 1) == "retreat",
  "Zuflucht should mark Retreat, got " .. marked("Look for the Farstrider Retreat.", "Zuflucht", 1))
assert(marked("Look for the Farstrider Retreat.", "Weltenwanderer", 1) == "farstrider",
  "Weltenwanderer should mark Farstrider, got " .. marked("Look for the Farstrider Retreat.", "Weltenwanderer", 1))
assert(marked("Retreat here. More Retreat left.", "Zuflucht", 2) == "retreat",
  "second Zuflucht should mark the second Retreat")
local hits = Addon.MatchEnglishTokenIndexes("Retreat here. More Retreat left.", "Zuflucht", 2)
assert(hits[4], "the second Retreat is the fourth token")
assert(not hits[1], "the first Retreat must not be marked")
print("  the matching English word is marked, not just the sentence")

print("english-sentence: ok")

-- Layout uses whitespace tokens: punctuation inside a token must never shift
-- the indexes of every subsequent button.
local tricky = 'Wartet... "Ja!" 3.5 Gold.\n\nZur Zuflucht.'
local tokenIndexes = Addon.TokenSentenceIndexes(tricky)
assert(#tokenIndexes == #Addon.FlattenTokens(tricky), "punctuation shifted layout token indexes")
assert(tokenIndexes[#tokenIndexes] == #Addon.SplitSentences(tricky), "last token lost its sentence")
local sentences, spans = Addon.SplitSentences('Go!\n\nGo!')
assert(spans and spans[2].start == 6 and spans[2].finish == 8, "repeated sentences need distinct byte spans")
assert(#Addon.SplitSentences('Dr. Jones has 3.5 gold. Go!') == 2, "abbreviation or decimal split a sentence")
assert(Addon.SentenceContaining('Kopfgeld. Kopf.', 'Kopf') == 2, "word lookup matched a substring")
assert(Addon.MatchEnglishSentence('', 'No translation.', 'Kopf') == nil, "missing source guessed sentence 1")

Addon.RegisterDictionaryProvider('deDE', 'regressions', {
  ich = { translation = 'I' }, ist = { translation = 'is' },
  ihr = { translation = 'you (formal/pl.); her/their; to her/them' },
  holen = { translation = 'to fetch, collect / retrieve' },
  wache = { translation = 'guard' },
  kunst = { translation = 'art' },
})
assert(marked('I am here.', 'ich') == 'i', 'short dictionary translations must work')
assert(marked('It is here.', 'ist') == 'is', 'two-letter dictionary translation lost')
assert(marked('You are here.', 'ihr') == 'you', 'dictionary annotation was treated as words')
assert(marked('Collect the supplies.', 'holen') == 'collect', 'comma/slash alternatives lost')
assert(marked('Fetch the supplies.', 'holen') == 'fetch', 'infinitive marker treated as required')
assert(marked('The headmaster waits.', 'Kopf') == '', 'head falsely matched headmaster')
assert(marked('The artifact waits.', 'kunst') == '', 'art falsely matched artifact')
assert(marked('The guards wait.', 'wache') == 'guards', 'regular plural no longer matches')
assert(marked('The refuge is safe.', 'Zuflucht', 2) == '', 'missing repeat silently selected last match')
local alternatives = Addon.MatchEnglishTokenIndexes('The refuge and the sanctuary.', 'Zuflucht', 2)
assert(alternatives[5] and not alternatives[2], 'repeat must count all matching alternatives in text order')

-- Editing the meaning must not switch the highlight off. GetEffectiveWord
-- answers with the player's own entry as soon as they save one, so a reworded
-- gloss used to be the only string the match had left to work with: correcting
-- "invaluable" to "of invaluable worth", or mistyping one letter of it, took
-- the English word out of the sentence. Every gloss anyone holds counts.
Addon.RegisterDictionaryProvider('deDE', 'edited', {
  ['unschätzbarem'] = { word = 'unschätzbarem', translation = 'invaluable' },
})
assert(marked('Your help has been invaluable.', 'unschätzbarem') == 'invaluable',
  'the dictionary gloss should mark the English word')
local words = Addon.GetWordsTable()
local key = Addon.wordKey('unschätzbarem')
words[key] = { word = 'unschätzbarem', translation = 'invaluable', status = 'learning' }
assert(marked('Your help has been invaluable.', 'unschätzbarem') == 'invaluable',
  'saving the word unchanged lost the match')
words[key].translation = 'of invaluable worth (adj.)'
assert(marked('Your help has been invaluable.', 'unschätzbarem') == 'invaluable',
  'a reworded meaning hid the dictionary gloss')
words[key].translation = 'invaluablee'
assert(marked('Your help has been invaluable.', 'unschätzbarem') == 'invaluable',
  'one typed letter switched the highlight off')
words[key].translation = ''
assert(marked('Your help has been invaluable.', 'unschätzbarem') == 'invaluable',
  'an emptied meaning should fall back to the dictionary')
-- A near miss is a last resort, never a thief: with "priceless" in the sentence
-- the exact word still wins, and nothing loose gets marked beside it.
words[key].translation = 'priceless'
assert(marked('Your help was priceless, not invaluable.', 'unschätzbarem') == 'priceless',
  'the exact match must win over the dictionary gloss elsewhere in the sentence')
words[key] = nil
assert(marked('They refuse to help.', 'unschätzbarem') == '',
  'refuse is not invaluable; tolerance reached too far')
print('english-sentence regressions: ok')
