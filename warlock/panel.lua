-- Ledger tab: the session headline (summons, gold, gold/hr, % paid), a
-- scrolling body with the last 7 days and 8 weeks, and the open tabs at the
-- bottom (arrived, not paid yet) with Paid / Block buttons.
-- A page inside the summon window (warlock/tabs.lua); /ssf opens it.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local UI = { page = nil, rows = {}, ROWS = 6 }

local function pctColor(p)
  if p >= 90 then return "green" end
  if p >= 70 then return "orange" end
  return "red"
end

local function gold(copper) return W.hex("yellow", W.fmtMoney(copper)) end
local function dim(text) return W.hex("comment", text) end

-- builds the ledger page into the summon window; returns the page frame
function UI:buildInto(parent)
  if self.page then return self.page end
  local listH = 30 + UI.ROWS * 22 + 8 -- open-tabs heading + rows
  local f = CreateFrame("Frame", "SteaWarlockLedgerPage", parent)
  f:SetAllPoints(parent)
  f:Hide()

  -- the inset holds the open tabs at the bottom
  local inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  inset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
  inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
  inset:SetHeight(listH)
  f.inset = inset

  -- headline: the numbers that matter, in large type
  f.headSub = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.headSub:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -32)
  f.headSub:SetPoint("RIGHT", f, "RIGHT", -14, 0)
  f.headSub:SetJustifyH("LEFT")
  f.head = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.head:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -48)
  f.head:SetPoint("RIGHT", f, "RIGHT", -14, 0)
  f.head:SetJustifyH("LEFT")
  f.head:SetWordWrap(false)

  -- scrolling body so a week of history never clips
  f.scroll = CreateFrame("ScrollFrame", "SteaWarlockLedgerScroll", f, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -76)
  f.scroll:SetPoint("BOTTOMRIGHT", inset, "TOPRIGHT", -30, 6)
  f.scrollChild = CreateFrame("Frame", nil, f.scroll)
  f.scrollChild:SetSize(300, 20)
  f.scroll:SetScrollChild(f.scrollChild)
  f.body = f.scrollChild:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.body:SetPoint("TOPLEFT", f.scrollChild, "TOPLEFT", 0, 0)
  f.body:SetWidth(300)
  f.body:SetJustifyH("LEFT")
  f.body:SetJustifyV("TOP")
  f.body:SetSpacing(3)

  f.npTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.npTitle:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)

  -- Options sits in the open-tabs title row
  f.opts = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.opts:SetSize(70, 20)
  f.opts:SetPoint("TOPRIGHT", inset, "TOPRIGHT", -6, -5)
  f.opts:SetText("Options")
  f.opts:SetScript("OnClick", function() W.options:open() end)
  f.opts:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Summon service settings")
    GameTooltip:AddLine("Prices, messages, blocklist, ads, sounds. Also /ssf options.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  f.opts:SetScript("OnLeave", function() GameTooltip:Hide() end)

  for i = 1, UI.ROWS do
    local r = CreateFrame("Frame", nil, inset)
    r:SetHeight(20)
    r:SetPoint("TOPLEFT", inset, "TOPLEFT", 6, -(30 + (i - 1) * 22))
    r:SetPoint("RIGHT", inset, "RIGHT", -6, 0)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, i % 2 == 0 and 0.04 or 0.09)
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", -112, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.paid = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.paid:SetSize(48, 18)
    r.paid:SetPoint("RIGHT", -58, 0)
    r.paid:SetText("Paid")
    r.paid:SetScript("OnEnter", function(this)
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine("Mark this summon paid")
      GameTooltip:AddLine("For gold that came by mail, a friend paying for them, or a summon you comp. Counts the quoted price and lifts any never-paid block.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    r.paid:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r.block = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.block:SetSize(56, 18)
    r.block:SetPoint("RIGHT", 0, 0)
    r.block:SetScript("OnEnter", function(this)
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(this:GetText() == "Unblock" and "Lift the block" or ("Block for " .. (W.db.autoBlockHours or 24) .. "h"))
      GameTooltip:AddLine("Blocked players get no reply, no invite and no queue spot.", 1, 1, 1, true)
      GameTooltip:Show()
    end)
    r.block:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    UI.rows[i] = r
  end

  self.page = f
  return f
end

-- headline label + line; nil session = nothing recorded yet
function UI:headline(now)
  local s = W.stats.session(W.db.summons, W.db.payments, now)
  if not s then
    return dim("They show up here after each cast."), dim("No summons yet")
  end
  local label = (s.active and "This session" or "Last session") .. " (" .. W.stats.duration((s.active and now or s.last) - s.first) .. ")"
  local line = string.format("%d summons   %s   %s/hr   %s",
    s.summons, gold(s.gold), gold(s.goldPerHour),
    W.hex(pctColor(s.paidPct), string.format("%d%% paid", math.floor(s.paidPct + 0.5))))
  return W.hex("cyan", label), line
end

function UI:bodyText(now)
  local db = W.db
  local S = W.stats
  local lines = {}
  local function add(s) table.insert(lines, s) end

  local b = S.buckets(db.summons, db.payments, now)
  add(W.hex("cyan", "Last 7 days"))
  local any = false
  for i = #b.days, 1, -1 do
    local d = b.days[i]
    if d.summons > 0 or d.gold > 0 then
      any = true
      add(string.format("  %s   %3d summons   %s", d.label, d.summons, gold(d.gold)))
    end
  end
  if not any then add(dim("  nothing yet")) end
  add("")
  add(W.hex("cyan", "Weeks (from Monday)"))
  any = false
  for i = #b.weeks, 1, -1 do
    local w = b.weeks[i]
    if w.summons > 0 or w.gold > 0 then
      any = true
      add(string.format("  %s   %3d summons   %s", w.label, w.summons, gold(w.gold)))
    end
  end
  if not any then add(dim("  nothing yet")) end
  add("")
  -- what this window is set to, dimmed, at the bottom
  local line = dim("role ") .. W.role() .. dim("   to ") .. W.destName() .. dim("   price ") .. gold(W.priceFor(W.destKey()))
  if W.role() == "warlock" then
    local shards = W.countShards()
    line = line .. dim("   shards ") .. W.hex(shards < 10 and "red" or "fg", tostring(shards))
  end
  add(line)
  return table.concat(lines, "\n")
end

-- one open-tab row: who, how long since the summon, and whether the grace time is up
function UI:tabText(s, now)
  local grace = (W.db.graceMinutes or 10) * 60
  local since = s.arrived or s.t
  local ago = W.stats.duration(now - since)
  if s.nonPayer or now - since >= grace then
    return W.hex("red", s.name) .. dim("  never paid, ") .. W.hex("red", ago .. " ago")
  end
  return s.name .. dim("  arrived " .. ago .. " ago, owes ") .. gold(s.price or W.priceFor(s.dest))
end

function UI:refresh()
  local f = self.page
  if not f or not f:IsShown() then return end
  local now = W.now()
  local sub, head = self:headline(now)
  f.headSub:SetText(sub)
  f.head:SetText(head)
  f.body:SetWidth(math.max(100, f.scroll:GetWidth() or 300))
  f.body:SetText(self:bodyText(now))
  f.scrollChild:SetWidth(f.body:GetWidth())
  local childH = math.max(20, (f.body:GetStringHeight() or 20) + 8)
  f.scrollChild:SetHeight(childH)
  -- the stock scroll bar always shows; hide it while everything fits
  local bar = f.scroll.ScrollBar
  if type(bar) == "table" then bar:SetShown(childH > (f.scroll:GetHeight() or 0)) end

  local tabs = W.stats.openTabs(W.db.summons, now, UI.ROWS)
  f.npTitle:SetText(#tabs > 0 and "Open tabs" or dim("Open tabs: none"))
  for i = 1, UI.ROWS do
    local r, s = UI.rows[i], tabs[i]
    if s then
      r.text:SetText(self:tabText(s, now))
      r.paid:SetScript("OnClick", function() W.ledger:recordPaymentFor(s, s.price or W.priceFor(s.dest), W.now()) end)
      local blocked = W.blocklist:isBlocked(s.name, now)
      r.block:SetText(blocked and "Unblock" or "Block")
      r.block:SetScript("OnClick", function()
        if W.blocklist:isBlocked(s.name) then
          W.blocklist:remove(s.name)
        else
          W.blocklist:add(s.name, (W.db.autoBlockHours or 24) * 3600, "manual")
        end
        UI:refresh()
      end)
      r:Show()
    else
      r:Hide()
    end
  end
end

-- /ssf: the window on the Ledger tab; again on that tab closes it
function UI:toggle()
  if addonData.tabs then return addonData.tabs:toggle("ledger") end
end

W.module("panel", UI)

function UI:init()
  W.on("LEDGER_CHANGED", function() UI:refresh() end)
  W.on("CONFIG_CHANGED", function() UI:refresh() end)
  C_Timer.NewTicker(10, function() UI:refresh() end)
  W.command("stats", "stats: open the ledger tab (also just /ssf)", function() UI:toggle() end)
end

addonData.panel = UI
