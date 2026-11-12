-- One-time setup for new users: welcome, pick a role, set up that role, done.
-- Shows once per character on first login; /sw setup brings it back.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local U = { frame = nil, page = 1, pages = {}, role = nil }

local ROLE_INFO = {
  warlock = { label = "Warlock", desc = "You cast the summons. Customers get replies, invites and a queue spot, and every payment is tracked." },
  clicker = { label = "Clicker", desc = "You help click the portal. A big banner tells you when to press your Interact key." },
  advertiser = { label = "Advertiser", desc = "You post the ad in a city. One click per post; whispers get pointed at the warlock." },
}
local ROLE_ORDER = { "warlock", "clicker", "advertiser" }

local function charState()
  local me = W.me()
  W.db.chars[me] = W.db.chars[me] or {}
  return W.db.chars[me]
end

function U:needed()
  return not charState().setupDone
end

local function text(parent, font, r, x, y, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
  fs:SetPoint("TOPLEFT", x or 0, y or 0)
  if width then fs:SetWidth(width) end
  fs:SetJustifyH("LEFT")
  fs:SetTextColor(W.rgb(r or "fg"))
  return fs
end

local function editBox(parent, x, y, width, onChange)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 160, 20)
  e:SetPoint("TOPLEFT", x + 6, y)
  e:SetAutoFocus(false)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnTextChanged", function(self, user) if user then onChange(self:GetText()) end end)
  return e
end

local function checkBox(parent, x, y, label, get, set)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  c:SetPoint("TOPLEFT", x, y)
  local fs = text(parent, "GameFontHighlight", "fg", x + 28, y - 5)
  fs:SetText(label)
  c:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  c.refresh = function() c:SetChecked(get()) end
  return c
end

