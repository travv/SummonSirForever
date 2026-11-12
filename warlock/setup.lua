-- One-time setup for new users: pick a role, set up that role, done.
-- Shows once per character on first login; /ssf setup brings it back.
-- Each page teaches one thing and shows whether it worked (green / orange).
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local U = { pageFrame = nil, page = 1, pages = {}, role = nil, opened = false }

local ROLE_INFO = {
  warlock = { label = "Warlock", desc = "You cast the summons. People who whisper you get a reply, an invite and a place in line; every payment is tracked in the ledger." },
  clicker = { label = "Clicker", desc = "You help click the portal. A big PORTAL UP banner tells you when to press your Interact key." },
  advertiser = { label = "Advertiser", desc = "You post the ad in a city. One click per ad round; people who whisper you get pointed at the warlock (or invited, when you have assist)." },
}
local ROLE_ORDER = { "warlock", "clicker", "advertiser" }
local NEXT_BINDING = "CLICK SteaSummonButton38:LeftButton"
local BIND_PATH_INTERACT = "Key Bindings > Targeting > Interact With Target"
local BIND_PATH_NEXT = "Key Bindings > AddOns > SummonSirForever > Summon Next"

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

-- saves on Enter or when you click away (not on every keystroke, so a
-- half-typed price never gets saved or broadcast); onPreview runs live
local function editBox(parent, x, y, width, onCommit, onPreview)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(width or 160, 20)
  e:SetPoint("TOPLEFT", x + 6, y)
  e:SetAutoFocus(false)
  e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  e:SetScript("OnEditFocusLost", function(self) onCommit(self:GetText()) end)
  if onPreview then
    e:SetScript("OnTextChanged", function(self, user) if user then onPreview(self:GetText()) end end)
  end
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

-- "Bound to F" in green, or an orange hint with the menu path
local function bindingStatus(binding, path)
  local key = GetBindingKey(binding)
  if key and key ~= "" then return W.hex("green", "Bound to " .. key) end
  return W.hex("orange", "Not bound yet. " .. path .. ". This line updates when you're done.")
end

---------------------------------------------------------------- pages
-- each page: { frame, refresh = function() } built once

