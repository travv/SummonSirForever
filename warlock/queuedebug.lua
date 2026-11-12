-- /ssf queuedebug: print the queue network state in one go, so a removal
-- that does nothing can be diagnosed from a paste instead of guesswork.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local Q = {}

local function yn(v)
  if v then return "yes" end
  return "no"
end

function Q:report()
  local g, s = addonData.gossip, addonData.summon
  if not g or not s then
    W.print("queue modules not loaded")
    return
  end
  local okLeader, leader = pcall(function() return g:isLeader() end)
  W.print("queue debug")
  print("  me:", tostring(g.me), " role:", tostring(W.role()))
  print("  in group:", yn(IsInGroup(LE_PARTY_CATEGORY_HOME)), " raid:", yn(IsInRaid()))
  print("  comms off:", yn(g:noComms()), " inInit:", yn(g.inInit),
        " isLeader:", okLeader and yn(leader) or ("error " .. tostring(leader)))
  print("  netList (" .. #g.netList .. "):", table.concat(g.netList, " | "))
  print("  waiting:", #s.waiting, " numwaiting:", tostring(s.numwaiting),
        (s.numwaiting ~= #s.waiting) and "  <-- out of sync" or "")
  for i, rec in ipairs(s.waiting) do
    print(string.format("    %d. %s [%s]", i, tostring(s:recPlayer(rec)), tostring(s:recStatus(rec))))
  end
  if g.lastRemoval then
    local r = g.lastRemoval
    print(string.format("  last removal: %s  in list: %s  as leader: %s  %ds ago",
          tostring(r.player), yn(r.had), yn(r.leader), math.floor(GetTime() - (r.at or GetTime()))))
  else
    print("  last removal: none this session")
  end
  if g.lastMsg then
    print("  last comm:", tostring(g.lastMsg), " from:", tostring(g.lastSender),
          " raw sender:", tostring(g.lastRawSender))
  else
    print("  last comm: none received this session")
  end
end

W.module("queuedebug", Q)

function Q:init()
  W.command("queuedebug", "queuedebug: print queue leader / list state (paste this when X or Clear fail)", function()
    Q:report()
  end)
end
