-- "Summon service" page in Settings > AddOns > SummonSirForever: every /sw
-- setting as a GUI. Registered from optionsgui:init so it nests under the
-- addon's own category. Getters read the saved data lazily.
-- Copyright (c) 2026 travv. MIT licensed.

local _, addonData = ...
local W = addonData.W

local O = { categoryID = nil }

local function db() return W.db end
local function changed() W.fire("CONFIG_CHANGED") end

local function moneyValidate(_, val)
  if W.parseMoneyUser(val) then return true end
  return "Use an amount like 1g, 80s, 1g50s, or just 1 (gold)"
end

-- destination dropdown: "" = your current zone, then presets A-Z
local function destValues()
  local values, order = { [""] = "(your current zone)" }, { "" }
  local presets = {}
  for _, p in ipairs(addonData.destinations.PRESETS) do table.insert(presets, p) end
  table.sort(presets, function(a, b) return a.name < b.name end)
  for _, p in ipairs(presets) do
    values[p.key] = p.name
    table.insert(order, p.key)
  end
  return values, order
end

local function blockedValues()
  local out = {}
  if not db() then return out end
  local now = W.now()
  for _, e in ipairs(W.blocklist:list(now)) do
    out[e.name] = e.name .. "  (" .. W.blocklist.left(e.untilT - now) .. ", " .. e.reason .. ")"
  end
  return out
end

local function placeholders(list)
  return W.hex("comment", "Filled in for you: " .. list)
end

-- one block per message type: mode dropdown, custom text, live sample
function O:messagesGroup(order)
  local M = W.messages
  local args = {
    plain = {
      order = 0, type = "toggle", name = "Plain mode", width = "full",
      desc = "Short, serious messages instead of the SummonSir lines, for when you're in a hurry. Custom texts still win.",
      get = function() return db().plainMode end,
      set = function(_, v) db().plainMode = v; changed() end,
    },
    help = {
      order = 1, type = "description",
      name = placeholders("{dest} {price} {lock} {asked} {pos} {ahead}. Random picks a different line each time. Each person gets each message at most once every few minutes."),
    },
  }
  for i, kind in ipairs(M.ORDER) do
    local t = M.TYPES[kind]
    local modes, sorting = { random = "Random line" }, { "random" }
    for n = 1, #t.lines do
      modes["fixed" .. n] = "Line " .. n .. ": " .. string.sub(t.lines[n], 1, 40) .. "..."
      table.insert(sorting, "fixed" .. n)
    end
    modes.custom, modes.off = "Custom text", "Off"
    table.insert(sorting, "custom"); table.insert(sorting, "off")
    local base = i * 10
    args[kind .. "Mode"] = {
      order = base, type = "select", name = t.label, width = "double",
      values = modes, sorting = sorting,
      get = function()
        local st = M:setting(kind)
        if st.mode == "fixed" then return "fixed" .. (st.line or 1) end
        return st.mode
      end,
      set = function(_, v)
        local st = M:setting(kind)
        local n = string.match(v, "^fixed(%d+)$")
        if n then st.mode, st.line = "fixed", tonumber(n) else st.mode = v end
        changed()
      end,
    }
    args[kind .. "Custom"] = {
      order = base + 1, type = "input", name = "Custom text", width = "full",
      hidden = function() return M:setting(kind).mode ~= "custom" end,
      get = function() return M:setting(kind).custom or "" end,
      set = function(_, v) M:setting(kind).custom = v; changed() end,
    }
    args[kind .. "Sample"] = {
      order = base + 2, type = "description",
      name = function()
        local st = M:setting(kind)
        if st.mode == "off" then return W.hex("comment", "(off)") end
        local saved = M.last[kind]
        local txt = M:text(kind, { pos = 3, ahead = 2, asked = "Orgrimmar" })
        M.last[kind] = saved
        return W.hex("comment", "e.g. ") .. (txt or "")
      end,
    }
  end
  return { order = order, type = "group", inline = true, name = "Messages", args = args }
