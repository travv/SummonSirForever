-- Customer messages: 8 reply types, 5 SummonSir lines each plus a plain line.
-- House style (Travis, 2026-11-12): brief, "sir" once, no theatrics. The first
-- reply is off by default (Travis, 2026-11-12): the invite popup is the
-- notification, and the ad already quoted the price. It stays available.
-- Each type can be random, a fixed line, custom text, or off. Plain mode swaps
-- every type to its short serious line.
-- Placeholders: {dest} {price} {lock} {asked} {pos} {ahead} {max}
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local M = {
  last = {},     -- type -> index of the line used last (random avoids repeats)
  sentAt = {},   -- player|type -> time
}

M.ORDER = { "queued", "position", "full", "nearby", "wrongdest", "complete", "noshards", "advertiser" }

M.TYPES = {
  queued = {
    label = "First reply (off by default: the invite is the notification)",
    defaultMode = "off",
    lines = {
      "Invite sent, sir. Accept it, take the summon when it pops, and trade me on arrival.",
      "You're invited, sir. Take the summon when it pops; pay by trade when you land.",
      "On it, sir. Accept the invite, then the summon, and trade me at {dest}.",
      "Invite's out, sir. Accept the summon when it pops and pay by trade on arrival.",
      "Sure thing, sir. Accept the invite and the summon; trade me when you land.",
    },
    plain = "Invite sent. Accept it and take the summon when it pops. Pay by trade on arrival.",
  },
  position = {
    label = "Place in line (on joining, and when they ask again)",
    lines = {
      "You're #{pos} in line, sir.",
      "#{pos} in line, sir, {ahead} ahead of you.",
      "Noted, sir. You're #{pos}.",
      "You're in, sir. #{pos} in the queue.",
      "#{pos}, sir. Won't be long.",
    },
    plain = "You're #{pos} in the queue.",
  },
  full = {
    label = "Queue is full",
    lines = {
      "Queue's full right now, sir. Try again in a few minutes.",
      "Sorry, sir, we're full. Whisper me again shortly.",
      "No room just now, sir. Back in a few minutes.",
      "Full at the moment, sir. Give it a few minutes.",
      "Packed right now, sir. Try again shortly.",
    },
    plain = "The queue is full. Try again in a few minutes.",
  },
  nearby = {
    label = "Already here",
    lines = {
      "You're already here, sir.",
      "You've already arrived, sir.",
      "You're at {dest} already, sir.",
      "No summon needed, sir, you're here.",
      "Already here, sir. Enjoy {dest}.",
    },
    plain = "You're already here, no summon needed.",
  },
  wrongdest = {
    label = "Asked for a different place",
    lines = {
      "Sorry, sir, I'm summoning to {dest} right now, not {asked}.",
      "{dest} only right now, sir, not {asked}.",
      "Not {asked} today, sir. I'm set up at {dest}.",
      "I'm at {dest} right now, sir, no {asked} summons.",
      "Sorry, sir. {dest} only at the moment.",
    },
    plain = "Summoning to {dest} right now, not {asked}.",
  },
  complete = {
    label = "Arrival reminder (off by default: customers expect to trade on arrival)",
    defaultMode = "off",
    lines = {
      "Welcome to {dest}, sir. That's {price}, trade me when you're ready.",
      "You made it, sir. {price} by trade when you have a moment.",
      "There you go, sir. {price} by trade, thanks.",
      "Delivered, sir. Trade me {price} whenever you're set.",
      "Enjoy {dest}, sir. {price} by trade, please.",
    },
    plain = "Summon complete. Please trade {price}.",
  },
  noshards = {
    label = "Out of soul shards (to the next in line)",
    lines = {
      "Out of soul shards, sir. Hang tight, you're next.",
      "Short delay, sir, restocking shards. You're still next.",
      "One moment, sir. Out of shards, your spot is safe.",
      "Need a shard first, sir. Back in a moment.",
      "Shards ran dry, sir. You're next as soon as I have one.",
    },
    plain = "Out of soul shards. You're still next, back shortly.",
  },
  advertiser = {
    label = "Advertiser's reply (points them at the warlock)",
    lines = {
      "Whisper {lock} \"123\" for a summon to {dest}, sir ({price}).",
      "{lock} does the summoning, sir. Whisper them \"123\" for {dest} ({price}).",
      "Send {lock} a \"123\", sir, and you're off to {dest} for {price}.",
      "For {dest}, sir, whisper {lock} \"123\". {price}.",
      "{lock} will get you there, sir. Whisper \"123\" ({price}).",
    },
    plain = "Whisper {lock} \"123\" for a summon to {dest} ({price}).",
  },
}

