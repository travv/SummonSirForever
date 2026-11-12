-- Warlock service core: account-wide saved data, money helpers, events, /sw
-- Copyright (c) 2026 travv. MIT licensed, same as the rest of this addon.

local addonName, addonData = ...

local W = {
  modules = {},   -- init order
  handlers = {},  -- event -> list of functions
  commands = {},  -- /sw subcommand -> function(args)
  helpLines = {},
}
addonData.W = W

-- Dracula palette (https://draculatheme.com, MIT)
W.colors = {
  bg      = { 0x28, 0x2a, 0x36 },
  line    = { 0x44, 0x47, 0x5a },
  fg      = { 0xf8, 0xf8, 0xf2 },
  comment = { 0x62, 0x72, 0xa4 },
  cyan    = { 0x8b, 0xe9, 0xfd },
  green   = { 0x50, 0xfa, 0x7b },
  orange  = { 0xff, 0xb8, 0x6c },
  pink    = { 0xff, 0x79, 0xc6 },
  purple  = { 0xbd, 0x93, 0xf9 },
  red     = { 0xff, 0x55, 0x55 },
  yellow  = { 0xf1, 0xfa, 0x8c },
}

function W.rgb(name, alpha)
  local c = W.colors[name]
  return c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1
end

function W.hex(name, text)
  local c = W.colors[name]
  return string.format("|cff%02x%02x%02x%s|r", c[1], c[2], c[3], text)
end

W.DEFAULTS = {
  schema = 1,
  price = 10000,          -- copper per summon (1g); /sw price
  prices = {},            -- destination key -> copper override
  dest = nil,             -- destination key used in ads and replies
  lockName = nil,         -- warlock name, for advertiser ads (synced when grouped)
  service = true,         -- warlock: auto-reply + auto-invite people who whisper a request
  maxQueue = 30,          -- queue cap for new customers (0 = no cap); a raid holds 40
  plainMode = false,      -- short serious messages instead of the SummonSir lines
  bigButton = true,       -- warlock: the big Summon Next button
  bigScale = 1,
  msg = {},               -- message type -> { mode, line, custom } (messages.lua)
  graceMinutes = 10,      -- unpaid this long after arriving = never paid
  autoBlock = true,       -- block never-paid customers automatically
  autoBlockHours = 24,
  alertSound = true,      -- clicker banner plays a sound
  adChannel = "Services",
  adTemplate = "Summons to {dest} for {price}, sir! /w {lock} 123, then sit back and relax!",
  replyText = "Right away, sir! Summon to {dest} is {price}. Invite sent! Accept the summon within 2 min and pay by trade when you land!",
  wrongDestText = "So sorry, sir! I'm summoning to {dest} right now, not {asked}!",
  advertiserReplyText = "Right this way, sir! Whisper {lock} \"123\" for a summon to {dest} ({price})!",
  summons = {},           -- { id, name, t, dest, price, arrived, paid, paidAmount, paidAt, nonPayer }
  payments = {},          -- { name, t, amount, summonId }
  blocklist = {},         -- name -> { untilT, at, reason }
  chars = {},             -- character name -> { role }
}

-- earlier stock wording: saved texts that still match get the new defaults
W.STOCK = {
  adTemplate = "{dest} summons {price}! /w {lock} 123",
  replyText = "Summon to {dest}: {price}. Invite sent, accept the summon within 2 min. Pay by trade on arrival.",
  wrongDestText = "Sorry, I'm summoning to {dest} right now, not {asked}.",
  advertiserReplyText = "Whisper {lock} \"123\" for a summon to {dest} ({price}).",
}

function W.upgradeStock(db)
  for k, old in pairs(W.STOCK) do
    if db[k] == old then db[k] = W.DEFAULTS[k] end
  end
  return db
end

-- fill missing keys (one level deep) without touching saved values
function W.applyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      if type(v) == "table" then
        local copy = {}
        for k2, v2 in pairs(v) do copy[k2] = v2 end
        db[k] = copy
      else
        db[k] = v
      end
    end
  end
  return db
end

---------------------------------
-- time, names, text
---------------------------------
W.clock = function() return time() end -- tests replace this

function W.now()
  return W.clock()
end

function W.shortName(name)
  if not name then return nil end
  if addonData.util and addonData.util.shortName then
    return addonData.util:shortName(name)
  end
  return (strsplit("-", name))
end

function W.me()
  if addonData.util and addonData.util.playerFullName then
    return addonData.util:playerFullName()
  end
  return UnitName("player")
end

-- "{key}" placeholders; unknown keys are left as typed
function W.fill(template, vars)
  return (string.gsub(template or "", "{(%w+)}", function(key)
    local v = vars[key]
    if v == nil then return "{" .. key .. "}" end
    return tostring(v)
  end))
end

-- Forever lists only C_ChatInfo.SendChatMessage (a shim covers the bare name too)
local SendChatMessage = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

-- a whisper to someone who contacted us first (never a cold whisper)
function W.whisper(player, msg)
  if player and msg and msg ~= "" then SendChatMessage(msg, "WHISPER", nil, player) end
end

-- soul shards in all bags (the reagent-slot soul bag included)
function W.countShards()
  local n = 0
  for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4) do
    for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
      if C_Container.GetContainerItemID(bag, slot) == 6265 then n = n + 1 end
    end
  end
  return n
