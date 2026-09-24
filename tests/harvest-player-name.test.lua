-- Run from the addon root:  lua tests/harvest-player-name.test.lua
--
-- The player's own name kept out of collected text, on a client that does not
-- simply answer UnitName("player") with it.
--
-- A harvest session on the Forever client stored the character's name "Aryo" as
-- the words "Aryo" and "ARYO" and verbatim in a gossip line, with the two guards
-- in Harvest.lua installed and unchanged. Both read UnitName("player") at the
-- moment of collecting, so at that moment it did not answer the plain name. The
-- cases below are the candidates for what it answered instead, and each one let
-- the name through before this file existed.

dofile("tests/wowstub.lua")

do
  local started = os.clock()
  debug.sethook(function()
    if os.clock() - started > 20 then
      debug.sethook()
      error(debug.traceback("this test has been running for 20s of CPU -- something is looping", 2), 2)
    end
  end, "", 200000)
end

-- Init.lua keeps its event frame in a local, so the frames it creates are
-- recorded as it loads and the first one is the dispatcher.
local realCreateFrame = CreateFrame
local initFrames
CreateFrame = function(...)
  local f = realCreateFrame(...)
  if initFrames then initFrames[#initFrames + 1] = f end
  return f
end

local answer = "Aryo"
UnitName = function(unit)
  if unit ~= "player" then return nil end
  if type(answer) == "function" then return answer() end
  return answer
end

for line in io.lines("WordHunterWoW_Mainline.toc") do
  local file = line:match("^(%S+%.lua)%s*$")
  if file then
    if file == "Init.lua" then initFrames = {} end
    local chunk = assert(loadfile(file))
    chunk("WordHunterWoW")
    if file == "Init.lua" then initFrames.done = true end
  end
end
local events = initFrames[1]
assert(events and events:GetScript("OnEvent"), "Init.lua created no event frame")
local fire = events:GetScript("OnEvent")

local Addon = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { harvestCorpus = true, targetLocale = "deDE" } }
WordHunterWoWCorpus = nil
Addon.initializeDatabase()
Addon.SetHarvestEnabled(true)

local function stored(kind, id)
  local byLocale = WordHunterWoWCorpus and WordHunterWoWCorpus.byLocale or {}
  for _, entry in pairs(byLocale[Addon.GetTargetLocale()] or {}) do
    if entry.kind == kind and entry.id == id then return entry.text end
  end
end

-- 1. A "Name-Realm" answer. The text says "Aryo", never "Aryo-Realm", so a
-- guard comparing against the whole answer matched nothing.
answer = "Aryo-Realm"
assert(not Addon.HarvestUnknownWord("Aryo"), "the name is not vocabulary when UnitName adds a realm")
assert(not Addon.HarvestUnknownWord("ARYO"), "nor in capitals")
assert(Addon.HarvestText("description", 201, "Ah, da seid Ihr ja, Aryo! Wir haben Euch erwartet."))
local text = assert(stored("description", 201))
assert(not text:find("Aryo", 1, true), "a realm suffix let the name into a passage: " .. text)
assert(text:find("Ihr ja, <name>!", 1, true), "it is replaced, not dropped: " .. text)
print("  a Name-Realm answer still keeps the name out")

-- 2. The name in capitals inside a passage. Shouted lines are written that way,
-- and a case-sensitive substitution let "ARYO" through with UnitName correct.
answer = "Aryo"
assert(Addon.HarvestText("description", 202, "ARYO! Kommt her, aryo, und hoert zu."))
text = assert(stored("description", 202))
assert(not text:lower():find("aryo", 1, true), "the name in another case reached the corpus: " .. text)
assert(text == "<name>! Kommt her, <name>, und hoert zu.", "only the name changes: " .. text)
-- Only where it stands as a word: a longer word that contains it is left whole,
-- including when the next letter is an accented one.
assert(Addon.HarvestText("description", 203, "Die Aryos und Aryoä und Karyo bleiben, „Aryo“ nicht."))
text = assert(stored("description", 203))
assert(text == "Die Aryos und Aryoä und Karyo bleiben, „<name>“ nicht.", "word edges wrong: " .. text)
print("  the name is replaced in any case, and only as a word of its own")

