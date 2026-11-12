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
      -- "Trade - City" for a name you typed; "2 Trade - City" for a number
      local shown = c.name or label
      if type(c.want) == "number" then shown = label .. " " .. shown end
      table.insert(parts, W.hex("green", shown))
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

-- one short line per destination for the {blurb} placeholder, so the ad says
-- why someone would want THIS spot instead of the Desolace line everywhere
A.BLURBS = {
  sm = "Skip the run through Tirisfal.",
  bb = "Flight path, neutral AH, Stranglethorn quests.",
  gadget = "Zul'Farrak and the Tanaris quest hub.",
  ulda = "Skip the Badlands run.",
  desolace = "Flight path and quest turn-ins.",
  zf = "Skip the Tanaris run.",
  mara = "Skip the Desolace run.",
  rfk = "Skip the Barrens run.",
  rfd = "Skip the Barrens run.",
  gnomer = "Skip the Dun Morogh run.",
  sfk = "Skip the Silverpine run.",
  st = "Skip the swamp run.",
  brd = "Straight to the mountain.",
  brs = "Straight to the mountain.",
  mc = "Straight to the raid.",
  ony = "Straight to the raid.",
  bwl = "Straight to the raid.",
  zg = "Straight to the raid.",
  aq = "Straight to the raid.",
  naxx = "Straight to the raid.",
  dire = "Skip the Feralas run.",
  strat = "Skip the Plaguelands run.",
  scholo = "Skip the Plaguelands run.",
  everlook = "Flight path and Winterspring quests.",
  silithus = "Cenarion Hold flight path.",
  ungoro = "Flight path and quest turn-ins.",
  felwood = "Flight path and quests.",
  epl = "Light's Hope flight path.",
  wpl = "Flight path and quests.",
  stv = "Stranglethorn quests.",
  tanaris = "Gadgetzan flight path.",
  feralas = "Flight path and quest hub.",
  azshara = "Skip the long walk.",
  searing = "Thorium Point flight path.",
  steppes = "Flight path and quests.",
  blasted = "Dark Portal quests.",
  tm = "Flight path and quests.",
  xroads = "Flight path and quests.",
  hinter = "Flight path and quests.",
  dustwallow = "Theramore flight path.",
  org = "Skip the travel.", tb = "Skip the travel.", uc = "Skip the travel.",
  sw = "Skip the travel.", ifo = "Skip the travel.", darn = "Skip the travel.",
}
A.DEFAULT_BLURB = "Skip the walk."

function A.blurbFor(destKey)
  return (destKey and A.BLURBS[destKey]) or A.DEFAULT_BLURB
end

function A:text()
  return W.fill(W.db.adTemplate, W.vars())
end

---------------------------------
-- channel picker: one checkbox per channel this character has joined
---------------------------------
-- "General - Ironforge" -> "General"
function A.baseName(name)
  return (string.match(name or "", "^(.-)%s+%-%s+.+$") or name or "")
end

-- channels this character is in: { id, full, name }
function A:joined()
  local list = { GetChannelList() }
  local out = {}
  for i = 1, #list, 3 do
    if type(list[i]) == "number" and type(list[i + 1]) == "string" then
      table.insert(out, { id = list[i], full = list[i + 1], name = A.baseName(list[i + 1]) })
    end
  end
  return out
end

-- is a joined channel (by base name) in the ad list, by name or by number?
function A:listed(name)
  for _, c in ipairs(self:channels()) do
    if c.id and A.baseName(c.name) == name then return true end
  end
  return false
end

-- add or remove a channel; numeric entries are rewritten as names on the way
function A:setListed(name, on)
  local names, seen = {}, {}
  for _, c in ipairs(self:channels()) do
    local base = c.id and A.baseName(c.name) or tostring(c.want)
    if base ~= name and not seen[base] then seen[base] = true; table.insert(names, base) end
  end
  if on and not seen[name] then table.insert(names, name) end
  W.db.adChannels = table.concat(names, ", ")
  W.fire("CONFIG_CHANGED")
end

A.MAX_PICK = 8

-- a grid of checkboxes that edits W.db.adChannels; call picker.refresh()
function A:buildPicker(parent, x, y, cols, colW)
  local p = CreateFrame("Frame", nil, parent)
  p:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  p:SetSize(cols * colW, math.ceil(A.MAX_PICK / cols) * 22)
  p.boxes = {}
  for i = 1, A.MAX_PICK do
    local c = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    c:SetPoint("TOPLEFT", p, "TOPLEFT", col * colW, -row * 22)
    c.label = c:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    c.label:SetWidth(colW - 30)
    c.label:SetJustifyH("LEFT")
    c.label:SetWordWrap(false)
    c:SetScript("OnClick", function(this)
      if this.chan then A:setListed(this.chan, this:GetChecked() and true or false) end
      p.refresh()
    end)
    c:Hide()
    p.boxes[i] = c
  end
  p.more = p:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  p.more:SetPoint("TOPLEFT", p, "BOTTOMLEFT", 0, -2)
  p.more:SetJustifyH("LEFT")
  function p.refresh()
    local items, seen = {}, {}
    for _, j in ipairs(A:joined()) do
      if not seen[j.name] then seen[j.name] = true; table.insert(items, { name = j.name, full = j.full, joined = true }) end
    end
    for _, c in ipairs(A:channels()) do
      if not c.id and type(c.want) == "string" and not seen[c.want] then
        seen[c.want] = true
        table.insert(items, { name = c.want, full = c.want .. " (not joined)", joined = false })
      end
    end
    for i, box in ipairs(p.boxes) do
      local it = items[i]
      if it then
        box.chan = it.name
        box.label:SetText(it.joined and it.full or W.hex("orange", it.full))
        box:SetChecked(it.joined and A:listed(it.name) or not it.joined)
        box:Show()
      else
        box.chan = nil
        box:Hide()
      end
    end
    if #items == 0 then
      p.more:SetText(W.hex("orange", "You are not in any chat channel. /join General, /join Trade ..."))
    elseif #items > #p.boxes then
      p.more:SetText("+" .. (#items - #p.boxes) .. " more: /ssf channels")
    else
      p.more:SetText("")
    end
  end
  return p
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
  p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 62, -30) -- right of the portrait circle
  p.title:SetText("Post ad")

  p.pickLabel = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  p.pickLabel:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -56)
  p.pickLabel:SetText("Posts to the checked channels:")
  p.picker = A:buildPicker(p, 14, -70, 2, 215)

  p.sync = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  p.sync:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -170)
  p.sync:SetPoint("RIGHT", p, "RIGHT", -14, 0)
  p.sync:SetJustifyH("LEFT")
  p.sync:SetWordWrap(true)

  -- the ad, as it will read, in its own box
  p.inset = CreateFrame("Frame", nil, p, "InsetFrameTemplate")
  p.inset:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -196)
  p.inset:SetPoint("RIGHT", p, "RIGHT", -8, 0)
  p.inset:SetHeight(60) -- refresh() fits it to the ad text
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
  p.picker.refresh()
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
  p.inset:SetHeight(math.max(44, (p.preview:GetStringHeight() or 20) + 24))
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

  W.command("adtext", "adtext <template>: {dest} {price} {blurb} {lock} {spell} are filled in", function(args)
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