end

function W.print(...)
  print(W.hex("purple", "Warlock:"), ...)
end

---------------------------------
-- money
---------------------------------
function W.fmtMoney(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g = math.floor(copper / 10000)
  local s = math.floor((copper % 10000) / 100)
  local c = copper % 100
  local parts = {}
  if g > 0 then table.insert(parts, g .. "g") end
  if s > 0 then table.insert(parts, s .. "s") end
  if c > 0 or #parts == 0 then table.insert(parts, c .. "c") end
  return table.concat(parts, " ")
end

-- "1g", "80s", "1g50s", "1g 50s", "1.5g", "150s", "25c", "10000" (copper)
function W.parseMoney(text)
  if not text then return nil end
  text = string.lower(string.gsub(text, "%s+", ""))
  if text == "" then return nil end
  if string.match(text, "^%d+$") then
    return tonumber(text)
  end
  local total, matched = 0, ""
  for num, unit in string.gmatch(text, "([%d%.]+)([gsc])") do
    local n = tonumber(num)
    if not n then return nil end
    local mult = (unit == "g" and 10000) or (unit == "s" and 100) or 1
    total = total + n * mult
    matched = matched .. num .. unit
  end
  if matched ~= text then return nil end
  return math.floor(total + 0.5)
end

---------------------------------
-- roles
---------------------------------
W.ROLES = { warlock = true, clicker = true, advertiser = true }

function W.role()
  local me = W.me()
  local c = W.db and W.db.chars[me]
  if c and c.role then return c.role end
  if addonData.util and addonData.util.playerIsWarlock and addonData.util:playerIsWarlock() then
    return "warlock"
  end
  return "clicker"
end

function W.setRole(role)
  local me = W.me()
  W.db.chars[me] = W.db.chars[me] or {}
  W.db.chars[me].role = role
  W.fire("ROLE_CHANGED", role)
end

---------------------------------
-- price + destination lookups shared by replies, ads and the ledger
---------------------------------
function W.priceFor(destKey)
  if destKey and W.db.prices[destKey] then
    return W.db.prices[destKey]
  end
  return W.db.price
end

function W.destName()
  local p = addonData.destinations and addonData.destinations.byKey(W.db.dest)
  if p then return p.name end
  local zone = GetZoneText and GetZoneText() or ""
  if zone ~= "" then return zone end
  return "here"
end

function W.lockName()
  if W.role() == "warlock" then return W.me() end
  return W.db.lockName or "me"
end

function W.vars(extra)
  local v = {
    dest = W.destName(),
    price = W.fmtMoney(W.priceFor(W.db.dest)),
    lock = W.lockName(),
  }
  for k, val in pairs(extra or {}) do v[k] = val end
  return v
end

---------------------------------
-- module + event plumbing
---------------------------------
function W.module(name, mod)
  W[name] = mod
  addonData[name] = mod
  table.insert(W.modules, mod)
  return mod
end

function W.on(event, fn)
  if not W.handlers[event] then
    W.handlers[event] = {}
    if W.frame and event ~= "ADDON_LOADED" then
      pcall(W.frame.RegisterEvent, W.frame, event)
    end
  end
  table.insert(W.handlers[event], fn)
end

-- internal events (ROLE_CHANGED, CONFIG_CHANGED) share the same table
function W.fire(event, ...)
  local list = W.handlers[event]
  if not list then return end
  for _, fn in ipairs(list) do
    local ok, err = pcall(fn, ...)
    if not ok then W.print("error in", event, err) end
  end
end

function W.command(name, help, fn)
  W.commands[name] = fn
  if help then table.insert(W.helpLines, "/sw " .. help) end
end

function W.slash(msg)
  msg = msg or ""
  local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" then cmd = "stats" end
  local fn = W.commands[cmd]
  if fn then
    fn(rest or "")
  else
    W.print("commands:")
    for _, line in ipairs(W.helpLines) do print("  " .. line) end
  end
end

local function onLoaded(name)
  if name ~= addonName then return end
  SteaWarlockDB = W.upgradeStock(W.applyDefaults(SteaWarlockDB or {}, W.DEFAULTS))
  W.db = SteaWarlockDB
  for _, mod in ipairs(W.modules) do
    if mod.init then
      local ok, err = pcall(mod.init, mod)
      if not ok then W.print("init failed:", err) end
    end
  end
  SLASH_STEAWARLOCK1 = "/sw"
  SlashCmdList["STEAWARLOCK"] = W.slash
  W.loaded = true
  W.fire("WARLOCK_READY")
end

function W.start()
  W.frame = CreateFrame("Frame")
  W.frame:RegisterEvent("ADDON_LOADED")
  for event in pairs(W.handlers) do
    if event ~= "ADDON_LOADED" then pcall(W.frame.RegisterEvent, W.frame, event) end
  end
  W.frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
      onLoaded(...)
      return
    end
    if W.loaded then W.fire(event, ...) end
  end)
