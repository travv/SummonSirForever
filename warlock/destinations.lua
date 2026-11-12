-- Destination presets and typo-tolerant request matching ("wtb sumon tb")
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local D = {}

-- Short aliases (3 letters or fewer) only match as whole words, never fuzzy.
-- Common English words ("if", "me", "in", "dm") are deliberately not aliases.
D.PRESETS = {
  -- capitals
  { key = "org",   name = "Orgrimmar",          aliases = { "org", "orgrimmar", "orgri", "orgrim", "og" } },
  { key = "tb",    name = "Thunder Bluff",      aliases = { "tb", "thunder bluff", "thunderbluff" } },
  { key = "uc",    name = "Undercity",          aliases = { "uc", "undercity" } },
  { key = "sw",    name = "Stormwind",          aliases = { "sw", "stormwind" } },
  { key = "ifo",   name = "Ironforge",          aliases = { "ifo", "ironforge" } },
  { key = "darn",  name = "Darnassus",          aliases = { "darn", "darnassus" } },
  -- dungeons and raids
  { key = "sm",    name = "Scarlet Monastery",  aliases = { "sm", "scarlet", "scarlet monastery", "monastery" } },
  { key = "sfk",   name = "Shadowfang Keep",    aliases = { "sfk", "shadowfang" } },
  { key = "rfk",   name = "Razorfen Kraul",     aliases = { "rfk", "kraul" } },
  { key = "rfd",   name = "Razorfen Downs",     aliases = { "rfd", "razorfen downs" } },
  { key = "gnomer",name = "Gnomeregan",         aliases = { "gnomer", "gnomeregan" } },
  { key = "ulda",  name = "Uldaman",            aliases = { "ulda", "uldaman" } },
  { key = "zf",    name = "Zul'Farrak",         aliases = { "zf", "zul farrak", "zulfarrak", "farrak" } },
  { key = "mara",  name = "Maraudon",           aliases = { "mara", "maraudon" } },
  { key = "st",    name = "Sunken Temple",      aliases = { "st", "sunken temple", "sunken" } },
  { key = "brd",   name = "Blackrock Depths",   aliases = { "brd", "blackrock depths", "depths" } },
  { key = "brs",   name = "Blackrock Spire",    aliases = { "brs", "lbrs", "ubrs", "blackrock spire", "spire" } },
  { key = "dire",  name = "Dire Maul",          aliases = { "dire maul", "diremaul", "dmn", "dme", "dmw" } },
  { key = "strat", name = "Stratholme",         aliases = { "strat", "stratholme" } },
  { key = "scholo",name = "Scholomance",        aliases = { "scholo", "scholomance" } },
  { key = "mc",    name = "Molten Core",        aliases = { "mc", "molten core" } },
  { key = "ony",   name = "Onyxia's Lair",      aliases = { "ony", "onyxia", "onyxias lair" } },
  { key = "bwl",   name = "Blackwing Lair",     aliases = { "bwl", "blackwing" } },
  { key = "zg",    name = "Zul'Gurub",          aliases = { "zg", "zul gurub", "zulgurub", "gurub" } },
  { key = "aq",    name = "Ahn'Qiraj",          aliases = { "aq", "aq20", "aq40", "ahn qiraj", "ahnqiraj" } },
  { key = "naxx",  name = "Naxxramas",          aliases = { "naxx", "naxxramas" } },
  -- zones and towns
  { key = "bb",    name = "Booty Bay",          aliases = { "bb", "booty bay", "bootybay" } },
  { key = "gadget",name = "Gadgetzan",          aliases = { "gadget", "gadgetzan", "zan" } },
  { key = "ratchet",name = "Ratchet",           aliases = { "ratchet" } },
  { key = "everlook",name = "Everlook",         aliases = { "everlook", "winterspring", "ws" } },
  { key = "silithus",name = "Silithus",         aliases = { "silithus", "cenarion hold" } },
  { key = "ungoro",name = "Un'Goro Crater",     aliases = { "ungoro", "un goro", "crater" } },
  { key = "felwood",name = "Felwood",           aliases = { "felwood" } },
  { key = "epl",   name = "Eastern Plaguelands",aliases = { "epl", "eastern plaguelands", "lhc", "lights hope" } },
  { key = "wpl",   name = "Western Plaguelands",aliases = { "wpl", "western plaguelands" } },
  { key = "stv",   name = "Stranglethorn Vale", aliases = { "stv", "stranglethorn" } },
  { key = "tanaris",name = "Tanaris",           aliases = { "tanaris" } },
  { key = "feralas",name = "Feralas",           aliases = { "feralas" } },
  { key = "azshara",name = "Azshara",           aliases = { "azshara" } },
  { key = "searing",name = "Searing Gorge",     aliases = { "searing gorge", "searing" } },
  { key = "steppes",name = "Burning Steppes",   aliases = { "burning steppes", "steppes" } },
  { key = "blasted",name = "Blasted Lands",     aliases = { "blasted lands", "blasted" } },
  { key = "tm",    name = "Tarren Mill",        aliases = { "tm", "tarren mill", "tarren" } },
  { key = "xroads",name = "The Crossroads",     aliases = { "xroads", "crossroads", "the crossroads" } },
  { key = "hinter",name = "The Hinterlands",    aliases = { "hinterlands" } },
  { key = "desolace",name = "Desolace",         aliases = { "desolace" } },
  { key = "dustwallow",name = "Dustwallow Marsh",aliases = { "dustwallow", "theramore" } },
}

