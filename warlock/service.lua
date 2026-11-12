-- The sales loop on whispers: blocklist gate, first reply + invite, queue on
-- join, place in line, queue cap, already-here, wrong destination, advertiser
-- redirect, out-of-shards warning, summon-complete reminder, pending watchdog.
-- Only people who whispered (or asked in group chat) get a whisper back.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local InviteUnit = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local ConvertToRaid = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid

local V = {
  pendingJoin = {},  -- name -> time invited
  pendingSince = {}, -- name -> GetTime() a row went "pending"
  offlineSince = {}, -- name -> GetTime() a row went "offline"
  shardWarned = {},  -- name -> true once told we're out of shards
  outOfShards = false,
  JOIN_WINDOW = 180,
  REPLY_EVERY = 600,
  POSITION_EVERY = 45,
  SERVED_WINDOW = 15 * 60,
  PENDING_TIMEOUT = 15,
}

local function M() return W.messages end

function V:inGroup(name)
  return (UnitInParty(name) or UnitInRaid(name)) and true or false
end

function V:isInviteWord(msg)
  local norm = W.destinations.normalize(msg)
  for _, v in pairs(SteaSummonSave and SteaSummonSave.autoInviteTriggers or {}) do
    if W.destinations.normalize(v) == norm then return true end
  end
  return false
end

-- "tb?", "org pls", "summon to tb": a short message naming a place counts too
function V:classify(msg)
  local D = W.destinations
  local asked = D.match(msg)
  local isReq = D.isSummonRequest(msg) or self:isInviteWord(msg)
  if not isReq and asked and #D.tokens(D.normalize(msg)) <= 3 then isReq = true end
  return isReq, asked
end

function V:recentlyServed(player, now)
  now = now or W.now()
  return W.ledger:findSummon(player, now, self.SERVED_WINDOW, function(s) return s.arrived end) ~= nil
end

-- queue position from the shared list: 1 = next
function V:position(player)
  local S = addonData.summon
  local idx = S and S:findWaitingPlayerIdx(player)
  return idx
end

function V:sendPosition(player, every)
  local pos = self:position(player)
  if not pos then return false end
  return M():send(player, "position", { pos = pos, ahead = pos - 1 }, every or self.POSITION_EVERY)
end

-- waiting + invited-but-not-joined, against the cap
function V:queueFull()
  local cap = W.db.maxQueue or 0
  if cap <= 0 then return false end
  local n = addonData.summon and addonData.summon.numwaiting or 0
  local now = W.now()
  for _, t in pairs(self.pendingJoin) do
    if now - t <= self.JOIN_WINDOW then n = n + 1 end
  end
  return n >= cap
end

function V:invite(player)
  self.pendingJoin[player] = W.now()
  if not IsInRaid() and GetNumGroupMembers() >= 5 and UnitIsGroupLeader("player") then
    ConvertToRaid()
    C_Timer.After(1, function() InviteUnit(player) end)
  else
    InviteUnit(player)
  end
end

function V:isNearby(player)
  local util = addonData.util
  return util and util.playerClose and util:playerClose(player) and true or false
end

function V:blockedNotice(player, entry, now)
  now = now or W.now()
  self.blockedTold = self.blockedTold or {}
  if self.blockedTold[player] and now - self.blockedTold[player] < self.REPLY_EVERY then return false end
  self.blockedTold[player] = now
  local left = ""
  if entry and entry.untilT and W.stats and W.stats.duration then
    left = ", " .. W.stats.duration(entry.untilT - now) .. " left"
  end
  W.print(W.hex("comment", "ignored " .. player .. " (blocked" .. (entry and entry.reason and (": " .. entry.reason) or "") .. left .. ")"))
  return true
end