end

function O:build()
  local dv, dorder = destValues()
  return {
    name = "Summon service",
    type = "group",
    args = {
      intro = {
        order = 0, type = "description", fontSize = "medium",
        name = "Settings for running a summon service. The same settings are also slash commands: type /sw help in chat for the list (bare /sw opens the ledger).",
      },
      rerunSetup = {
        order = 1, type = "execute", name = "Run setup again",
        desc = "The one-time setup walkthrough (/sw setup).",
        func = function() W.setup:open() end,
      },

      ---------------------------------------------------------------- role
      roleGroup = {
        order = 10, type = "group", inline = true, name = "This window",
        args = {
          role = {
            order = 1, type = "select", name = "Role", width = "normal",
            values = { warlock = "Warlock", clicker = "Clicker", advertiser = "Advertiser" },
            sorting = { "warlock", "clicker", "advertiser" },
            get = function() return W.role() end,
            set = function(_, v) W.setRole(v) end,
          },
          roleHelp = {
            order = 2, type = "description",
            name = "Warlock: replies to customers, invites them, queues them and keeps the ledger.\n"
              .. "Clicker: shows a big alert when the portal is up.\n"
              .. "Advertiser: shows a Post ad button for the ad channel.\n"
              .. W.hex("comment", "Saved per character."),
          },
        },
      },

      ---------------------------------------------------------------- summon window
      windowGroup = {
        order = 12, type = "group", inline = true, name = "Summon window",
        args = {
          show = {
            order = 1, type = "select", name = "Show the window", width = "double",
            desc = "The warlock's window holds AFK, Ad, Ledger and Menu, so \"always\" is the default there. Escape or the X hides it until the Menu or minimap button brings it back.",
            values = { [1] = "Always", [2] = "Only while someone is in line", [3] = "Only while I am in line", [4] = "Never" },
            sorting = { 1, 2, 3, 4 },
            get = function() return SteaSummonSave and SteaSummonSave.show or 1 end,
            set = function(_, v)
              SteaSummonSave.show = v
              if addonData.summon then addonData.summon.show = nil; addonData.summon:showSummons() end
            end,
          },
          listSize = {
            order = 2, type = "range", name = "Queue row size", min = 0.7, max = 1.5, step = 0.05, isPercent = true,
            desc = "Scale of the names in the queue. Widen the window if the time column clips.",
            get = function() return SteaSummonSave and SteaSummonSave.listSize or 1 end,
            set = function(_, v)
              SteaSummonSave.listSize = v
              if SteaSummonButtonFrame then SteaSummonButtonFrame:SetScale(v) end
            end,
          },
        },
      },

      ---------------------------------------------------------------- big button
      bigGroup = {
        order = 15, type = "group", inline = true, name = "Big Summon Next button (warlock)",
        args = {
          show = {
            order = 1, type = "toggle", name = "Show it",
            desc = "A big button that does exactly what your Summon Next keybind does. Drag its top strip to move it.",
            get = function() return db().bigButton ~= false end,
            set = function(_, v) db().bigButton = v; changed() end,
          },
          scale = {
            order = 2, type = "range", name = "Size", min = 0.6, max = 2, step = 0.05, isPercent = true,
            get = function() return db().bigScale or 1 end,
            set = function(_, v) db().bigScale = v; changed() end,
          },
          reset = {
            order = 3, type = "execute", name = "Reset position",
            func = function() W.commands.big("reset") end,
          },
        },
      },

      ---------------------------------------------------------------- destination + price
      destGroup = {
        order = 20, type = "group", inline = true, name = "Destination and price",
        args = {
          dest = {
            order = 1, type = "select", name = "Summoning to", width = "normal",
            desc = "Used in your replies and ads. Requests for a different place get a polite no.",
            values = dv, sorting = dorder,
            get = function() return db().dest or "" end,
            set = function(_, v) db().dest = (v ~= "" and v or nil); changed() end,
          },
          price = {
            order = 2, type = "input", name = "Default price", width = "half",
            desc = "Per summon: 1g, 80s, 1g50s, or just a number for gold.",
            validate = moneyValidate,
            get = function() return W.fmtMoney(db().price) end,
            set = function(_, v) db().price = W.parseMoneyUser(v); changed() end,
          },
          destPrice = {
            order = 3, type = "input", name = "Price for this destination", width = "normal",
            desc = "Overrides the default price for the destination picked above. Leave empty to use the default.",
            disabled = function() return not db().dest end,
            validate = function(info, v) if v == "" then return true end return moneyValidate(info, v) end,
            get = function()
              local d = db().dest
              return (d and db().prices[d]) and W.fmtMoney(db().prices[d]) or ""
            end,
            set = function(_, v)
              local d = db().dest
              if not d then return end
              db().prices[d] = (v ~= "" and W.parseMoneyUser(v) or nil)
              changed()
            end,
          },
          overrides = {
            order = 4, type = "description",
            name = function()
              local parts = {}
              for key, copper in pairs(db().prices) do
                local p = addonData.destinations.byKey(key)
                table.insert(parts, (p and p.name or key) .. " " .. W.fmtMoney(copper))
              end
              table.sort(parts)
              if #parts == 0 then return W.hex("comment", "No per-destination prices set.") end
              return W.hex("comment", "Per-destination prices: ") .. table.concat(parts, ", ")
            end,
          },
          clearOverrides = {
            order = 5, type = "execute", name = "Clear per-destination prices",
            hidden = function() return next(db().prices) == nil end,
            func = function() db().prices = {}; changed() end,
          },
        },
      },

      ---------------------------------------------------------------- whispers
      whisperGroup = {
        order = 30, type = "group", inline = true, name = "Customers",
        args = {
          service = {
            order = 1, type = "toggle", name = "Auto-reply and invite", width = "full",
            desc = "Warlock role: anyone who whispers a request gets the first reply and an invite, and joins the queue once they're in the group.",
            get = function() return db().service end,
            set = function(_, v) db().service = v; changed() end,
          },
          maxQueue = {
            order = 2, type = "range", name = "Queue cap (0 = none)", min = 0, max = 39, step = 1,
            desc = "New customers get the \"queue is full\" reply past this many waiting or invited. A raid holds 40.",
            get = function() return db().maxQueue end,
            set = function(_, v) db().maxQueue = v; changed() end,
          },
        },
      },

      messagesGroup = O:messagesGroup(31),

      ---------------------------------------------------------------- payments + blocklist
      payGroup = {
        order = 40, type = "group", inline = true, name = "Payments and blocklist",
        args = {
          grace = {
            order = 1, type = "range", name = "Never paid after (minutes)", min = 1, max = 60, step = 1,
            desc = "How long after arriving before an unpaid customer counts as never paid.",
            get = function() return db().graceMinutes end,
            set = function(_, v) db().graceMinutes = v; changed() end,
          },
          offlineMinutes = {
            order = 1.5, type = "range", name = "Drop offline customers after (minutes)", min = 0, max = 60, step = 1,
            desc = "A queued customer who stays logged off this long leaves the queue. 0 keeps them. Leaving the group always drops them.",
            get = function() return db().offlineMinutes or 0 end,
            set = function(_, v) db().offlineMinutes = v; changed() end,
          },
          autoBlock = {
            order = 2, type = "toggle", name = "Auto-block never-paid customers",
            desc = "Paying later lifts the block automatically.",
            get = function() return db().autoBlock end,
            set = function(_, v) db().autoBlock = v; changed() end,
          },
          blockHours = {
            order = 3, type = "range", name = "Block length (hours)", min = 1, max = 168, step = 1,
            desc = "Used for auto-blocks, the Block button and names added below.",
            get = function() return db().autoBlockHours end,
            set = function(_, v) db().autoBlockHours = v; changed() end,
          },
          blockName = {
            order = 4, type = "input", name = "Block a player", width = "normal",
            desc = "Type the full name (e.g. Summ Bert) and press Enter.",
            get = function() return "" end,
            set = function(_, v)
              if v and v ~= "" then
                W.blocklist:add(v, db().autoBlockHours * 3600, "manual")
                W.print("blocked", v)
                changed()
              end
            end,
          },
          unblock = {
            order = 5, type = "select", name = "Unblock a player", width = "double",
            values = blockedValues,
            disabled = function() return next(blockedValues()) == nil end,
            get = function() return nil end,
            set = function(_, v) W.blocklist:remove(v); W.print("unblocked", v); changed() end,
          },
          paidName = {
            order = 6, type = "input", name = "Mark a summon paid by hand", width = "normal",
            desc = "For mail or a friend paying. Counts that summon's price.",
            get = function() return "" end,
            set = function(_, v)
              local s = v ~= "" and W.ledger:markPaid(v)
              W.print(s and ("marked paid: " .. s.name) or ("no unpaid summon for " .. tostring(v)))
            end,
          },
          openLedger = {
            order = 7, type = "execute", name = "Open ledger panel",
            func = function() W.panel:toggle() end,
          },
        },
      },

      ---------------------------------------------------------------- ads
      adGroup = {
        order = 50, type = "group", inline = true, name = "Ads",
        args = {
          adChannels = {
            order = 1, type = "input", name = "Ad channels", width = "normal",
            desc = "Your chat channel numbers (1, 2, 8) or names (General, Trade, Services), comma separated. One click posts the ad once to each one you've joined.",
            get = function() return db().adChannels end,
            set = function(_, v) if v ~= "" then db().adChannels = v; changed() end end,
          },
          adCooldown = {
            order = 2, type = "range", name = "Minutes between ads", min = 1, max = 30, step = 1,
            get = function() return SteaSummonSave and SteaSummonSave.adCooldown or 5 end,
            set = function(_, v) SteaSummonSave.adCooldown = v; changed() end,
          },
          adTemplate = {
            order = 3, type = "input", name = "Ad text", width = "full",
            get = function() return db().adTemplate end,
            set = function(_, v) if v ~= "" then db().adTemplate = v; changed() end end,
          },
          lockName = {
            order = 4, type = "input", name = "Main warlock's name (advertiser)", width = "normal",
            desc = "Fills in by itself from the warlock's addon. Typing it lets the advertiser sync by whisper even when you're not grouped.",
            get = function() return db().lockName or "" end,
            set = function(_, v) db().lockName = (v ~= "" and v or nil); changed() end,
          },
          adPreview = {
            order = 5, type = "description",
            name = function()
              local sync = ""
              if W.role() == "advertiser" then
                local age = db().remoteAt and (W.now() - db().remoteAt)
                sync = "\n" .. ((age and age < 120)
                  and W.hex("green", "Synced with " .. tostring(db().lockName) .. ": " .. W.destName() .. ", " .. W.fmtMoney(W.priceFor(W.destKey())))
                  or W.hex("orange", "Not synced with the main warlock yet. Group with them, or type their name above."))
              end
              return placeholders("{dest} {price} {lock} {spell} (the [Ritual of Summoning] link)")
                .. "\n" .. W.hex("purple", "Preview: ") .. W.ads:text()
                .. "\n" .. "Posts to: " .. W.ads:channelSummary() .. sync
                .. "\n" .. W.hex("comment", "Ads only go out when you click Ad or Post ad: one click, once per channel.")
            end,
          },
        },
      },

      ---------------------------------------------------------------- clicker alert
      clickGroup = {
        order = 60, type = "group", inline = true, name = "Alerts and sounds",
        args = {
          sound = {
            order = 1, type = "toggle", name = "PORTAL UP sound (clicker)",
            desc = "Plays with the banner when the warlock starts a summon.",
            get = function() return db().alertSound end,
            set = function(_, v) db().alertSound = v end,
          },
          soundJoin = {
            order = 1.1, type = "toggle", name = "Ping when someone joins the queue (warlock)",
            get = function() return db().soundJoin ~= false end,
            set = function(_, v) db().soundJoin = v end,
          },
          soundPaid = {
            order = 1.2, type = "toggle", name = "Coin sound when a payment lands",
            get = function() return db().soundPaid ~= false end,
            set = function(_, v) db().soundPaid = v end,
          },
          background = {
            order = 1.5, type = "toggle", name = "Hear it in the background", width = "full",
            desc = "Game setting: play sound while another window has focus. Clicker windows streamed from the VM are never the focused window, so without this the alert is silent.",
            get = function() return C_CVar.GetCVar("Sound_EnableSoundWhenGameIsInactive") == "1" end,
            set = function(_, v) pcall(C_CVar.SetCVar, "Sound_EnableSoundWhenGameIsInactive", v and "1" or "0") end,
          },
          test = {
            order = 2, type = "execute", name = "Test the banner",
            func = function() W.commands.testportal("") end,
          },
          keyInfo = {
            order = 3, type = "description",
            name = function()
              local key = GetBindingKey("INTERACTTARGET")
              if key then return "Interact With Target is bound to " .. W.hex("yellow", key) .. "." end
              return W.hex("red", "Interact With Target is not bound.")
                .. " Bind it under Key Bindings > Targeting > Interact With Target, and turn on soft interact (the clicker page of /sw setup does both checks)."
            end,
          },
        },
      },

      ---------------------------------------------------------------- data
      dataGroup = {
        order = 70, type = "group", inline = true, name = "Ledger data",
        args = {
          counts = {
            order = 1, type = "description",
            name = function()
              return string.format("%d summons and %d payments recorded on this account.",
                #db().summons, #db().payments)
            end,
          },
          reset = {
            order = 2, type = "execute", name = "Erase ledger history",
            confirm = true, confirmText = "Erase every recorded summon and payment? This can't be undone.",
            func = function()
              db().summons, db().payments = {}, {}
              W.fire("LEDGER_CHANGED")
              W.print("ledger history erased")
            end,
          },
        },
      },
    },
  }
end

W.module("options", O)

-- called from optionsgui:init with the parent category name
function O:register(parentName)
  -- the table is registered on its own first, so the standalone window works
  -- even if the Settings page can't be added
  local ok, err = pcall(function()
    LibStub("AceConfig-3.0"):RegisterOptionsTable("SummonSirService", function() return O:build() end)
  end)
  if not ok then W.print("options failed:", err) return end
  ok, err = pcall(function()
    local _, id = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("SummonSirService", "Summon service", parentName)
    O.categoryID = id
  end)
  if not ok then W.print("Settings page not added (use /sw options for the window):", err) end
end

-- standalone AceConfig window: works even if the Settings panel can't be opened
function O:openWindow()
  local ok, err = pcall(function() LibStub("AceConfigDialog-3.0"):Open("SummonSirService") end)
  if not ok then W.print("options window failed:", err) end
  return ok
end

-- Settings > AddOns page first; if it did not actually appear by the next
-- frame, fall back to the standalone window. onDone(true) once something opened.
function O:open(onDone)
  if InCombatLockdown() then W.print("options can't open in combat") return end
  local tried = false
  if O.categoryID and Settings and Settings.OpenToCategory then
    tried = pcall(Settings.OpenToCategory, O.categoryID)
  end
  C_Timer.After(0, function()
    local shown = tried and SettingsPanel and SettingsPanel:IsShown()
    if not shown then shown = O:openWindow() end
    if onDone then onDone(shown) end
  end)
end

function O:init()
  W.on("CONFIG_CHANGED", function()
    pcall(function() LibStub("AceConfigRegistry-3.0"):NotifyChange("SummonSirService") end)
  end)
  W.command("options", "options: open the Summon service settings page", function() O:open() end)
end

addonData.serviceOptions = O
