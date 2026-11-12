_,addonData = ...
local L = LibStub("AceLocale-3.0"):GetLocale("SummonSirForever")
local g_self -- for callbacks

-- API compat: the WoW: Forever client removed these classic-era globals
local GetSpellInfo = GetSpellInfo or function(spellID)
  local info = C_Spell.GetSpellInfo(spellID)
  if info then
    return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
  end
end
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)

-- mana can be a secret value on the Forever client that addon code may not
-- compare; when unknown, assume there is enough to summon (no auto life tap)
local function hasSummonMana()
  local ok, result = pcall(function() return UnitPower("player") >= 300 end)
  return (not ok) or result
end

-- "Location: Nijel's Point, Desolace" with the label in the standard gold
local function goldLabel(text)
  return (string.gsub(text, "^([^:]+:)", "|cffffd200%1|r", 1))
end
local DESTINATION_UNSET = "|cffffd200Destination:|r |cff808080not set. Click to summon to where you stand.|r"
local NEXT_MARK = "|cff1aff1aNEXT|r"
local DESTINATION_TEAM = "|cffffd200Destination:|r |cff808080the warlock sets it; it shows here once pinned.|r"
local MAX_RAID = 40

-- API compat: create a frame, falling back to another (or no) template when the
-- client no longer ships the classic-era one
local function CreateFrameCompat(frameType, name, parent, template, fallbackTemplate)
  local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
  if ok then return frame end
  return CreateFrame(frameType, name, parent, fallbackTemplate)
end