-- per-type setting: { mode = "random" | "fixed" | "custom" | "off", line = n, custom = text }
function M:setting(kind)
  W.db.msg = W.db.msg or {}
  local t = M.TYPES[kind]
  W.db.msg[kind] = W.db.msg[kind] or { mode = (t and t.defaultMode) or "random", line = 1, custom = "" }
  return W.db.msg[kind]
end

-- the template that would be used, before placeholders (nil = off)
function M:template(kind)
  local t = M.TYPES[kind]
  if not t then return nil end
  local s = self:setting(kind)
  if s.mode == "off" then return nil end
  if s.mode == "custom" and s.custom and s.custom ~= "" then return s.custom end
  if W.db.plainMode then return t.plain end
  if s.mode == "fixed" then return t.lines[s.line] or t.lines[1] end
  local n = #t.lines
  local i = math.random(n)
  if n > 1 and i == self.last[kind] then i = (i % n) + 1 end
  self.last[kind] = i
  return t.lines[i]
end

function M:text(kind, extra)
  local tpl = self:template(kind)
  if not tpl then return nil end
  return W.fill(tpl, W.vars(extra))
end

-- whisper `player` (who contacted us first) at most once per `every` seconds per type
function M:send(player, kind, extra, every, now)
  now = now or W.now()
  every = every or 600
  local key = player .. "|" .. kind
  if self.sentAt[key] and now - self.sentAt[key] < every then return false end
  local msg = self:text(kind, extra)
  if not msg or msg == "" then return false end
  self.sentAt[key] = now
  W.whisper(player, msg)
  return true
end

-- old single-text settings (w1 to w5) become custom text if they were edited
function M:migrate(db)
  if db.msgMigrated then return end
  db.msg = db.msg or {}
  local map = { replyText = "queued", wrongDestText = "wrongdest", advertiserReplyText = "advertiser" }
  local oldDefaults = {
    replyText = "Right away, sir! Summon to {dest} is {price}. Invite sent! Accept the summon within 2 min and pay by trade when you land!",
    wrongDestText = "So sorry, sir! I'm summoning to {dest} right now, not {asked}!",
    advertiserReplyText = "Right this way, sir! Whisper {lock} \"123\" for a summon to {dest} ({price})!",
  }
  for field, kind in pairs(map) do
    local v = db[field]
    if v and v ~= "" and v ~= oldDefaults[field] and v ~= (W.STOCK[field] or "") then
      db.msg[kind] = { mode = "custom", line = 1, custom = v }
    end
  end
  db.msgMigrated = true
end

W.module("messages", M)

function M:init()
  self:migrate(W.db)
  W.command("plain", "plain on|off: short serious messages instead of the SummonSir lines", function(args)
    if args == "on" then W.db.plainMode = true elseif args == "off" then W.db.plainMode = false end
    W.print("plain mode:", W.db.plainMode and "on" or "off")
    W.fire("CONFIG_CHANGED")
  end)
  W.command("say", "say <type>: print a sample line (queued, position, full, nearby, wrongdest, complete, noshards, advertiser)", function(args)
    local kind = args ~= "" and args or "queued"
    if not M.TYPES[kind] then W.print("types:", table.concat(M.ORDER, ", ")) return end
    W.print(kind .. ":", M:text(kind, { pos = 3, ahead = 2, asked = "Orgrimmar" }) or "(off)")
  end)
end

addonData.messages = M
