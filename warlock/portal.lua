-- Clicker alert: the warlock tells the group when the portal is up, and
-- clicker windows show a banner with the Interact key, a sound and a taskbar
-- flash. It only tells you; you still press the key yourself.
-- Also carries the warlock's destination/price/name to advertiser windows.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local P = {
  PREFIX = "SteaWarlock",
  SAFETY_HIDE = 30, -- a portal never stays up longer than this
  banner = nil,
  upSince = nil,
}

LibStub("AceComm-3.0"):Embed(P)

local function groupChannel()
  if IsInRaid() then return "RAID" end
  if IsInGroup() then return "PARTY" end
  return nil
end

-- payload fields are joined with "+", so strip it from free text
local function clean(s) return (string.gsub(tostring(s or ""), "%+", " ")) end

function P:send(msg)
  local ch = groupChannel()
  if ch then self:SendCommMessage(self.PREFIX, msg, ch) end
end

function P.parse(msg)
  local cmd, rest = string.match(msg or "", "^(%S+)%s?(.*)$")
  if not cmd then return nil end
  local fields = {}
  for f in string.gmatch(rest .. "+", "([^+]*)%+") do table.insert(fields, f) end
  return cmd, fields
end

---------------------------------
-- banner (clicker windows)
---------------------------------
local function interactKey()
  local key = GetBindingKey("INTERACTTARGET")
  if key and key ~= "" then return key end
  return nil
end

function P:buildBanner()
  if self.banner then return self.banner end
  local f = CreateFrame("Frame", "SteaWarlockPortalBanner", UIParent, "BackdropTemplate")
  f:SetSize(560, 74)
  f:SetPoint("TOP", UIParent, "TOP", 0, -120)
  f:SetFrameStrata("HIGH")
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 })
  f:SetBackdropColor(W.rgb("bg", 0.94))
  f:SetBackdropBorderColor(W.rgb("green"))

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.title:SetPoint("TOP", 0, -10)
  f.title:SetTextColor(W.rgb("green"))

  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
  f.sub:SetTextColor(W.rgb("fg"))

  f.who = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.who:SetPoint("BOTTOMRIGHT", -10, 6)
  f.who:SetTextColor(W.rgb("comment"))

  f:EnableMouse(false) -- never steals a click meant for the portal
  f:Hide()
  self.banner = f
  return f
end

function P:showBanner(target, dest)
  local f = self:buildBanner()
  local key = interactKey()
  f.title:SetText("PORTAL UP")
  if key then
    f.sub:SetText("press " .. W.hex("yellow", key) .. " to click it")
    f:SetBackdropBorderColor(W.rgb("green"))
  else
    f.sub:SetText(W.hex("red", "bind \"Interact With Target\" in Key Bindings"))
    f:SetBackdropBorderColor(W.rgb("orange"))
  end
  local who = target ~= "" and ("summoning " .. target) or ""
  if dest and dest ~= "" then who = who .. " to " .. dest end
  f.who:SetText(who)
  f:Show()
  self.upSince = GetTime()
  if W.db.alertSound then
    pcall(PlaySound, (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959, "Master")
  end
  pcall(FlashClientIcon) -- taskbar flash shows through the Moonlight stream
  local since = self.upSince
  C_Timer.After(self.SAFETY_HIDE, function()
    if self.upSince == since then self:hideBanner() end
  end)
end

function P:hideBanner()
  self.upSince = nil
  if self.banner then self.banner:Hide() end
end

---------------------------------
-- messages
---------------------------------
function P:onComm(prefix, msg, dist, sender)
  if prefix ~= self.PREFIX then return end
  if W.shortName(sender) == W.me() then return end
  local cmd, f = P.parse(msg)
  local role = W.role()
  if cmd == "up" then
    if role == "clicker" then self:showBanner(f[1] or "", f[2] or "") end
  elseif cmd == "down" then
    self:hideBanner()
  elseif cmd == "cfg" then
    -- warlock -> advertiser: what the ads should say
    if role == "advertiser" then
      local dest, price, lock = f[1], tonumber(f[2]), f[3]
      if dest and dest ~= "" then W.db.dest = dest end
      if price then W.db.price = price; W.db.prices = {} end
      if lock and lock ~= "" then W.db.lockName = lock end
      W.fire("CONFIG_CHANGED", "remote")
    end
  end
end

function P:sendConfig()
  if W.role() ~= "warlock" then return end
  self:send(string.format("cfg %s+%d+%s", clean(W.db.dest or ""), W.priceFor(W.db.dest), clean(W.me())))
end

W.module("portal", P)

function P:init()
  self:RegisterComm(self.PREFIX, "onComm")

  W.on("PORTAL_UP", function(target)
    if W.role() == "warlock" then
      P:send(string.format("up %s+%s", clean(target), clean(W.destName())))
    end
  end)
  W.on("PORTAL_DOWN", function()
    if W.role() == "warlock" then P:send("down") end
  end)

  -- keep advertisers current: on changes, and when the group changes (throttled)
  local pending = false
  local function soon()
    if pending then return end
    pending = true
    C_Timer.After(5, function() pending = false; P:sendConfig() end)
  end
  W.on("CONFIG_CHANGED", function(source) if source ~= "remote" then soon() end end)
  W.on("GROUP_ROSTER_UPDATE", soon)

  W.command("testportal", "testportal: show the clicker banner here for 5 seconds", function()
    P:showBanner("Test Customer", W.destName())
    C_Timer.After(5, function() P:hideBanner() end)
  end)
end

addonData.portal = P
