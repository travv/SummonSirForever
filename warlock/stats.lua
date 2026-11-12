-- Stats: summons and gold by hour (today), day (7 days), week (8 weeks),
-- the current session, and the never-paid list.
-- Times use the PC clock (date()), which is Central Time on Travis's PCs.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local S = {
  SESSION_GAP = 30 * 60, -- a 30 min break starts a new session
  dateFn = function(fmt, t) return date(fmt, t) end, -- tests replace this
}

local function dayKey(t) return S.dateFn("%Y-%m-%d", t) end
local function hourOf(t) return tonumber(S.dateFn("%H", t)) end

-- Monday 00:00 of t's week, as a day key
local function weekKey(t)
  local wday = tonumber(S.dateFn("%w", t)) -- 0 = Sunday
  local back = (wday + 6) % 7
  -- step back by whole days at noon so DST shifts never cross midnight
  local noon = t - (tonumber(S.dateFn("%H", t)) - 12) * 3600
  return dayKey(noon - back * 86400)
end
S.dayKey, S.weekKey = dayKey, weekKey

local function newBucket(label) return { label = label, summons = 0, paid = 0, gold = 0 } end

local function addSummon(b, s)
  b.summons = b.summons + 1
  if s.paid then b.paid = b.paid + 1 end
end

-- buckets for display; all lists newest last
function S.buckets(summons, payments, now)
  local today = dayKey(now)
  local hours = {}
  for h = 0, 23 do hours[h] = newBucket(string.format("%02d", h)) end

  local days, dayIdx = {}, {}
  local noon = now - (hourOf(now) - 12) * 3600
  for i = 6, 0, -1 do
    local k = dayKey(noon - i * 86400)
    local b = newBucket(k)
    table.insert(days, b)
    dayIdx[k] = b
  end

  local weeks, weekIdx = {}, {}
  for i = 7, 0, -1 do
    local k = weekKey(noon - i * 7 * 86400)
    if not weekIdx[k] then
      local b = newBucket(k)
      table.insert(weeks, b)
      weekIdx[k] = b
    end
  end

  local oldest = now - 8 * 7 * 86400 - 86400
  for i = #summons, 1, -1 do
    local s = summons[i]
    if s.t < oldest then break end
    local dk = dayKey(s.t)
    if dk == today then addSummon(hours[hourOf(s.t)], s) end
    if dayIdx[dk] then addSummon(dayIdx[dk], s) end
    local wk = weekIdx[weekKey(s.t)]
    if wk then addSummon(wk, s) end
  end
  for i = #payments, 1, -1 do
    local p = payments[i]
    if p.t < oldest then break end
    local dk = dayKey(p.t)
    if dk == today then hours[hourOf(p.t)].gold = hours[hourOf(p.t)].gold + p.amount end
    if dayIdx[dk] then dayIdx[dk].gold = dayIdx[dk].gold + p.amount end
    local wk = weekIdx[weekKey(p.t)]
    if wk then wk.gold = wk.gold + p.amount end
  end
  return { hours = hours, days = days, weeks = weeks }
end

-- the run of summons with no 30 min gap that ends with the newest one.
-- A session older than 30 min is over, and the result is still returned.
function S.session(summons, payments, now)
  local n = #summons
  if n == 0 then return nil end
  local last = summons[n].t
  local first = last
  local i = n
  while i > 1 and summons[i].t - summons[i - 1].t <= S.SESSION_GAP do
    i = i - 1
    first = summons[i].t
  end
  local out = { first = first, last = last, summons = 0, paid = 0, gold = 0,
                active = (now - last) <= S.SESSION_GAP }
  for j = i, n do
    out.summons = out.summons + 1
    if summons[j].paid then out.paid = out.paid + 1 end
  end
  for j = #payments, 1, -1 do
    local p = payments[j]
    if p.t < first then break end
    out.gold = out.gold + p.amount
  end
  local stop = out.active and now or last
  out.hours = math.max(0.25, (stop - first) / 3600) -- floor at 15 min so 1 sale is not 400g/hr
  out.goldPerHour = out.gold / out.hours
  out.paidPct = out.summons > 0 and (100 * out.paid / out.summons) or 0
  return out
end

function S.neverPaid(summons, limit)
  local out = {}
  for i = #summons, 1, -1 do
    local s = summons[i]
    if s.nonPayer and not s.paid then
      table.insert(out, s)
      if limit and #out >= limit then break end
    end
  end
  return out
end

function S.duration(seconds)
  seconds = math.max(0, math.floor(seconds))
  local h = math.floor(seconds / 3600)
  local m = math.floor((seconds % 3600) / 60)
  if h > 0 then return string.format("%dh%02dm", h, m) end
  return string.format("%dm", m)
end

W.module("stats", S)

function S:init()
  W.command("today", "today: summons and gold per hour today", function()
    local b = S.buckets(W.db.summons, W.db.payments, W.now())
    for h = 0, 23 do
      local x = b.hours[h]
      if x.summons > 0 or x.gold > 0 then
        print(string.format("  %s:00  %3d summons  %s", x.label, x.summons, W.fmtMoney(x.gold)))
      end
    end
  end)
end

addonData.stats = S
