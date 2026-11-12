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

-- "1, 2, 8" or "General, Trade, Services": numbers are your chat channel
-- numbers (/1, /2, /8), names match from the start of the channel name
function A.parseChannels(text)
  local out = {}
  for token in string.gmatch(text or "", "[^,]+") do
    token = string.gsub(token, "^%s+", "")
    token = string.gsub(token, "%s+$", "")
    if token ~= "" then table.insert(out, tonumber(token) or token) end
  end
  return out
end

-- each listed channel: { want, id, name } (id nil = not joined)
function A:channels()
  local list = { GetChannelList() }
  local out = {}
  for _, want in ipairs(A.parseChannels(W.db.adChannels)) do
    local id, name
    if type(want) == "number" then
      for i = 1, #list do
        if list[i] == want and type(list[i + 1]) == "string" then id, name = want, list[i + 1] end
      end
    else
      id, name = A.findChannel(list, want)
    end
    table.insert(out, { want = want, id = id, name = name })
  end
  return out
end

-- joined channel ids to post to, in your order, no repeats
function A:targets()
  local ids, seen = {}, {}
  for _, c in ipairs(self:channels()) do
    if c.id and not seen[c.id] then seen[c.id] = true; table.insert(ids, c.id) end
  end
  return ids
end

function A:channelSummary()
  local parts = {}
  for _, c in ipairs(self:channels()) do
    local label = tostring(c.want)
    if c.id then
      table.insert(parts, W.hex("green", label .. " " .. (c.name or "")))
    else
      table.insert(parts, W.hex("orange", label .. " (not joined)"))
    end
  end
  return #parts > 0 and table.concat(parts, ", ") or W.hex("orange", "no channels listed")
end

-- old single-channel lookup, kept for callers that want the first joined one
function A:channel()
  local c = self:channels()
  for _, x in ipairs(c) do if x.id then return x.id, x.name end end
  return nil
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
  f:SetSize(300, 84)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
  W.stockBackdrop(f, nil, 0.9)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("TOPLEFT", 10, -8)

  f.preview = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.preview:SetPoint("TOPLEFT", 10, -22)
  f.preview:SetPoint("RIGHT", -10, 0)
  f.preview:SetJustifyH("LEFT")

  f.button = CreateFrame("Button", "SteaWarlockAdButton", f, "UIPanelButtonTemplate")
  f.button:SetSize(140, 22)
  f.button:SetPoint("BOTTOM", 0, 8)
  f.button:SetScript("OnClick", function()
    addonData.chat:advertise() -- one post per click
    A:refresh()
  end)
  f.button:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Post ad")
    GameTooltip:AddLine("Channels: " .. A:channelSummary(), 1, 1, 1, true)
    GameTooltip:AddLine("One click posts the ad once to each channel, then counts down " .. tostring(SteaSummonSave and SteaSummonSave.adCooldown or 5)
      .. " minutes. Nothing posts on its own.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  f.button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  f:Hide()
  self.frame = f
  return f
end

-- the advertiser's ad is only worth posting once the warlock has told it
-- where and for how much (otherwise it would read "WTS summon ? 1g")
function A:synced()
  if W.role() ~= "advertiser" then return true end
  local age = W.db.remoteAt and (W.now() - W.db.remoteAt)
  return (age and age < 120 and W.destName() ~= "?") and true or false
end

function A:refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  local synced = self:synced()
  f.label:SetText("Ad to " .. self:channelSummary())
  f.preview:SetText(self:text())
  -- the window grows with the ad text instead of spilling past the border
  local textH = f.preview:GetStringHeight() or 12
  f:SetHeight(math.max(84, 22 + textH + 44))
  local ready, remaining = addonData.chat:adReady()
  if not synced then
    f.button:SetText("Waiting for warlock")
    f.button:Disable()
  elseif ready then
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
  W.command("channels", "channels <1, 2, 8 or names>: where one Post ad click posts", function(args)
    if args ~= "" then W.db.adChannels = args end
    W.print("ad channels:", A:channelSummary())
    W.fire("CONFIG_CHANGED")
  end)
  W.commands.channel = W.commands.channels -- old name
  W.command("lock", "lock <name>: warlock name for advertiser ads", function(args)
    if args ~= "" then W.db.lockName = args end
    W.print("warlock for ads:", W.lockName())
    W.fire("CONFIG_CHANGED")
  end)
end

addonData.ads = A
