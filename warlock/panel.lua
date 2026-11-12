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
  local f = CreateFrame("Frame", "SteaWarlockPanel", UIParent, "BackdropTemplate")
  f:SetSize(360, 430)
  f:SetPoint("CENTER", UIParent, "CENTER", 260, 0)
  f:SetFrameStrata("DIALOG")
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
  f:SetBackdropColor(W.rgb("bg", 0.96))
  f:SetBackdropBorderColor(W.rgb("line"))
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  table.insert(UISpecialFrames, "SteaWarlockPanel") -- Escape closes it

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 12, -10)
  f.title:SetText("Summon ledger")
  f.title:SetTextColor(W.rgb("purple"))

  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetPoint("TOPRIGHT", 2, 2)

  f.opts = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.opts:SetSize(70, 20)
  f.opts:SetPoint("TOPRIGHT", -30, -8)
  f.opts:SetText("Options")
  f.opts:SetScript("OnClick", function()
    W.options:open(function(opened) if opened then f:Hide() end end)
  end)

  f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.body:SetPoint("TOPLEFT", 12, -34)
  f.body:SetPoint("RIGHT", -12, 0)
  f.body:SetJustifyH("LEFT")
  f.body:SetJustifyV("TOP")
  f.body:SetSpacing(3)
  f.body:SetTextColor(W.rgb("fg"))

  f.npTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.npTitle:SetPoint("BOTTOMLEFT", 12, 12 + UI.ROWS * 22 + 4)
  f.npTitle:SetTextColor(W.rgb("red"))

  for i = 1, UI.ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(336, 20)
    r:SetPoint("BOTTOMLEFT", 12, 12 + (UI.ROWS - i) * 22)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(W.rgb("line", i % 2 == 0 and 0.35 or 0.6))
    r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 4, 0)
    r.text:SetPoint("RIGHT", -110, 0)
    r.text:SetJustifyH("LEFT")
    r.paid = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.paid:SetSize(48, 18)
    r.paid:SetPoint("RIGHT", -56, 0)
    r.paid:SetText("Paid")
    r.block = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
    r.block:SetSize(54, 18)
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

  local shards = addonData.summon and addonData.summon.shards
  if W.role() == "warlock" and shards then
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

-- a small "$" button on the summon window, added the first time it exists
function UI:attachButton()
  if self.dollar or not SteaSummonFrame then return end
  local b = CreateFrame("Button", "SteaWarlockLedgerButton", SteaSummonFrame, "UIPanelButtonTemplate")
  b:SetSize(16, 14)
  b:SetPoint("TOPLEFT", SteaSummonFrame, "TOPRIGHT", -124, -5)
  b:SetText("$")
  b:SetNormalFontObject("GameFontNormalSmall")
  b:SetFrameLevel(3)
  b:SetScript("OnClick", function() UI:toggle() end)
  b:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Summon ledger")
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
