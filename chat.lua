-- chat message interpretation

local _, addonData = ...
local L = LibStub("AceLocale-3.0"):GetLocale("SteaSummonForever")
local gossip = addonData.gossip
local debug = addonData.debug
local settings = addonData.settings
local summon = addonData.summon
local raid = addonData.raid

-- API compat: Forever lists only C_ChatInfo.SendChatMessage (same arguments)
local SendChatMessage = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

local chat = {
  init = function(_)
    debug:registerCategory("chat")
  end,

  callback = function (_, event, msg, servername, ...)
    local me = addonData.util:playerFullName()

    -- warlock service: blocklist, auto-reply + invite, loose phrases
    if addonData.W and addonData.W.onChat(event, msg, servername) then
      return
    end

    -- don't want randos adding themselves
    local player, server = strsplit("-", servername)
    if event == "CHAT_MSG_SAY" and player ~= me then
      return
    end
    -- modern clients send authors as Name-Realm even on the home realm;
    -- keep the full name only for genuinely foreign realms so comparisons
    -- against UnitName("player") and roster names still match
    local _, myrealm = UnitFullName("player")
    if server and server ~= "" and server ~= myrealm then
        player = servername
    end

    db("chat", "testing chat for keywords")

    if player == me then
      if msg and msg:find("!SS") == 1 then
        local _, cmd, args = strsplit(" ", msg)
        if cmd == nil then cmd = "list" end
        if args == nil then args = "" end
        cmd = string.lower(cmd)

        db("chat","Received command : " .. cmd .. " " .. args)
        if cmd == L["list"] then
          local waitlist = summon:getWaiting()
          cprint(L["Summon waiting list"])
          local count = 0

          for _,waiting in pairs(waitlist) do
            local pats = {["%%name"] = waiting[1], ["%%number"] = waiting[2]}
            local s = L["%name waiting: %number seconds"]
            s = tstring(s, pats)
            cprint(s)
            count = count + 1
          end

          local pats = {["%%count"] = count}
          local s = L["%count waiting"]
          s = tstring(s, pats)
          cprint(s)

        end

        if cmd == L["debug"] then
          if args == L["on"] then settings:debug(true)
          elseif args == L["off"] then settings:debug(false)
          else settings:debug(not settings:debug())
          end

          local offon = L["off"]
          if settings:debug() then offon = L["on"] end
          cprint("Debugging: ", offon)
        end

        if cmd == L["add"] then
          -- add someone to list
          if args ~= "" then
            gossip:add(args, true )
          end
        end
      end
    end

    if msg then
      if string.sub(msg, 1,1) == "-" and settings:findSummonWord(string.sub(msg, 2)) then
        local name = strsplit("-", servername)
        gossip:arrived(name, true)
      elseif settings:findSummonWord(msg) then
        -- someone wants a summon
        db("chat","adding ", player, "to summon list")

        -- IsInGroup takes a category constant, not a player: classic clients
        -- ignored the bad argument (truthy), modern clients return false.
        -- What we actually want: is the requester in my group?
        if UnitInParty(player) or UnitInRaid(player) or (player == me and settings:debug()) then
          gossip:add(player, event == "CHAT_MSG_WHISPER" )
        end
        if event == "CHAT_MSG_WHISPER" then
          addonData.chat:afkReply(player) -- no-op unless AFK
        end
      elseif event == "CHAT_MSG_WHISPER" then
        if raid:isInvTrigger(msg) then
          if addonData.summon.afk then
            addonData.chat:afkReply(player) -- AFK: reply instead of inviting
          else
            raid:whisperedTrigger(player)
          end
        else
          addonData.alt:whispered(player, msg)
        end
      end
    end
  end,

  raid = function(self, msg, player)
    if IsInRaid() then
      self:sendChat(msg, "RAID", "RAID", player)
    else
      self:sendChat(msg, "PARTY", "PARTY", player)
    end
  end,

  say = function(self, msg, player)
    self:sendChat(msg, "SAY", "SAY", player)
  end,

  whisper = function(self, msg, player)
    self:sendChat(msg, "WHISPER", player, player)
  end,

  -- whisper the AFK message back, once per player per AFK session
  afkReply = function(self, player)
    local summon = addonData.summon
    if not summon.afk then
      return
    end
    if summon.afkReplied[player] then
      return
    end
    summon.afkReplied[player] = true
    self:whisper(SteaSummonSave.afkText, player)
  end,

  -- find the joined Trade channel (cities only)
  tradeChannel = function(_)
    local args = { GetChannelList() }
    for i = 2, #args do
      if type(args[i]) == "string" and string.find(args[i], "^Trade") then
        return args[i-1], args[i]
      end
    end
  end,

  -- is the trade ad off cooldown? returns ready, secondsRemaining
  adReady = function(_)
    local last = SteaSummonSave.lastAdTime or 0
    local wait = (SteaSummonSave.adCooldown or 5) * 60
    local remaining = wait - (time() - last)
    if remaining > 0 then
      return false, remaining
    end
    return true, 0
  end,

  -- send the configured advertisement to Trade, hard-gated by the cooldown
  advertise = function(self)
    local ready, remaining = self:adReady()
    if not ready then
      cprint(L["Next ad ready in"], string.format("%d:%02d", math.floor(remaining / 60), remaining % 60))
      return
    end

    local msg = SteaSummonSave.adText
    local chanId
    if addonData.ads then
      msg = addonData.ads:text()
      chanId = addonData.ads:channel()
      if not chanId then
        cprint("Not in the " .. tostring(SteaWarlockDB.adChannel) .. " channel. Join it, or set another with /sw channel <name>.")
        return
      end
    else
      chanId = self:tradeChannel()
      if not chanId then
        cprint(L["No Trade channel found. Trade ads only work in cities."])
        return
      end
    end
    if msg == nil or msg == "" then
      return
    end

    local trigphrase = SteaSummonSave.summonWords[1] or ""
    msg = tstring(msg, {["%%l"] = GetMinimapZoneText(), ["%%z"] = GetZoneText(), ["%%t"] = trigphrase})
    SendChatMessage(msg, "CHANNEL", nil, chanId)
    SteaSummonSave.lastAdTime = time()
    addonData.summon:adButtonUpdate()
  end,

  sendChat = function(_, msg, channel, channel2, to)
    db("chat", "sendChat ", msg, " ", channel, " ", to)
    if msg ~= nil and msg ~= "" then
      -- substitute variables in message
      local trigphrase = SteaSummonSave.summonWords[1]
      if trigphrase == nil then
        trigphrase = ""
      end

      local l = GetMinimapZoneText()
      local z = GetZoneText()
      if l == z then
        -- "Thunder Bluff in Thunder Bluff" reads badly: collapse the
        -- location phrase when subzone and zone are the same
        msg = string.gsub(msg, "%%l in %%z", "%%z")
      end

      local patterns = {["%%p"] = to,
                        ["%%l"] = l,
                        ["%%z"] = z,
                        ["%%t"] = trigphrase
      }
      msg = tstring(msg, patterns)
      msg = "[SteaSummon] " .. msg
      -- argument 3 is the language id: classic clients tolerated a channel
      -- name there, modern clients validate the number. nil = default
      -- language; the target only applies to whispers
      SendChatMessage(msg, channel, nil, channel == "WHISPER" and to or nil)
    end
  end
}

addonData.chat = chat
