-- Keys.lua: the key that uses each entry on the Consumable Bar: its own button's binding, or an action button holding it.
local ns = _G.NaowhForever

local CB = ns.ConsumableBar
local S = CB.S
local ActionKeys = ns.Shared.ActionKeys

local keys = {}
local hidden = {}

function CB.EntryOf(kind, id)
    if kind == "item" and type(id) == "number" then return id end
end

local function Note(btn, slot, item)
    local entry = item
    if slot then entry = CB.EntryOf(GetActionInfo(slot)) end
    if entry == nil then return end
    local hotkey = ActionKeys.OfButton(btn)
    if not hotkey then return end
    if btn:IsVisible() then keys[entry] = keys[entry] or hotkey
    else hidden[entry] = hidden[entry] or hotkey end
end

function CB.KeyMap()
    wipe(keys)
    wipe(hidden)
    if not S.Get("consumableBarKeybinds") then return keys end
    for _, entry in ipairs(CB.Items()) do
        keys[entry] = ActionKeys.Bound(CB.BindAction(entry))
    end
    ActionKeys.Each(Note)
    for entry, hotkey in pairs(hidden) do keys[entry] = keys[entry] or hotkey end
    return keys
end

function CB.KeyFor(cell, map)
    return cell.entry ~= nil and (map[cell.entry] or (cell.itemID and map[cell.itemID])) or nil
end
