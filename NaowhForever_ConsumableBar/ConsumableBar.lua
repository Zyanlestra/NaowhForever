-- ConsumableBar.lua: the Consumable Bar's module table (ns.ConsumableBar), its entries, their settings and its change listeners.
local ns = _G.NaowhForever

local S = ns.QoLSettings

local ITEM_FALLBACK = "Item %d"
local BUTTON_ITEM = "NaowhForeverConsumableBarItem%s"
local BIND_CLICK = "CLICK %s:LeftButton"

local NO_FLAGS = {}
local NO_ITEMS = {}
local listeners = {}

local CB = {}
ns.ConsumableBar = CB
CB.S = S
CB.PREFIX = "consumableBar"
CB.PAGE = "Consumable Bar/Settings"
CB.CARD = "Consumable Bar/Settings:bar"

function CB.On()
    return S.Get("consumableBar") == true
end

function CB.Has(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

function CB.Secret(v)
    return issecretvalue and issecretvalue(v)
end

function CB.Items()
    local items = S.Get("consumableBarItems")
    return type(items) == "table" and items or NO_ITEMS
end

function CB.Flags(entry)
    local all = S.Get("consumableBarItemFlags")
    return type(all) == "table" and all[entry] or NO_FLAGS
end

function CB.ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or ITEM_FALLBACK:format(itemID)
end

function CB.ItemSpell(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not spellID then C_Item.RequestLoadItemDataByID(itemID) end
    return spellID
end

function CB.Resolve(entry)
    if type(entry) == "number" then return entry end
end

function CB.EntryName(entry)
    return CB.ItemName(entry)
end

function CB.ButtonName(entry)
    return BUTTON_ITEM:format(tostring(entry))
end

function CB.BindAction(entry)
    return BIND_CLICK:format(CB.ButtonName(entry))
end

function CB.OnChange(fn)
    listeners[#listeners + 1] = fn
end

function CB.Changed()
    for _, fn in ipairs(listeners) do fn() end
end
