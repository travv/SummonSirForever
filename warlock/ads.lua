-- Services-channel ads: our template, one click per post, upstream cooldown.
-- The send itself stays in chat.lua's advertise(), called from a button's
-- OnClick (a hardware event). Nothing here posts on a timer.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local A = { frame = nil }

-- GetChannelList() returns id, name, disabled triples
function A.findChannel(list, wanted)
  wanted = string.lower(wanted or "")
  if wanted == "" then return nil end
  for i = 1, #list do
    local v = list[i]
    if type(v) == "string" and type(list[i - 1]) == "number" then
      local lower = string.lower(v)
      if string.sub(lower, 1, #wanted) == wanted then
        return list[i - 1], v
      end
    end
  end
  return nil
end

function A:channel()
  return A.findChannel({ GetChannelList() }, W.db.adChannel)
end

function A:text()
  return W.fill(W.db.adTemplate, W.vars())
end

---------------------------------
-- advertiser window: one button, a preview and the cooldown
---------------------------------
function A:build()
  if self.frame then return self.frame end
  local f = CreateFrame("Frame", "SteaWarlockAdFrame", UIParent, "BackdropTemplate")
  f:SetSize(300, 78)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
  f:SetBackdropColor(W.rgb("bg", 0.92))
  f:SetBackdropBorderColor(W.rgb("purple"))
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("TOPLEFT", 8, -6)
  f.label:SetTextColor(W.rgb("purple"))

  f.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.preview:SetPoint("TOPLEFT", 8, -20)
  f.preview:SetPoint("RIGHT", -8, 0)
  f.preview:SetJustifyH("LEFT")
  f.preview:SetTextColor(W.rgb("fg"))

  f.button = CreateFrame("Button", "SteaWarlockAdButton", f, "UIPanelButtonTemplate")
  f.button:SetSize(120, 22)
  f.button:SetPoint("BOTTOM", 0, 6)
  f.button:SetScript("OnClick", function()
    addonData.chat:advertise() -- one post per click
    A:refresh()
  end)

  f:Hide()
  self.frame = f
  return f
end

function A:refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  local _, chanName = self:channel()
  f.label:SetText("Ad to " .. (chanName or (W.db.adChannel .. " (not joined)")))
  f.preview:SetText(self:text())
  local ready, remaining = addonData.chat:adReady()
  if ready then
    f.button:SetText("Post ad")
    f.button:Enable()
  else
    f.button:SetText(string.format("%d:%02d", math.floor(remaining / 60), remaining % 60))
    f.button:Disable()
  end
end

function A:applyRole()
  local show = W.role() == "advertiser"
  local f = self:build()
  if show then f:Show() else f:Hide() end
  self:refresh()
end

W.module("ads", A)

function A:init()
  self:build()
  W.on("WARLOCK_READY", function() A:applyRole() end)
  W.on("ROLE_CHANGED", function() A:applyRole() end)
  W.on("CONFIG_CHANGED", function() A:refresh() end)
  C_Timer.NewTicker(1, function() A:refresh() end)

  W.command("adtext", "adtext <template>: {dest} {price} {lock} are filled in", function(args)
    if args ~= "" then W.db.adTemplate = args end
    W.print("ad:", A:text())
    W.fire("CONFIG_CHANGED")
  end)
  W.command("channel", "channel <name>: ad channel (default Services)", function(args)
    if args ~= "" then W.db.adChannel = args end
    local id, name = A:channel()
    W.print("ad channel:", W.db.adChannel, id and ("joined as " .. id .. ". " .. name) or "(not joined)")
    W.fire("CONFIG_CHANGED")
  end)
  W.command("lock", "lock <name>: warlock name for advertiser ads", function(args)
    if args ~= "" then W.db.lockName = args end
    W.print("warlock for ads:", W.lockName())
    W.fire("CONFIG_CHANGED")
  end)
end

addonData.ads = A
