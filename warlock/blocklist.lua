-- Timed blocklist: blocked players are ignored (no reply, no invite, no queue)
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local B = {}

local UNITS = { m = 60, h = 3600, d = 86400, w = 604800 }
local FOREVER = 10 * 365 * 86400

-- "30m", "24h", "7d", "2w", "perm"; a bare number is hours
function B.parseDuration(text)
  text = string.lower(text or "")
  if text == "" then return nil end
  if text == "perm" or text == "forever" then return FOREVER end
  local n, unit = string.match(text, "^(%d+)([mhdw]?)$")
  if not n then return nil end
  return tonumber(n) * UNITS[unit ~= "" and unit or "h"]
end

function B:add(name, seconds, reason, now)
  if not name or name == "" then return end
  now = now or W.now()
  W.db.blocklist[name] = { untilT = now + seconds, at = now, reason = reason or "manual" }
end

function B:remove(name)
  local had = W.db.blocklist[name] ~= nil
  W.db.blocklist[name] = nil
  return had
end

-- expired entries are dropped as they are checked
function B:isBlocked(name, now)
  if not name then return false end
  local e = W.db.blocklist[name]
  if not e then return false end
  now = now or W.now()
  if e.untilT <= now then
    W.db.blocklist[name] = nil
    return false
  end
  return true, e
end

function B:list(now)
  now = now or W.now()
  local out = {}
  for name in pairs(W.db.blocklist) do
    local blocked, e = self:isBlocked(name, now)
    if blocked then table.insert(out, { name = name, untilT = e.untilT, reason = e.reason }) end
  end
  table.sort(out, function(a, b) return a.untilT < b.untilT end)
  return out
end

local function left(seconds)
  if seconds >= FOREVER / 2 then return "permanent" end
  if seconds >= 86400 then return string.format("%dd", math.floor(seconds / 86400)) end
  if seconds >= 3600 then return string.format("%dh", math.floor(seconds / 3600)) end
  return string.format("%dm", math.max(1, math.floor(seconds / 60)))
end
B.left = left

W.module("blocklist", B)

function B:init()
  -- names have a space on Forever ("Summ Bert"): the duration is the last word if it parses
  local function nameAndDuration(args)
    local name, last = string.match(args, "^(.-)%s+(%S+)$")
    if name and B.parseDuration(last) then
      return name, B.parseDuration(last)
    end
    return args, (W.db.autoBlockHours or 24) * 3600
  end

  W.command("block", "block <name> [30m|24h|7d|perm]", function(args)
    if args == "" then W.print("usage: /sw block <name> [24h]") return end
    local name, secs = nameAndDuration(args)
    B:add(name, secs, "manual")
    W.print("blocked", name, "for", left(secs))
    W.fire("CONFIG_CHANGED")
  end)

  W.command("unblock", "unblock <name>", function(args)
    if B:remove(args) then W.print("unblocked", args) else W.print(args, "was not blocked") end
    W.fire("CONFIG_CHANGED")
  end)

  W.command("blocklist", "blocklist: who is blocked and for how long", function()
    local list = B:list()
    if #list == 0 then W.print("nobody is blocked") return end
    local now = W.now()
    for _, e in ipairs(list) do
      print(string.format("  %s  %s  (%s)", e.name, left(e.untilT - now), e.reason))
    end
  end)
end

addonData.blocklist = B
