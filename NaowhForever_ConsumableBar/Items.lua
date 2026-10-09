-- Items.lua: the Consumable Bar's item rules: what counts as a consumable, the list on the bar and each item's settings.
local ns = _G.NaowhForever

local CB = ns.ConsumableBar
local S, C, D = CB.S, CB.C, CB.Data

local MAX_ITEM_ID = 2147483647
local TEXT_PROMPT = "Item IDs or names, separated by commas"
local TEXT_NOT_ONE = "%s is not a consumable. Only consumables go on the Consumable Bar."
local TEXT_NOT_MANY = "%s are not consumables. Only consumables go on the Consumable Bar."
local TEXT_NO_NAME = "No item called %s in your bags or loaded by the game. Try its ID, or shift-click it into the box."
local TEXT_NONE_KNOWN = "No known item in that. Enter item IDs or names, such as 13446 or Major Healing Potion."
local TEXT_ADDED = "Added %d consumable%s to the Consumable Bar."
local TEXT_NOTHING_NEW = "No consumables in your bags that are not on the bar already."
local TEXT_CLEAR = "Remove every item from the Consumable Bar?"
local TEXT_ASK_AGAIN = "The Consumable Bar will ask about those items again."
local LIST_JOIN = ", "

function CB.Category(itemID)
    if D.WEAPON[itemID] then return "weapon" end
    if CB.Has(ns.HEALTHSTONES, itemID) then return "healthstone" end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID == C.TRADE_GOODS_CLASS then return D.TRADE_GOODS[subclassID] end
    if classID ~= C.CONSUMABLE_CLASS then return nil end
    return D.BY_SUBCLASS[subclassID] or "other"
end

function CB.Wanted(itemID)
    local category = CB.Category(itemID)
    local skip = S.Get("consumableBarSkip") or {}
    return category ~= nil and not skip[category]
end

function CB.SetFlag(entry, key, value)
    local copy = {}
    for id, flags in pairs(S.Get("consumableBarItemFlags") or {}) do
        local f = {}
        for k, v in pairs(flags) do f[k] = v end
        copy[id] = f
    end
    copy[entry] = copy[entry] or {}
    if value == "" or (value == false and key ~= "textOn") then value = nil end
    copy[entry][key] = value
    if not next(copy[entry]) then copy[entry] = nil end
    S.Set("consumableBarItemFlags", copy)
end

function CB.AddItems(ids)
    local items, have, added = {}, {}, 0
    for i, id in ipairs(CB.Items()) do
        items[i] = id
        have[id] = true
    end
    for _, id in ipairs(ids) do
        if not have[id] then
            items[#items + 1] = id
            have[id] = true
            added = added + 1
        end
    end
    if added > 0 then S.Set("consumableBarItems", items) end
    return added
end

function CB.PlaceItem(entry, at)
    local items, from = {}, nil
    local list = CB.Items()
    at = at or #list + 1
    for i, id in ipairs(list) do
        if id == entry then from = i else items[#items + 1] = id end
    end
    if from and from < at then at = at - 1 end
    table.insert(items, math.min(at, #items + 1), entry)
    S.Set("consumableBarItems", items)
end

function CB.MoveItem(from, to)
    local items = {}
    for i, id in ipairs(CB.Items()) do items[i] = id end
    local entry = table.remove(items, from)
    if entry == nil then return end
    table.insert(items, to, entry)
    S.Set("consumableBarItems", items)
end

function CB.RemoveItem(entry)
    local items = {}
    for _, id in ipairs(CB.Items()) do
        if id ~= entry then items[#items + 1] = id end
    end
    local flags = {}
    for id, f in pairs(S.Get("consumableBarItemFlags") or {}) do
        if id ~= entry then flags[id] = f end
    end
    S.Set("consumableBarItemFlags", flags)
    S.Set("consumableBarItems", items)
end

local function ItemByName(name)
    local want, partial = name:lower(), nil
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            local itemName = id and C_Item.GetItemNameByID(id)
            if itemName then
                local lower = itemName:lower()
                if lower == want then return id end
                if not partial and lower:find(want, 1, true) then partial = id end
            end
        end
    end
    if partial then return partial end
    return (C_Item.GetItemInfoInstant(name))
end

function CB.ParseItems(text)
    if type(text) ~= "string" then return end
    local ids, seen, missing = {}, {}, {}
    local function Add(id)
        id = tonumber(id)
        if id and id >= 1 and id <= MAX_ITEM_ID and not seen[id] and C_Item.GetItemInfoInstant(id) then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[%w_]*:", ""):gsub("|r", "")
    text = text:gsub("|H(item:[^|]*)|h.-|h", "%1")
    text = text:gsub("item:(%d+)[%d:%-]*", ",#%1,")
    for piece in text:gmatch("[^,]+") do
        piece = strtrim(piece)
        if piece:match("^#%d+$") then
            Add(piece:sub(2))
        elseif piece:match("^[%d%s]+$") then
            for id in piece:gmatch("%d+") do Add(id) end
        elseif piece ~= "" then
            local id = ItemByName(piece)
            if id then Add(id) else missing[#missing + 1] = piece end
        end
    end
    return #ids > 0 and ids or nil, missing
end

local function OnlyConsumables(ids)
    local kept, refused = {}, {}
    for _, id in ipairs(ids or {}) do
        if CB.Category(id) then kept[#kept + 1] = id else refused[#refused + 1] = CB.ItemName(id) end
    end
    return kept, refused
end

function CB.SayNotConsumable(names)
    ns.Print((#names == 1 and TEXT_NOT_ONE or TEXT_NOT_MANY):format(table.concat(names, LIST_JOIN)))
end

local function Typed(text)
    local found, missing = CB.ParseItems(text)
    local ids, refused = OnlyConsumables(found)
    if #ids > 0 then CB.AddItems(ids) end
    if #refused > 0 then CB.SayNotConsumable(refused) end
    if missing and #missing > 0 then
        ns.Print(TEXT_NO_NAME:format(table.concat(missing, LIST_JOIN)))
    elseif not found then
        ns.Print(TEXT_NONE_KNOWN)
    end
end

function CB.PromptAdd()
    ns.PromptText(TEXT_PROMPT, "", 0, Typed)
end

function CB.BagConsumables(found, seen)
    found, seen = found or {}, seen or {}
    wipe(found)
    wipe(seen)
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] and CB.Category(id) then
                seen[id] = true
                found[#found + 1] = id
            end
        end
    end
    return found
end

function CB.ScanBags()
    local wanted = {}
    for _, id in ipairs(CB.BagConsumables()) do
        if CB.Wanted(id) then wanted[#wanted + 1] = id end
    end
    local added = CB.AddItems(wanted)
    if added > 0 then
        ns.Print(TEXT_ADDED:format(added, added == 1 and "" or "s"))
    else
        ns.Print(TEXT_NOTHING_NEW)
    end
end

local function ClearAll()
    S.Set("consumableBarItemFlags", {})
    S.Set("consumableBarItems", {})
end

function CB.Clear()
    ns.Confirm(TEXT_CLEAR, ClearAll)
end

function CB.ForgetDeclined()
    S.Set("consumableBarDeclined", {})
    ns.Print(TEXT_ASK_AGAIN)
end
