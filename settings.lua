-- user config

local _, addonData = ...
local L = LibStub("AceLocale-3.0"):GetLocale("SummonSirForever")

-- defaults

local summonWords = {}
summonWords[1] = "123"
summonWords[2] = "123 please"
summonWords[3] = "123 plz"
summonWords[4] = "summon"
summonWords[5] = "summon please"
summonWords[6] = "summon plz"
summonWords[7] = "summon me"
summonWords[8] = "summon me please"
summonWords[9] = "summon me plz"
summonWords[10] ="are summons available?"
summonWords[11] ="are summons available"
summonWords[12] ="are summons avail?"
summonWords[13] ="are summons avail"
summonWords[14] ="are summons ready?"
summonWords[15] ="are summons ready"
summonWords[16] ="summons available?"
summonWords[17] ="summons available"
summonWords[18] ="summons avail?"
summonWords[19] ="summons avail"
summonWords[20] ="summons ready?"
summonWords[21] ="summons ready"
summonWords[22] ="123 summons"
summonWords[23] ="123 summon"
summonWords[24] ="[SteaSummon] 123"

-- SummonSir house style: "sir" and exclamation points. %p player, %l subzone,
-- %z zone, %t summon phrase. Saved texts still on the old stock wording get
-- upgraded at login; anything you typed yourself is left alone.
local FLAVOR = {
  raidchat = "Now summoning Sir %p!",
  whisperchat = "Sit back and relax! The summon is on the way, sir :)",
  saychat = "Summoning Sir %p! Click the portal please!",
  raidinfo = "Summons are open, sir! Type %t for a summon, -%t to cancel, or %t again if one fails!",
  clickersnag = "Need more clickers at %l, %z! Come help, sir!",
  clicknag = "Click the summoning portal, sir!",
  altWhisper = "You're in the summon queue, sir! Whisper me an alt name if you'd rather not wait online.",
  altGetOnlineWhisper = "You're near the top of the summon queue, sir! Get online now!",
  afkText = "I'm AFK for a moment, sir! I'll be right back!",
}

