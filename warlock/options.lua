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
  if W.parseMoney(val) then return true end
  return "Use an amount like 80s, 1g or 1g50s"
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

function O:build()
  local dv, dorder = destValues()
  return {
    name = "Summon service",
    type = "group",
    args = {
      intro = {
        order = 0, type = "description", fontSize = "medium",
        name = "Settings for running a summon service. The same settings are also slash commands: type /sw in chat for the list.",
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
            desc = "Per summon, e.g. 80s, 1g, 1g50s",
            validate = moneyValidate,
            get = function() return W.fmtMoney(db().price) end,
            set = function(_, v) db().price = W.parseMoney(v); changed() end,
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
              db().prices[d] = (v ~= "" and W.parseMoney(v) or nil)
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
        order = 30, type = "group", inline = true, name = "Customer whispers",
        args = {
          service = {
            order = 1, type = "toggle", name = "Auto-reply and invite", width = "full",
            desc = "Warlock role: anyone who whispers a request gets the reply below once and an invite. They join the queue as soon as they're in the group.",
            get = function() return db().service end,
            set = function(_, v) db().service = v; changed() end,
          },
          replyText = {
            order = 2, type = "input", name = "Reply to new customers", width = "full",
            get = function() return db().replyText end,
            set = function(_, v) db().replyText = v; changed() end,
          },
          wrongDestText = {
            order = 3, type = "input", name = "Reply when they ask for a different place", width = "full",
            get = function() return db().wrongDestText end,
            set = function(_, v) db().wrongDestText = v; changed() end,
          },
          advertiserReplyText = {
            order = 4, type = "input", name = "Advertiser's reply (points them at the warlock)", width = "full",
            get = function() return db().advertiserReplyText end,
            set = function(_, v) db().advertiserReplyText = v; changed() end,
          },
          whisperHelp = {
            order = 5, type = "description",
            name = placeholders("{dest} {price} {lock} {asked}. Each person gets each reply at most once every 10 minutes. Only people who whispered you get a reply."),
          },
        },
      },

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
          adChannel = {
            order = 1, type = "input", name = "Ad channel", width = "normal",
            desc = "Name or start of the name, e.g. Services. You have to have joined it.",
            get = function() return db().adChannel end,
            set = function(_, v) if v ~= "" then db().adChannel = v; changed() end end,
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
            order = 4, type = "input", name = "Warlock name in ads (advertiser)", width = "normal",
            desc = "Set automatically while you're grouped with the warlock.",
            get = function() return db().lockName or "" end,
            set = function(_, v) db().lockName = (v ~= "" and v or nil); changed() end,
          },
          adPreview = {
            order = 5, type = "description",
            name = function()
              local _, chan = W.ads:channel()
              return placeholders("{dest} {price} {lock}") .. "\n" .. W.hex("purple", "Preview: ") .. W.ads:text()
                .. "\n" .. (chan and W.hex("green", "Channel joined: " .. chan)
                  or W.hex("orange", "Not in a channel called " .. db().adChannel .. " yet"))
                .. "\n" .. W.hex("comment", "Ads only go out when you click Ad or Post ad.")
            end,
          },
        },
      },

      ---------------------------------------------------------------- clicker alert
      clickGroup = {
        order = 60, type = "group", inline = true, name = "Clicker alert",
        args = {
          sound = {
            order = 1, type = "toggle", name = "Play a sound",
            get = function() return db().alertSound end,
            set = function(_, v) db().alertSound = v end,
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
                .. " Bind it in Key Bindings > Targeting, and run /console SoftTargetInteract 3."
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