local summon = {
  waiting = {}, -- the summon list
  numwaiting = 0, -- the summon list length
  afk = false, -- while AFK: auto invites pause, asks get an AFK whisper
  afkReplied = {}, -- players already given the AFK reply this session
  hasSummoned = false, -- when true we believe you more
  tainted = false, -- indicates player has cancelled something that's nothing to do with them
  myLocation = "", -- the location player is
  myZone = "", -- the zone player is
  location = "", -- area of zone summons are going to
  zone = "", -- the zone summons are going to
  summoningPlayer = "", -- the player currently being summoned
  shards = 0, -- the number of shards in our bag
  isWarlock = false,
  infoSend = false,
  me = "",
  dirty = true, -- waiting list changed flag, to begin we want to show load list so default dirty
  postInit = false,
  isCasting = false,
  buffLetter = {
    ["Warlock"] = L["W"],
    ["Buffed"] = L["B"],
    ["Normal"] = L["N"],
    ["Prioritized"] = L["P"],
    ["Last"] = L["L"]
  },
  localLocks = 0,
  localClickers = 0,
  needBoost = false,
  show = nil,
  nextIdx = nil,
  countSummoned = 0,
  shrunk = false,

  reConfigureFrames = function(self)
    if SteaSummonFrame and not SteaSummonFrame.location then
      -- header line 1, left: where the warlock stands (shared text: counts sit to its right)
      SteaSummonFrame.location = (SteaSummonFrame.queuePage or SteaSummonFrame):CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      SteaSummonFrame.location:SetPoint("TOPLEFT", "SteaSummonFrame", "TOPLEFT", 62, -27) -- right of the portrait
      SteaSummonFrame.location:SetPoint("RIGHT", "SteaSummonFrame", "RIGHT", -160, 0)
      SteaSummonFrame.location:SetJustifyH("LEFT")
      SteaSummonFrame.location:SetWordWrap(false)
      SteaSummonFrame.location:SetText("")
    end

    if SteaSummonFrame and not SteaSummonFrame.destination then
      -- header line 2, left: where summons go (click to set / unset)
      SteaSummonFrame.destination = (SteaSummonFrame.queuePage or SteaSummonFrame):CreateFontString(nil, "ARTWORK", "GameFontHighlight")
      SteaSummonFrame.destination:SetPoint("TOPLEFT", "SteaSummonFrame", "TOPLEFT", 62, -46)
      SteaSummonFrame.destination:SetPoint("RIGHT", "SteaSummonFrame", "RIGHT", -92, 0)
      SteaSummonFrame.destination:SetJustifyH("LEFT")
      SteaSummonFrame.destination:SetWordWrap(false)
      SteaSummonFrame.destination:SetText(DESTINATION_UNSET)
    end

    if SteaSummonFrame and not SteaSummonFrame.status then
      -- header line 1, right: warlock / clicker counts in the group
      SteaSummonFrame.status = (SteaSummonFrame.queuePage or SteaSummonFrame):CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
      SteaSummonFrame.status:SetPoint("TOPRIGHT", "SteaSummonFrame", "TOPRIGHT", -14, -29)
      SteaSummonFrame.status:SetJustifyH("RIGHT")
      SteaSummonFrame.status:SetWordWrap(false)
      SteaSummonFrame.status:SetText("")
    end
    
  end,
  
  ---------------------------------
  init = function(self)
    g_self = self
    addonData.debug:registerCategory("summon.display")
    addonData.debug:registerCategory("summon.waitlist.record")
    addonData.debug:registerCategory("summon.tick")
    addonData.debug:registerCategory("summon.misc")
    addonData.debug:registerCategory("summon.spellcast")

    self.isWarlock = addonData.util:playerIsWarlock()
    self.me = addonData.util:playerFullName()
    self.me = strsplit("-", self.me)

    self.waiting = SteaSummonSave.waiting
    self.numwaiting = #self.waiting
    self.postInit = true

    -- fix up for old version things (they could be lurking in alts for months)
    -- and before the table gets cleared something may access the data and blow up
    if self.waiting then
      for _,v in pairs(self.waiting) do
        -- make sure altwhispered is numeric (was a string)
        if #v > 6 then -- have alts
          if type(self:recAltWhispered(v) == "string") then
            self:recAltWhispered(v, "x")
          end
        end
      end
    end

    -- there seems to be no good event/time to check if we are in a group
    -- group roster changes fail to tell us when we are NOT in a group
    -- so we're gonna bodge this one, worst case is it takes a while to clear the list
    C_Timer.After(10, self.postInitSetup) -- bumped to 10 seconds, after laggy server experiences, an eternity I know
  end,

  ---------------------------------
  postInitSetup = function(self)
    self = addonData.summon

    if not self.postInit then
      return
    end
    self.postInit = false

    local ts = GetTime()

    if not IsInGroup(LE_PARTY_CATEGORY_HOME)
        or SteaSummonSave.waitingKeepTime == 0
        or ts - 10 - SteaSummonSave.timeStamp > SteaSummonSave.waitingKeepTime * 60 then -- -10 for the bodge factor
      db("wiping wait list")
      db("saved mins", (ts - 10 - SteaSummonSave.timeStamp)/60, "keep mins", SteaSummonSave.waitingKeepTime)
      db("group status:", IsInGroup(LE_PARTY_CATEGORY_HOME))
      self:listClear()
    else
      addonData.gossip:raidJoined()
    end

    -- good time for a version check -- this goes to guild if not in raid
    addonData.gossip:SteaSummonVersion()
  end,

  ---------------------------------
  setClicks = function(self, locks, clicks)
    self.localLocks = tonumber(locks)
    self.localClickers = tonumber(clicks)
    self:headerCounts()
  end,

  ---------------------------------
  -- header line 1, right side: "Clickers 2   Raid 7/40". Clickers turn
  -- green once there are enough people at the destination to click the
  -- portal; the raid count turns orange near full and red when full, since
  -- invites fail silently past 40
  headerCounts = function(self)
    if not SteaSummonFrame then
      return
    end
    if not SteaSummonFrame.status then
      self:reConfigureFrames()
    end
    if not IsInGroup(LE_PARTY_CATEGORY_HOME) then
      SteaSummonFrame.status:SetText("|cff808080not grouped|r")
      return
    end
    local parts = {}
    if self.location ~= "" and self.zone ~= nil and self.localLocks then
      local enough = self.localLocks + self.localClickers > 2
      local color = enough and "|cff1aff1a" or "|cffffffff"
      table.insert(parts, color .. L["Clickers"] .. " " .. tostring(self.localClickers) .. "|r")
    end
    local n = GetNumGroupMembers() or 0
    local color = "|cffffffff"
    if n >= MAX_RAID - 1 then
      color = "|cffff2020"
    elseif n >= MAX_RAID - 5 then
      color = "|cffff8040"
    end
    table.insert(parts, color .. "Raid " .. n .. "/" .. MAX_RAID .. "|r")
    SteaSummonFrame.status:SetText(table.concat(parts, "   "))
  end,

  ---------------------------------
  listClear = function(self)
    wipe(self.waiting)
    self.numwaiting = 0
    self:listDirty(true)
  end,

  ---------------------------------
  listDirty = function(self, dirty)
    if dirty ~= nil then
      self.dirty = dirty
    end
    addonData.monitor:start()
    return self.dirty
  end,

  ---------------------------------
  waitRecord = function(self, player, time, status, prioReason, buffs, alts, altwhispered)
    local rec
    assert(player)
    rec = {
      player,
      time or 0,
      status or "requested",
      prioReason or "Normal",
      true, -- dirty flag
      buffs or {},
      alts or {},
      altwhispered or "x"
    }
    db("summon.waitlist.record","Created record {",
        self:recPlayer(rec), self:recTime(rec), self:recStatus(rec), self:recPrio(rec), true,
        self:recBuffs(rec), self:recAlts(rec), self:recAltWhispered(rec), "}")

    return rec
  end,

  ---------------------------------
  recMarshal = function(self, rec)
    return self:recPlayer(rec)
        .. "+" .. self:recTime(rec)
        .. "+" .. self:recStatus(rec)
        .. "+" .. self:recPrio(rec)
        .. "+" .. addonData.buffs:marshallBuffs(self:recBuffs(rec))
        .. "+" .. self:recMarshallAlts(rec)
        .. "+" .. self:recAltWhispered(rec)
  end,

  ---------------------------------
  recUnMarshal = function(self, data)
    if data then
      local player, time, status, prio, buffs, alts, altwhispered = strsplit("+", data)
      if player and time and status and prio and buffs and alts and altwhispered then
        return self:waitRecord(player, time, status, prio, addonData.buffs:unmarshallBuffs(buffs),
            self:unmarshallAlts(alts), altwhispered)
      else
        db("summon.waitlist.record", "unmarshalled data contains nil", player, time, status, prio, buffs)
      end
    else
      db("summon.waitlist.record", "tried to unmarshal nil")
    end
  end,

  ---------------------------------
  recPlayer = function(self, rec, val)
    if val then
      self:listDirty(true)
      db("summon.waitlist.record","setting record player value:", val)
      rec[1] = val
    end
    return rec[1]
  end,

  ---------------------------------
  recTime = function(self, rec, val)
    if val then
      self:listDirty(true)
      db("summon.waitlist.record","setting record time value:", val)
      rec[2] = val
    end
    return rec[2]
  end,

  ---------------------------------
  recTimeIncr = function(self, rec)
    self:listDirty(true)
    rec[2] = rec[2] + 1
    if rec[8] and rec[8] ~= "x" then
      rec[8] = rec[8] + 1
    end
    db("summon.tick","setting record time value:", rec[2], rec[8]) -- too verbose for summon.waitlist.record

    return rec[2]
  end,

  ---------------------------------
  recStatus = function(self, rec, val)
    if val then
      self:listDirty(true)
      db("summon.waitlist.record","setting record status value:", val)
      rec[3] = val
    end
    return rec[3]
  end,

  ---------------------------------
  recPrio = function(self, rec, val)
    if val then
      self:listDirty(true)
      db("summon.waitlist.record","setting record priority reason value:", val)
      rec[4] = val
    end
    return rec[4]
  end,

  ---------------------------------
  recNew = function(self, rec, val)
    if val ~= nil then
      self:listDirty(true)
      db("summon.waitlist.record","setting record new value:", val)
      rec[5] = val
    end
    return rec[5]
  end,

  ---------------------------------
  recBuffs = function(self, rec, val)
    if val ~= nil then
      self:listDirty(true)
      db("summon.waitlist.record","setting record buffs value:", val)
      rec[6] = val
    end
    return rec[6] or {}
  end,

  ---------------------------------
  recAlts = function(self, rec, val)
    if val ~= nil then
      self:listDirty(true)
      db("summon.waitlist.record","setting record alts value:", val)
      rec[7] = {}
      rec[7] = self:recMergeAlts(rec, val) -- duplicate proof add
    end
    return rec[7] or {}
  end,

  ---------------------------------
  marshallAlts = function(_, alts)
    local out = ""
    local spacer = ""
    for _,v in pairs(alts) do
      if v and v ~= "" then
        out = out .. spacer .. v
        spacer = "&"
      end
    end
    return out
  end,

  ---------------------------------
  recMarshallAlts = function(self, rec)
    return self:marshallAlts(rec[7])
  end,

  ---------------------------------
  unmarshallAlts = function(_, marshalled)
    local out = {}
    local tmpOut = { strsplit("&", marshalled) }
    for i,v in pairs(tmpOut) do
      if v and v ~= "" then
        db("summon.waitlist.record", "unmarshalling", v)
        out[i] = v
      end
    end
    return out
  end,

  ---------------------------------
  recMergeAlts = function(_, rec, alts)
    db("summon.waitlist.record","merging alts:", alts)
    local oldAlts = rec[7] or {}
    local newAlts = {}
    local altMap = {} -- for duplicates in new map
    local newIdx = 1

    for _,alt in pairs(alts) do
      if not altMap[alt] then
        local add = true
        for _,oldAlt in pairs(oldAlts) do
          if alt == oldAlt then
            add = false
            break
          end
        end
        if add then
          altMap[alt] = true
          newAlts[newIdx] = alt
          newIdx = newIdx + 1
        end
      end
    end

    for _,v in pairs(newAlts) do
      db("summon.waitlist.record", "merging alt", v)
      table.insert(oldAlts, v)
    end

    rec[7] = oldAlts -- in case we made it
    return rec[7]
  end,

  ---------------------------------
  recAltWhispered = function(self, rec, val)
    if val ~= nil then
      self:listDirty(true)
      db("summon.waitlist.record","setting record alt whispered:", val)
      rec[8] = val
    end
    return rec[8]
  end,

  ---------------------------------
  recRemove = function(self, player)
    local ret = false
    local idx = self:findWaitingPlayerIdx(player)
    if idx then
      ret = self:recRemoveIdx(idx)
    end
    return ret
  end,

  ---------------------------------
  recRemoveIdx = function(self, idx)
    local ret = false
    if idx and type(idx) == "string" then
      idx = tonumber(idx)
    end
    -- check the real list, not the cached count: when the two drift apart
    -- (list replaced by a sync, count not), removals were refused
    if idx and idx >= 1 and idx <= #self.waiting then
      self:listDirty(true)
      db("summon.waitlist.record", "removing", self:recPlayer(self.waiting[idx]), "from the waiting list")
      table.remove(self.waiting, idx)
      ret = true
    else
      db("summon.waitlist.record","invalid index for remove", idx, "max:", #self.waiting)
    end
    self.numwaiting = #self.waiting
    return ret
  end,

  recAdd = function(self, rec, pos)
    self:listDirty(true)
    if not pos or pos > self.numwaiting then
      db("summon.waitlist.record","appending record to waiting list for", self:recPlayer(rec))
      table.insert(self.waiting, rec)
    else
      db("summon.waitlist.record","adding record to waiting list index", pos,"for", self:recPlayer(rec))
      table.insert(self.waiting, pos, rec)
    end
    self.numwaiting = self.numwaiting + 1
  end,

  ---------------------------------
  addWaiting = function(self, player, fromPlayer)
    local name, realm = strsplit("-", player)
    if realm == GetRealmName() then
        player = name
    end
    
    -- IsInGroup takes a category constant, not a player (same fix as chat.lua)
    if not (UnitInParty(player) or UnitInRaid(player) or player == self.me) then
      return nil
    end

    if (fromPlayer) then
      local isWaiting = self:findWaitingPlayer(player)
      if isWaiting then
        db("summon.waitlist", "Resetting status of player", player, "to requested")
        self:recStatus(isWaiting, "requested")-- allow those in summon queue to reset status when things go wrong
        return
      end
    else
      if self:findWaitingPlayer(player) then
        return nil
      end
    end
    db("summon.waitlist", "Making some space for ", player)

    -- priorities
    local inserted = false
    local buffs = addonData.buffs:report(player)

    -- Prio warlock
    if SteaSummonSave.warlocks and addonData.util:playerCanSummon(player)
        and #buffs == 0 and self.localLocks < SteaSummonSave.maxLocks then
      for k, wait in pairs(self.waiting) do
        if self:recPrio(wait) ~= "Warlock" then
          db("summon.waitlist", "Warlock", player, "gets prio")
          self:recAdd(self:waitRecord(player, 0, "requested", "Warlock"), k)
          inserted = true
          break
        end
      end
      if not inserted then
        db("summon.waitlist", "Warlock", player, "gets prio")
        self:recAdd(self:waitRecord(player, 0, "requested", "Warlock"))
        inserted = true
      end
    end

    -- Prio buffs
    if not inserted and SteaSummonSave.buffs == true and #buffs > 0 then
      for k, wait in pairs(self.waiting) do
        if (self:recPrio(wait) ~= "Warlock" and self:recPrio(wait) ~= "Buffed")
            or (self:recPrio(wait) == "Buffed" and #self:recBuffs(wait) < #buffs) then
          self:recAdd(self:waitRecord(player, 0, "requested", "Buffed"), k)
          db("summon.waitlist", "Buffed " .. player .. " gets prio")
          inserted = true
          break
        end
      end
      if not inserted then
        self:recAdd(self:waitRecord(player, 0, "requested", "Buffed"))
        db("summon.waitlist", "Buffed " .. player .. " gets prio")
        inserted = true
      end
    end

    -- Prio list
    if not inserted and addonData.settings:findPrioPlayer(player) ~= nil then
      for k, wait in pairs(self.waiting) do
        if not (self:recPrio(wait) == "Warlock" or self:recPrio(wait) == "Buffed"
            or addonData.settings:findPrioPlayer(self:recPlayer(wait))) then
          self:recAdd(self:waitRecord(player, 0, "requested", "Prioritized"), k)
          db("summon.waitlist", "Priority " .. player .. " gets prio")
          inserted = true
          break
        end
      end
      if not inserted then
        self:recAdd(self:waitRecord(player, 0, "requested", "Prioritized"))
        db("summon.waitlist", "Priority " .. player .. " gets prio")
        inserted = true
      end
    end

    -- Prio last
    if not inserted and addonData.settings:findShitlistPlayer(player) ~= nil then
      self:recAdd(self:waitRecord(player, 0, "requested", "Last"))
      inserted = true
    end

    -- Prio normal
    if not inserted then
      local i = self.numwaiting + 1
      while i > 1 and self:recPrio(self.waiting[i-1]) == "Last"
          and not (self:recPrio(self.waiting[i-1]) == "Buffed"
          or self:recPrio(self.waiting[i-1]) == "Warlock"
          or self:recPrio(self.waiting[i-1]) == "Prioritized") do
        db("summon.waitlist", self:recPlayer(self.waiting[i-1]), "on shitlist, finding a better spot")
        i = i - 1
      end
      self:recAdd(self:waitRecord(player, 0, "requested", "Normal"), i)
    end

    local rec = self:findWaitingPlayer(player)
    self:recBuffs(rec, buffs)

    db("summon.waitlist", player .. " added to waiting list")
    self:showSummons()
    if addonData.W then addonData.W.queueAdded(player) end
  end,

  ---------------------------------
  timerSecondTick = function(self)
    --- update timers
    -- yea this is dumb, but time doesnt really work in wow
    -- so we count (rough) second ticks for how long someone has been waiting
    -- and need to update each individually (a global would wrap)
    for _, wait in pairs(self.waiting) do
      self:recTimeIncr(wait)
    end
  end,

  ---------------------------------
  -- arrival self-report: range APIs are secret on the Forever client, but
  -- zone text is not, so each addon user detects reaching the destination
  -- themselves and tells everyone
  reportSelfArrival = function(self)
    self = addonData.summon
    if self.zone ~= "" and self:findWaitingPlayer(self.me) and self:isAtDestination() then
      db("summon.waitlist", "arrived at destination, reporting self")
      addonData.gossip:arrived(self.me, false)
    end
  end,

  ---------------------------------
  zoneChanged = function()
    local self = addonData.summon
    self:setCurrentLocation()
    self:reportSelfArrival()
  end,

  ---------------------------------
  tick = function(self)
    --- detect arriving players
    local players = {}
    for _, wait in pairs(self.waiting) do
      local player = self:recPlayer(wait)
      if addonData.util:playerClose(player) then
        db("summon.tick", player .. " detected close by")
        table.insert(players, player) -- don't mess with tables while iterating on them
      end
    end

    for _, player in pairs(players) do
      local z, l = self:getCurrentLocation()
      if z == self.zone and l == self.location -- at destination, anyone can report
          or (self.countSummoned > 0 and self.zone == "" and self.location == "") -- no destination, anyone can report
          or player == self.summoningPlayer then -- summoner can report
        addonData.gossip:arrived(player, false) -- let everyone else know
      end
    end

    --- update display
    self:showSummons()

    --- update our location
    self:setCurrentLocation()
    self:reportSelfArrival()
  end,

  ---------------------------------
  getWaiting = function(self) return self.waiting end,

  ---------------------------------
  showSummons = function(self)
    if InCombatLockdown() then
      return
    end

    self = addonData.summon -- often we are not ourselves, be positive

    if not SteaSummonFrame then

      -- Stock Forever window: ButtonFrameTemplate gives the title bar, the
      -- portrait circle (we put the Ritual of Summoning icon in it), the
      -- close button and an inset for the queue. Header below the title:
      --   line 1: Location ............ Warlocks n  Clickers n
      --   line 2: Destination (click)... [shard] n
      --   row 3:  [Next] [Summon me] ............ [AFK] [Ad] [Ledger] [Menu]
      local MIN_W, MIN_H = 460, 340 -- room for the setup and ledger tabs
      local HEADER_H = 106

      local f = CreateFrame("Frame", "SteaSummonFrame", UIParent, "ButtonFrameTemplate")
      f:SetPoint("CENTER")
      f:SetSize(480, 400)
      f:SetScale(SteaSummonSave.windowSize)
      f:SetToplevel(true)
      f.minWidth, f.minHeight, f.headerHeight = MIN_W, MIN_H, HEADER_H

      -- template children are tables; guard so a leaner template can't error
      local function child(frame, key)
        local c = frame and frame[key]
        if type(c) == "table" then return c end
        return nil
      end
      if child(f, "TitleContainer") and child(f.TitleContainer, "TitleText") then
        f.TitleContainer.TitleText:SetText("SummonSir")
      end
      if child(f, "PortraitContainer") and child(f.PortraitContainer, "portrait") then
        f.PortraitContainer.portrait:SetTexture("Interface/ICONS/Spell_Shadow_Twilight")
      elseif ButtonFrameTemplate_HidePortrait then
        ButtonFrameTemplate_HidePortrait(f)
      end
      if child(f, "CloseButton") then
        f.CloseButton:SetScript("OnClick", function() addonData.summon:showSummonsToggle() end)
      end
      if child(f, "Inset") then
        f.Inset:ClearAllPoints()
        f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -HEADER_H)
        f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
      end

      --- everything queue-specific sits on one page frame, so the bottom
      --- tabs (warlock/tabs.lua) can swap it for the Ledger, Ads or Setup page
      f.queuePage = CreateFrame("Frame", "SteaSummonQueuePage", f)
      f.queuePage:SetAllPoints(f)
      if child(f, "Inset") then f.Inset:SetParent(f.queuePage) end

      --- what an empty queue says (showSummons fills in the role-specific line)
      local emptyParent = child(f, "Inset") or f
      f.emptyText = emptyParent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
      f.emptyText:SetPoint("LEFT", emptyParent, "LEFT", 24, 6)
      f.emptyText:SetPoint("RIGHT", emptyParent, "RIGHT", -24, 6)
      f.emptyText:SetJustifyH("CENTER")
      f.emptyText:SetWordWrap(true)
      f.emptyText:SetText("")

      --- Escape closes the window like any other panel; closing it by hand
      --- (Escape or the X) sticks until the Menu or minimap button reopens it
      table.insert(UISpecialFrames, "SteaSummonFrame")
      f:HookScript("OnHide", function()
        if not addonData.summon.hidingSelf then
          addonData.summon.show = false
        end
      end)

      --- saved position and size, never smaller than the layout needs
      local wpos = addonData.settings:getWindowPos()
      if wpos and #wpos > 0 then
        db("summon.display",  wpos[1], wpos[2], wpos[3], wpos[4], wpos[5], "width:", wpos["width"], "height:", wpos["height"])
        f:ClearAllPoints()
        f:SetPoint(wpos[1], wpos[2], wpos[3], wpos[4], wpos[5])
        f:SetSize(math.max(wpos["width"] or 0, MIN_W), math.max(wpos["height"] or 0, MIN_H))
      end

      --- movable (drag anywhere on the chrome) and resizable from the corner
      f:SetMovable(true)
      f:SetResizable(true)
      f:SetClampedToScreen(true)
      f:EnableMouse(true)
      f:RegisterForDrag("LeftButton")
      f:SetScript("OnDragStart", function(this) this:StartMoving() end)

      local movefunc = function()
        SteaSummonFrame:StopMovingOrSizing()
        SteaSummonFrame:SetUserPlaced(false)
        local p1, p2, p3, p4, p5 = SteaSummonFrame:GetPoint()
        local pos = {p1, p2, p3, p4, p5}
        pos["width"] = SteaSummonFrame:GetWidth()
        pos["height"] = SteaSummonFrame:GetHeight()
        addonData.settings:setWindowPos(pos)
        db("summon.display", pos[1], pos[2], pos[3], pos[4], pos[5], "width:", pos["width"], "height:", pos["height"])
      end
      f:SetScript("OnDragStop", movefunc)

      f:SetResizeBounds(MIN_W, MIN_H)
      local rb = CreateFrame("Button", "SteaSummonResizeButton", f)
      rb:SetPoint("BOTTOMRIGHT", -5, 5)
      rb:SetSize(16, 16)
      rb:SetFrameLevel(f:GetFrameLevel() + 20)
      rb:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
      rb:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
      rb:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
      rb:SetScript("OnMouseDown", function(this, button)
        if button == "LeftButton" then
          f:StartSizing("BOTTOMRIGHT")
        end
      end)
      rb:SetScript("OnMouseUp", movefunc)

      --- the queue list lives in the inset
      local listParent = child(f, "Inset") or f
      local sf = CreateFrame("ScrollFrame", "SteaSummonScrollFrame", listParent, "UIPanelScrollFrameTemplate")
      sf:SetPoint("TOPLEFT", listParent, "TOPLEFT", 4, -4)
      sf:SetPoint("BOTTOMRIGHT", listParent, "BOTTOMRIGHT", -27, 22) -- clear of the resize grip

      f.scroll = sf
      addonData.buttonFrame = CreateFrame("Frame", "SteaSummonButtonFrame", sf)
      addonData.buttonFrame:SetSize(330, 37 * 25 + 10)
      addonData.buttonFrame:SetScale(SteaSummonSave.listSize)
      sf:SetScrollChild(addonData.buttonFrame)

      --- Table of summon info
      addonData.buttons = {}
      for i=1, 39 do
        self:createButton(i)
      end

      --- Next button: the secure cast button, keybind "CLICK SteaSummonButton38"
      local nextBtn = addonData.buttons[38].Button
      nextBtn:SetParent(f.queuePage)
      nextBtn:ClearAllPoints()
      nextBtn:SetSize(30, 30)
      nextBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -68)
      nextBtn:SetText("")
      nextBtn:SetScript("OnEnter", function(this)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Next"])
        local key = GetBindingKey("CLICK SteaSummonButton38:LeftButton")
        GameTooltip:AddLine(key and ("Summon the next person in line (" .. key .. ")")
                                 or "Summon the next person in line. Bind a key under Key Bindings > AddOns.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      nextBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
      -- PreClick runs for the mouse and the keybind, but on both the down
      -- and up half of a press: act only on the half the secure cast uses
      -- (ActionButtonUseKeyDown), so announces go out once
      nextBtn:SetScript("PreClick", function(this, button, down)
        if down ~= nil and down ~= (C_CVar.GetCVarBool("ActionButtonUseKeyDown") and true or false) then
          return
        end
        addonData.summon:nextClick(button)
      end)

      --- the old portrait "Summon Me" button is replaced by a plain button
      addonData.buttons[39].Button:Hide()
      addonData.buttons[39].Button:SetScript("OnClick", nil)
      f.meButton = CreateFrame("Button", "SteaSummonMeButton", f.queuePage, "UIPanelButtonTemplate")
      f.meButton:SetSize(104, 22)
      if addonData.util:playerCanSummon() then
        f.meButton:SetPoint("TOPLEFT", f, "TOPLEFT", 48, -72)
      else
        f.meButton:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -72)
      end
      f.meButton:SetText(L["Request Summon"])
      f.meButton:SetScript("OnClick", function()
        if self:findWaitingPlayer(self.me) then
          self:resetMe()
        else
          self:addMe()
        end
      end)
      f.meButton:SetScript("OnEnter", function(this)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["Request/Reset Summon"])
        if self:findWaitingPlayer(self.me) then
          GameTooltip:AddLine("You are in line. Click to go back to \"waiting\" if your summon failed.", 1, 1, 1, true)
        else
          GameTooltip:AddLine("Put yourself in the warlock's queue for a summon.", 1, 1, 1, true)
        end
        GameTooltip:Show()
      end)
      f.meButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
      f.meButton:Hide()

      --- raid information toggle: menu item + keybind only, no button on the window
      if addonData.util:playerCanSummon() then
        local summonTo = function()
          if not self.infoSend then
            addonData.gossip:destination(self.myZone, self.myLocation)
          else
            addonData.gossip:destination("", "")
          end
          self.infoSend = not self.infoSend
          addonData.gossip:nag(self.infoSend)
        end
        local place = CreateFrame("Button", "SteaSummonToButton", f)
        place:SetSize(1, 1)
        place:SetPoint("TOPLEFT")
        place:RegisterForClicks()
        place:SetScript("OnClick", summonTo)
        place:Hide()
      end

      --- destination line: click to set it to where you stand, click again to unset
      if addonData.util.playerCanSummon() then
        local function invisDest()
          if self.zone ~= "" then
            addonData.gossip:destination("", "")
          else
            addonData.gossip:destination(self.myZone, self.myLocation)
          end
        end

        local invdest = CreateFrame("Button", "SteaSummonInvisibleSetDestinationButton", f.queuePage)
        invdest:SetPoint("TOPLEFT", f, "TOPLEFT", 58, -44)
        invdest:SetPoint("TOPRIGHT", f, "TOPRIGHT", -90, -44)
        invdest:SetHeight(18)
        invdest:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        invdest:SetScript("OnClick", invisDest)
        invdest:SetScript("OnEnter", function(this)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:AddLine(L["Set/Unset Destination"])
          GameTooltip:AddLine("Click: summon to where you stand now. Click again to clear.", 1, 1, 1, true)
          GameTooltip:Show()
        end)
        invdest:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end

      --- shard count, right end of the destination line
      if self.isWarlock then
        f.shards = CreateFrame("Frame", "SteaSummonShardIcon", f.queuePage)
        f.shards:SetSize(16, 16)
        f.shards:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -45)
        f.shards.icon = f.shards:CreateTexture(nil, "ARTWORK")
        f.shards.icon:SetAllPoints()
        f.shards.icon:SetTexture("Interface\\ICONS\\INV_Misc_Gem_Amethyst_02")
        f.shards.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.shards.count = f.shards:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.shards.count:SetPoint("LEFT", f.shards, "RIGHT", 4, 0)
        f.shards.count:SetText("0")
        f.shards:SetScript("OnEnter", function(this)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:AddLine("Soul shards in your bags")
          GameTooltip:Show()
        end)
        f.shards:SetScript("OnLeave", function() GameTooltip:Hide() end)
        f.shards:EnableMouse(true)
        self.shards = self:shardCount()
      end

      --- button row, right side: [AFK] [Ad] [Menu]  (the ledger is a tab now)
      f.context = CreateFrame("Button", "SteaSummonContextMenuButton", f.queuePage, "UIPanelButtonTemplate")
      f.context:SetSize(52, 22)
      f.context:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -72)
      f.context:SetText("Menu")
      f.context:SetScript("OnClick", function() addonData.appbutton:menu() end)
      f.context:SetScript("OnEnter", function(this)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Menu")
        GameTooltip:AddLine("Show or hide this window, request a summon, raid tools, options and key bindings. The minimap button opens the same menu.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      f.context:SetScript("OnLeave", function() GameTooltip:Hide() end)

      if addonData.util:playerCanSummon() then
        f.adbutton = CreateFrame("Button", "SteaSummonAdButton", f.queuePage, "UIPanelButtonTemplate")
        f.adbutton:SetSize(44, 22)
        f.adbutton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -66, -72)
        f.adbutton:SetText(L["Ad"])
        f.adbutton:SetScript("OnClick", function()
          addonData.chat:advertise()
        end)
        f.adbutton:SetScript("OnEnter", function(this)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:AddLine("Post the ad")
          local where = (SteaWarlockDB and SteaWarlockDB.adChannels) or "Trade"
          if addonData.ads and addonData.ads.channelSummary then
            where = addonData.ads:channelSummary()
          end
          GameTooltip:AddLine("Channels: " .. where, 1, 1, 1, true)
          GameTooltip:AddLine("One click posts the ad once to each channel, then the button counts down until you can post again.", 1, 1, 1, true)
          GameTooltip:Show()
        end)
        f.adbutton:SetScript("OnLeave", function() GameTooltip:Hide() end)
        self:adButtonUpdate()

        f.afkbutton = CreateFrame("Button", "SteaSummonAfkButton", f.queuePage, "UIPanelButtonTemplate")
        f.afkbutton:SetSize(44, 22)
        f.afkbutton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -114, -72)
        f.afkbutton:SetText(L["AFK"])
        f.afkbutton:SetScript("OnClick", function()
          addonData.summon:afkToggle()
        end)
        f.afkbutton:SetScript("OnEnter", function(this)
          GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
          GameTooltip:AddLine(addonData.summon.afk and "AFK is on" or "AFK")
          GameTooltip:AddLine(L["Toggle AFK: pauses auto invites and replies to asks"], 1, 1, 1, true)
          GameTooltip:AddLine(addonData.summon.afk and "Click to go back to work." or "Click when you step away.", 1, 1, 1, true)
          GameTooltip:Show()
        end)
        f.afkbutton:SetScript("OnLeave", function() GameTooltip:Hide() end)
      end

      --- Text items
      self:reConfigureFrames()

      db("summon.display","Screen Size (w/h):", GetScreenWidth(), GetScreenHeight() )
    end

    ------------------------------------------------------------
    --- Start of on tick visual updates
    ------------------------------------------------------------
    --- update buttons
    local next = false
    self.nextIdx = nil
    local listActive = false
    self:layoutRows() -- stable rows: no reshuffle under the mouse
    local nextRec = self:firstRequested() -- Next follows queue order, not row order

    for i=1, 37 do
      local rec, recIdx = self:rowRecord(i)
      local player
      local summonClick
      local cancelClick
      local r,g,b,_ = 0.5, 0.5, 0.5

      if rec ~= nil then
        player = self:recPlayer(rec)
        self:enableButton(i, true, player)
        addonData.buttons[i].Button:SetText(strsplit("-", player))

        -- the cell upstream used for raid priority letters marks who is next
        addonData.buttons[i].Priority["FS"]:SetText(rec == nextRec and NEXT_MARK or "")

        -- alts tooltip
        if #self:recAlts(rec) > 0 then
          addonData.buttons[i].Status:SetScript("OnEnter", function(this)
            GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
            GameTooltip:AddLine(L["Alt Support"])
            for _,v in pairs(self:recAlts(rec)) do
              GameTooltip:AddLine(v)
            end
            GameTooltip:Show()
          end)
          addonData.buttons[i].Status:SetScript("OnLeave", function()
            GameTooltip:Hide()
          end)
        else
          addonData.buttons[i].Status:SetScript("OnEnter", nil)
          addonData.buttons[i].Status:SetScript("OnLeave", nil)
        end

        if self:offline(player) or self:dead(player) then
          addonData.buttons[i].Button:SetEnabled(false)
          if self:offline(player) and #self:recAlts(rec) > 0 then
            addonData.buttons[i].Status["FS"]:SetTextColor(0,0.5,0, 1)
          else
            addonData.buttons[i].Status["FS"]:SetTextColor(0.5,0.5,0.5, 1)
          end
          if self:recAltWhispered(rec) ~= "x" then
            addonData.buttons[i].Status["FS"]:SetTextColor(0.5,1,0.5, 1)
          end
          addonData.buttons[i].Button:SetAttribute("macrotext", "")
          addonData.buttons[i].Button:SetScript("OnMouseDown", nil)
        elseif self:listDirty() then
          local _, class = UnitClass(player)
          r,g,b,_ = GetClassColor(class)
          addonData.buttons[i].Button:SetEnabled(true)
          addonData.buttons[i].Status["FS"]:SetTextColor(r,g,b, 1)

          self:SetMacro(i, player)

          -- check the status of summons - apparently this api doesn't exist in Classic really but is doc'd
          -- and used in the classic UI code download...
          -- I may have misread the error during raid, just adding extra caution detects
          if player and C_IncomingSummon and C_IncomingSummon.HasIncomingSummon then -- paranoia
            if C_IncomingSummon.HasIncomingSummon(player) then
              local status = self:recStatus(rec)
              if status ~= "summoned" and status ~= "accepted" and status ~= "declined" then
                self:recStatus(rec, "summoned")
              end
              if status ~= "accepted" and status ~= "declined" then
                if C_IncomingSummon.IncomingSummonStatus then -- paranoia
                  local summonStatus = C_IncomingSummon.IncomingSummonStatus(player)
                  if summonStatus == 2 then
                    self:recStatus(rec, "accepted")
                    -- accepting a summon teleports the player to the
                    -- destination: that is an arrival, remove them
                    addonData.gossip:arrived(player, false)
                  elseif summonStatus == 3 then
                    self:recStatus(rec, "declined")
                  end
                end
              end
            end
          end

          if (addonData.util:playerCanSummon()) then
            -- resolve the row's person at click time, not at redraw time:
            -- if the row changed hands since, re-aim the macro so the
            -- whisper and the cast always name the same player
            summonClick = function(_, button)
              if button == nil or button == "LeftButton" then
                local cur = self:rowRecord(i)
                local who = cur and self:recPlayer(cur)
                if not who then
                  return
                end
                if who ~= player and not InCombatLockdown() then
                  self:SetMacro(i, who)
                end
                self:summonAnnounce(who)
              end
            end
            addonData.buttons[i].Button:SetScript("OnMouseDown", summonClick)
          end
        end
      else
        self:enableButton(i, false)
      end

      if self:listDirty() then
        --- flare size
        addonData.buttons[i].flare:SetBackdrop( {
          bgFile = "Interface\\TradeFrame\\UI-TradeFrame-Highlight",
          tile = true, tileSize = SteaSummonButtonFrame:GetWidth(),
          edgeSize = 15, insets = { left = 1, right = 1, top = 1, bottom = 1 }
        });

        --- Cancel Button
        -- OnClick, not OnMouseUp: modern clients don't pass the "released
        -- inside" flag the old handler waited for, so the X did nothing
        cancelClick = function(_, button)
          if button == nil or button == "LeftButton" then
            addonData.gossip:arrived(player, true)
            db("summon.display","cancelling", player)
          end
        end

        addonData.buttons[i].Cancel:SetScript("OnClick", cancelClick)

        if rec then
          --- Next Button
          if self:recStatus(rec) == "requested" then
            if not next and rec == nextRec and (addonData.util:playerCanSummon()) then
              next = true
              self.nextIdx = recIdx
              self:SetMacro(38, player)
              -- the PreClick is permanent (set once at frame creation) and
              -- re-resolves the next person when pressed
              addonData.buttons[38].Button:Show()
            end
            listActive = true
          elseif next and self.isCasting then
            addonData.buttons[38].Button:Show()
            -- by record, not by the index saved at the last redraw: the
            -- list can shift under that index mid-cast and re-aim the
            -- macro at a different person than the one announced
            if nextRec then
              self:SetMacro(38, self:recPlayer(nextRec))
            end
          end

          --- Time
          local noSecs = false
          if tonumber(self:recTime(rec)) > 59 then
            noSecs = true
          end
          addonData.buttons[i].Time["FS"]:SetText(string.format(SecondsToTime(self:recTime(rec), noSecs)))
          local strwd = addonData.buttons[i].Time["FS"]:GetStringWidth()
          if strwd < 70 then
            addonData.buttons[i].Time["FS"]:SetWidth(80)
          else
            addonData.buttons[i].Time:SetWidth(strwd+20)
            addonData.buttons[i].Time["FS"]:SetWidth(strwd+10)
          end

          --- Status
          addonData.buttons[i].Status["FS"]:SetText(L[self:recStatus(rec)])

          --- New flare
          if self:recNew(rec) then
            addonData.buttons[i].flare.ag:Play()
            self:recNew(rec,false)
          end
        end

        self.needBoost = not listActive

        if not next then
          if not self.isCasting then
            -- all summons left are pending, disable the next button
            addonData.buttons[38].Button:Hide()
          end
        end
      end -- skip visual updates
    end -- rows

    --- clickers and advertisers cannot pin a destination: show the warlock's
    --- instead of the "click to summon" hint (the synced one for advertisers)
    if SteaSummonFrame.destination and self.zone == "" and not addonData.util:playerCanSummon() then
      local Wk = addonData.W
      local remote = Wk and Wk.role and Wk.role() == "advertiser" and Wk.db and Wk.db.remoteDest
      if remote and remote ~= "" then
        SteaSummonFrame.destination:SetText("|cffffd200Destination:|r " .. remote .. " |cff808080(from the warlock)|r")
      else
        SteaSummonFrame.destination:SetText(DESTINATION_TEAM)
      end
    end

    --- the stock scroll bar always shows; hide it while the list fits
    if SteaSummonFrame.scroll then
      local bar = SteaSummonFrame.scroll.ScrollBar
      if type(bar) == "table" then
        local listH = (self.numwaiting * 25 + 10) * (SteaSummonSave.listSize or 1)
        bar:SetShown(listH > (SteaSummonFrame.scroll:GetHeight() or 0))
      end
    end

    --- empty queue: say so, and what fills it
    if SteaSummonFrame.emptyText then
      if self.numwaiting == 0 then
        local role = addonData.W and addonData.W.role and addonData.W.role() or "clicker"
        if role == "warlock" then
          SteaSummonFrame.emptyText:SetText("Nobody in line.\nPeople who whisper you for a summon show up here.")
        else
          SteaSummonFrame.emptyText:SetText("Nobody in line.\nThe warlock's queue shows up here.")
        end
        SteaSummonFrame.emptyText:Show()
      else
        SteaSummonFrame.emptyText:Hide()
      end
    end
    self:headerCounts()

    --- Summon me button: anyone grouped who is not at the destination,
    --- except the warlock running the service (a misclick would queue
    --- the warlock itself and post "123" to the raid). Still in the Menu.
    if SteaSummonFrame.meButton then
      local me = SteaSummonFrame.meButton
      local serviceLock = addonData.W and addonData.W.role and addonData.W.role() == "warlock"
      if IsInGroup(LE_PARTY_CATEGORY_HOME) and not self:isAtDestination() and not serviceLock then
        if self:findWaitingPlayer(self.me) then
          me:SetText(L["Reset Summon"])
        else
          me:SetText(L["Request Summon"])
        end
        me:Show()
      else
        me:Hide()
      end
    end

    --- show summon window
    local show = false
    if addonData.settings:showWindow() or (addonData.settings:showActive() and self.numwaiting > 0) then
      show = true
    elseif addonData.settings:showJustMe() then
      if self:findWaitingPlayer(self.me) then
        show = true
      end
    elseif addonData.settings:showNever() then
      show = false
    end

    if self.numwaiting == 0 then
      self.hasSummoned = false
    end

    -- another tab (ledger, ads, setup) is up: the queue's show rules do not apply
    if addonData.tabs and addonData.tabs.offQueue and addonData.tabs:offQueue() then
      show = true
    end

    if show then
      if self.show == false then
        show = false
      end
    else
      if self.show == true then
        show = true
      end
    end

    if show then
      SteaSummonFrame:Show()
      if self.numwaiting > 0 then
        addonData.monitor:start() -- start ui update tick
      end
    else
      self.hidingSelf = true -- our own hide, not the user's Escape
      SteaSummonFrame:Hide()
      self.hidingSelf = false
      if not self.isCasting then
        addonData.monitor:stop() -- stop ui update tick
      end
    end

    if not self.isCasting then
      self:listDirty(false)
    end
  end,

  ---------------------------------
  showSummonsToggle = function(self)
    self = addonData.summon
    if SteaSummonFrame:IsVisible() then
      if self.show == nil then
        self.show = false
      else
        self.show = nil
        if addonData.settings:showWindow() or (addonData.settings:showActive() and self.numwaiting > 0) then
          self.show = false
        elseif addonData.settings:showJustMe() then
          if self:findWaitingPlayer(self.me) then
            self.show = false
          end
        end
      end
    else -- not visible
      self.show = true
    end
    db("summon.display", "setting show", self.show)
    self:showSummons()
  end,

  ---------------------------------
  -- Announce one summon: status, group/say/whisper lines, destination.
  -- Shared by the row buttons, the Next button and the big button, and
  -- always given the person the macro is about to target.
  summonAnnounce = function(self, player)
    self = addonData.summon
    if not player or player == "" then
      return
    end
    if self.isCasting then
      addonData.chat:say(SteaSummonSave.clicknag, player)
      return
    end
    if not hasSummonMana() then
      return -- the macro Life Taps instead, nothing to announce
    end
    db("summon.display", "summoning ", player)
    self.summoningPlayer = player
    addonData.gossip:status(player, "pending")
    addonData.chat:raid(SteaSummonSave.raidchat, player)
    addonData.chat:say(SteaSummonSave.saychat, player)
    addonData.chat:whisper(SteaSummonSave.whisperchat, player)
    local z, l = self:getCurrentLocation()
    addonData.gossip:destination(z, l)
    self.hasSummoned = true
  end,

  ---------------------------------
  -- Next pressed (button, keybind or the big button): pick the first
  -- requested person NOW, aim the macro at them, then announce them. The
  -- old code announced a name captured at the last redraw while the macro
  -- could have been re-pointed through a stale list index.
  nextClick = function(self, button)
    self = addonData.summon
    if button ~= nil and button ~= "LeftButton" then
      return
    end
    local rec = self:firstRequested()
    if not rec then
      return
    end
    local player = self:recPlayer(rec)
    self.nextIdx = self:findWaitingPlayerIdx(player)
    if not InCombatLockdown() then
      self:SetMacro(38, player)
    end
    self:summonAnnounce(player)
  end,

  ---------------------------------
  SetMacro = function(self, index, player)
    if (addonData.util:playerCanSummon()) then
      if not self.isCasting then
        if hasSummonMana() then
          --self.isCasting = true
          local spell = GetSpellInfo(698) -- Ritual of Summoning
          local name = strsplit("-", player)
          addonData.buttons[index].Button:SetAttribute("macrotext", "/stopmacro [channeling:"
              .. spell .. "]\n/target " .. name .. "\n/cast " .. spell .. "\n/cqs")
        else
          local spell = GetSpellInfo(1454) -- Life tap rank 1, but we don't use rank
          addonData.buttons[index].Button:SetAttribute("macrotext", "/cast " .. spell)
        end
      else
        addonData.buttons[index].Button:SetAttribute("macrotext", "")
      end
    end
  end,

  ---------------------------------
  createButton = function(_, i)
    -- Summon Button
    local bw = 96   -- name button width
    local bh = 25
    local wpad = 38 -- X button (25) + gap
    local hpad = 5

    local parent = addonData.buttonFrame
    if i >= 38 then
      parent = SteaSummonFrame
    end

    addonData.buttons[i] = {}
    addonData.buttons[i].Button = CreateFrame("Button", "SteaSummonButton"..i, parent, "SecureActionButtonTemplate");
    addonData.buttons[i].Button:SetPoint("TOPLEFT","SteaSummonButtonFrame","TOPLEFT", wpad,-(((i-1)*bh)+hpad))
    addonData.buttons[i].Button:SetNormalFontObject("GameFontNormalSmall")

    -- API compat: modern clients (WoW: Forever) removed the Set*Texture(textureObject)
    -- overloads, so state textures are set by path and adjusted via Get*Texture()
    local function setStateTextures(button, normal, highlight, pushed, disabled, l, r, t, b)
      button:SetNormalTexture(normal)
      button:SetHighlightTexture(highlight)
      button:SetPushedTexture(pushed)
      button:SetDisabledTexture(disabled)
      if l then
        button:GetNormalTexture():SetTexCoord(l, r, t, b)
        button:GetHighlightTexture():SetTexCoord(l, r, t, b)
        button:GetPushedTexture():SetTexCoord(l, r, t, b)
        button:GetDisabledTexture():SetTexCoord(l, r, t, b)
      end
    end

    if i < 38 then
      addonData.buttons[i].Button:SetWidth(bw)
      addonData.buttons[i].Button:SetHeight(bh)
      setStateTextures(addonData.buttons[i].Button,
          "Interface/Buttons/UI-Panel-Button-Up",
          "Interface/Buttons/UI-Panel-Button-Highlight",
          "Interface/Buttons/UI-Panel-Button-Down",
          "Interface/Buttons/UI-Panel-Button-Disabled",
          0, 0.625, 0, 0.6875)
    else
      addonData.buttons[i].Button:ClearAllPoints()
      addonData.buttons[i].Button:SetWidth(bw - 30)
      addonData.buttons[i].Button:SetHeight(bw - 30)
      addonData.buttons[i].Button:SetFrameLevel(100)
      -- icon
      addonData.buttons[i].Button.icon = addonData.buttons[i].Button:CreateTexture()

      if i == 38 then
        setStateTextures(addonData.buttons[i].Button,
            "Interface/Buttons/UI-QuickSlot2",
            "Interface/Buttons/UI-QuickSlot-Depress",
            "Interface/Buttons/UI-QuickSlot",
            "Interface/Buttons/UI-QuickSlotRed")
        addonData.buttons[i].Button:GetNormalTexture():SetTexCoord(0.2, 0.8, 0.2, 0.8)
        addonData.buttons[i].Button.icon:SetTexture("Interface/ICONS/Spell_Shadow_Twilight")
        addonData.buttons[i].Button.icon:SetTexCoord(0, 1, 0, 1)
        addonData.buttons[i].Button.icon:SetAllPoints()
      else
        addonData.buttons[i].Button.icon:SetAllPoints()

        -- animation move and shrink
        local button = addonData.buttons[39].Button
        button.shrink = button:CreateAnimationGroup()
        button.shrink:SetScript("OnPlay", function()
          if addonData.summon.shrunk then
            button:SetWidth(bw - 30)
            button:SetHeight(bw - 30)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT","SteaSummonFrame","TOPLEFT", -10, 10)
          end
        end)

        button.shrink:SetScript("OnFinished", function()
          if not addonData.summon.shrunk then
            button:SetWidth((bw - 30)/2)
            button:SetHeight((bw - 30)/2)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT","SteaSummonFrame","TOPLEFT", 40, 15)
            addonData.summon.shrunk = true
          else
            button:SetWidth(bw - 30)
            button:SetHeight(bw - 30)
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT","SteaSummonFrame","TOPLEFT", -10, 10)
            addonData.summon.shrunk = false
          end
        end)
        button.shrink.anim = button.shrink:CreateAnimation("Scale")
        button.shrink.anim:SetScale(1, 1)
        button.shrink.anim:SetDuration(0.8)
        button.shrink.anim:SetSmoothing("IN")
        button.shrink.anim2 = button.shrink:CreateAnimation("Translation")
        button.shrink.anim2:SetOffset(40, 15)
        button.shrink.anim2:SetDuration(0.8)
        button.shrink.anim2:SetSmoothing("IN")
        button.icon = addonData.buttons[i].Button.icon
        addonData.buttons[i].Button:SetFrameLevel(101)
      end
    end

    -- modern clients cast on key down by default: a secure button registered
    -- only for up-clicks never triggers its action, so register both; the
    -- secure handler runs the action once, on the phase the client expects
    addonData.buttons[i].Button:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
    addonData.buttons[i].Button:SetAttribute("type", "macro");
    addonData.buttons[i].Button:SetAttribute("macrotext", "")

    if i < 38 then -- last button we use for next summon, so don't want these
      --- flare
      addonData.buttons[i].flare = CreateFrame("Frame", "SteaSummonFlare"..i, parent, BackdropTemplateMixin and "BackdropTemplate")
      addonData.buttons[i].flare:SetHeight(bh + hpad)
      addonData.buttons[i].flare:SetPoint("TOPLEFT","SteaSummonButtonFrame","TOPLEFT", 2,-((i-1)*(bh)+(hpad/2)))
      --addonData.buttons[i].flare:SetPoint("TOPRIGHT","SteaSummonButtonFrame","TOPRIGHT", 0,-(((i-1)*bh)+(hpad/2)))
      addonData.buttons[i].flare:SetWidth(320)
      addonData.buttons[i].flare.tex = addonData.buttons[i].flare:CreateTexture(nil, "BACKGROUND",nil,0)
      addonData.buttons[i].flare.tex:SetAllPoints()
      addonData.buttons[i].flare.tex:SetColorTexture(1, 1, 1, 1)
      addonData.buttons[i].flare.tex:SetBlendMode("MOD")
      addonData.buttons[i].flare:SetAlpha(0)
      addonData.buttons[i].flare.ag = addonData.buttons[i].flare:CreateAnimationGroup()
      addonData.buttons[i].flare.ag.anim = addonData.buttons[i].flare.ag:CreateAnimation("Alpha")
      addonData.buttons[i].flare.ag.anim:SetFromAlpha(0.5)
      addonData.buttons[i].flare.ag.anim:SetToAlpha(1)
      addonData.buttons[i].flare.ag.anim:SetDuration(0.1)
      addonData.buttons[i].flare.ag.anim:SetSmoothing("IN")
      addonData.buttons[i].flare.ag.anim:SetOrder(1)
      addonData.buttons[i].flare.ag.anim2 = addonData.buttons[i].flare.ag:CreateAnimation("Alpha")
      addonData.buttons[i].flare.ag.anim2:SetFromAlpha(0.9)
      addonData.buttons[i].flare.ag.anim2:SetToAlpha(0)
      addonData.buttons[i].flare.ag.anim2:SetDuration(1)
      addonData.buttons[i].flare.ag.anim2:SetSmoothing("OUT")
      addonData.buttons[i].flare.ag.anim2:SetOrder(2)
      --addonData.buttons[i].flare.ag:SetScript("OnFinished", function() addonData.buttons[i].flare.ag:Stop() end)
      addonData.buttons[i].flare:Show()

      --- Cancel
      addonData.buttons[i].Cancel = CreateFrameCompat("Button", "SteaSummonCancelButton"..i,
          parent, "UIPanelCloseButtonNoScripts", "UIPanelCloseButton")
      addonData.buttons[i].Cancel:SetWidth(bh)
      addonData.buttons[i].Cancel:SetHeight(bh)
      addonData.buttons[i].Cancel:SetText("X")
      addonData.buttons[i].Cancel:SetPoint("TOPLEFT","SteaSummonButtonFrame","TOPLEFT", 8,-(((i-1)*bh)+hpad))
      addonData.buttons[i].Cancel:SetScript("OnEnter", function(this)
        local rec = addonData.summon:rowRecord(i)
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Remove " .. (rec and addonData.summon:recPlayer(rec) or "this person") .. " from the queue")
        GameTooltip:AddLine("No charge, no block. Right-click the name for more.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      addonData.buttons[i].Cancel:SetScript("OnLeave", function() GameTooltip:Hide() end)

      --- the name is the cast button: say so on hover
      addonData.buttons[i].Button:SetScript("OnEnter", function(this)
        local rec = addonData.summon:rowRecord(i)
        if not rec then
          return
        end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine(addonData.summon:recPlayer(rec))
        if addonData.util:playerCanSummon() then
          GameTooltip:AddLine("Click: summon them now, ahead of the line.", 1, 1, 1, true)
        end
        GameTooltip:AddLine("Right-click: move, remove, block or whisper.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      addonData.buttons[i].Button:SetScript("OnLeave", function() GameTooltip:Hide() end)

      --- Wait Time
      addonData.buttons[i].Time = CreateFrame("Frame", "SteaSummonWaitTime"..i, addonData.buttonFrame, BackdropTemplateMixin and "BackdropTemplate")
      addonData.buttons[i].Time:SetWidth(bw)
      addonData.buttons[i].Time:SetHeight(bh)
      addonData.buttons[i].Time:SetPoint("TOPLEFT", addonData.buttonFrame, "TOPLEFT",bw + wpad + 108,-(((i-1)*bh)+hpad))
      addonData.buttons[i].Time:SetBackdrop( {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 5, edgeSize = 15, insets = { left = 1, right = 1, top = 1, bottom = 1 }
      });

      addonData.buttons[i].Time["FS"] = addonData.buttons[i].Time:CreateFontString(
          "SteaSummonTimeText"..i,"ARTWORK", "ChatFontNormal")
      addonData.buttons[i].Time["FS"]:SetParent(addonData.buttons[i].Time)
      addonData.buttons[i].Time["FS"]:SetPoint("TOP",addonData.buttons[i].Time,"TOP",0,0)
      addonData.buttons[i].Time["FS"]:SetWidth(bw)
      addonData.buttons[i].Time["FS"]:SetHeight(bh)
      addonData.buttons[i].Time["FS"]:SetJustifyH("CENTER")
      addonData.buttons[i].Time["FS"]:SetJustifyV("MIDDLE")
      addonData.buttons[i].Time["FS"]:SetFontObject("GameFontNormalSmall")
      addonData.buttons[i].Time["FS"]:SetText(string.format(SecondsToTime(0)))

      --- Next marker (upstream's raid-priority letter cell, repurposed)
      local nextW = 38
      addonData.buttons[i].Priority = CreateFrame("Frame", "SteaSummonPriority"..i, addonData.buttonFrame, BackdropTemplateMixin and "BackdropTemplate")
      addonData.buttons[i].Priority:SetWidth(nextW)
      addonData.buttons[i].Priority:SetHeight(bh)
      addonData.buttons[i].Priority:SetPoint("TOPLEFT", addonData.buttonFrame, "TOPLEFT",bw + wpad + 1,-(((i-1)*bh)+hpad))
      addonData.buttons[i].Priority:SetBackdrop( {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 5, edgeSize = 15, insets = { left = 1, right = 1, top = 1, bottom = 1 }
      });
      addonData.buttons[i].Priority:SetScript("OnEnter", function(this)
        if this.FS:GetText() == "" then
          return
        end
        GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Next in line")
        GameTooltip:AddLine("The Next button, its key and the big Summon Next button all summon this person.", 1, 1, 1, true)
        GameTooltip:Show()
      end)
      addonData.buttons[i].Priority:SetScript("OnLeave", function()
        GameTooltip:Hide()
      end)
      addonData.buttons[i].Priority:EnableMouse(true)

      addonData.buttons[i].Priority["FS"] = addonData.buttons[i].Priority:CreateFontString(
          "SteaSummonStatusText"..i,"ARTWORK", "ChatFontNormal")
      addonData.buttons[i].Priority["FS"]:SetParent(addonData.buttons[i].Priority)
      addonData.buttons[i].Priority["FS"]:SetPoint("TOP",addonData.buttons[i].Priority,"TOP",0,0)
      addonData.buttons[i].Priority["FS"]:SetWidth(nextW)
      addonData.buttons[i].Priority["FS"]:SetHeight(bh)
      addonData.buttons[i].Priority["FS"]:SetJustifyH("CENTER")
      addonData.buttons[i].Priority["FS"]:SetJustifyV("MIDDLE")
      addonData.buttons[i].Priority["FS"]:SetFontObject("GameFontNormalSmall")
      addonData.buttons[i].Priority["FS"]:SetTextColor(1,1,1)
      addonData.buttons[i].Priority["FS"]:SetText("")

      --- Status (plain words from the locale: Waiting, Casting, Portal up, ...)
      local statusW = 66
      addonData.buttons[i].Status = CreateFrame("Frame", "SteaSummonStatus"..i, addonData.buttonFrame, BackdropTemplateMixin and "BackdropTemplate")
      addonData.buttons[i].Status:SetWidth(statusW)
      addonData.buttons[i].Status:SetHeight(bh)
      addonData.buttons[i].Status:SetPoint("TOPLEFT", addonData.buttonFrame, "TOPLEFT",bw + wpad + nextW + 2,-(((i-1)*bh)+hpad))
      addonData.buttons[i].Status:SetBackdrop( {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 5, edgeSize = 15, insets = { left = 1, right = 1, top = 1, bottom = 1 }
      });
      addonData.buttons[i].Status["FS"] = addonData.buttons[i].Status:CreateFontString(
          "SteaSummonStatusText"..i,"ARTWORK", "ChatFontNormal")
      addonData.buttons[i].Status["FS"]:SetParent(addonData.buttons[i].Status)
      addonData.buttons[i].Status["FS"]:SetPoint("TOP",addonData.buttons[i].Status,"TOP",0,0)
      addonData.buttons[i].Status["FS"]:SetWidth(statusW)
      addonData.buttons[i].Status["FS"]:SetHeight(bh)
      addonData.buttons[i].Status["FS"]:SetJustifyH("CENTER")
      addonData.buttons[i].Status["FS"]:SetJustifyV("MIDDLE")
      addonData.buttons[i].Status["FS"]:SetFontObject("GameFontNormalSmall")
      addonData.buttons[i].Status["FS"]:SetTextColor(1,1,1)
      addonData.buttons[i].Status["FS"]:SetText("Waiting")
    end
  end,

  ---------------------------------
  -- toggle AFK: pause auto invites, whisper the AFK reply to asks, and
  -- tint the button red while on
  afkToggle = function(self)
    self = addonData.summon
    self.afk = not self.afk
    wipe(self.afkReplied) -- each AFK session replies to each player once
    local btn = SteaSummonAfkButton
    if self.afk then
      if btn then
        btn:SetNormalFontObject("GameFontRed")
      end
      cprint(L["You are now AFK: auto invites are paused and asks get an AFK reply"])
    else
      if btn then
        btn:SetNormalFontObject("GameFontNormal")
      end
      cprint(L["You are no longer AFK"])
    end
  end,

  ---------------------------------
  -- keep the Ad button's text in sync with the trade ad cooldown: shows a
  -- ticking countdown while waiting, re-enables as "Ad" when ready
  adButtonUpdate = function(self)
    self = addonData.summon
    local btn = SteaSummonAdButton
    if not btn then
      return
    end

    local ready, remaining = addonData.chat:adReady()
    if ready then
      btn:SetText(L["Ad"])
      btn:Enable()
      if self.adTicker then
        self.adTicker:Cancel()
        self.adTicker = nil
      end
    else
      btn:SetText(string.format("%d:%02d", math.floor(remaining / 60), remaining % 60))
      btn:Disable()
      if not self.adTicker then
        self.adTicker = C_Timer.NewTicker(1, function()
          addonData.summon:adButtonUpdate()
        end)
      end
    end
  end,

  ---------------------------------
  summonsReady = function(self)
    return self.localLocks and self.localLocks + self.localClickers > 2 and self.zone ~= ""
  end,

  ---------------------------------
  shardCount = function(_)
    local count = 0
    if SteaSummonShardIcon then
      -- compare item IDs: on modern clients item links carry dynamic
      -- context fields, so link-to-link comparison fails, and GetItemInfo
      -- returns nil for uncached items
      -- NUM_TOTAL_EQUIPPED_BAG_SLOTS includes the reagent bag slot that
      -- the Forever client has (a soul bag there must count too)
      for bag = 0, (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
          if C_Container.GetContainerItemID(bag, slot) == 6265 then -- "Soul Shard"
            count = count + 1
          end
        end
      end
      SteaSummonShardIcon.count:SetText(tostring(count))
    end
    return count
  end,

  ---------------------------------
  shardIncrementBy = function(self, incr)
    self.shards = self.shards + incr
    db("summon.display", "Shard count update", incr, self.shards)
    if SteaSummonShardIcon then
      SteaSummonShardIcon.count:SetText(tostring(self.shards))
    end
  end,

  ---------------------------------
  bagPushShardCheck = function(_, event, bag, iconFileID)
    db("summon.display", event, bag, iconFileID)
    if iconFileID == 134075 then -- "Soul Shard"
      g_self:shardIncrementBy(1)
    end
  end,

  ---------------------------------
  ClickNext = function()
    addonData.buttons[38].Button:Click("LeftButton")
  end,

  ---------------------------------
  ClickSetDestination = function()
    if SteaSummonToButton then
      SteaSummonToButton:Click()--"LeftButton")
    end
  end,

  ---------------------------------
  enableButton = function(self, idx, enable, player)
    if enable == nil then
      enable = true
    end

    if enable then
      if not InCombatLockdown() then
        addonData.buttons[idx].Button:Show()
        -- upstream showed the X only to a warlock standing at the destination.
        -- Our clickers and advertiser manage the same queue, so anyone running
        -- this addon in the group may remove a row (and always themselves).
        if player == self.me or addonData.util:playerCanSummon() or (addonData.W and addonData.W.role()) then
          addonData.buttons[idx].Cancel:Show()
        else
          addonData.buttons[idx].Cancel:Hide()
        end
        addonData.buttons[idx].Time:Show()
        addonData.buttons[idx].Status:Show()
        addonData.buttons[idx].Priority:Show()
        addonData.buttons[idx].Button:Enable()
      end
    else
      if not InCombatLockdown() then
        addonData.buttons[idx].Button:Hide()
        addonData.buttons[idx].Cancel:Hide()
        addonData.buttons[idx].Time:Hide()
        addonData.buttons[idx].Status:Hide()
        addonData.buttons[idx].Priority:Hide()
        addonData.buttons[idx].Button:Enable()
      end
    end
  end,

  ---------------------------------
  enableButtons = function(self, enable)
    for i=1, 35 do
      self:enableButton(i, enable)
    end
  end,

  ---------------------------------
  findWaitingPlayerIdx = function(self, player)
    for i, wait in pairs(self.waiting) do
      if self:recPlayer(wait) == player then
        return i
      end
    end
    return nil
  end,

  ---------------------------------
  -- Stable rows: rowOrder maps a display row to a player name. While the
  -- mouse is over the summon window rows keep their place (new names go to
  -- the bottom, departed names leave a gap); when it leaves, the rows
  -- compact back to queue order. Stops a click landing on the wrong person.
  rowOrder = {},

  layoutRows = function(self)
    local frozen = SteaSummonFrame and SteaSummonFrame:IsShown() and SteaSummonFrame:IsMouseOver()
    local changed = false
    if not frozen then
      local n = 0
      for i, rec in ipairs(self.waiting) do
        local name = self:recPlayer(rec)
        if self.rowOrder[i] ~= name then changed = true end
        self.rowOrder[i] = name
        n = i
      end
      for i = #self.rowOrder, n + 1, -1 do
        self.rowOrder[i] = nil
        changed = true
      end
    else
      local placed, last = {}, 0
      for slot, name in pairs(self.rowOrder) do
        placed[name] = slot
        if slot > last then last = slot end
      end
      for _, rec in ipairs(self.waiting) do
        local name = self:recPlayer(rec)
        if not placed[name] and last < 37 then
          last = last + 1
          self.rowOrder[last] = name
          placed[name] = last
          changed = true
        end
      end
    end
    if changed then
      self:listDirty(true)
    end
  end,

  rowRecord = function(self, slot)
    local name = self.rowOrder[slot]
    if name then
      local idx = self:findWaitingPlayerIdx(name)
      if idx then
        return self.waiting[idx], idx
      end
    end
    return nil, nil
  end,

  firstRequested = function(self)
    for _, rec in ipairs(self.waiting) do
      if self:recStatus(rec) == "requested" then
        return rec
      end
    end
    return nil
  end,

  ---------------------------------
  findWaitingPlayer = function(self, player)
    local idx = self:findWaitingPlayerIdx(player)
    if idx then
      return self.waiting[idx]
    end
    return nil
  end,

  ---------------------------------
  summoned = function(self, player)
    -- update status
    local waitEntry = self:findWaitingPlayer(player)
    if waitEntry ~= nil then
      db("summon.waitlist", "a summon is pending for " .. player)
      self:recStatus(waitEntry, "pending")
    end
  end,

  ---------------------------------
  status = function(self, player, status)
    -- update status
    local waitEntry = self:findWaitingPlayer(player)
    if waitEntry ~= nil then
      db("summon.waitlist", "status changed to", status, "for", player)
      self:recStatus(waitEntry, status)
    end
  end,

  ---------------------------------
  arrived = function(self, player, cancel)
    if cancel ~= nil and not cancel then
      local rec = self:findWaitingPlayer(player)
      if rec then
        self.countSummoned = self.countSummoned + 1
        if addonData.W then addonData.W.summonArrived(player) end
      end
    end

    self:remove(player)
  end,

  ---------------------------------
  summonFail = function(self)
    db("summon.waitlist", "something went wrong, resetting status of " .. self.summoningPlayer .. " to requested")
    addonData.gossip:status(self.summoningPlayer, "requested")
    self.isCasting = false
  end,

  ---------------------------------
  summonSuccess = function(self)
    db("summon.waitlist", "summon succeeded, setting status of " .. self.summoningPlayer .. " to summoned")
    addonData.gossip:status(self.summoningPlayer, "summoned")
    self.isCasting = false
    if addonData.W then addonData.W.summonCast(self.summoningPlayer) end
  end,

  offline = function(self, player)
    player, _ = strsplit("-", player)
    -- UnitIsConnected can be secret on the Forever client: when unknown,
    -- treat the player as online rather than erroring
    local connected = addonData.util:secretSafe(function() return UnitIsConnected(player) and true or false end)
    local offline = connected == false
    local rec = self:findWaitingPlayer(player)
    if rec then
      local state = ""
      if offline and self:recStatus(rec) ~= "offline" then
        db("summon.waitlist", "setting status of " .. player .. " to offline")
        state = "offline"
      elseif not offline and self:recStatus(rec) == "offline" then
        db("summon.waitlist", "setting status of " .. player .. " from offline to requested")
        state = "requested"
      end
      if state ~= "" then
        self:recStatus(rec, state)
      end
    end
    return offline
  end,

  remove = function(self, player)
    local out
    if type(player) == "number" then
      out = self:recRemoveIdx(player)
    else
      out = self:recRemove(player)
    end
    return out
  end,

  dead = function(self, player)
    -- UnitIsDeadOrGhost can be secret on the Forever client: assume alive
    local dead = addonData.util:secretSafe(function() return UnitIsDeadOrGhost(player) and true or false end) or false
    local idx = self:findWaitingPlayerIdx(player)
    if idx then
      local state = ""
      if dead and self.waiting[idx][3] ~= "dead" then
        state = "dead"
        db("summon.waitlist", "setting status of", player, "to dead")
      elseif not dead and self.waiting[idx][3] == "dead" then
        db("summon.waitlist", "setting status of", player, "from dead to requested")
        state = "requested"
      end
      if state ~= "" then
        self:recStatus(self.waiting[idx], state)
      end
    end
    return dead
  end,

  ---------------------------------
  callback = function(_, event, ...)
    if event == "PLAYER_REGEN_DISABLED" then
      -- entered combat, stop everything or bad things happen
      if SteaSummonFrame then
        addonData.summon.hidingSelf = true -- not the user's Escape: comes back after combat
        SteaSummonFrame:Hide()
        addonData.summon.hidingSelf = false
      end
    end
    if event == "PLAYER_REGEN_ENABLED" then
      -- start things up again, nothing to do
    end
  end,

  ---------------------------------
  setRaidNags = function(self, nag)
    if nag then
      self.infoSend = true
      if SteaSummonToButton then
        SteaSummonToButton:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-MOTD-Up")
      end
    else
      self.infoSend = false
      if SteaSummonToButton then
        SteaSummonToButton:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-MOTD-Disabled")
      end
    end
  end,

  ---------------------------------
  getCurrentLocation = function(self)
    return self.myZone, self.myLocation
  end,

  ---------------------------------
  setCurrentLocation = function(self)
    local oldZone, oldLocation = self.myZone, self.myLocation
    self.myZone, self.myLocation = GetZoneText(), GetMinimapZoneText()

    if self:isAtDestination() then
      if SteaSummonFrame then

        if not SteaSummonFrame.location or not SteaSummonFrame.destination then
          self:reConfigureFrames()
        end

        SteaSummonFrame.destination:SetTextColor(0.1, 1, 0.1)
        SteaSummonFrame.location:SetTextColor(1, 1, 1)
      end

      if oldZone ~= self.myZone or oldLocation ~= self.myLocation then -- we changed location to destination
        addonData.gossip:atDestination(true)
      end
    else
      if SteaSummonFrame then
        if not SteaSummonFrame.location or not SteaSummonFrame.destination then
          self:reConfigureFrames()
        end
        SteaSummonFrame.destination:SetTextColor(1, 1, 1)
        SteaSummonFrame.location:SetTextColor(1, 1, 1)
      end

      if self.zone ~= "" and self.location ~= "" then -- destination is set
        if oldZone ~= self.myZone or oldLocation ~= self.myLocation then -- we changed location
          if oldZone == self.zone and oldLocation == self.location then -- from the destination
            addonData.gossip:atDestination(false)
          end
        end
      end
    end

    if SteaSummonFrame and oldZone ~= self.myZone or oldLocation ~= self.myLocation then
      local pat = {["%%zone"] = self.myZone, ["%%subzone"] = self.myLocation}
      local s = L["Location: %subzone, %zone"]
      s = goldLabel(tstring(s, pat))
      SteaSummonFrame.location:SetText(s)
    end
  end,

  ---------------------------------
  setDestination = function(self, zone, location)
    if location == nil or zone == nil then
      location = ""
      zone = ""
    end

    if self.zone == zone and self.location == location then
      return
    end
    self.location = location
    self.zone = zone

    db("summon.misc", "setting destination: ", location, " in ", zone)
    if location and location ~= "" and zone and zone ~= "" then
      self.countSummoned = 0
      if SteaSummonFrame then

        if not SteaSummonFrame.destination then
          self:reConfigureFrames()
        end

        local pat = {["%%zone"] = self.zone, ["%%subzone"] = self.location}
        local s = L["Destination: %subzone, %zone"]
        s = goldLabel(tstring(s, pat))
        SteaSummonFrame.destination:SetText(s)
      end
      if self:isAtDestination() then
        addonData.gossip:atDestination(true)
      end
    else
      if SteaSummonFrame then
        if not SteaSummonFrame.destination then
          self:reConfigureFrames()
        end
        SteaSummonFrame.destination:SetText(DESTINATION_UNSET)
      end
      self.show = nil
      addonData.raid:relinquish()
    end
  end,

  ---------------------------------
  addMe = function(self)
    self = addonData.summon
    addonData.gossip:add(self.me, true)
    addonData.chat:raid("%t")
  end,

  ---------------------------------
  resetMe = function(self)
    self = addonData.summon
    addonData.gossip:status(self.me, "requested")
    addonData.chat:raid("%t")
  end,

  ---------------------------------
  cancelMe = function(self)
    self = addonData.summon
    addonData.gossip:arrived(self.me, true)
  end,

  ---------------------------------
  clearList = function(self, really)
    self = addonData.summon
    if not really then
      if not StaticPopupDialogs["STEASUMMON_CLEARLIST"] then
        StaticPopupDialogs["STEASUMMON_CLEARLIST"] = {
          text = L["clearlistdesc"],
          button1 = ACCEPT,
          button2 = CANCEL,
          OnAccept = function()
            self:clearList(true)
          end,
          timeout = 0,
          whileDead = true,
          hideOnEscape = true,
        }
      end
      StaticPopup_Show("STEASUMMON_CLEARLIST")
    else
      local remv = {} -- don't remove things from tables you are iterating over...
      for _,v in pairs(self.waiting) do
        table.insert(remv, self:recPlayer(v))
      end
      for _,v in pairs(remv) do
        addonData.gossip:arrived(v, true)
      end
      self.countSummoned = 0
    end
  end,

  ---------------------------------
  setDestinationAsCurrent = function(self)
    self = addonData.summon
    addonData.gossip:destination(self.myZone, self.myLocation)
  end,

  ---------------------------------
  destinationToggle = function(self)
    self = addonData.summon
    if self.zone == "" then
      self:setDestinationAsCurrent()
    else
      addonData.gossip:destination("", "")
    end
  end,

  ---------------------------------
  getDestination = function(self)
    return self.zone, self.location
  end,

  ---------------------------------
  isAtDestination = function(self)
    self = addonData.summon
    return self.zone == self.myZone and self.location == self.myLocation
  end,

  ---------------------------------
  usesSoulShard = {
    [27565] = 1, -- Banish
    [8994] = 1, -- banish (again)
    [12890] = 1, -- deep slumber, probably not in game
    [1098] = 1, -- enslave demon rank 1
    [11725] = 1, -- enslave demon rank 2
    [11726] = 1, -- enslave demon rank 3
    [17877] = 1, -- ["Shadowburn"] = 1, -- Rank 1
    [18867] = 1, -- shadowburn rank 2
    [18868] = 1, -- shadowburn rank 3
    [18869] = 1, -- shadowburn rank 4
    [18870] = 1, -- shadowburn rank 5
    [18871] = 1, -- shadowburn rank 6
    [20755] = 1, -- ["Create Soulstone"] = 1,
    [20752] = 1, -- ["Create Soulstone (Lesser)"] = 1,
    [693] = 1, -- ["Create Soulstone (Minor)"] = 1,
    [20756] = 1, -- ["Create Soulstone (Greater)"] = 1,
    [20757] = 1, -- ["Create Soulstone (Major)"] = 1,
    [2362] = 1, -- ["Create Spellstone"] = 1,
    [17727] = 1, -- ["Create Spellstone (Greater)"] = 1,
    [17728] = 1, -- ["Create Spellstone (Major)"] = 1,
    [691] = 1, -- ["Summon Felhunter"] = 1,
    [712] = 1, -- ["Summon Succubus"] = 1, 8722 used by npcs
    [8722] = 1, -- just in case
    [697] = 1, -- ["Summon Voidwalker"] = 1, 12746 used by npcs
    [12746] = 1, -- just in case
    [6353] = 1, -- ["Soul Fire"] = 1, rank 1
    [17924] = 1, -- soul fire rank 2
    [6366] = 1, -- ["Create Firestone (Lesser)"] = 1,
    [17952] = 1, -- ["Create Firestone (Greater)"] = 1,
    [17953] = 1, -- ["Create Firestone (Major)"] = 1,
    [17951] = 1, -- ["Create Firestone"] = 1,
    [5699] = 1, --["Create Healthstone"] = 1, level 34
    [6202] = 1, -- ["Create Healthstone (Lesser)"] = 1,
    [6201] = 1, -- ["Create Healthstone (Minor)"] = 1,
    [11729] = 1, -- ["Create Healthstone (Greater)"] = 1,
    [208023] = 1, -- ["Create Healthstone"] = 1, level 10
    [11730] = 1, -- ["Create Healthstone (Major)"] = 1,
  },

  ---------------------------------
  lastCast = "",

  castWatch = function(self, event, target, castUID, spellId, ...)
    self = addonData.summon
    db("summon.spellcast", event, " ", target, castUID, spellId, ...)

    -- only interested in summons cast by player for now
    if target ~= "player" then
      return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" then
      -- this is the place to find out if a non-channelled spell used a soul shard
      if self.isWarlock and self.usesSoulShard[spellId] then
        self:shardIncrementBy(-1)
      end
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" or
        event == "UNIT_SPELLCAST_START" then
      if spellId == 698 then
        self.isCasting = true
        if addonData.W then addonData.W.portalUp(self.summoningPlayer) end
      end
    elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
      if self.isWarlock then
        local oldCount = self.shards
        self.shards = addonData.summon.shardCount(self)
        if spellId == 698 then -- "Ritual of Summoning"
          if addonData.W then addonData.W.portalDown() end
          --- update shards (if shard count decreased then the summon went through!)
          if oldCount > g_self.shards then
            addonData.summon.summonSuccess(self)
          else
            addonData.summon.summonFail(self)
          end
        end
      end
    elseif event == "UNIT_SPELLCAST_INTERRUPTED"
        or event == "UNIT_SPELLCAST_FAILED" then
      -- we can get this multiple times for "player" for the same cast, we only want to act once
      if spellId == 698 and self.lastCast ~= castUID then -- "Ritual of Summoning"
        self.lastCast = castUID
        if addonData.W then addonData.W.portalDown() end
        addonData.summon.summonFail(self)
      end
    end
  end,
}

addonData.summon = summon