-- 3. Nothing at gossip time. The name was available at login and is remembered
-- from then, so a moment that answers nil still has it.
answer = "Aryo"
fire(events, "PLAYER_LOGIN")
answer = nil
C_GossipInfo = { GetText = function() return "Kann Euch nich' helfen, Aryo. Ich bilde bloss Schurken aus." end }
fire(events, "GOSSIP_SHOW")
local gossip
for _, entry in pairs(WordHunterWoWCorpus.byLocale[Addon.GetTargetLocale()]) do
  if entry.kind == "gossip" then gossip = entry.text end
end
assert(gossip, "the gossip line should still be collected")
assert(not gossip:find("Aryo", 1, true), "a nil answer at gossip time let the name in: " .. gossip)
assert(gossip:find("helfen, <name>.", 1, true), gossip)
assert(not Addon.HarvestUnknownWord("Aryo"), "the remembered name also guards single words")
print("  a name remembered at login guards a gossip window that answers nothing")

-- 4. A secret value. It cannot be compared or matched -- in the client, trying
-- raises -- so it is refused, and the remembered name is used instead.
local SECRET = setmetatable({}, {
  __index = function() error("attempt to read a secret value") end,
  __tostring = function() error("attempt to print a secret value") end,
  __concat = function() error("attempt to concatenate a secret value") end,
  __len = function() error("attempt to measure a secret value") end,
  __eq = function() error("attempt to compare a secret value") end,
})
issecretvalue = function(value) return rawequal(value, SECRET) end
answer = SECRET
local ok, collected = pcall(Addon.HarvestUnknownWord, "Aryo")
assert(ok, "a secret UnitName made the word guard raise: " .. tostring(collected))
assert(not collected, "with a secret answer the remembered name still guards words")
local okText, err = pcall(Addon.HarvestText, "progress", 204, "Aryo, habt Ihr es?")
assert(okText, "a secret UnitName made the passage guard raise: " .. tostring(err))
text = assert(stored("progress", 204))
assert(text == "<name>, habt Ihr es?", text)
assert(Addon.PlayerName() == "Aryo", "the secret value must never replace the remembered name")
-- In the client a secret string still says "string" to type(), so the type
-- check alone does not catch one. Only issecretvalue can.
local SECRET_STRING = "Verborgen"
issecretvalue = function(value) return rawequal(value, SECRET) or value == SECRET_STRING end
answer = SECRET_STRING
assert(Addon.PlayerName() == "Aryo", "a string that issecretvalue flags was taken as the name")
answer = SECRET
print("  a secret value is refused and the remembered name used")

-- 5. /whw diag says what the client answers now, and describes a secret value
-- without printing it.
local run = SlashCmdList["WORDHUNTERWOW"]
local said = {}
local realPrint = print
print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
local okDiag, diagErr = pcall(run, "diag")
print = realPrint
assert(okDiag, "/whw diag raised with a secret name: " .. tostring(diagErr))
local nameLine
for _, line in ipairs(said) do
  if line:find("name:", 1, true) then nameLine = line end
end
assert(nameLine, "/whw diag has no line about the player's name")
assert(nameLine:find("secret=yes", 1, true) and nameLine:find('cached="Aryo"', 1, true)
  and nameLine:find("value=-", 1, true), "diag line wrong for a secret: " .. nameLine)
answer = "Aryo-Realm"
issecretvalue = nil
said = {}
print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
okDiag, diagErr = pcall(run, "diag")
print = realPrint
assert(okDiag, tostring(diagErr))
nameLine = nil
for _, line in ipairs(said) do
  if line:find("name:", 1, true) then nameLine = line end
end
assert(nameLine and nameLine:find('type=string', 1, true) and nameLine:find('value="Aryo-Realm"', 1, true)
  and nameLine:find("secret=no issecretvalue", 1, true), "diag line wrong for a plain answer: " .. tostring(nameLine))
print("  /whw diag reports the raw answer and the remembered name")

print("harvest-player-name: ok")