settings = {
  init = function(self)
    addonData.debug:registerCategory("settings")
    if SteaSummonSave == nil or SteaSummonSave.prioplayers == nil then
      self:reset()
    end

    -- init settings that have been added since release

    -- older versions could accidentally store a table here
    if type(SteaSummonSave.debug) ~= "boolean" then
      SteaSummonSave.debug = nil
    end

    if SteaSummonSave.shitlist == nil then
      SteaSummonSave.shitlist = {}
    end

    if SteaSummonSave.windowSize == nil then
      SteaSummonSave.windowSize = 1
    end

    if SteaSummonSave.listSize == nil or not SteaSummonSave.listSizeV2 then
      -- w11: the scroll list is no longer pre-shrunk to half, so 1.0 is normal size
      SteaSummonSave.listSize = 1
      SteaSummonSave.listSizeV2 = true
    end

    if not SteaSummonSave.showV2 then
      -- w13: the warlock's window holds AFK, Ad, Ledger and Menu, so it stays
      -- up even with nobody in line (was "only while summons are active")
      if addonData.util:playerIsWarlock() then
        SteaSummonSave.show = 1
      end
      SteaSummonSave.showV2 = true
    end

    if SteaSummonSave.waiting == nil then
      db("wait list empty on load")
      SteaSummonSave.waiting = {}
      SteaSummonSave.timeStamp = 0
      SteaSummonSave.waitingKeepTime = 5
    end

    if SteaSummonSave.buffs == nil then
      SteaSummonSave.buffs = true
    end

    if SteaSummonSave.windowPos == nil or (type(SteaSummonSave.windowPos[2]) == "table" or not SteaSummonSave.windowPos["height"]) then
      SteaSummonSave.windowPos = {"CENTER", nil, "CENTER", 0, 0, ["height"] = 300, ["width"] = 250}
    end

    if SteaSummonSave.maxLocks == nil then
      SteaSummonSave.maxLocks = 2
    end

    if SteaSummonSave.raidinfo == nil then
      SteaSummonSave.raidinfo = L["raidinfo"]
      SteaSummonSave.clickersnag = L["clickersnag"]
      SteaSummonSave.clicknag = L["clicknag"]
      SteaSummonSave.clickersnagtimer = 5
      SteaSummonSave.raidinfotimer = 5
      SteaSummonSave.clicknagtimer = 10
    end

    if SteaSummonSave.altbuffed == nil then
      SteaSummonSave.altbuffed = false
      SteaSummonSave.qspot = 2
      SteaSummonSave.initialQspot = 6
      SteaSummonSave.alttoons = {}
      SteaSummonSave.qboost = 2
      SteaSummonSave.altWhisper = L["You are in the summon queue. Whisper me an alt name if you don't want to wait online."]
      SteaSummonSave.altGetOnlineWhisper = L["You are near the top of the summon queue. Get online now."]
    end

    if SteaSummonSave.adText == nil then
      SteaSummonSave.adText = L["adtext"]
      SteaSummonSave.adCooldown = 5 -- minutes
      SteaSummonSave.lastAdTime = 0
    end

    if SteaSummonSave.afkText == nil then
      SteaSummonSave.afkText = L["afktext"]
    end

    -- upgrade untouched stock texts to the SummonSir wording
    local STOCK = {
      raidchat = L["Summoning %p"],
      whisperchat = L["Summoning you to %l in %z"],
      saychat = L["Summoning %p, please click the portal"],
      raidinfo = L["raidinfo"],
      clickersnag = L["clickersnag"],
      clicknag = L["clicknag"],
      altWhisper = L["You are in the summon queue. Whisper me an alt name if you don't want to wait online."],
      altGetOnlineWhisper = L["You are near the top of the summon queue. Get online now."],
      afkText = L["afktext"],
    }
    for k, v in pairs(FLAVOR) do
      if SteaSummonSave[k] == nil or SteaSummonSave[k] == STOCK[k] then
        SteaSummonSave[k] = v
      end
    end

    if SteaSummonSave.warlocksAssist == nil then
      SteaSummonSave.warlocksAssist = false
      SteaSummonSave.finalLeadership = false
      SteaSummonSave.assistPlayers = {}
      SteaSummonSave.raidLeaders = {}
      SteaSummonSave.masterLoot = {}
      SteaSummonSave.autoInviteTriggers = {"inv", "invite"}
      SteaSummonSave.autoInvite = 0
      SteaSummonSave.autoAccept = 0
      SteaSummonSave.delayLeadership = false
      SteaSummonSave.convertToRaid = false
    end
  end,

  reset = function()
    SteaSummonSave = {}
    SteaSummonSave.summonWords = summonWords
    if addonData.util:playerIsWarlock() then
      SteaSummonSave.show = 1 -- always: the window carries the service buttons
    else
      SteaSummonSave.show = 3
    end
    SteaSummonSave.showV2 = true
    SteaSummonSave.updates = true
    SteaSummonSave.prioplayers = {[1]="Stea"}
    SteaSummonSave.shitlist = {}
    SteaSummonSave.warlocks = true
    SteaSummonSave.raidchat = L["Summoning %p"]
    SteaSummonSave.whisperchat = L["Summoning you to %l in %z"]
    SteaSummonSave.saychat = L["Summoning %p, please click the portal"]
    SteaSummonSave.experimental = false
    SteaSummonSave.windowSize = 1
    SteaSummonSave.listSize = 1
    SteaSummonSave.waiting = {}
    SteaSummonSave.timeStamp = 0
    SteaSummonSave.waitingKeepTime = 5
    SteaSummonSave.buffs = true
    SteaSummonSave.windowPos = {"CENTER", nil, "CENTER", 0, 0, ["height"] = 300, ["width"] = 250}
    SteaSummonSave.maxLocks = 2
    SteaSummonSave.raidinfo = L["raidinfo"]
    SteaSummonSave.clickersnag = L["clickersnag"]
    SteaSummonSave.clicknag = L["clicknag"]
    SteaSummonSave.clickersnagtimer = 1
    SteaSummonSave.raidinfotimer = 2
    SteaSummonSave.clicknagtimer = 10
    SteaSummonSave.altbuffed = false
    SteaSummonSave.qspot = 2
    SteaSummonSave.initialQspot = 6
    SteaSummonSave.alttoons = {}
    SteaSummonSave.qboost = 4
    SteaSummonSave.altWhisper = L["You are in the summon queue. Whisper me an alt name if you don't want to wait online."]
    SteaSummonSave.altGetOnlineWhisper = L["You are near the top of the summon queue. Get online now."]
    SteaSummonSave.warlocksAssist = true
    SteaSummonSave.finalLeadership = true
    SteaSummonSave.assistPlayers = {"Stea", "Stec"}
    SteaSummonSave.raidLeaders = {"Stea", "Stec"}
    SteaSummonSave.masterLoot = {"Stea", "Ninja"}
    SteaSummonSave.adText = L["adtext"]
    SteaSummonSave.adCooldown = 5
    SteaSummonSave.lastAdTime = 0
    SteaSummonSave.afkText = L["afktext"]
    SteaSummonSave.autoInviteTriggers = {"inv", "invite"}
    SteaSummonSave.autoInvite = 1
    SteaSummonSave.autoAccept = 1
    SteaSummonSave.delayLeadership = true
    SteaSummonSave.convertToRaid = false
    for k, v in pairs(FLAVOR) do
      SteaSummonSave[k] = v
    end
  end,

  saveOnLogout = function(self, event, ...)
    --- timestamp and the list
    addonData.gossip:retire() -- while we can recover on /reload, if we don't retire as leader events might be missed
    SteaSummonSave.timeStamp = GetTime()
    SteaSummonSave.waiting = addonData.summon.waiting -- can get displaced if list is unmarshalled
  end,

  -- case and surrounding spaces/punctuation no longer matter ("123!", "Summon Plz")
  findSummonWord = function(_, phrase)
    if type(phrase) ~= "string" then
      return nil
    end
    local function norm(s)
      s = string.lower(s)
      s = string.gsub(s, "^%s*%[[^%]]*%]", "") -- tagged phrases ("[SteaSummon] 123") from other SteaSummon users
      s = string.gsub(s, "^[%s%p]+", "")
      s = string.gsub(s, "[%s%p]+$", "")
      return s
    end
    local want = norm(phrase)
    for k,v in pairs(SteaSummonSave.summonWords) do
      if v == phrase or norm(v) == want then
        return k
      end
    end
    return nil
  end,

  findPrioPlayer = function(_, player)
    for k,v in pairs(SteaSummonSave.prioplayers) do
      if v == player then
        return k
      end
    end
    return nil
  end,

  findShitlistPlayer = function(_, player)
    for k,v in pairs(SteaSummonSave.shitlist) do
      if v == player then
        return k
      end
    end
    return nil
  end,

  -- NOTE: callers use colon syntax, so the first argument is the module
  debug = function(_, bug)
    if bug ~= nil then
      SteaSummonSave.debug = bug
      if bug then
        addonData.debug:installErrorTrap() -- start capturing errors at once
      end
    end
    return SteaSummonSave.debug and true or false
  end,

  showWindow = function()
    return SteaSummonSave.show == 1
  end,

  showActive = function()
    return SteaSummonSave.show == 2
  end,

  showJustMe = function()
    return SteaSummonSave.show == 3
  end,

  showNever = function()
    return SteaSummonSave.show == 4
  end,

  useUpdates = function()
    return SteaSummonSave.updates
  end,

  getSettings = function()
    return SteaSummonSave
  end,

  getWindowPos = function()
    return SteaSummonSave.windowPos
  end,

  setWindowPos = function(_, pos)
    SteaSummonSave.windowPos = pos
  end,
}

addonData.settings = settings