-- true = handled, upstream chat.lua stops
function V:onChat(event, msg, player)
  if not player or player == W.me() or not msg then return false end

  local blocked, entry = W.blocklist:isBlocked(player)
  if blocked then
    -- no reply, no invite, no queue; one dim chat line per name every 10 min
    -- so the operator knows why a whisper went unanswered
    if event == "CHAT_MSG_WHISPER" then self:blockedNotice(player, entry) end
    return true
  end
  if event ~= "CHAT_MSG_WHISPER" then return false end

  local role = W.role()
  local isReq, asked = self:classify(msg)
  if not isReq then return false end

  if role == "advertiser" then
    return self:advertiserRequest(player, asked)
  end
  if role ~= "warlock" or not W.db.service then return false end

  if asked and W.db.dest and asked.key ~= W.db.dest then
    M():send(player, "wrongdest", { asked = asked.name }, self.REPLY_EVERY)
    return true
  end

  if self:recentlyServed(player) then
    return true -- just arrived: "summon pls thx" again is not a new order
  end

  if self:inGroup(player) then
    if self:position(player) then
      self:sendPosition(player) -- asking again: tell them where they stand
      return false -- upstream resets a failed summon back to "requested"
    end
    if self:isNearby(player) then
      M():send(player, "nearby", nil, self.REPLY_EVERY)
      return true
    end
    if self:queueFull() then
      M():send(player, "full", nil, 120)
      return true
    end
    if addonData.settings:findSummonWord(msg) then
      return false -- an exact phrase: upstream queues it as before
    end
    addonData.gossip:add(player, true) -- loose phrase upstream would miss
    return true
  end

  if addonData.summon.afk then return false end -- upstream sends the AFK reply

  if self.pendingJoin[player] then
    return true -- already invited, the reply went out
  end
  if self:queueFull() then
    M():send(player, "full", nil, 120)
    return true
  end

  M():send(player, "queued", nil, self.REPLY_EVERY)
  self:invite(player)
  return true
end

-- advertiser with invite rights in the warlock's group: reply, invite, and
-- queue them with the warlock once they join. Otherwise point them at the warlock.
function V:canInvite()
  if not IsInGroup() then return false end
  local ok, can = pcall(C_PartyInfo.CanInvite)
  return ok and can and true or false
end

function V:advertiserRequest(player, asked)
  local destKey = W.destKey()
  if asked and destKey and asked.key ~= destKey then
    M():send(player, "wrongdest", { asked = asked.name }, self.REPLY_EVERY)
    return true
  end
  if not W.db.service or not self:canInvite() then
    M():send(player, "advertiser", nil, self.REPLY_EVERY)
    return true
  end
  if self:inGroup(player) then
    if not self:position(player) then addonData.gossip:add(player, true) end
    return true
  end
  if self.pendingJoin[player] then return true end
  if self:queueFull() then
    M():send(player, "full", nil, 120)
    return true
  end
  M():send(player, "queued", nil, self.REPLY_EVERY)
  self:invite(player)
  return true
end

-- invited people get queued as soon as they show up in the group
function V:checkJoins()
  local now = W.now()
  for name, t in pairs(self.pendingJoin) do
    if now - t > self.JOIN_WINDOW then
      self.pendingJoin[name] = nil
    elseif self:inGroup(name) then
      self.pendingJoin[name] = nil
      if not W.blocklist:isBlocked(name) then addonData.gossip:add(name, true) end
    end
  end
end

-- a row stuck on "pending" with no cast going (the macro bailed: out of
-- range, no line of sight) goes back to "requested" so Next offers it again
function V:watchdog()
  local summon = addonData.summon
  if not summon or not summon.waiting then return end
  local now = GetTime()
  local seen = {}
  for _, rec in ipairs(summon.waiting) do
    local name, status = rec[1], rec[3]
    if status == "pending" and name == summon.summoningPlayer and not summon.isCasting then
      seen[name] = true
      self.pendingSince[name] = self.pendingSince[name] or now
      if now - self.pendingSince[name] >= self.PENDING_TIMEOUT then
        self.pendingSince[name] = nil
        addonData.gossip:status(name, "requested")
      end
    end
  end
  for name in pairs(self.pendingSince) do
    if not seen[name] then self.pendingSince[name] = nil end
  end
  self:dropGone(summon, now)
end

-- Customers who logged off or left the group used to sit in the queue
-- forever ("offline", 1 hr) because only a warlock at the destination had an
-- X. Left the group = gone now; offline = gone after offlineMinutes.
function V:dropGone(summon, now)
  local limit = (W.db.offlineMinutes or 0) * 60
  local drop = {}
  local stillOffline = {}
  for _, rec in ipairs(summon.waiting) do
    local name, status = rec[1], rec[3]
    if name ~= W.me() then
      if IsInGroup(LE_PARTY_CATEGORY_HOME) and not self:inGroup(name) then
        table.insert(drop, { name, "left the group" })
      elseif status == "offline" and limit > 0 then
        stillOffline[name] = true
        self.offlineSince[name] = self.offlineSince[name] or now
        if now - self.offlineSince[name] >= limit then
          table.insert(drop, { name, "offline " .. W.db.offlineMinutes .. " min" })
        end
      end
    end
  end
  for name in pairs(self.offlineSince) do
    if not stillOffline[name] then self.offlineSince[name] = nil end
  end
  for _, d in ipairs(drop) do
    self.offlineSince[d[1]] = nil
    W.print("dropped", d[1], "from the queue:", d[2])
    addonData.gossip:arrived(d[1], true)
  end
