local _, addonData = ...

local util = {
  init = function(_)
    addonData.debug:registerCategory("util")
  end,

  trim = function(_, s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
  end,

  tableToMultiLine = function(_, table, sep)
    local text = ""
    local word
    if sep == nil then
      sep = ", "
    end
    local ins = ""
    for key, val in pairs(table) do
      if type(val) == "string" then
        word = val
      else
        word = key
      end
      if word ~= "" then
        text = text .. ins .. word
        if ins == "" then
          ins = sep
        end
      end
    end
    return text
  end,

  multiLineToTable = function(_, text, sep)
    -- might be comma or carriage return delimited
    if not sep and string.find(text, ",") then
      sep = ","
    else
      sep = "\n"
    end
    local out = {strsplit(sep, text)}

    -- sanitize
    local idx = 1
    for _,v in pairs(out) do
      local sanitized = strtrim(v)
      if sanitized ~= "" then
        out[idx] = sanitized
        idx = idx + 1
      end
    end

    return out
  end,

  multiLineToMap = function(self,text, sep)
    local tbl = self:multiLineToTable(text, sep)
    local map = {}

    for _,v in pairs(tbl) do
      map[v] = 1
    end

    return map
  end,

  case = function(_, text, sep)
    local out = ""
    if text ~= nil and text ~= "" then
      local i = 2
      local last = 2
      out = strupper(strsub(text,1,1))
      while(i ~= nil) do
        i = strfind(text, sep, i)
        if i ~= nil then
          out = out .. strsub(text,last,i) .. strupper(strsub(text,i+1,i+1))
          last = i + 2
          i = i + 1
        end
      end
      out = out .. strsub(text,last)
    end
    return out
  end,

  marshalWaitingTable = function()
    db("summon.waitlist", "marshalling waitlist")
    local out = ""
    local comma = ""

    for _, wait in pairs(addonData.summon.waiting) do
      out = out .. comma .. addonData.summon:recMarshal(wait)
      if comma == "" then
        comma = ","
      end
    end

    db("summon.waitlist", "marshalled waitlist:", out)
    return out
  end,

  unmarshalWaitingTable = function(_, marshalled)
    db("summon.waitlist", "unmarshalling waitlist:", marshalled)
    wipe(addonData.summon.waiting)
    if not marshalled or marshalled == "" then
      addonData.summon.numwaiting = 0
      return
    end
    local recs = { strsplit(",", marshalled) }
    local waiting = {}
    local numwaiting = 0
    if recs and #recs > 0 then
      for _, rec in pairs(recs) do
        table.insert(waiting, addonData.summon:recUnMarshal(rec))
        numwaiting = numwaiting + 1
      end
    end
    addonData.summon.waiting = waiting
    addonData.summon.numwaiting = numwaiting
    addonData.summon:listDirty(true)
    addonData.summon:showSummons()
  end,

  sortWaitingTableByTime = function()
    table.sort(addonData.summon.waiting, function(k1, k2)
      return k1[3] > k2[3]
    end)
  end,

  isInTable = function(_, tbl, item)
    local inTable = false

    for _,v in pairs(tbl) do
      if v == item then
        inTable = true
        break
      end
    end

    return inTable
  end,

  -- WoW: Forever characters have first and last names: UnitName("player")
  -- returns them as two values ("Summ", "Bert") while rosters and chat
  -- authors use the full "Summ Bert". Identity comparisons must use the
  -- full name. On classic clients the second value is nil (realm slot).
  playerFullName = function(_)
    local first, second = UnitName("player")
    if second and second ~= "" then
      return first .. " " .. second
    end
    return first
  end,

  -- modern clients often report group members as Name-Realm even on the
  -- home realm (Forever is realm-less); strip the suffix unless the player
  -- is from a genuinely foreign realm, so names compare with UnitName
  shortName = function(_, name)
    if not name then return name end
    local n, realm = strsplit("-", name)
    local _, myrealm = UnitFullName("player")
    if realm == nil or realm == "" or realm == myrealm then
      return n
    end
    return name
  end,

  -- API compat: on the WoW: Forever client some unit APIs (UnitInRange,
  -- UnitIsVisible, UnitPosition) can return secret values that addon code
  -- may not branch on; evaluating inside pcall turns that into a nil result
  secretSafe = function(_, fn)
    local ok, result = pcall(fn)
    if ok then
      return result
    end
    return nil -- value was secret (or errored): caller falls back
  end,

  unitNearby = function(self, unit)
    local r = self:secretSafe(function() return UnitInRange(unit) and true or false end)
    if r ~= nil then return r end
    -- range is secret: approximate with visibility (~100yd, same phase)
    r = self:secretSafe(function() return UnitIsVisible(unit) and true or false end)
    if r ~= nil then return r end
    return self:isNear(unit)
  end,

  playerClose = function(self, player)
    local me = self:playerFullName()
    player = strsplit("-", player) -- might turn up as player-server

    if me == player or player == "player" then
      return false -- don't trip for yourself, we'll let others tell us you're summoned :)
    end

    if self:unitNearby(player) or self:isNear(player) then
      return true
    end
  end,

  playerIsWarlock = function(_, player)
    if player == nil then player = "player" end
    player = strsplit("-", player) -- might turn up as player-server
    local _, class = UnitClass(player)

    return class == "WARLOCK"
  end,

  playerCanSummon = function(self, player)
    self = addonData.util
    if player == nil then player = "player" end
    player = strsplit("-", player) -- might turn up as player-server

    local level = UnitLevel(player)
    return self:playerIsWarlock(player) and level >= 20
  end,

  distance = function(_, unit1, unit2)
    -- positions can be secret on the Forever client; pcall turns the
    -- forbidden branch into a nil distance (unknown)
    local ok, out = pcall(function()
      local y1, x1, _, instance1 = UnitPosition(unit1)
      local y2, x2, _, instance2 = UnitPosition(unit2)
      if y1 and x1 and x2 and y2 then
        if instance1 == instance2 then
          return ((x2 - x1) ^ 2 + (y2 - y1) ^ 2) ^ 0.5
        end
      end
    end)
    if ok then
      return out
    end
    return nil
  end,

  isNear = function(self, player)
    local ret = false
    local dist = self:distance("player", player)
    if dist ~= nil and dist <= 40 then
      db("util", "player detected by alt method")
      ret = true
    end
    return ret
  end,

  -- Dracula palette for the summon window (https://draculatheme.com, MIT).
  -- Kept here rather than in warlock/core.lua so the window can style
  -- itself even though our modules load after it.
  dracula = {
    bg      = { 0x28, 0x2a, 0x36 },
    line    = { 0x44, 0x47, 0x5a },
    fg      = { 0xf8, 0xf8, 0xf2 },
    comment = { 0x62, 0x72, 0xa4 },
    cyan    = { 0x8b, 0xe9, 0xfd },
    green   = { 0x50, 0xfa, 0x7b },
    orange  = { 0xff, 0xb8, 0x6c },
    pink    = { 0xff, 0x79, 0xc6 },
    purple  = { 0xbd, 0x93, 0xf9 },
    red     = { 0xff, 0x55, 0x55 },
    yellow  = { 0xf1, 0xfa, 0x8c },
  },

  rgb = function(self, name, alpha)
    local c = self.dracula[name] or self.dracula.fg
    return c[1] / 255, c[2] / 255, c[3] / 255, alpha or 1
  end,

  -- A flat Dracula button: solid face, 1px border, readable text. Built on a
  -- plain Button + BackdropTemplate because UIPanelButtonTemplate's stock
  -- textures can't be recolored cleanly. Use btn:SetFace(color) to tint.
  flatButton = function(self, name, parent, width, height, text, fontSize)
    local btn = CreateFrame("Button", name, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Buttons\\WHITE8x8",
      edgeSize = 1,
    })
    btn:SetBackdropColor(self:rgb("line"))
    btn:SetBackdropBorderColor(self:rgb("purple"))
    btn:SetNormalFontObject("GameFontHighlight")
    btn:SetDisabledFontObject("GameFontDisable")
    btn:SetText(text or "")
    local fs = btn:GetFontString()
    if fs then
      fs:SetFont("Fonts\\FRIZQT__.TTF", fontSize or 12, "")
      fs:SetPoint("CENTER", 0, 0)
      fs:SetJustifyH("CENTER")
    end
    btn:SetHighlightTexture("Interface\\Buttons\\WHITE8x8", "ADD")
    btn:GetHighlightTexture():SetVertexColor(self:rgb("purple", 0.25))
    btn:SetPushedTextOffset(1, -1)
    btn.face = "line"
    btn.SetFace = function(this, color)
      this.face = color or "line"
      this:SetBackdropColor(self:rgb(this.face))
    end
    -- text tint survives enable/disable (a state change re-applies the
    -- font object, which would reset a plain SetTextColor)
    btn.SetTextTint = function(this, color)
      this.tint = color
      local s = this:GetFontString()
      if s and color then s:SetTextColor(self:rgb(color)) end
    end
    btn:SetScript("OnDisable", function(this)
      this:SetBackdropColor(self:rgb("bg"))
      this:SetBackdropBorderColor(self:rgb("comment"))
    end)
    btn:SetScript("OnEnable", function(this)
      this:SetBackdropColor(self:rgb(this.face))
      this:SetBackdropBorderColor(self:rgb("purple"))
      if this.tint then this:SetTextTint(this.tint) end
    end)
    return btn
  end,
}

addonData.util = util
