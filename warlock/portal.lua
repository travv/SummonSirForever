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
  W.stockBackdrop(f, "green", 0.9)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  f.title:SetPoint("TOP", 0, -10)
  f.title:SetTextColor(W.rgb("green"))

  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
  f.sub:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
  f.sub:SetTextColor(W.rgb("fg"))

  f.who = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.who:SetPoint("BOTTOMRIGHT", -10, 6)
  f.who:SetTextColor(W.rgb("comment"))

  -- a thin bar that drains over the 30 s the portal can stay up, so a
  -- clicker who looks up late can see how much time is left
  f.bar = CreateFrame("StatusBar", nil, f)
  f.bar:SetPoint("BOTTOMLEFT", 10, 7)
  f.bar:SetPoint("RIGHT", f.who, "LEFT", -12, 0)
  f.bar:SetHeight(4)
  f.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  f.bar:SetStatusBarColor(W.rgb("green"))
  f.bar:SetMinMaxValues(0, 1)
  f.bar:SetValue(1)
  f:SetScript("OnUpdate", function(this)
    if P.upSince then
      this.bar:SetValue(math.max(0, 1 - (GetTime() - P.upSince) / P.SAFETY_HIDE))
    end
  end)

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
    f.sub:SetText(W.hex("red", "bind it: Key Bindings > Targeting > Interact With Target"))
    f:SetBackdropBorderColor(W.rgb("orange"))
  end
  local who = target ~= "" and ("summoning " .. target) or ""
  if dest and dest ~= "" then who = who .. " to " .. dest end
  f.who:SetText(who)
  f.bar:SetValue(1)
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
    -- warlock -> advertiser: where the warlock summons to and for how much
    if role == "advertiser" then
      P.applyConfig(f, W.shortName(sender))
    end
  elseif cmd == "cfgreq" then
    -- advertiser -> warlock: "what should my ad say?" (works ungrouped too)
    if role == "warlock" then
      P.advertisers[W.shortName(sender)] = true
      P:sendConfig(W.shortName(sender))
      P:promoteAdvertisers()
    end
  end
end

-- cfg payload: destKey + price + warlock name + destination name
function P.configPayload()
  return string.format("cfg %s+%d+%s+%s", clean(W.destKey() or ""), W.priceFor(W.destKey()),
    clean(W.me()), clean(W.destName()))
end

function P.applyConfig(f, sender)
  local key, price, lock, destName = f[1], tonumber(f[2]), f[3], f[4]
  W.db.dest = (key and key ~= "") and key or nil
  if price then W.db.remotePrice = price end
  if destName and destName ~= "" then W.db.remoteDest = destName end
  W.db.lockName = (lock and lock ~= "") and lock or sender or W.db.lockName
  W.db.remoteAt = W.now()
  W.fire("CONFIG_CHANGED", "remote")
end

-- to the group, or to one advertiser by whisper
function P:sendConfig(to)
  if W.role() ~= "warlock" then return end
  local msg = P.configPayload()
  if to then
    self:SendCommMessage(self.PREFIX, msg, "WHISPER", to)
  else
    self:send(msg)
  end
end

-- advertisers need invite rights: in a raid, assist; a party is made a raid first
P.advertisers = {}
function P:promoteAdvertisers()
  if not UnitIsGroupLeader("player") or InCombatLockdown() then return end
  local any = false
  for name in pairs(P.advertisers) do
    if UnitInParty(name) or UnitInRaid(name) then
      any = true
      if IsInRaid() and not UnitIsGroupAssistant(name) then
        C_PartyInfo.PromoteToAssistant(name)
      end
    end
  end
  if any and not IsInRaid() then C_PartyInfo.ConvertToRaid() end
end

-- advertiser: ask the warlock (group if grouped, else whisper the saved name)
function P:requestConfig()
  if W.role() ~= "advertiser" then return end
  if IsInGroup() then
    self:send("cfgreq")
  elseif W.db.lockName and W.db.lockName ~= "" then
    self:SendCommMessage(self.PREFIX, "cfgreq", "WHISPER", W.db.lockName)
  end
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
  W.on("GROUP_ROSTER_UPDATE", function()
    soon()
    C_Timer.After(2, function() P:promoteAdvertisers() end)
    C_Timer.After(2, function() P:requestConfig() end)
  end)
  -- the warlock moving changes the ad when no preset destination is set
  W.on("ZONE_CHANGED_NEW_AREA", soon)
  hooksecurefunc(addonData.summon, "setDestination", soon)
  W.on("WARLOCK_READY", function() C_Timer.After(5, function() P:requestConfig() end) end)
  C_Timer.NewTicker(30, function() P:requestConfig() end)

  W.command("testportal", "testportal: show the clicker banner here for 5 seconds", function()
    P:showBanner("Test Customer", W.destName())
    C_Timer.After(5, function() P:hideBanner() end)
  end)
end

addonData.portal = P