end

-- out of shards: tell the warlock once, and the next person in line once
function V:shardCheck(count)
  local summon = addonData.summon
  if count > 0 then
    if self.outOfShards then W.print(W.hex("green", "soul shards restocked:"), count) end
    self.outOfShards = false
    wipe(self.shardWarned)
    return
  end
  if not self.outOfShards then
    self.outOfShards = true
    W.print(W.hex("red", "out of soul shards!"))
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
  local nextRec = summon and summon.firstRequested and summon:firstRequested()
  local name = nextRec and nextRec[1]
  if name and not self.shardWarned[name] then
    self.shardWarned[name] = true
    M():send(name, "noshards", nil, 300)
  end
end

-- arrived and not yet paid: the summon-complete line doubles as the payment reminder
function V:onArrived(name, now)
  now = now or W.now()
  local s = W.ledger:findSummon(name, now, 600, function(r) return r.arrived and not r.completeSent end)
  if not s then return false end
  s.completeSent = true
  if s.paid then return false end
  return M():send(name, "complete", { price = W.fmtMoney(s.price or W.priceFor(s.dest)) }, 0, now)
end

W.module("service", V)

function V:init()
  W.on("GROUP_ROSTER_UPDATE", function()
    C_Timer.After(1, function() V:checkJoins() end) -- unit info lags the roster event
  end)
  W.on("QUEUE_ADDED", function(name)
    if W.role() == "warlock" then
      W.playSound("IG_PLAYER_INVITE", 880, "soundJoin") -- a customer landed in the queue
      C_Timer.After(0.5, function() V:sendPosition(name, 0) end)
    end
  end)
  W.on("SUMMON_ARRIVED", function(name)
    if W.role() == "warlock" then V:onArrived(name) end
  end)
  local function shards()
    if W.role() == "warlock" and addonData.summon and addonData.summon.isWarlock then
      V:shardCheck(W.countShards())
    end
  end
  W.on("BAG_UPDATE_DELAYED", shards)
  W.on("QUEUE_ADDED", function() C_Timer.After(1, shards) end)
  C_Timer.NewTicker(1, function()
    if W.role() == "warlock" then V:watchdog() end
  end)

  W.command("role", "role warlock|clicker|advertiser: what this window does", function(args)
    args = string.lower(args)
    if args ~= "" then
      if not W.ROLES[args] then W.print("roles: warlock, clicker, advertiser") return end
      W.setRole(args)
    end
    W.print("role:", W.role())
  end)

  W.command("price", "price <1g|80s|1g50s|1> [destination]: a bare number is gold", function(args)
    local amt, destText = string.match(args, "^(%S+)%s*(.-)$")
    local copper = W.parseMoneyUser(amt)
    if not copper then
      W.print("price:", W.fmtMoney(W.priceFor(W.db.dest)), "(usage: /sw price 1g [tb])")
      return
    end
    if destText and destText ~= "" then
      local p = W.destinations.match(destText)
      if not p then W.print("no preset matches", destText) return end
      W.db.prices[p.key] = copper
      W.print("price for", p.name, W.fmtMoney(copper))
    else
      W.db.price = copper
      W.print("price:", W.fmtMoney(copper))
    end
    W.fire("CONFIG_CHANGED")
  end)

  W.command("service", "service on|off: auto-reply and invite people who whisper", function(args)
    if args == "on" then W.db.service = true elseif args == "off" then W.db.service = false end
    W.print("auto-reply and invite:", W.db.service and "on" or "off")
  end)

  W.command("cap", "cap <n>: queue cap for new customers (0 = none)", function(args)
    local n = tonumber(args)
    if n then W.db.maxQueue = math.max(0, math.floor(n)) end
    W.print("queue cap:", W.db.maxQueue == 0 and "none" or W.db.maxQueue)
    W.fire("CONFIG_CHANGED")
  end)
end

addonData.service = V