end

---------------------------------
-- hooks called from the upstream files (one line each there)
---------------------------------
-- a Ritual of Summoning finished and used a shard (summon.lua summonSuccess)
function W.summonCast(player)
  if not W.loaded or not player or player == "" then return end
  W.fire("SUMMON_CAST", W.shortName(player))
end

-- someone left the queue by arriving, not by cancelling (summon.lua arrived)
function W.summonArrived(player)
  if not W.loaded or not player then return end
  W.fire("SUMMON_ARRIVED", W.shortName(player))
end

-- portal channel started / ended on this warlock (summon.lua castWatch)
function W.portalUp(player)
  if not W.loaded then return end
  W.fire("PORTAL_UP", W.shortName(player or ""))
end

function W.portalDown()
  if not W.loaded then return end
  W.fire("PORTAL_DOWN")
end

-- chat.lua callback: true = handled here, upstream must stop
function W.onChat(event, msg, player)
  if not W.loaded or not W.service then return false end
  local ok, handled = pcall(W.service.onChat, W.service, event, msg, W.shortName(player))
  if not ok then
    W.print("chat hook error:", handled)
    return false
  end
  return handled and true or false
end

-- summon.lua addWaiting (runs on the queue leader only): someone joined the queue
function W.queueAdded(player)
  if not W.loaded or not player then return end
  W.fire("QUEUE_ADDED", W.shortName(player))
end

-- gossip.lua add (leader side): false = refuse this player
function W.allowAdd(player)
  if not W.loaded or not W.blocklist then return true end
  return not W.blocklist:isBlocked(W.shortName(player))
end
