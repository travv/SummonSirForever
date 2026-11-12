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

-- Color names used across the modules, mapped to the game's standard font
-- colors so every panel reads like a stock Forever window (decision 2026-11-11:
-- default styling, not Dracula). Keep the names; change values here only.
W.colors = {
  bg      = { 0x00, 0x00, 0x00 },  -- tooltip backdrop black
  line    = { 0x40, 0x40, 0x40 },  -- row stripes
  fg      = { 0xff, 0xff, 0xff },  -- HIGHLIGHT_FONT_COLOR
  comment = { 0x80, 0x80, 0x80 },  -- GRAY_FONT_COLOR (disabled / hints)
  cyan    = { 0x82, 0xc5, 0xff },  -- BATTLENET_FONT_COLOR (section headings)
  green   = { 0x1a, 0xff, 0x1a },  -- GREEN_FONT_COLOR
  orange  = { 0xff, 0x80, 0x40 },  -- ORANGE_FONT_COLOR (warnings)
  pink    = { 0xa3, 0x35, 0xee },  -- epic purple (rare accents)
  purple  = { 0x87, 0x88, 0xee },  -- Warlock class color (titles)
  red     = { 0xff, 0x20, 0x20 },  -- RED_FONT_COLOR
  yellow  = { 0xff, 0xd2, 0x00 },  -- NORMAL_FONT_COLOR gold (money, keys)
}

function W.rgb(name, alpha)
  local c = W.colors[name]
  return c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1
end

-- the stock tooltip backdrop: dark, bordered, what most addons' floating
-- panels look like. border = optional color name for the edge
function W.stockBackdrop(frame, border, alpha)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
  })
  frame:SetBackdropColor(0, 0, 0, alpha or 0.85)
  if border then
    frame:SetBackdropBorderColor(W.rgb(border))
  else
    frame:SetBackdropBorderColor(1, 1, 1)
  end
end

-- a template's child frame by key, or nil when the template lacks it
function W.child(frame, key)
  local c = frame and frame[key]
  if type(c) == "table" then return c end
  return nil
end

-- a stock window with a title bar, close button and inset (ButtonFrameTemplate)
function W.stockWindow(name, parent, width, height, title, portraitIcon)
  local f = CreateFrame("Frame", name, parent or UIParent, "ButtonFrameTemplate")
  f:SetSize(width, height)
  local titleBox = W.child(f, "TitleContainer")
  if titleBox and W.child(titleBox, "TitleText") then
    titleBox.TitleText:SetText(title or "")
  end
  local portraitBox = W.child(f, "PortraitContainer")
  if portraitIcon and portraitBox and W.child(portraitBox, "portrait") then
    portraitBox.portrait:SetTexture(portraitIcon)
  elseif ButtonFrameTemplate_HidePortrait then
    ButtonFrameTemplate_HidePortrait(f)
  end
  f:SetMovable(true)
  f:EnableMouse(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  return f
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
  offlineMinutes = 5,     -- warlock: a queued customer offline this long is dropped (0 = keep)
  autoBlock = true,       -- block never-paid customers automatically
  autoBlockHours = 24,
  alertSound = true,      -- clicker banner plays a sound
  soundJoin = true,       -- warlock: ping when someone lands in the queue
  soundPaid = true,       -- coin sound when a payment is recorded
  adChannel = "Services",  -- (pre-w9 single channel; adChannels replaces it)
  adChannels = "1, 2, 8",  -- channel numbers or names; one click posts the ad to each
  adTemplate = "WTS summon {dest} {price}. Come get your flight path or quest turn-ins! PST \"inv\" {spell}",
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
  adTemplate = {
    "{dest} summons {price}! /w {lock} 123",
    "Summons to {dest} for {price}, sir! /w {lock} 123, then sit back and relax!",
  },
  replyText = "Summon to {dest}: {price}. Invite sent, accept the summon within 2 min. Pay by trade on arrival.",
  wrongDestText = "Sorry, I'm summoning to {dest} right now, not {asked}.",
  advertiserReplyText = "Whisper {lock} \"123\" for a summon to {dest} ({price}).",
}

