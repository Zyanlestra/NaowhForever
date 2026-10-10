-- Keys.lua: the key that uses each entry on the Consumable Bar: its own button's binding, or an action button holding it.
local ns = _G.NaowhForever

local CB = ns.ConsumableBar
local S = CB.S
local ActionKeys = ns.Shared.ActionKeys

function CB.EntryOf(kind, id)
    if kind == "item" and type(id) == "number" then return id end
end

local function EntryOfSlot(slot, item)
    if slot then return CB.EntryOf(GetActionInfo(slot)) end
    return item
end

local keyMap = ActionKeys.NewMap(EntryOfSlot)

local function OwnBindings(keys)
    for _, entry in ipairs(CB.Items()) do
        keys[entry] = ActionKeys.Bound(CB.BindAction(entry))
    end
end

function CB.KeyMap()
    if not S.Get("consumableBarKeybinds") then return keyMap.Clear() end
    return keyMap.Read(OwnBindings)
end

function CB.KeyFor(cell, map)
    return cell.entry ~= nil and (map[cell.entry] or (cell.itemID and map[cell.itemID])) or nil
end
