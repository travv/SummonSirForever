-- The sales loop on whispers: blocklist gate, auto-reply, invite, queue on join,
-- wrong-destination reply, advertiser redirect, and the pending watchdog.
-- Only people who whispered first get a whisper back. No cold whispers.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local InviteUnit = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
local ConvertToRaid = (C_PartyInfo and C_PartyInfo.ConvertToRaid) or ConvertToRaid
-- Forever lists only C_ChatInfo.SendChatMessage (same arguments)
local SendChatMessage = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

local V = {
  pendingJoin = {},  -- name -> time invited
  replied = {},      -- name..kind -> time of last auto-reply
  pendingSince = {}, -- name -> GetTime() a row went "pending"
  JOIN_WINDOW = 180,
  REPLY_EVERY = 600,
  SERVED_WINDOW = 15 * 60,
  PENDING_TIMEOUT = 15,
}

function V:inGroup(name)
  return (UnitInParty(name) or UnitInRaid(name)) and true or false
end

-- whisper back at most once per REPLY_EVERY per kind of reply
function V:replyOnce(player, kind, template, extra, now)
  now = now or W.now()
  local key = player .. "|" .. kind
  if self.replied[key] and now - self.replied[key] < self.REPLY_EVERY then return false end
  self.replied[key] = now
  local msg = W.fill(template, W.vars(extra))
  if msg ~= "" then SendChatMessage(msg, "WHISPER", nil, player) end
  return true
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

function V:invite(player)
  self.pendingJoin[player] = W.now()
  if not IsInRaid() and GetNumGroupMembers() >= 5 and UnitIsGroupLeader("player") then
    ConvertToRaid()
    C_Timer.After(1, function() InviteUnit(player) end)
  else
    InviteUnit(player)
  end
end

-- true = handled, upstream chat.lua stops
function V:onChat(event, msg, player)
  if not player or player == W.me() or not msg then return false end

  if W.blocklist:isBlocked(player) then
    return true -- silent on every channel: no reply, no invite, no queue
  end
  if event ~= "CHAT_MSG_WHISPER" then return false end

  local role = W.role()
  local isReq, asked = self:classify(msg)
  if not isReq then return false end

  if role == "advertiser" then
    self:replyOnce(player, "adv", W.db.advertiserReplyText)
    return true
  end
  if role ~= "warlock" or not W.db.service then return false end

  if asked and W.db.dest and asked.key ~= W.db.dest then
    self:replyOnce(player, "wrong", W.db.wrongDestText, { asked = asked.name })
    return true
  end

  if self:recentlyServed(player) then
    return true -- just arrived: "summon pls thx" again is not a new order
  end

  if self:inGroup(player) then
    if addonData.settings:findSummonWord(msg) then
      return false -- an exact phrase: upstream queues it as before
    end
    addonData.gossip:add(player, true) -- loose phrase upstream would miss
    return true
  end

  if addonData.summon.afk then return false end -- upstream sends the AFK reply

  self:replyOnce(player, "price", W.db.replyText)
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
end

W.module("service", V)

function V:init()
  W.on("GROUP_ROSTER_UPDATE", function()
    C_Timer.After(1, function() V:checkJoins() end) -- unit info lags the roster event
  end)
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

  W.command("price", "price <80s|1g|1g50s> [destination]", function(args)
    local amt, destText = string.match(args, "^(%S+)%s*(.-)$")
    local copper = W.parseMoney(amt)
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
    W.print("service replies:", W.db.service and "on" or "off")
  end)

  W.command("reply", "reply <text>: the whisper new customers get", function(args)
    if args ~= "" then W.db.replyText = args end
    W.print("reply:", W.fill(W.db.replyText, W.vars()))
  end)
end

addonData.service = V
