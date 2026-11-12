-- Ledger panel: session, today, 7 days, 8 weeks, never-paid list with
-- Paid / Block buttons. Open with /sw or the "$" button on the summon window.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local UI = { frame = nil, rows = {}, ROWS = 6 }

local function pctColor(p)
  if p >= 90 then return "green" end
  if p >= 70 then return "orange" end
  return "red"
end

local function gold(copper) return W.hex("yellow", W.fmtMoney(copper)) end
local function dim(text) return W.hex("comment", text) end

function UI:build()
  if self.frame then return self.frame end
  local listH = 30 + UI.ROWS * 22 + 8 -- never-paid heading + rows
  local f = W.stockWindow("SteaWarlockPanel", UIParent, 380, 500, "Summon ledger", "Interface/ICONS/INV_Misc_Coin_02")
  f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  f:SetFrameStrata("DIALOG")
  table.insert(UISpecialFrames, "SteaWarlockPanel") -- Escape closes it

  -- the inset holds the never-paid list at the bottom
  local inset = W.child(f, "Inset") or f
  if inset ~= f then
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    f.Inset:SetHeight(listH)
  end

  f.opts = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.opts:SetSize(80, 22)
  f.opts:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -28)
  f.opts:SetText("Options")
  f.opts:SetScript("OnClick", function()
    W.options:open(function(opened) if opened then f:Hide() end end)
  end)

  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.body:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -30)
  f.body:SetPoint("RIGHT", f.opts, "LEFT", -8, 0)
  f.body:SetPoint("BOTTOM", inset, "TOP", 0, 4)
  f.body:SetJustifyH("LEFT")
  f.body:SetJustifyV("TOP")
  f.body:SetSpacing(3)

  f.npTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.npTitle:SetPoint("TOPLEFT", inset, "TOPLEFT", 8, -8)

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
    r.block = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.block:SetSize(56, 18)
    r.block:SetPoint("RIGHT", 0, 0)
    r:Hide()
    UI.rows[i] = r
  end

  f:Hide()
  self.frame = f
  return f
end

function UI:bodyText(now)
  local db = W.db
  local S = W.stats
  local lines = {}
  local function add(s) table.insert(lines, s) end

  add(dim("role ") .. W.role() .. dim("   to ") .. W.destName() .. dim("   price ") .. gold(W.priceFor(db.dest)))

  if W.role() == "warlock" then
    local shards = W.countShards()
    add(dim("soul shards ") .. W.hex(shards < 10 and "red" or "fg", tostring(shards)))
  end
  add("")

  local s = S.session(db.summons, db.payments, now)
  if s then
    add(W.hex("cyan", s.active and "This session" or "Last session")
      .. dim(" (" .. S.duration((s.active and now or s.last) - s.first) .. ")"))
    add(string.format("  %d summons   %s   %s/hr   %s",
      s.summons, gold(s.gold), gold(s.goldPerHour),
      W.hex(pctColor(s.paidPct), string.format("%d%% paid", math.floor(s.paidPct + 0.5)))))
  else
    add(dim("No summons yet. They show up here after each cast."))
  end
  add("")

  local b = S.buckets(db.summons, db.payments, now)
  add(W.hex("cyan", "Last 7 days"))
  for i = #b.days, 1, -1 do
    local d = b.days[i]
    if d.summons > 0 or d.gold > 0 then
      add(string.format("  %s   %3d summons   %s", d.label, d.summons, gold(d.gold)))
    end
  end
  add(W.hex("cyan", "Weeks (from Monday)"))
  for i = #b.weeks, 1, -1 do
    local w = b.weeks[i]
    if w.summons > 0 or w.gold > 0 then
      add(string.format("  %s   %3d summons   %s", w.label, w.summons, gold(w.gold)))
    end
  end
  return table.concat(lines, "\n")
end

function UI:refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  local now = W.now()
  f.body:SetText(self:bodyText(now))

  local np = W.stats.neverPaid(W.db.summons, UI.ROWS)
  f.npTitle:SetText(#np > 0 and "Never paid" or "")
  for i = 1, UI.ROWS do
    local r, s = UI.rows[i], np[i]
    if s then
      local ago = W.stats.duration(now - s.t)
      r.text:SetText(W.hex("red", s.name) .. dim("  " .. ago .. " ago"))
      r.paid:SetScript("OnClick", function() W.ledger:markPaid(s.name) end)
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

function UI:toggle()
  local f = self:build()
  if f:IsShown() then f:Hide() else f:Show(); self:refresh() end
end

-- "Ledger" button in the summon window's button row (left of Menu), added
-- the first time the window exists
function UI:attachButton()
  if self.dollar or not SteaSummonFrame then return end
  local b = CreateFrame("Button", "SteaWarlockLedgerButton", SteaSummonFrame, "UIPanelButtonTemplate")
  b:SetSize(56, 22)
  b:SetPoint("TOPRIGHT", SteaSummonFrame, "TOPRIGHT", -66, -72)
  b:SetText("Ledger")
  b:SetScript("OnClick", function() UI:toggle() end)
  b:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Summon ledger")
    GameTooltip:AddLine("Who paid, gold per hour, never-paid list. Also /sw.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  self.dollar = b
end

W.module("panel", UI)

function UI:init()
  self:build()
  W.on("LEDGER_CHANGED", function() UI:refresh() end)
  W.on("CONFIG_CHANGED", function() UI:refresh() end)
  C_Timer.NewTicker(10, function() UI:refresh() end)
  hooksecurefunc(addonData.summon, "showSummons", function() UI:attachButton() end)
  W.command("stats", "stats: open the ledger panel (also just /sw)", function() UI:toggle() end)
end

addonData.panel = UI
