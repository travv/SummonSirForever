-- Customer messages: 8 reply types, 5 SummonSir lines each plus a plain line.
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
    label = "First reply (price + invite)",
    lines = {
      "Right away, sir! Summon to {dest} is {price}. Invite sent! Accept the summon within 2 min and pay by trade when you land!",
      "At your service, sir! {dest} for {price}. Invite's on the way, accept it and then the summon within 2 min!",
      "Splendid choice, sir! One summon to {dest}, {price}. Accept the invite and the summon pops shortly!",
      "Your carriage awaits, sir! {dest} for {price}. Invite sent! Accept the summon within 2 min and pay on arrival!",
      "Say no more, sir! {dest} is {price}. Hop in the group, sit back and relax, the summon comes to you!",
    },
    plain = "Summon to {dest}: {price}. Invite sent. Accept the summon within 2 min and pay by trade on arrival.",
  },
  position = {
    label = "Place in line (on joining, and when they ask again)",
    lines = {
      "You're #{pos} in line, sir! Sit back and relax!",
      "Splendid, sir! You're #{pos} in the queue. The portal will find you shortly!",
      "Noted, sir! #{pos} in line, {ahead} ahead of you. Sit tight!",
      "You're in, sir! Number {pos} in the queue. Keep an eye out for the summon!",
      "Patience will be rewarded, sir! You're #{pos} in line!",
    },
    plain = "You're #{pos} in the queue.",
  },
  full = {
    label = "Queue is full",
    lines = {
      "Terribly sorry, sir! The queue is full right now. Try again in a few minutes!",
      "Apologies, sir! We're packed at the moment. Whisper me again shortly!",
      "So sorry, sir! No room in the queue just now. Back in a few minutes?",
      "The portal is overbooked, sir! Please try again in a few minutes!",
      "Full house, sir! Give it a few minutes and whisper me again!",
    },
    plain = "The queue is full. Try again in a few minutes.",
  },
  nearby = {
    label = "Already here",
    lines = {
      "You're already here, sir! No summon needed!",
      "Look around, sir! You've already arrived!",
      "Good news, sir! You're already at {dest}!",
      "No portal needed, sir! You're standing right here!",
      "Already among us, sir! Enjoy {dest}!",
    },
    plain = "You're already here, no summon needed.",
  },
  wrongdest = {
    label = "Asked for a different place",
    lines = {
      "So sorry, sir! I'm summoning to {dest} right now, not {asked}!",
      "Apologies, sir! Today's destination is {dest}, not {asked}!",
      "Alas, sir! The portal only goes to {dest} at the moment, not {asked}!",
      "Not today, sir! I'm set up at {dest}. {asked} will have to wait!",
      "Terribly sorry, sir! {dest} only right now. No {asked} summons yet!",
    },
    plain = "Summoning to {dest} right now, not {asked}.",
  },
  complete = {
    label = "Summon complete (payment reminder)",
    lines = {
      "Welcome to {dest}, sir! That'll be {price}, trade me whenever you're ready!",
      "You've arrived, sir! {price} by trade when you get a moment. Thank you!",
      "Safe and sound, sir! Kindly trade {price} at your convenience!",
      "Splendid, sir, you made it! {price} by trade please, and enjoy {dest}!",
      "Delivered, sir! Trade me {price} when ready. A pleasure doing business!",
    },
    plain = "Summon complete. Please trade {price}.",
  },
  noshards = {
    label = "Out of soul shards (to the next in line)",
    lines = {
      "Terribly sorry, sir! I'm out of soul shards. Hang tight, I'll have you shortly!",
      "A brief delay, sir! Restocking soul shards, you're next as soon as I'm ready!",
      "Apologies, sir! The portal needs shards and I'm out. Back in a moment!",
      "Hold tight, sir! Gathering soul shards, you're still next in line!",
      "One moment, sir! Out of shards, but your spot is safe!",
    },
    plain = "Out of soul shards. You're still next, back shortly.",
  },
  advertiser = {
    label = "Advertiser's reply (points them at the warlock)",
    lines = {
      "Right this way, sir! Whisper {lock} \"123\" for a summon to {dest} ({price})!",
      "Excellent, sir! {lock} does the summoning. Whisper \"123\" to {lock} for {dest} ({price})!",
      "You want {lock}, sir! Whisper \"123\" for a summon to {dest}, {price}!",
      "Splendid, sir! Send {lock} a \"123\" and you'll be in {dest} in no time ({price})!",
      "At your service, sir! Whisper {lock} \"123\" for {dest}, just {price}!",
    },
    plain = "Whisper {lock} \"123\" for a summon to {dest} ({price}).",
  },
}

-- per-type setting: { mode = "random" | "fixed" | "custom" | "off", line = n, custom = text }
function M:setting(kind)
  W.db.msg = W.db.msg or {}
  W.db.msg[kind] = W.db.msg[kind] or { mode = "random", line = 1, custom = "" }
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