local function pageRole(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  local t = text(p, "GameFontNormalHuge", "purple", 0, 0)
  t:SetText("Welcome, sir!")
  local intro = text(p, "GameFontHighlight", "fg", 0, -34, 430)
  intro:SetText("SummonSirForever runs a warlock summon service. Each window (warlock, clickers, advertiser) runs this once. Pick what this window does:")
  intro:SetSpacing(2)
  local btns = {}
  for i, role in ipairs(ROLE_ORDER) do
    local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    b:SetSize(136, 40)
    b:SetPoint("TOPLEFT", (i - 1) * 148, -84)
    b:SetNormalFontObject("GameFontNormalLarge")
    b:SetHighlightFontObject("GameFontHighlightLarge")
    b:SetText(ROLE_INFO[role].label)
    b:SetScript("OnClick", function()
      U.role = role
      W.setRole(role)
      U:go(2) -- straight on to that role's page
    end)
    b:SetScript("OnEnter", function(this)
      GameTooltip:SetOwner(this, "ANCHOR_BOTTOM")
      GameTooltip:AddLine(ROLE_INFO[role].label)
      GameTooltip:AddLine(ROLE_INFO[role].desc, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    btns[role] = b
  end
  local desc = text(p, "GameFontHighlight", "fg", 0, -140, 430)
  desc:SetSpacing(2)
  return { frame = p, refresh = function()
    for role, b in pairs(btns) do
      if role == U.role then b:LockHighlight() else b:UnlockHighlight() end
    end
    desc:SetText(W.hex("comment", "This window is set up as: ") .. W.hex("purple", ROLE_INFO[U.role].label) .. "\n"
      .. ROLE_INFO[U.role].desc .. "\n\n" .. W.hex("comment", "Click a role to continue. You can change it later with /ssf role."))
  end }
end

local function pageWarlock(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalLarge", "purple", 0, 0):SetText("Warlock setup")

  text(p, "GameFontNormal", "cyan", 0, -30):SetText("1. Where do you summon to?")
  local destOut = text(p, "GameFontHighlight", "fg", 190, -50, 240)
  local dest = editBox(p, 0, -46, 170, function(v)
    local m = v ~= "" and W.destinations.match(v)
    W.db.dest = m and m.key or nil
    W.fire("CONFIG_CHANGED")
    U:refresh()
  end)

  text(p, "GameFontNormal", "cyan", 0, -76):SetText("2. Price per summon")
  local priceOut = text(p, "GameFontHighlight", "fg", 190, -96, 240)
  local price = editBox(p, 0, -92, 80, function(v)
    local c = W.parseMoneyUser(v)
    if c then W.db.price = c; W.fire("CONFIG_CHANGED") end
    U:refresh()
  end, function(v)
    local c = W.parseMoneyUser(v)
    priceOut:SetText(c and W.hex("green", W.fmtMoney(c)) or W.hex("orange", "use 1g, 80s, 1g50s, or just 1"))
  end)

  text(p, "GameFontNormal", "cyan", 0, -122):SetText("3. Bind your Summon Next key")
  local keyOut = text(p, "GameFontHighlight", "fg", 0, -142, 430)

  local svc = checkBox(p, 0, -170, "Auto-reply and invite people who whisper you",
    function() return W.db.service end, function(v) W.db.service = v end)
  local plain = checkBox(p, 0, -194, "Plain messages (skip the \"sir\" flavor)",
    function() return W.db.plainMode end, function(v) W.db.plainMode = v; U:refresh() end)
  local remind = checkBox(p, 0, -218, "Whisper a payment reminder when they arrive (off: they know to trade you)",
    function() return W.messages:setting("complete").mode ~= "off" end,
    function(v) W.messages:setting("complete").mode = v and "random" or "off"; W.fire("CONFIG_CHANGED") end)
  local sample = text(p, "GameFontHighlightSmall", "comment", 0, -248, 430)

  return { frame = p, refresh = function()
    local cur = W.destinations.byKey(W.db.dest)
    if not dest:HasFocus() then dest:SetText(cur and cur.name or "") end
    destOut:SetText(cur and W.hex("green", "-> " .. cur.name)
      or W.hex("comment", "blank = wherever you stand (" .. W.destName() .. ")"))
    if not price:HasFocus() then
      price:SetText(W.fmtMoney(W.db.price))
      priceOut:SetText(W.hex("green", W.fmtMoney(W.db.price)) .. W.hex("comment", " per summon"))
    end
    keyOut:SetText(bindingStatus(NEXT_BINDING, BIND_PATH_NEXT))
    svc.refresh(); plain.refresh(); remind.refresh()
    local saved = W.messages.last.queued
    local reply = W.messages:text("queued")
    sample:SetText(reply and ("First reply: " .. W.hex("fg", reply))
      or (W.hex("fg", "No first reply: ") .. "the invite is the notification, and your ad quotes the price. Turn a reply on under Options > Messages."))
    W.messages.last.queued = saved
  end }
end

local function pageClicker(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalLarge", "purple", 0, 0):SetText("Clicker setup")

  text(p, "GameFontNormal", "cyan", 0, -30):SetText("1. Let the Interact key reach the portal")
  local cvarOut = text(p, "GameFontHighlight", "fg", 0, -50, 300)
  local cvarBtn = button(p, "Turn it on", 110, function()
    pcall(C_CVar.SetCVar, "SoftTargetInteract", "3")
    U:refresh()
  end)
  cvarBtn:SetPoint("TOPLEFT", 310, -46)

  text(p, "GameFontNormal", "cyan", 0, -76):SetText("2. Bind \"Interact With Target\"")
  local keyOut = text(p, "GameFontHighlight", "fg", 0, -96, 430)

  text(p, "GameFontNormal", "cyan", 0, -130):SetText("3. Hear the alert while this window is in the background")
  local sndOut = text(p, "GameFontHighlight", "fg", 0, -150, 300)
  local sndBtn = button(p, "Turn it on", 110, function()
    pcall(C_CVar.SetCVar, "Sound_EnableSoundWhenGameIsInactive", "1")
    U:refresh()
  end)
  sndBtn:SetPoint("TOPLEFT", 310, -146)

  text(p, "GameFontNormal", "cyan", 0, -176):SetText("4. Check the alert")
  local test = button(p, "Show the banner", 130, function() W.commands.testportal("") end)
  test:SetPoint("TOPLEFT", 0, -196)
  local snd = checkBox(p, 150, -195, "Play a sound", function() return W.db.alertSound end,
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
    keyOut:SetText(bindingStatus("INTERACTTARGET", BIND_PATH_INTERACT))
    local s = C_CVar.GetCVar("Sound_EnableSoundWhenGameIsInactive")
    if s == "1" then
      sndOut:SetText(W.hex("green", "On: sound plays even when another window has focus"))
      sndBtn:Hide()
    else
      sndOut:SetText(W.hex("orange", "Off: silent while another window has focus"))
      sndBtn:Show()
    end
    snd.refresh()
  end }
end

local function pageAdvertiser(parent)
  local p = CreateFrame("Frame", nil, parent)
  p:SetAllPoints()
  text(p, "GameFontNormalLarge", "purple", 0, 0):SetText("Advertiser setup")

  text(p, "GameFontNormal", "cyan", 0, -30):SetText("1. Post the ad to these channels")
  local picker = W.ads:buildPicker(p, 0, -50, 2, 215)
  text(p, "GameFontHighlightSmall", "comment", 0, -146, 430):SetText(
    "Only channels this character has joined are listed. Missing one? /join Services in chat and it shows up here.")

  text(p, "GameFontNormal", "cyan", 0, -176):SetText("2. Main warlock's name")
  local lockOut = text(p, "GameFontHighlightSmall", "comment", 190, -198, 250)
  local lock = editBox(p, 0, -192, 170, function(v)
    W.db.lockName = v ~= "" and v or nil
    W.fire("CONFIG_CHANGED")
    U:refresh()
  end)
  local preview = text(p, "GameFontHighlightSmall", "comment", 0, -236, 430)

  return { frame = p, refresh = function()
    picker.refresh()
    if not lock:HasFocus() then lock:SetText(W.db.lockName or "") end
    local age = W.db.remoteAt and (W.now() - W.db.remoteAt)
    lockOut:SetText((age and age < 120) and W.hex("green", "synced: " .. W.destName() .. ", " .. W.fmtMoney(W.priceFor(W.destKey())))
      or W.hex("orange", "Not synced yet. Group with them, or type their name."))
    preview:SetText("Your ad: " .. W.hex("fg", W.ads:text()) .. "\n\n"
      .. W.hex("comment", "The ad follows the main warlock's destination and price, and the middle sentence changes with the destination. The Ads tab has the Post ad button: one click posts once to each checked channel."))
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
      table.insert(lines, "Summoning to " .. W.destName() .. " for " .. W.fmtMoney(W.priceFor(W.destKey())) .. ".")
      local key = GetBindingKey(NEXT_BINDING)
      table.insert(lines, "Summon the next person with " .. (key and (W.hex("yellow", key) .. ", ") or "your Summon Next key, ")
        .. "the Next button on the summon window, or the big Summon Next button.")
      table.insert(lines, "Right-click a name in the queue to move, remove, block or whisper them.")
      table.insert(lines, W.hex("cyan", "/ssf") .. " opens the ledger.")
    elseif U.role == "clicker" then
      table.insert(lines, "When the banner says PORTAL UP, press your Interact key.")
    else
      table.insert(lines, "Click Post ad for each ad round. The button counts down until the next one.")
    end
    table.insert(lines, W.hex("cyan", "/ssf options") .. " has every setting, " .. W.hex("cyan", "/ssf help") .. " lists the commands, "
      .. W.hex("cyan", "/ssf setup") .. " runs this again.")
    b:SetText(table.concat(lines, "\n"))
  end }
end

---------------------------------------------------------------- frame

function U:currentPages()
  local rolePage = (U.role == "clicker" and self.pages.clicker)
    or (U.role == "advertiser" and self.pages.advertiser) or self.pages.warlock
  return { self.pages.role, rolePage, self.pages.done }
end

-- the Setup tab: a page inside the summon window (warlock/tabs.lua)
function U:buildInto(parent)
  if self.pageFrame then return self.pageFrame end
  local f = CreateFrame("Frame", "SummonSirSetupPage", parent)
  f:SetAllPoints(parent)
  f:Hide()
  -- the inset frames the current step; Back / Next sit below it
  f.inset = CreateFrame("Frame", nil, f, "InsetFrameTemplate")
  f.inset:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -48)
  f.inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 44)

  f.steps = text(f, "GameFontNormalSmall", "comment", 62, -30) -- right of the portrait circle

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", 24, -62)
  content:SetPoint("BOTTOMRIGHT", -24, 56)
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

  -- leaving the page early (another tab, Escape, the X) counts as done:
  -- the Setup tab or /ssf setup brings it back any time
  f:SetScript("OnHide", function()
    if U.opened then charState().setupDone = true end
    U.opened = false
  end)
  -- live status (keybinds, cvars, channel joins) while open
  local acc = 0
  f:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc > 0.5 then acc = 0; U:refresh() end
  end)
  self.pageFrame = f
  return f
end

function U:refresh()
  local f = self.pageFrame
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
  self.role = W.role()
  self.page = 1
  self.opened = true
  if addonData.tabs and addonData.tabs.show then addonData.tabs:show("setup") end -- creates the window and this page
  if not self.pageFrame then self:buildInto(SteaSummonFrame or UIParent) end
  self:refresh()
end

function U:finish()
  charState().setupDone = true
  self.opened = false
  if addonData.tabs and addonData.tabs.built then addonData.tabs:select("queue") end
  W.fire("ROLE_CHANGED", W.role())
  W.print("setup done. /ssf options for every setting, /ssf help for the commands, /ssf setup to run this again.")
end

W.module("setup", U)

function U:init()
  W.command("setup", "setup: run the one-time setup again", function() U:open() end)
  -- PLAYER_LOGIN, not ADDON_LOADED: by then the character's full two-word
  -- name is known, so the per-character flag lands under the right key
  W.on("PLAYER_LOGIN", function()
    if U:needed() then
      C_Timer.After(4, function()
        if U:needed() and not InCombatLockdown() then U:open() end
      end)
    end
  end)
end

addonData.setup = U
