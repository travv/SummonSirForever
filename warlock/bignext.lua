-- Big "Summon Next" button for the warlock: the same cast and announce as the
-- Next button / keybind, just big. It mirrors the Next button's secure macro
-- (set out of combat, like the original) and forwards its PreClick, so one
-- click = one Ritual of Summoning on the next person in line.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local N = { frame = nil, button = nil }

local function next38()
  return addonData.buttons and addonData.buttons[38] and addonData.buttons[38].Button
end

local function charState()
  local me = W.me()
  W.db.chars[me] = W.db.chars[me] or {}
  return W.db.chars[me]
end

local function lowMana()
  local ok, low = pcall(function() return UnitPower("player") < 300 end)
  return ok and low
end

function N:wanted()
  local util = addonData.util
  return W.role() == "warlock" and W.db.bigButton ~= false
    and util and util.playerCanSummon and util:playerCanSummon()
end

function N:build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "SummonSirNextFrame", UIParent, "BackdropTemplate")
  f:SetSize(236, 92)
  f:SetFrameStrata("MEDIUM")
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
  f:SetBackdropColor(W.rgb("bg", 0.92))
  f:SetBackdropBorderColor(W.rgb("purple"))
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetClampedToScreen(true)
  f:SetScript("OnDragStart", function(this) if not InCombatLockdown() then this:StartMoving() end end)
  f:SetScript("OnDragStop", function(this)
    this:StopMovingOrSizing()
    local point, _, rel, x, y = this:GetPoint()
    charState().bigPos = { point, rel, x, y }
  end)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.title:SetPoint("TOPLEFT", 8, -5)
  f.title:SetText("SummonSir  (drag here to move)")
  f.title:SetTextColor(W.rgb("comment"))

  f.clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  f.clear:SetSize(54, 16)
  f.clear:SetPoint("TOPRIGHT", -6, -3)
  f.clear:SetText("Clear")
  f.clear:SetNormalFontObject("GameFontNormalSmall")
  f.clear:SetScript("OnClick", function() addonData.summon:clearList() end) -- asks first
  f.clear:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Clear the whole summon queue")
    GameTooltip:Show()
  end)
  f.clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- the secure cast button
  local b = CreateFrame("Button", "SummonSirNextButton", f, "SecureActionButtonTemplate")
  b:SetPoint("BOTTOMLEFT", 6, 6)
  b:SetPoint("BOTTOMRIGHT", -6, 6)
  b:SetHeight(64)
  b:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
  b:SetAttribute("type", "macro")
  b:SetAttribute("macrotext", "")

  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(W.rgb("line", 1))
  b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(56, 56)
  b.icon:SetPoint("LEFT", 4, 0)
  b.icon:SetTexture("Interface/ICONS/Spell_Shadow_Twilight")

  b.line1 = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.line1:SetPoint("TOPLEFT", b.icon, "TOPRIGHT", 8, -2)
  b.line1:SetPoint("RIGHT", -6, 0)
  b.line1:SetJustifyH("LEFT")
  b.line2 = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.line2:SetPoint("TOPLEFT", b.line1, "BOTTOMLEFT", 0, -3)
  b.line2:SetPoint("RIGHT", -6, 0)
  b.line2:SetJustifyH("LEFT")
  b.line3 = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.line3:SetPoint("TOPLEFT", b.line2, "BOTTOMLEFT", 0, -3)
  b.line3:SetPoint("RIGHT", -6, 0)
  b.line3:SetJustifyH("LEFT")

  -- same announce/pending logic as the Next button, once per press. The
  -- Next PreClick re-aims its macro at the person it announces, so copy
  -- that macro here before our own secure click fires (the 0.5s refresh
  -- copy could be half a second stale)
  b:SetScript("PreClick", function(this, button, down)
    local nb = next38()
    local pre = nb and nb:GetScript("PreClick")
    if pre then pre(nb, button, down) end
    if nb and not InCombatLockdown() then
      local macro = nb:GetAttribute("macrotext") or ""
      if this:GetAttribute("macrotext") ~= macro then this:SetAttribute("macrotext", macro) end
    end
  end)

  self.frame, self.button = f, b
  self:place()
  f:Hide()
  return f
end

function N:place()
  local f = self.frame
  if not f or InCombatLockdown() then return end
  f:ClearAllPoints()
  local pos = charState().bigPos
  if pos then
    f:SetPoint(pos[1] or "CENTER", UIParent, pos[2] or "CENTER", pos[3] or 0, pos[4] or 0)
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, -160)
  end
  f:SetScale(W.db.bigScale or 1)
end

-- what the button shows and casts; secure attributes only out of combat
function N:refresh()
  local f, b = self.frame, self.button
  if not f then return end
  local S = addonData.summon
  local nextRec = S and S.firstRequested and S:firstRequested()
  local queued = S and S.numwaiting or 0
  local shards = W.countShards()

  if not InCombatLockdown() then
    local want = self:wanted()
    if want and not f:IsShown() then f:Show() elseif not want and f:IsShown() then f:Hide() end
    local nb = next38()
    local macro = (nextRec and nb and nb:GetAttribute("macrotext")) or ""
    if b:GetAttribute("macrotext") ~= macro then b:SetAttribute("macrotext", macro) end
  end

  if S and S.isCasting then
    b.line1:SetText(W.hex("green", "Summoning..."))
    b.line2:SetText(S.summoningPlayer or "")
  elseif not nextRec then
    b.line1:SetText(W.hex("comment", "Queue empty"))
    b.line2:SetText(W.hex("comment", "Waiting for customers"))
  elseif lowMana() then
    b.line1:SetText(W.hex("orange", "Life Tap"))
    b.line2:SetText("Low mana. Next: " .. nextRec[1])
  else
    b.line1:SetText(W.hex("purple", "SUMMON NEXT"))
    b.line2:SetText(nextRec[1])
  end
  b.line3:SetText(W.hex("comment", queued .. " in queue   ")
    .. W.hex(shards == 0 and "red" or (shards < 5 and "orange" or "comment"), shards .. " shards"))
  f:SetBackdropBorderColor(W.rgb(nextRec and (shards > 0 and "purple" or "red") or "comment"))
  b:SetAlpha(nextRec and 1 or 0.6)
end

W.module("bignext", N)

function N:init()
  self:build()
  hooksecurefunc(addonData.summon, "showSummons", function() N:refresh() end)
  C_Timer.NewTicker(0.5, function() N:refresh() end)
  W.on("ROLE_CHANGED", function() N:refresh() end)
  W.on("CONFIG_CHANGED", function() N:place(); N:refresh() end)
  W.on("PLAYER_REGEN_ENABLED", function() N:place(); N:refresh() end)

  W.command("big", "big on|off|reset: the big Summon Next button", function(args)
    if args == "on" then W.db.bigButton = true
    elseif args == "off" then W.db.bigButton = false
    elseif args == "reset" then charState().bigPos = nil; W.db.bigScale = 1; N:place()
    end
    W.print("big Summon Next button:", W.db.bigButton == false and "off" or "on")
    N:refresh()
  end)
  W.command("clear", "clear: clear the whole summon queue (asks first)", function()
    addonData.summon:clearList()
  end)
end

addonData.bignext = N
