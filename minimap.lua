local addonName, addonData = ...
local L = LibStub("AceLocale-3.0"):GetLocale("SummonSirForever")
local icon = LibStub("LibDBIcon-1.0")

local appbutton = {
  icon = icon,
}

function appbutton:toggleMenu()
  self:toggle()
end

function appbutton:menu(button)
    if button == "LeftButton" then
        addonData.summon.showSummonsToggle()
        return
    end
        
  local me = addonData.util:playerFullName()

  local menu = {
    { text = L["Show/Hide Summon Window"], notCheckable = true,
      icon = "Interface/ICONS/Spell_Shadow_Twilight", func = addonData.summon.showSummonsToggle },
  }
  if addonData.summon:findWaitingPlayer(me) then
    table.insert(menu, { text = L["Reset Summon"], notCheckable = true,
                         icon = "Interface\\RAIDFRAME\\ReadyCheck-Ready", func = addonData.summon.resetMe })
    table.insert(menu, { text = L["Cancel Summon"], notCheckable = true,
                         icon = "Interface\\RAIDFRAME\\ReadyCheck-NotReady", func = addonData.summon.cancelMe })
  else
    if IsInGroup(LE_PARTY_CATEGORY_HOME) then
      table.insert(menu, { text = L["Request Summon"], notCheckable = true,
                           icon = "Interface\\RAIDFRAME\\ReadyCheck-Ready", func = addonData.summon.addMe })
    end
  end
  if addonData.util.playerCanSummon() then
    local submenu = { text = L["Manage List"], notCheckable = true, hasArrow = true, menuList = {}}
    table.insert(submenu.menuList, { text = L["Set/Unset Destination"], notCheckable = true,
                            icon = "Interface\\Buttons\\UI-HomeButton", func = addonData.summon.destinationToggle })

    table.insert(submenu.menuList, { text = L["Toggle Raid Information"], notCheckable = true,
                            icon = "Interface\\Buttons\\UI-GuildButton-MOTD-Up", func = addonData.summon.ClickSetDestination })

    if (addonData.summon.isAtDestination() or addonData.summon.zone == "") and addonData.summon.numwaiting > 0 then
      table.insert(submenu.menuList, { text = L["Clear Summon List"], notCheckable = true,
                              icon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up", func = addonData.summon.clearList })
    end

    if UnitIsGroupLeader("player") then
      table.insert(submenu.menuList, { text = L["Relinquish Raid Lead"], notCheckable = true,
                           icon = "Interface\\GROUPFRAME\\UI-Group-LeaderIcon", func = addonData.raid.relinquish })
    end

    table.insert(menu,submenu)
  end

  table.insert(menu, { text = L["Configuration"], notCheckable = true, hasArrow = true,
                 menuList = {
                   { text = L["Options"], notCheckable = true, func = addonData.optionsgui.show },
                   { text = L["Key Bindings"], notCheckable = true, func = function()
                     if InCombatLockdown() then
                       return
                     end
                     if KeyBindingFrame_LoadUI then -- classic-era clients
                       if (not KeyBindingFrame) then
                         KeyBindingFrame_LoadUI()
                       end
                       KeyBindingFrame:Show()
                       for _,v in pairs(KeyBindingFrame.categoryList.buttons) do
                         if v:GetText() == "AddOns" or v:GetText() == "ADDONS" then
                           v:Click()
                         end
                       end
                     elseif Settings and Settings.OpenToCategory and Settings.KEYBINDINGS_CATEGORY_ID then
                       Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
                     elseif SettingsPanel then
                       SettingsPanel:Open()
                     end
                   end },
                   { text = L["Show/Hide Minimap Button"], notCheckable = true, func = appbutton.toggle },
                 },

  } )

  if EasyMenu then -- classic-era clients
    local menuFrame = CreateFrame("Frame", "SteaSummonMenuFrame", UIParent, "UIDropDownMenuTemplate")
    EasyMenu(menu, menuFrame, "cursor", 0 , 0, "MENU", 2);
  else -- modern menu system (WoW: Forever client)
    -- the owner must be a real frame: self is the LDB button when clicked
    -- from the minimap, but a plain table when called as appbutton:menu()
    local owner = (type(self) == "table" and self.GetObjectType) and self or UIParent
    MenuUtil.CreateContextMenu(owner, function(_, root)
      local function build(desc, items)
        for _, item in ipairs(items) do
          if item.menuList then
            build(desc:CreateButton(item.text), item.menuList)
          else
            desc:CreateButton(item.text, item.func)
          end
        end
      end
      build(root, menu)
    end)
  end
end

local ldb = LibStub("LibDataBroker-1.1"):NewDataObject(addonName, {
  type = "data source",
  text = addonName,
  icon = "Interface/ICONS/Spell_Shadow_Twilight",
  OnClick = appbutton.menu,
})

function appbutton:init()
  local ldbdata =
      {
        profile = {
          minimap = {
            hide = false,
          },
        },
      }

  addonData.debug:registerCategory("minimap")
  SteaSummonSave.ldb = SteaSummonSave.ldb or ldbdata
  icon:Register("SteaSummon", ldb, SteaSummonSave.ldb.profile.minimap)
end

function appbutton:toggle(state)
  db("minimap", "toggle minimap, to state", state)
  if state == nil then
    SteaSummonSave.ldb.profile.minimap.hide = not SteaSummonSave.ldb.profile.minimap.hide
  else
    SteaSummonSave.ldb.profile.minimap.hide = state
  end
  if SteaSummonSave.ldb.profile.minimap.hide then
    icon:Hide("SteaSummon")
  else
    icon:Show("SteaSummon")
  end
end

addonData.appbutton = appbutton
