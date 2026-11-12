-- Right-click menu on queue names: move to front / back, mark summoned,
-- remove, block, and whisper any message type. Rows register left clicks only
-- for the secure cast, so a right-click can never start a summon.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local R = { hooked = {} }

local function isLeader()
  local g = addonData.gossip
  return g and g.isLeader and g:isLeader()
end

-- reorder the shared list; only the queue leader may, then everyone gets it
function R:move(name, toFront)
  local S = addonData.summon
  local idx = S:findWaitingPlayerIdx(name)
  if not idx then return false end
  if not isLeader() then
    W.print("only the queue leader can reorder (another warlock leads this group)")
    return false
  end
  local rec = table.remove(S.waiting, idx)
  if toFront then table.insert(S.waiting, 1, rec) else table.insert(S.waiting, rec) end
  wipe(S.rowOrder) -- you asked for it: re-lay the rows now
  S:listDirty(true)
  local g = addonData.gossip
  if not g:noComms() then
    g:SendCommMessage(g.channel, "l " .. addonData.util:marshalWaitingTable(), g:groupText(), "BULK")
  end
  S:showSummons()
  return true
end

function R:open(owner, name)
  if not (MenuUtil and MenuUtil.CreateContextMenu) then
    W.print("right-click menus need MenuUtil, which this client lacks")
    return
  end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(name)
    local front = root:CreateButton("Move to front", function() R:move(name, true) end)
    local back = root:CreateButton("Move to back", function() R:move(name, false) end)
    if not isLeader() then front:SetEnabled(false); back:SetEnabled(false) end
    root:CreateButton("Mark summoned", function() addonData.gossip:arrived(name, false) end)
    root:CreateButton("Remove from queue", function() addonData.gossip:arrived(name, true) end)
    root:CreateButton("Block (" .. (W.db.autoBlockHours or 24) .. "h) and remove", function()
      W.blocklist:add(name, (W.db.autoBlockHours or 24) * 3600, "manual")
      addonData.gossip:arrived(name, true)
      W.print("blocked", name)
    end)
    root:CreateButton("Clear whole queue...", function() addonData.summon:clearList() end)
    root:CreateDivider()
    local sub = root:CreateButton("Whisper")
    local M = W.messages
    for _, kind in ipairs(M.ORDER) do
      if kind ~= "advertiser" then
        sub:CreateButton(M.TYPES[kind].label, function()
          local pos = addonData.service:position(name)
          local msg = M:text(kind, { pos = pos or "?", ahead = pos and (pos - 1) or "?", asked = "there" })
          if msg then W.whisper(name, msg) else W.print(kind, "is turned off") end
        end)
      end
    end
  end)
end

-- hook each row once, after the summon window has built its buttons
function R:attach()
  if not addonData.buttons then return end
  for i = 1, 37 do
    local b = addonData.buttons[i] and addonData.buttons[i].Button
    if b and not self.hooked[i] then
      self.hooked[i] = true
      b:HookScript("OnMouseUp", function(this, button)
        if button ~= "RightButton" then return end
        local rec = addonData.summon:rowRecord(i)
        if rec then R:open(this, rec[1]) end
      end)
    end
  end
end

W.module("rowmenu", R)

function R:init()
  hooksecurefunc(addonData.summon, "showSummons", function() R:attach() end)
end

addonData.rowmenu = R