function W.upgradeStock(db)
  for k, old in pairs(W.STOCK) do
    local olds = type(old) == "table" and old or { old }
    for _, o in ipairs(olds) do
      if db[k] == o then db[k] = W.DEFAULTS[k] end
    end
  end
  -- a customized single ad channel carries over as the channel list
  if not db.adChannelsMigrated then
    if db.adChannel and db.adChannel ~= "" and db.adChannel ~= "Services" then
      db.adChannels = db.adChannel
    end
    db.adChannelsMigrated = true
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
  print(W.hex("purple", "SummonSir:"), ...)
end

-- a stock UI sound, by SOUNDKIT name with the numeric fallback, gated by a
-- W.db toggle (nil toggle = always)
function W.playSound(kitName, fallbackId, setting)
  if setting and W.db and W.db[setting] == false then return false end
  pcall(PlaySound, (SOUNDKIT and SOUNDKIT[kitName]) or fallbackId, "Master")
  return true
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

-- what a person types into a price box: a bare number is gold ("1" = 1g),
-- "1g50" is 1g 50s; everything parseMoney takes still works
function W.parseMoneyUser(text)
  if not text then return nil end
  local t = string.lower(string.gsub(text, "%s+", ""))
  if t == "" then return nil end
  if string.match(t, "^%d+%.?%d*$") then
    return math.floor(tonumber(t) * 10000 + 0.5)
  end
  local g, s = string.match(t, "^(%d+)g(%d+)$")
  if g then return tonumber(g) * 10000 + tonumber(s) * 100 end
  return W.parseMoney(t)
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
  -- an advertiser quotes whatever the main warlock charges
  if W.role() == "advertiser" and W.db.remotePrice then
    return W.db.remotePrice
  end
  if destKey and W.db.prices[destKey] then
    return W.db.prices[destKey]
  end
  return W.db.price
end

-- where summons go. Warlock: the preset you picked, else the destination
-- set on the summon window, else the zone you're standing in.
-- Advertiser: always the main warlock's answer (synced), never its own city.
function W.destName()
  if W.role() == "advertiser" then
    if W.db.remoteDest and W.db.remoteDest ~= "" then return W.db.remoteDest end
    local p = addonData.destinations and addonData.destinations.byKey(W.db.dest)
    return p and p.name or "?"
  end
  local p = addonData.destinations and addonData.destinations.byKey(W.db.dest)
  if p then return p.name end
  local S = addonData.summon
  if S and S.zone and S.zone ~= "" then return S.zone end
  local zone = GetZoneText and GetZoneText() or ""
  if zone ~= "" then return zone end
  return "here"
end

-- preset key for the current destination (typed preset, else matched from the zone)
function W.destKey()
  if W.db.dest then return W.db.dest end
  local D = addonData.destinations
  local m = D and D.match(W.destName())
  return m and m.key or nil
end

-- clickable [Ritual of Summoning] link for ads
function W.spellLink()
  local link = C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(698)
  if link and link ~= "" then return link end
  return "\124cff71d5ff\124Hspell:698\124h[Ritual of Summoning]\124h\124r"
end

function W.lockName()
  if W.role() == "warlock" then return W.me() end
  return W.db.lockName or "me"
end

function W.vars(extra)
  local v = {
    dest = W.destName(),
    price = W.fmtMoney(W.priceFor(W.destKey())),
    lock = W.lockName(),
    spell = W.spellLink(),
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

function W.help()
  W.print("commands (bare /sw opens the ledger):")
  for _, line in ipairs(W.helpLines) do print("  " .. line) end
end
W.command("help", "help: this list", W.help)

function W.slash(msg)
  msg = msg or ""
  local cmd, rest = string.match(msg, "^%s*(%S*)%s*(.-)%s*$")
  cmd = string.lower(cmd or "")
  if cmd == "" then cmd = "stats" end
  local fn = W.commands[cmd]
  if fn then
    fn(rest or "")
  else
    W.print("no such command:", cmd)
    W.help()
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
