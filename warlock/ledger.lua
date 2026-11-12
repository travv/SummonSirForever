-- Payment ledger: who was summoned, who paid, who never paid.
-- Forever has no TRADE_COMPLETE, so a payment counts only when our gold goes
-- up by what the other side put in the trade window.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local L = {
  trade = nil,           -- open trade: { partner, money0, offer, mine, closed }
  MATCH_WINDOW = 30 * 60, -- a payment pays a summon cast in the last 30 min
  ARRIVE_WINDOW = 10 * 60,
  CONFIRM_SECONDS = 2,
}

-- Forever splits names in two ("Summ", "Bert")
function W.unitFullName(unit)
  local first, second = UnitName(unit)
  if not first then return nil end
  if second and second ~= "" then return first .. " " .. second end
  return first
end

---------------------------------
-- records
---------------------------------
function L:recordSummon(name, now, destKey)
  now = now or W.now()
  local list = W.db.summons
  local id = (list[#list] and list[#list].id or 0) + 1
  local rec = { id = id, name = name, t = now, dest = destKey, price = W.priceFor(destKey) }
  table.insert(list, rec)
  return rec
end

-- newest summon for `name` newer than `window` seconds that passes `filter`
function L:findSummon(name, now, window, filter)
  local list = W.db.summons
  for i = #list, 1, -1 do
    local s = list[i]
    if now - s.t > window then return nil end
    if s.name == name and (not filter or filter(s)) then return s end
  end
  return nil
end

function L:markArrived(name, now)
  now = now or W.now()
  local s = self:findSummon(name, now, self.ARRIVE_WINDOW, function(r) return not r.arrived end)
  if s then s.arrived = now end
  return s
end

function L:recordPayment(name, amount, now)
  now = now or W.now()
  local s = self:findSummon(name, now, self.MATCH_WINDOW, function(r) return not r.paid end)
  local p = { name = name, t = now, amount = amount, summonId = s and s.id or nil }
  table.insert(W.db.payments, p)
  if s then
    s.paid = true
    s.paidAmount = amount
    s.paidAt = now
    s.nonPayer = nil
  end
  -- paying up clears an automatic never-paid block
  local blocked, e = W.blocklist:isBlocked(name, now)
  if blocked and e.reason == "never paid" then
    W.blocklist:remove(name)
  end
  -- one line and the coin sound on every settle path (timer or PLAYER_MONEY)
  -- any amount counts as paid: discounts are part of the business (Travis, 2026-11-12)
  local note = ""
  if not s then note = W.hex("comment", "(tip: no open summon)") end
  W.print(W.hex("green", "paid:"), name, W.fmtMoney(amount), note)
  W.playSound("LOOT_WINDOW_COIN_SOUND", 120, "soundPaid")
  W.fire("LEDGER_CHANGED")
  return p, s
end

-- manual "they paid" (mail, a friend paid for them): counts the expected price
function L:markPaid(name, amount, now)
  now = now or W.now()
  local list = W.db.summons
  for i = #list, 1, -1 do
    local s = list[i]
    if s.name == name and not s.paid then
      return self:recordPaymentFor(s, amount or s.price, now)
    end
  end
  return nil
end

function L:recordPaymentFor(s, amount, now)
  table.insert(W.db.payments, { name = s.name, t = now, amount = amount, summonId = s.id, manual = true })
  s.paid, s.paidAmount, s.paidAt, s.nonPayer = true, amount, now, nil
  local blocked, e = W.blocklist:isBlocked(s.name, now)
  if blocked and e.reason == "never paid" then W.blocklist:remove(s.name) end
  W.fire("LEDGER_CHANGED")
  return s
end

-- flag arrived-but-unpaid summons past the grace time; auto-block them
function L:sweep(now)
  now = now or W.now()
  local grace = (W.db.graceMinutes or 10) * 60
  local flagged = {}
  local list = W.db.summons
  for i = #list, 1, -1 do
    local s = list[i]
    if now - s.t > 7 * 86400 then break end
    if s.arrived and not s.paid and not s.nonPayer and now - s.arrived >= grace then
      s.nonPayer = now
      table.insert(flagged, s)
      if W.db.autoBlock and not W.blocklist:isBlocked(s.name, now) then
        W.blocklist:add(s.name, (W.db.autoBlockHours or 24) * 3600, "never paid", now)
      end
    end
  end
  if #flagged > 0 then W.fire("LEDGER_CHANGED") end
  return flagged
end

---------------------------------
-- trade window state machine
---------------------------------
function L:tradeShow(partner, money)
  self.trade = { partner = partner, money0 = money, offer = 0, mine = 0 }
end

function L:tradeMoney(offer, mine)
  if not self.trade then return end
  self.trade.offer = offer or self.trade.offer
  self.trade.mine = mine or self.trade.mine
end

function L:tradeClosed(now)
  if not self.trade then return end
  self.trade.closed = now or W.now()
end

-- called on PLAYER_MONEY after the window closed (and from the timeout with
-- the money unchanged): a payment only if gold went up by the offer
function L:tradeSettle(money, now)
  local t = self.trade
  if not t or not t.closed then return nil end
  self.trade = nil
  local delta = money - t.money0
  local expected = t.offer - t.mine
  if t.offer > 0 and delta > 0 and delta == expected then
    return self:recordPayment(t.partner, t.offer, now)
  end
  return nil
end

W.module("ledger", L)

function L:init()
  W.on("TRADE_SHOW", function()
    local partner = W.unitFullName("NPC")
    if partner then L:tradeShow(W.shortName(partner), GetMoney()) end
  end)
  local function refresh()
    L:tradeMoney(GetTargetTradeMoney(), GetPlayerTradeMoney())
  end
  W.on("TRADE_MONEY_CHANGED", refresh)
  W.on("TRADE_ACCEPT_UPDATE", refresh)
  W.on("TRADE_CLOSED", function()
    if not L.trade or L.trade.closed then return end
    L:tradeClosed()
    -- gold arrives just after TRADE_CLOSED; if it never moves the trade was cancelled
    C_Timer.After(L.CONFIRM_SECONDS, function() L:tradeSettle(GetMoney()) end)
  end)
  W.on("PLAYER_MONEY", function()
    if L.trade and L.trade.closed then L:tradeSettle(GetMoney()) end
  end)

  W.on("SUMMON_CAST", function(name)
    if W.role() ~= "warlock" then return end
    L:recordSummon(name, W.now(), W.db.dest)
    W.fire("LEDGER_CHANGED")
  end)
  W.on("SUMMON_ARRIVED", function(name)
    if L:markArrived(name) then W.fire("LEDGER_CHANGED") end
  end)

  C_Timer.NewTicker(30, function()
    for _, s in ipairs(L:sweep()) do
      W.print(W.hex("red", "never paid:"), s.name, W.db.autoBlock and "(blocked)" or "")
    end
  end)

  W.command("paid", "paid <name> [amount]: mark a summon paid by hand", function(args)
    local name, amt = string.match(args, "^(.-)%s+(%S+)$")
    local copper = amt and W.parseMoney(amt)
    if not copper then name = args end
    local s = L:markPaid(name, copper)
    if s then W.print("marked paid:", s.name, W.fmtMoney(s.paidAmount)) else W.print("no unpaid summon for", name) end
  end)
end

addonData.ledger = L
