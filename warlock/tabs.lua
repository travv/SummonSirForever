-- Bottom tabs on the summon window: Queue, Ledger, Ads, Setup. One window,
-- and every character can reach every screen (Travis's call, 2026-11-12).
-- The queue page is built by summon.lua; the other pages are built by their
-- modules (panel, ads, setup) into the window the first time it exists.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local T = {
  ORDER = { "queue", "ledger", "ads", "setup" },
  LABELS = { queue = "Queue", ledger = "Ledger", ads = "Ads", setup = "Setup" },
  HELP = {
    queue = "Who is in line, who is next, and the summon buttons.",
    ledger = "Gold per hour, who still owes, who never paid.",
    ads = "The ad text, where it posts, and the Post ad button.",
    setup = "The role walkthrough: keybinds, sound, channels. Safe to rerun.",
  },
  pages = {},
  current = "queue",
  built = false,
}

function T:index(key)
  for i, k in ipairs(self.ORDER) do
    if k == key then return i end
  end
  return 1
end

-- build the tab row and the pages once the summon window exists
function T:attach()
  if self.built then return end
  local f = SteaSummonFrame
  if not f or not f.queuePage then return end
  self.built = true
  self.pages.queue = f.queuePage
  self.pages.ledger = W.panel and W.panel.buildInto and W.panel:buildInto(f) or nil
  self.pages.ads = W.ads and W.ads.buildInto and W.ads:buildInto(f) or nil
  self.pages.setup = W.setup and W.setup.buildInto and W.setup:buildInto(f) or nil

  f.Tabs = {}
  local prev
  for i, key in ipairs(self.ORDER) do
    local tab = CreateFrame("Button", "SteaSummonFrameTab" .. i, f, "PanelTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(self.LABELS[key])
    if prev then
      tab:SetPoint("LEFT", prev, "RIGHT", 3, 0)
    else
      tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
    end
    tab:SetScript("OnClick", function(this) T:select(T.ORDER[this:GetID()]) end)
    tab:SetScript("OnEnter", function(this)
      GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
      GameTooltip:AddLine(T.LABELS[key])
      GameTooltip:AddLine(T.HELP[key], 1, 1, 1, true)
      GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if PanelTemplates_TabResize then pcall(PanelTemplates_TabResize, tab, 0) end
    f.Tabs[i] = tab
    prev = tab
  end
  if PanelTemplates_SetNumTabs then pcall(PanelTemplates_SetNumTabs, f, #self.ORDER) end

  -- an advertiser lives on the Ads tab; everyone else starts on the queue
  if W.role() == "advertiser" and self.current == "queue" then self.current = "ads" end
  self:select(self.current)
end

-- true while a tab other than the queue is up: the window must stay shown
-- regardless of the "show only while someone is in line" setting
function T:offQueue()
  return self.built and self.current ~= "queue"
end

function T:select(key)
  if not self.LABELS[key] then return false end
  if not self.built then
    self.current = key -- remembered for when the window appears
    return false
  end
  if not self.pages[key] then return false end
  if InCombatLockdown() and key ~= self.current then
    W.print("tabs switch after combat (the queue's cast buttons are locked)")
    return false
  end
  for k, page in pairs(self.pages) do
    page:SetShown(k == key)
  end
  self.current = key
  if PanelTemplates_SetTab then pcall(PanelTemplates_SetTab, SteaSummonFrame, self:index(key)) end
  local mod = (key == "ledger" and W.panel) or (key == "ads" and W.ads) or (key == "setup" and W.setup) or nil
  if mod and mod.refresh then mod:refresh() end
  if key == "queue" and addonData.summon then addonData.summon:showSummons() end
  return true
end

-- open the window on a tab, creating the window first if it does not exist yet
function T:show(key)
  local S = addonData.summon
  if not SteaSummonFrame and S and S.showSummons then S:showSummons() end
  if not SteaSummonFrame then return false end
  self:attach()
  S.show = true -- stays up until closed by hand
  if not InCombatLockdown() then SteaSummonFrame:Show() end
  return self:select(key)
end

-- the tab's button / command: a second press on the same tab closes the window
function T:toggle(key)
  if SteaSummonFrame and SteaSummonFrame:IsShown() and self.built and self.current == key then
    addonData.summon:showSummonsToggle()
    return false
  end
  return self:show(key)
end

W.module("tabs", T)

function T:init()
  hooksecurefunc(addonData.summon, "showSummons", function() T:attach() end)
  W.command("tab", "tab queue|ledger|ads|setup: open the window on that tab", function(args)
    local key = string.lower(args or "")
    if not T.LABELS[key] then W.print("tabs: queue, ledger, ads, setup") return end
    T:show(key)
  end)
end

addonData.tabs = T