local byKey = {}
for _, p in ipairs(D.PRESETS) do byKey[p.key] = p end

function D.byKey(key)
  if not key then return nil end
  return byKey[key]
end

-- lowercase, apostrophes dropped ("un'goro" -> "ungoro"), other punctuation
-- to spaces, spaces collapsed
function D.normalize(text)
  text = string.lower(text or "")
  text = string.gsub(text, "'", "")
  text = string.gsub(text, "[^%w%s]", " ")
  text = string.gsub(text, "%s+", " ")
  text = string.gsub(text, "^ ", "")
  text = string.gsub(text, " $", "")
  return text
end

function D.tokens(text)
  local out = {}
  for t in string.gmatch(text, "%S+") do table.insert(out, t) end
  return out
end

-- Levenshtein distance, gives up early past `cap`
function D.lev(a, b, cap)
  cap = cap or 99
  local la, lb = #a, #b
  if math.abs(la - lb) > cap then return cap + 1 end
  local prev = {}
  for j = 0, lb do prev[j] = j end
  for i = 1, la do
    local cur = { [0] = i }
    local rowMin = i
    local ca = string.byte(a, i)
    for j = 1, lb do
      local cost = (ca == string.byte(b, j)) and 0 or 1
      local v = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
      cur[j] = v
      if v < rowMin then rowMin = v end
    end
    if rowMin > cap then return cap + 1 end
    prev = cur
  end
  return prev[lb]
end

-- 4-letter aliases ("mara", "darn") are exact only: "mark" is not Maraudon
local function allowedTypos(len)
  if len >= 8 then return 2 end
  if len >= 5 then return 1 end
  return 0
end

-- best preset named in free text, or nil. Exact (whole-word) alias hits
-- beat fuzzy ones; fuzzy needs the same first letter.
function D.match(text)
  local norm = D.normalize(text)
  if norm == "" then return nil end
  local padded = " " .. norm .. " "
  local toks = D.tokens(norm)

  -- 1. exact alias as a whole word or phrase; longest alias wins
  local best, bestLen = nil, 0
  for _, p in ipairs(D.PRESETS) do
    for _, alias in ipairs(p.aliases) do
      if #alias > bestLen and string.find(padded, " " .. alias .. " ", 1, true) then
        best, bestLen = p, #alias
      end
    end
  end
  if best then return best, 0 end

  -- 2. fuzzy: single tokens and joined token pairs against aliases of 5+ letters
  local cands = {}
  for i, t in ipairs(toks) do
    table.insert(cands, t)
    if toks[i + 1] then table.insert(cands, t .. toks[i + 1]) end
  end
  local bestDist
  for _, p in ipairs(D.PRESETS) do
    for _, alias in ipairs(p.aliases) do
      local a = string.gsub(alias, " ", "")
      if #a >= 5 then
        local cap = allowedTypos(#a)
        for _, c in ipairs(cands) do
          if #c >= 4 and string.sub(c, 1, 1) == string.sub(a, 1, 1) then
            local d = D.lev(c, a, cap)
            if d <= cap and (bestDist == nil or d < bestDist) then
              best, bestDist = p, d
            end
          end
        end
      end
    end
  end
  return best, bestDist
end

local THANKS = { thanks = true, thank = true, thx = true, ty = true, tyvm = true, thnx = true, tnx = true }

-- does this text ask for a summon? ("123", "wtb summon", "sumon pls", "summons to tb?")
function D.isSummonRequest(text)
  local norm = D.normalize(text)
  if norm == "" then return false end
  local toks = D.tokens(norm)
  for _, t in ipairs(toks) do
    if THANKS[t] then return false end -- "thanks for the summon" is not a request
  end
  for _, t in ipairs(toks) do
    if t == "123" then return true end
    if string.find(t, "^summon") or string.find(t, "^sumon") then return true end
    if #t >= 5 and #t <= 8 and string.sub(t, 1, 1) == "s" and D.lev(t, "summon", 1) <= 1 then
      return true
    end
  end
  return false
end

W.module("destinations", D)

function D:init()
  W.command("dest", "dest <name> | dest list | dest clear: what you summon to", function(args)
    args = args or ""
    if args == "" then
      W.print("destination:", W.destName(), "price:", W.fmtMoney(W.priceFor(W.db.dest)))
      return
    end
    if args == "list" then
      local names = {}
      for _, p in ipairs(D.PRESETS) do table.insert(names, p.name .. " (" .. p.key .. ")") end
      W.print(table.concat(names, ", "))
      return
    end
    if args == "clear" then
      W.db.dest = nil
      W.print("destination cleared, using your zone:", W.destName())
      W.fire("CONFIG_CHANGED")
      return
    end
    local p = D.match(args)
    if not p then
      W.print("no preset matches", args, "(try /ssf dest list)")
      return
    end
    W.db.dest = p.key
    W.print("destination:", p.name, "price:", W.fmtMoney(W.priceFor(p.key)))
    W.fire("CONFIG_CHANGED")
  end)
end

addonData.destinations = D
