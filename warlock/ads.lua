-- Ads tab: our template, one click per post, upstream cooldown.
-- The send itself stays in chat.lua's advertise(), called from a button's
-- OnClick (a hardware event). Nothing here posts on a timer.
-- A page inside the summon window (warlock/tabs.lua).
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local A = { page = nil }

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

-- "General, Trade, Services" or "1, 2, 8": names match from the start of the
-- channel name and work on every character; numbers are that character's own
-- /1 /2 /8 and differ between characters (on the advertiser /8 was LFG)
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

-- the advertiser's ad is only worth posting once the warlock has told it
-- where and for how much (otherwise it would read "WTS summon ? 1g")
function A:synced()
  if W.role() ~= "advertiser" then return true end
  local age = W.db.remoteAt and (W.now() - W.db.remoteAt)
  return (age and age < 120 and W.destName() ~= "?") and true or false
end

---------------------------------
-- the Ads page: channels, sync state, the ad as it will read, Post ad
---------------------------------
function A:buildInto(parent)
  if self.page then return self.page end
  local p = CreateFrame("Frame", "SteaWarlockAdPage", parent)
  p:SetAllPoints(parent)
  p:Hide()

  p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -32)
  p.title:SetText("Post ad")

  p.channels = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.channels:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -56)
  p.channels:SetPoint("RIGHT", p, "RIGHT", -14, 0)
  p.channels:SetJustifyH("LEFT")
  p.channels:SetWordWrap(true)

  p.sync = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.sync:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -84)
  p.sync:SetPoint("RIGHT", p, "RIGHT", -14, 0)
  p.sync:SetJustifyH("LEFT")
  p.sync:SetWordWrap(true)

  -- the ad, as it will read, in its own box
  p.inset = CreateFrame("Frame", nil, p, "InsetFrameTemplate")
  p.inset:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -112)
  p.inset:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -8, 76)
  p.preview = p.inset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.preview:SetPoint("TOPLEFT", p.inset, "TOPLEFT", 12, -12)
  p.preview:SetPoint("RIGHT", p.inset, "RIGHT", -12, 0)
  p.preview:SetJustifyH("LEFT")
  p.preview:SetJustifyV("TOP")
  p.preview:SetWordWrap(true)
  p.preview:SetSpacing(2)

  p.hint = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.hint:SetPoint("BOTTOM", p, "BOTTOM", 0, 50)
  p.hint:SetPoint("LEFT", p, "LEFT", 14, 0)
  p.hint:SetPoint("RIGHT", p, "RIGHT", -14, 0)
  p.hint:SetJustifyH("CENTER")
  p.hint:SetText("One click posts the ad once to each channel. Nothing posts on its own. Change the text and channels under Options > Ads or /ssf adtext, /ssf channels.")

  p.button = CreateFrame("Button", "SteaWarlockAdButton", p, "UIPanelButtonTemplate")
  p.button:SetSize(160, 26)
  p.button:SetPoint("BOTTOM", p, "BOTTOM", 0, 16)
  p.button:SetScript("OnClick", function()
    addonData.chat:advertise() -- one post per click
    A:refresh()
  end)
  p.button:SetScript("OnEnter", function(this)
    GameTooltip:SetOwner(this, "ANCHOR_TOP")
    GameTooltip:AddLine("Post ad")
    GameTooltip:AddLine("Channels: " .. A:channelSummary(), 1, 1, 1, true)
    GameTooltip:AddLine("Posts once to each channel, then counts down " .. tostring(SteaSummonSave and SteaSummonSave.adCooldown or 5)
      .. " minutes before the next round.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  p.button:SetScript("OnLeave", function() GameTooltip:Hide() end)

  self.page = p
  return p
end

function A:refresh()
  local p = self.page
  if not p or not p:IsShown() then return end
  p.channels:SetText(W.hex("comment", "Posts to: ") .. self:channelSummary())
  if W.role() == "advertiser" then
    if self:synced() then
      p.sync:SetText(W.hex("green", "Synced with " .. tostring(W.db.lockName or "the warlock") .. ": ")
        .. W.destName() .. ", " .. W.fmtMoney(W.priceFor(W.destKey())))
    else
      p.sync:SetText(W.hex("orange", "Not synced with the main warlock yet. Group with them, or set their name under Setup."))
    end
  else
    p.sync:SetText(W.hex("comment", "Advertises ") .. W.destName() .. W.hex("comment", " for ") .. W.fmtMoney(W.priceFor(W.destKey())))
  end
  p.preview:SetText(self:text())
  local ready, remaining = addonData.chat:adReady()
  if not self:synced() then
    p.button:SetText("Waiting for warlock")
    p.button:Disable()
  elseif ready then
    p.button:SetText("Post ad")
    p.button:Enable()
  else
    p.button:SetText(string.format("Next ad in %d:%02d", math.floor(remaining / 60), remaining % 60))
    p.button:Disable()
  end
end

W.module("ads", A)

function A:init()
  W.on("ROLE_CHANGED", function() A:refresh() end)
  W.on("CONFIG_CHANGED", function() A:refresh() end)
  C_Timer.NewTicker(1, function() A:refresh() end)

  W.command("adtext", "adtext <template>: {dest} {price} {lock} {spell} are filled in", function(args)
    if args ~= "" then W.db.adTemplate = args end
    W.print("ad:", A:text())
    W.fire("CONFIG_CHANGED")
  end)
  W.command("channels", "channels <General, Trade, Services or numbers>: where one Post ad click posts", function(args)
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