local function button(parent, label, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width or 120, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

---------------------------------------------------------------- pages
-- each page: { frame, refresh = function() } built once

local function pageWelcome(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  local t = text(p, "GameFontNormalHuge", "purple", 0, 0)
  t:SetText("Welcome, sir!")
  local b = text(p, "GameFontHighlight", "fg", 0, -40, 420)
  b:SetText("SummonSirForever runs a warlock summon service: one-button summons, replies and invites for "
    .. "customers, a payment ledger, a never-paid blocklist, clicker alerts and ads.\n\n"
    .. "This takes about a minute. Each window (warlock, clickers, advertiser) runs it once.")
  b:SetSpacing(3)
  return { frame = p }
end

local function pageRole(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  local t = text(p, "GameFontNormalLarge", "purple", 0, 0)
  t:SetText("What does this window do?")
  local desc = text(p, "GameFontHighlight", "fg", 0, -120, 420)
  local btns = {}
  for i, role in ipairs(ROLE_ORDER) do
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(136, 40)
    b:SetPoint("TOPLEFT", (i - 1) * 148, -36)
    b:SetNormalFontObject("GameFontNormalLarge")
    b:SetHighlightFontObject("GameFontHighlightLarge")
    b:SetText(ROLE_INFO[role].label)
    b:SetScript("OnClick", function() U.role = role; W.setRole(role); U:refresh() end)
    btns[role] = b
  end
  return { frame = p, refresh = function()
    for role, b in pairs(btns) do
      -- the chosen role stays lit (stock button highlight), the others are plain
      if role == U.role then b:LockHighlight() else b:UnlockHighlight() end
    end
    desc:SetText(ROLE_INFO[U.role].desc .. "\n\n" .. W.hex("comment", "You can change this later with /sw role."))
  end }
end

local function pageWarlock(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalLarge", "purple", 0, 0):SetText("Warlock setup")

  text(p, "GameFontNormal", "cyan", 0, -34):SetText("Where do you summon to?")
  local destOut = text(p, "GameFontHighlight", "fg", 190, -54)
  local dest = editBox(p, 0, -50, 170, function(v)
    local m = v ~= "" and W.destinations.match(v)
    W.db.dest = m and m.key or nil
    W.fire("CONFIG_CHANGED")
    U:refresh()
  end)
  text(p, "GameFontNormal", "cyan", 0, -84):SetText("Price per summon")
  local priceOut = text(p, "GameFontHighlight", "fg", 190, -104)
  local price = editBox(p, 0, -100, 80, function(v)
    local c = W.parseMoney(v)
    if c then W.db.price = c; W.fire("CONFIG_CHANGED") end
    priceOut:SetText(c and W.hex("green", W.fmtMoney(c)) or W.hex("orange", "use 80s, 1g or 1g50s"))
  end)
  local svc = checkBox(p, 0, -132, "Auto-reply and invite people who whisper you",
    function() return W.db.service end, function(v) W.db.service = v end)
  local plain = checkBox(p, 0, -158, "Plain messages (skip the \"sir\" flavor)",
    function() return W.db.plainMode end, function(v) W.db.plainMode = v; U:refresh() end)
  local sample = text(p, "GameFontHighlightSmall", "comment", 0, -192, 430)

  return { frame = p, refresh = function()
    if not dest:HasFocus() then
      local cur = W.destinations.byKey(W.db.dest)
      dest:SetText(cur and cur.name or "")
    end
    local cur = W.destinations.byKey(W.db.dest)
    destOut:SetText(cur and W.hex("green", "-> " .. cur.name)
      or W.hex("comment", "blank = your current zone (" .. W.destName() .. ")"))
    if not price:HasFocus() then price:SetText(W.fmtMoney(W.db.price)) end
    if priceOut:GetText() == nil or priceOut:GetText() == "" then priceOut:SetText(W.hex("green", W.fmtMoney(W.db.price))) end
    svc.refresh(); plain.refresh()
    local saved = W.messages.last.queued
    sample:SetText("Customers will get: " .. W.hex("fg", W.messages:text("queued") or "(off)"))
    W.messages.last.queued = saved
  end }
end

local function pageClicker(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalLarge", "purple", 0, 0):SetText("Clicker setup")

  text(p, "GameFontNormal", "cyan", 0, -34):SetText("1. Let the Interact key reach the portal")
  local cvarOut = text(p, "GameFontHighlight", "fg", 0, -56, 300)
  local cvarBtn = button(p, "Turn it on", 110, function()
    pcall(C_CVar.SetCVar, "SoftTargetInteract", "3")
    U:refresh()
  end)
  cvarBtn:SetPoint("TOPLEFT", 310, -52)

  text(p, "GameFontNormal", "cyan", 0, -88):SetText("2. Bind \"Interact With Target\"")
  local keyOut = text(p, "GameFontHighlight", "fg", 0, -110, 430)

  text(p, "GameFontNormal", "cyan", 0, -150):SetText("3. Check the alert")
  local test = button(p, "Show the banner", 130, function() W.commands.testportal("") end)
  test:SetPoint("TOPLEFT", 0, -170)
  local snd = checkBox(p, 150, -169, "Play a sound", function() return W.db.alertSound end,
    function(v) W.db.alertSound = v end)

  return { frame = p, refresh = function()
    local v = C_CVar.GetCVar("SoftTargetInteract")
    if v == "3" then
      cvarOut:SetText(W.hex("green", "On (SoftTargetInteract = 3)"))
      cvarBtn:Hide()
    else
      cvarOut:SetText(W.hex("orange", "Off (it's " .. tostring(v) .. ", needs 3)"))
      cvarBtn:Show()
    end
    local key = GetBindingKey("INTERACTTARGET")
    keyOut:SetText(key and W.hex("green", "Bound to " .. key)
      or W.hex("orange", "Not bound yet. Esc > Options > Keybindings > Targeting > Interact With Target. This page updates when you're done."))
    snd.refresh()
  end }
end

local function pageAdvertiser(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalLarge", "purple", 0, 0):SetText("Advertiser setup")

  text(p, "GameFontNormal", "cyan", 0, -34):SetText("Ad channels (numbers or names)")
  local chanOut = text(p, "GameFontHighlight", "fg", 190, -54, 240)
  local chan = editBox(p, 0, -50, 170, function(v)
    if v ~= "" then W.db.adChannels = v; W.fire("CONFIG_CHANGED") end
    U:refresh()
  end)
  text(p, "GameFontNormal", "cyan", 0, -84):SetText("Main warlock's name")
  local lockOut = text(p, "GameFontHighlight", "comment", 190, -104, 240)
  local lock = editBox(p, 0, -100, 170, function(v)
    W.db.lockName = v ~= "" and v or nil
    W.fire("CONFIG_CHANGED")
    U:refresh()
  end)
  local preview = text(p, "GameFontHighlightSmall", "comment", 0, -140, 430)

  return { frame = p, refresh = function()
    if not chan:HasFocus() then chan:SetText(W.db.adChannels or "") end
    if not lock:HasFocus() then lock:SetText(W.db.lockName or "") end
    chanOut:SetText(W.ads:channelSummary())
    local age = W.db.remoteAt and (W.now() - W.db.remoteAt)
    lockOut:SetText((age and age < 120) and W.hex("green", "synced: " .. W.destName() .. ", " .. W.fmtMoney(W.priceFor(W.destKey())))
      or "syncs by itself when you group with them")
    preview:SetText("Your ad: " .. W.hex("fg", W.ads:text()) .. "\n\n"
      .. W.hex("comment", "The ad follows the main warlock's destination and price. The Post ad button appears after setup: one click posts once to each channel. With assist in the warlock's raid you invite and queue \"inv\" whispers yourself."))
  end }
end

local function pageDone(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalHuge", "green", 0, 0):SetText("All set, sir!")
  local b = text(p, "GameFontHighlight", "fg", 0, -40, 430)
  b:SetSpacing(4)
  return { frame = p, refresh = function()
    local lines = { "Role: " .. W.hex("purple", ROLE_INFO[U.role].label) }
    if U.role == "warlock" then
      table.insert(lines, "Summoning to " .. W.destName() .. " for " .. W.fmtMoney(W.priceFor(W.db.dest)) .. ".")
      table.insert(lines, "Press your Summon Next key (Key Bindings > AddOns) or the portal button.")
      table.insert(lines, "Right-click a name in the queue to move, remove, block or whisper them.")
      table.insert(lines, W.hex("cyan", "/sw") .. " opens the ledger.")
    elseif U.role == "clicker" then
      table.insert(lines, "When the banner says PORTAL UP, press your Interact key.")
    else
      table.insert(lines, "Click Post ad for each ad. It counts down between posts.")
    end
    table.insert(lines, W.hex("cyan", "/sw options") .. " has every setting. " .. W.hex("cyan", "/sw setup") .. " runs this again.")
    b:SetText(table.concat(lines, "\n"))
  end }
end

---------------------------------------------------------------- frame

function U:currentPages()
  local rolePage = (U.role == "clicker" and self.pages.clicker)
    or (U.role == "advertiser" and self.pages.advertiser) or self.pages.warlock
  return { self.pages.welcome, self.pages.role, rolePage, self.pages.done }
end

function U:build()
  if self.frame then return self.frame end
  local f = W.stockWindow("SummonSirSetup", UIParent, 500, 380, "SummonSir setup", "Interface/ICONS/Spell_Shadow_Twilight")
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  table.insert(UISpecialFrames, "SummonSirSetup")
  if W.child(f, "Inset") then
    -- the inset frames the page; buttons sit below it
    f.Inset:ClearAllPoints()
    f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -48)
    f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 44)
  end

  f.steps = text(f, "GameFontNormalSmall", "comment", 14, -30)

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 28, -64)
  content:SetPoint("BOTTOMRIGHT", -28, 60)
  self.pages.welcome = pageWelcome(content)
  self.pages.role = pageRole(content)
  self.pages.warlock = pageWarlock(content)
  self.pages.clicker = pageClicker(content)
  self.pages.advertiser = pageAdvertiser(content)
  self.pages.done = pageDone(content)

  f.back = button(f, "Back", 90, function() U:go(U.page - 1) end)
  f.back:SetPoint("BOTTOMLEFT", 12, 12)
  f.next = button(f, "Next", 110, function()
    if U.page >= #U:currentPages() then U:finish() else U:go(U.page + 1) end
  end)
  f.next:SetPoint("BOTTOMRIGHT", -12, 12)
  f.skip = button(f, "Skip setup", 100, function() U:finish() end)
  f.skip:SetPoint("BOTTOM", 0, 12)

  -- closing early counts as done: /sw setup brings it back
  f:SetScript("OnHide", function() charState().setupDone = true end)
  -- live status (keybind, channel join) while open
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 0.5 then acc = 0; U:refresh() end
  end)
  f:Hide()
  self.frame = f
  return f
end

function U:refresh()
  local f = self.frame
  if not f or not f:IsShown() then return end
  local pages = self:currentPages()
  for _, pg in pairs(self.pages) do pg.frame:Hide() end
  local cur = pages[self.page]
  cur.frame:Show()
  if cur.refresh then cur.refresh() end
  f.steps:SetText(string.format("SummonSirForever setup   step %d of %d", self.page, #pages))
  f.back:SetShown(self.page > 1)
  f.skip:SetShown(self.page < #pages)
  f.next:SetText(self.page == #pages and "Finish" or "Next")
end

function U:go(n)
  self.page = math.max(1, math.min(n, #self:currentPages()))
  self:refresh()
end

function U:open()
  if InCombatLockdown() then W.print("setup will open after combat") return end
  self:build()
  self.role = W.role()
  self.page = 1
  self.frame:Show()
  self:refresh()
end

function U:finish()
  charState().setupDone = true
  if self.frame then self.frame:Hide() end
  W.fire("ROLE_CHANGED", W.role())
  W.print("setup done. /sw options for every setting, /sw setup to run it again.")
end

W.module("setup", U)

function U:init()
  W.command("setup", "setup: run the one-time setup again", function() U:open() end)
  W.on("WARLOCK_READY", function()
    if U:needed() then
      C_Timer.After(4, function()
        if U:needed() and not InCombatLockdown() then U:open() end
      end)
    end
  end)
end

addonData.setup = U
