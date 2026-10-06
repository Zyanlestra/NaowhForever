-------------------------------------------------------------------------------
--  NaowhForever_ConsumableBar.lua -- the QoL consumable bar: a row of the items the player
--  picks, each showing how many are in the bags, click to use. An item the bags are out of
--  turns grey with NONE in red, or hides. Its settings are a card on QoL > Loot & Items whose
--  live preview is the bar itself at its real size, to drop items on, add them by ID or name
--  with +, and right-click each for its settings; a picker anchors it to a frame on screen.
--  A new consumable in the bags can ask to be added. An entry can also be one of the Macros
--  module's consumable macros (NF Health, NF Mana, NF Food, NF Bandage): its button runs that
--  macro by name, so the macro is the one thing kept current, and the bar keeps it switched
--  on while it uses it. Every icon's button is named after what it holds, so a key can be
--  bound to it directly, from its settings, and follows it wherever it sits on the bar.
--
--  The icons are secure item buttons, so their layout, anchor, attributes and visibility only
--  change outside combat; a change made in combat applies when it ends. What an icon does in
--  a fight is set before it starts, through state drivers: Hide in Combat hides it, and Hide
--  After Use, which hides an item while its effect is on you, brings it back for the fight.
--  Counts, keybinds, the grey icon and cooldowns are plain textures and text, and update in
--  combat. A hidden icon keeps its slot, so the bar does not shift under the cursor.
-------------------------------------------------------------------------------
local ns = _G.NaowhForever
local S = ns.QoLSettings
local UI = ns.UI
local T = ns.THEME

local NONE_COLOR = { r = 1, g = 0.1, b = 0.1 }
local WHITE = { r = 1, g = 1, b = 1 }
local INSET = 2           -- the text's gap from the icon edge, inside
local ROW_INSET = 10      -- a popup's rows from its edges: the Shared panel's padding
local BG_PAD = 3          -- how far the background reaches past the icons
local GCD = 1.5           -- a cooldown this short is the global cooldown, not the item's own
local CONSUMABLE_CLASS = 0
local TRADE_GOODS_CLASS = 7
local PREVIEW_TOP, PREVIEW_PAD = 30, 12   -- the hint line above the bar, and the room below
local EARLY_DEFAULT, EARLY_STEP, EARLY_MIN, EARLY_MAX = 120, 15, 15, 1800

local POINT_VALUES = { TOPLEFT = "Top Left", TOP = "Top", TOPRIGHT = "Top Right", LEFT = "Left",
    CENTER = "Center", RIGHT = "Right", BOTTOMLEFT = "Bottom Left", BOTTOM = "Bottom",
    BOTTOMRIGHT = "Bottom Right" }
local POINT_ORDER = { "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" }
local TRACK_VALUES = { buff = "Its Buff", mainhand = "Main Hand Enchant", offhand = "Off Hand Enchant" }
local TRACK_ORDER = { "buff", "mainhand", "offhand" }

-- Scan Bags and Ask to Add sort what they find by the game's own subclass of Consumable.
-- Stones, weightstones, oils and poisons put a temporary enchant on a weapon; the game files
-- them under different subclasses, so the classic ones are also known by ID. Explosives and
-- engineering devices are Trade Goods to the game, but are used like consumables, so they
-- count too.
local CATEGORY_ORDER = { "potion", "elixir", "flask", "scroll", "food", "bandage", "weapon",
    "healthstone", "explosive", "device", "other" }
local CATEGORY_NAMES = { potion = "Potions", elixir = "Elixirs", flask = "Flasks", scroll = "Scrolls",
    food = "Food & Drink Items", bandage = "Bandages", weapon = "Weapon Enhancements",
    healthstone = "Healthstones", explosive = "Explosives", device = "Devices", other = "Other Consumables" }
local SUBCLASS_CATEGORY = { [1] = "potion", [2] = "elixir", [3] = "flask", [4] = "scroll",
    [5] = "food", [6] = "weapon", [7] = "bandage" }
local TRADE_GOODS_CATEGORY = { [2] = "explosive", [3] = "device" }
local WEAPON_ITEMS = {}
for _, id in ipairs({
    2862, 2863, 2871, 7964, 12404, 18262, 23122,              -- sharpening stones
    3239, 3240, 3241, 7965, 12643,                            -- weightstones
    20744, 20745, 20746, 20747, 20748, 20749, 20750, 23123,   -- wizard and mana oils
    3824, 3829,                                               -- shadow and frost oil
    6947, 6949, 6950, 8926, 8927, 8928,                       -- instant poison
    2892, 2893, 8984, 8985, 20844,                            -- deadly poison
    3775, 3776, 5237, 6951, 9186,                             -- crippling, mind-numbing
    10918, 10920, 10921, 10922,                               -- wound poison
}) do WEAPON_ITEMS[id] = true end
ns.ConsumableBarCategories = { order = CATEGORY_ORDER, names = CATEGORY_NAMES }

-- Text outside the icon sits beyond the edge it names: above or below for the top and bottom
-- points, corners included, and beside it for left and right.
local OUTSIDE = {
    TOPLEFT = "BOTTOMLEFT", TOP = "BOTTOM", TOPRIGHT = "BOTTOMRIGHT",
    LEFT = "RIGHT", CENTER = "CENTER", RIGHT = "LEFT",
    BOTTOMLEFT = "TOPLEFT", BOTTOM = "TOP", BOTTOMRIGHT = "TOPRIGHT",
}

local frame, unlocked, pending, preview, picker, panel, ask
local buttons = {}
local wakeGen, wakeAt = 0, nil
local keysPending         -- a keybind refresh is queued
local known               -- itemID -> true for each consumable seen in the bags this session
local asking = {}         -- consumables waiting to be offered, in order

local function On()
    return S.Get("enabled") and S.Get("consumableBar")
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Items()
    local items = S.Get("consumableBarItems")
    return type(items) == "table" and items or {}
end

local function Flags(itemID)
    local all = S.Get("consumableBarItemFlags")
    return type(all) == "table" and all[itemID] or {}
end

local function ItemName(itemID)
    return C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
end

-- The spell the item casts on use, nil for an item without one or not loaded yet.
local function ItemSpell(itemID)
    local _, spellID = C_Item.GetItemSpell(itemID)
    if not spellID then C_Item.RequestLoadItemDataByID(itemID) end
    return spellID
end

local function Clock(seconds)
    return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

-- An entry is an item ID, or "macro:<key>" for one of the Macros module's consumable macros
-- (ns.ConsumableMacros).
local function MacroKey(entry)
    local key = type(entry) == "string" and entry:match("^macro:(%a+)$")
    return key and ns.ConsumableMacros and ns.ConsumableMacros[key] and key
end

local function MacroInfo(entry)
    local key = MacroKey(entry)
    return key and ns.ConsumableMacros[key]
end

-- A macro's own button, so a key can be bound to it: NaowhForeverConsumableBarHealth.
local function PickButtonName(key)
    return "NaowhForeverConsumableBar" .. key:gsub("^%l", string.upper)
end

-- Every entry's button name: the macro's, or the item's by ID (NaowhForeverConsumableBarItem13446),
-- so a key bound to it follows the item wherever it sits on the bar.
local function ButtonName(entry)
    local key = MacroKey(entry)
    if key then return PickButtonName(key) end
    return "NaowhForeverConsumableBarItem" .. tostring(entry)
end

-- The binding command for an entry's button, for a key field.
function ns.ConsumableBarBindAction(entry)
    return "CLICK " .. ButtonName(entry) .. ":LeftButton"
end

-- The item an entry uses now. A macro's is the first item in its text: nil until the Macros
-- module has written it, and kept when the bags run out, as the macro keeps it.
local function Resolve(entry)
    local info = MacroInfo(entry)
    if not info then
        if type(entry) == "number" then return entry end
        return nil
    end
    local body = GetMacroBody(info.name)
    return body and tonumber(body:match("item:(%d+)"))
end

local function EntryName(entry)
    local info = MacroInfo(entry)
    if info then return info.label .. " (" .. info.name .. ")" end
    if type(entry) ~= "number" then return "Macro" end
    return ItemName(entry)
end

local function EntryIcon(entry, item)
    if item then return C_Item.GetItemIconByID(item) end
    local info = MacroInfo(entry)
    return info and info.icon or 134400
end

local function Category(itemID)
    if WEAPON_ITEMS[itemID] then return "weapon" end
    if ns.HEALTHSTONES and tContains(ns.HEALTHSTONES, itemID) then return "healthstone" end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    if classID == TRADE_GOODS_CLASS then return TRADE_GOODS_CATEGORY[subclassID] end
    if classID ~= CONSUMABLE_CLASS then return nil end
    return SUBCLASS_CATEGORY[subclassID] or "other"
end
ns.ConsumableBarCategory = Category

local function Wanted(itemID)
    local category = Category(itemID)
    local skip = S.Get("consumableBarSkip") or {}
    return category ~= nil and not skip[category]
end

-------------------------------------------------------------------------------
--  The item list. Saved tables are copied before every change, so the shared defaults are
--  never written.
-------------------------------------------------------------------------------
local function SetFlag(itemID, key, value)
    local copy = {}
    for id, flags in pairs(S.Get("consumableBarItemFlags") or {}) do
        local f = {}
        for k, v in pairs(flags) do f[k] = v end
        copy[id] = f
    end
    copy[itemID] = copy[itemID] or {}
    if value == "" or (value == false and key ~= "textOn") then value = nil end
    copy[itemID][key] = value
    if not next(copy[itemID]) then copy[itemID] = nil end
    S.Set("consumableBarItemFlags", copy)
end

local function AddItems(ids)
    local items, have, added = {}, {}, 0
    for i, id in ipairs(Items()) do items[i] = id; have[id] = true end
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

-- Puts an entry at `at` in the list, or at the end; one already on the bar moves there and
-- keeps its settings.
local function PlaceEntry(entry, at)
    local items, from = {}, nil
    local list = Items()
    at = at or #list + 1
    for i, id in ipairs(list) do
        if id == entry then from = i else items[#items + 1] = id end
    end
    if from and from < at then at = at - 1 end
    table.insert(items, math.min(at, #items + 1), entry)
    S.Set("consumableBarItems", items)
end

local function RemoveItem(itemID)
    local items = {}
    for _, id in ipairs(Items()) do
        if id ~= itemID then items[#items + 1] = id end
    end
    local flags = {}
    for id, f in pairs(S.Get("consumableBarItemFlags") or {}) do
        if id ~= itemID then flags[id] = f end
    end
    S.Set("consumableBarItemFlags", flags)
    S.Set("consumableBarItems", items)
end

-- An item by its name, case aside: one in the bags first, the whole name before part of it,
-- then any item the game has loaded.
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

-- Items from the options prompt, separated by commas: IDs (spaces between work too), names,
-- or pasted item links. Only items the game knows are kept, each once. Returns the IDs, nil
-- when there are none, and the names that matched nothing.
function ns.ParseConsumableBarItems(text)
    if type(text) ~= "string" then return end
    local ids, seen, missing = {}, {}, {}
    local function Add(id)
        id = tonumber(id)
        if id and id >= 1 and id <= 2147483647 and not seen[id]
            and C_Item.GetItemInfoInstant(id) then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    -- Links and item strings become #<id> where they stand, so their names and colours are not
    -- read as names and the order typed is kept.
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

-- Only consumables go on the bar. Splits `ids` into those and the names of the rest.
local function OnlyConsumables(ids)
    local kept, refused = {}, {}
    for _, id in ipairs(ids or {}) do
        if Category(id) then kept[#kept + 1] = id else refused[#refused + 1] = ItemName(id) end
    end
    return kept, refused
end

local function SayNotConsumable(names)
    ns.Print(table.concat(names, ", ") .. (#names == 1 and " is not a consumable" or " are not consumables")
        .. ". Only consumables go on the Consumable Bar.")
end

function ns.AddConsumableBarItems()
    ns.PromptText("Item IDs or names, separated by commas", "", 0, function(text)
        local found, missing = ns.ParseConsumableBarItems(text)
        local ids, refused = OnlyConsumables(found)
        if #ids > 0 then AddItems(ids) end
        if #refused > 0 then SayNotConsumable(refused) end
        if missing and #missing > 0 then
            ns.Print("No item called " .. table.concat(missing, ", ") .. " in your bags or loaded by "
                .. "the game. Try its ID, or shift-click it into the box.")
        elseif not found then
            ns.Print("No known item in that. Enter item IDs or names, such as 13446 or Major Healing Potion.")
        end
    end)
end

-- Every consumable in the bags, in bag order, each once.
local function BagConsumables()
    local found, seen = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not seen[id] and Category(id) then
                seen[id] = true
                found[#found + 1] = id
            end
        end
    end
    return found
end

-- What Scan Bags adds: the consumables in the kinds switched on under Scan Filters.
local function WantedInBags()
    local wanted = {}
    for _, id in ipairs(BagConsumables()) do
        if Wanted(id) then wanted[#wanted + 1] = id end
    end
    return wanted
end

function ns.ScanBagsForConsumableBar()
    local added = AddItems(WantedInBags())
    if added > 0 then
        ns.Print(("Added %d consumable%s to the Consumable Bar."):format(added, added == 1 and "" or "s"))
    else
        ns.Print("No consumables in your bags that are not on the bar already.")
    end
end

function ns.ClearConsumableBar()
    ns.Confirm("Remove every item from the Consumable Bar?", function()
        S.Set("consumableBarItemFlags", {})
        S.Set("consumableBarItems", {})
    end)
end

function ns.ConsumableBarHasMacro(key)
    return tContains(Items(), "macro:" .. key)
end

-- Whether the bar is on and carries the macro: the Macros module keeps such a macro.
function ns.ConsumableBarUsesMacro(key)
    return On() and ns.ConsumableBarHasMacro(key) or false
end

-- Switched from the options page: the macro joins the end of the bar, or leaves it. Apply
-- switches it on in Macros.
function ns.SetConsumableBarMacro(key, on)
    local entry = "macro:" .. key
    if on then AddItems({ entry }) elseif tContains(Items(), entry) then RemoveItem(entry) end
end

function ns.ForgetConsumableBarDeclined()
    S.Set("consumableBarDeclined", {})
    ns.Print("The Consumable Bar will ask about those items again.")
end

-------------------------------------------------------------------------------
--  An icon, as the bar and the preview both draw it
-------------------------------------------------------------------------------
local function MakeCell(cell)
    -- Each icon carries its own piece of the background, so a hidden icon hides its piece.
    cell.bg = cell:CreateTexture(nil, "BACKGROUND")
    cell.bg:SetColorTexture(0, 0, 0, 1)
    cell.icon = cell:CreateTexture(nil, "ARTWORK")
    cell.icon:SetAllPoints()
    cell.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    ns.Border(cell, { r = 0, g = 0, b = 0 })
    cell.timer = CreateFrame("Cooldown", nil, cell, "CooldownFrameTemplate")
    cell.timer:SetAllPoints()
    cell.timer:SetDrawEdge(false)
    -- The text draws above the cooldown swirl.
    cell.overlay = CreateFrame("Frame", nil, cell)
    cell.overlay:SetAllPoints()
    cell.overlay:SetFrameLevel(cell.timer:GetFrameLevel() + 2)
    cell.count = ns.Font(cell.overlay, 14, "OUTLINE")
    cell.custom = ns.Font(cell.overlay, 12, "OUTLINE")
    cell.key = ns.Font(cell.overlay, 10, "OUTLINE", { r = 0.85, g = 0.85, b = 0.85 })
    cell.key:Hide()
    cell.none = ns.Font(cell.overlay, 10, "OUTLINE", NONE_COLOR)
    cell.none:SetPoint("CENTER")
    cell.none:SetText("NONE")
end

local function PlaceText(fs, cell, point, outside, x, y, path, size)
    if not OUTSIDE[point] then point = "BOTTOMRIGHT" end
    fs:ClearAllPoints()
    if outside then
        fs:SetPoint(OUTSIDE[point], cell, point, x, y)
    else
        local dx = point:find("LEFT") and INSET or point:find("RIGHT") and -INSET or 0
        local dy = point:find("TOP") and -INSET or point:find("BOTTOM") and INSET or 0
        fs:SetPoint(point, cell, point, x + dx, y + dy)
    end
    fs:SetJustifyH(point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER")
    fs:SetFont(path, size, "OUTLINE")
end

-- An item's own text is on once switched on; an item given text before the switch existed
-- keeps showing it.
local function CustomOn(f)
    if f.textOn ~= nil then return f.textOn end
    return (f.text or "") ~= ""
end

-- The item's own text, from its settings; its font follows the bar's unless it has its own.
local function PlaceCustom(cell, entry)
    local f = Flags(entry)
    if not CustomOn(f) or not f.text or f.text == "" then cell.custom:Hide() return end
    local face = f.textFont
    if not face or face == "" then face = S.Get("consumableBarFont") end
    PlaceText(cell.custom, cell, f.textPoint or "TOP", f.textOutside, f.textX or 0, f.textY or 0,
        UI.FontPath(face), f.textSize or 12)
    local c = f.textColor or WHITE
    cell.custom:SetText(f.text)
    cell.custom:SetTextColor(c.r, c.g, c.b, 1)
    cell.custom:Show()
end

-- NONE follows the icon size, not the count's font size: as large as fits between the edges.
local function FitNone(cell, size)
    local path = UI.FontPath(S.Get("consumableBarFont"))
    local guess = math.max(4, math.floor(size * 0.4))
    cell.none:SetFont(path, guess, "OUTLINE")
    local width = cell.none:GetStringWidth()
    if width and width > 0 then
        local fit = math.floor(guess * (size - 2 * INSET) / width)
        cell.none:SetFont(path, math.max(4, math.min(fit, math.floor(size * 0.5))), "OUTLINE")
    end
end

local function StyleCell(cell, entry, item, size)
    cell:SetSize(size, size)
    cell.icon:SetTexture(EntryIcon(entry, item))
    PlaceText(cell.count, cell, S.Get("consumableBarTextPoint"), S.Get("consumableBarTextOutside"),
        S.Get("consumableBarTextX"), S.Get("consumableBarTextY"),
        UI.FontPath(S.Get("consumableBarFont")), S.Get("consumableBarFontSize"))
    PlaceCustom(cell, entry)
    FitNone(cell, size)
    -- The keybind's own text settings; its font follows the count's unless it has its own.
    local face = S.Get("consumableBarKeyFont")
    if not face or face == "" then face = S.Get("consumableBarFont") end
    PlaceText(cell.key, cell, S.Get("consumableBarKeyPoint"), S.Get("consumableBarKeyOutside"),
        S.Get("consumableBarKeyX"), S.Get("consumableBarKeyY"), UI.FontPath(face), S.Get("consumableBarKeySize"))
    local c = S.Get("consumableBarKeyColor")
    cell.key:SetTextColor(c.r, c.g, c.b, 1)
end

-- `faded` is the alpha for an item the bags are out of while Hide When Out is on: nothing on
-- the bar, a ghost in the preview so it can still be set up.
local function ShowCount(cell, itemID, faded)
    local count = itemID and C_Item.GetItemCount(itemID) or 0
    local c = S.Get("consumableBarTextColor")
    local hideEmpty = S.Get("consumableBarHideEmpty") and not unlocked
    cell.count:SetText(count)
    cell.count:SetTextColor(c.r, c.g, c.b, 1)
    cell.count:SetShown(count > 0 and S.Get("consumableBarShowCount") ~= false)
    cell.none:SetShown(count == 0 and not hideEmpty)
    cell.icon:SetDesaturated(count == 0)
    cell.empty = count == 0 and hideEmpty
    cell:SetAlpha(cell.empty and faded or 1)
end

-- A cooldown handed back secret is left as it was drawn; the next update catches up.
local function ShowCooldown(cell, itemID)
    if not (itemID and S.Get("consumableBarCooldown")) then cell.timer:Hide() return end
    local start, duration, enable = C_Container.GetItemCooldown(itemID)
    if Secret(start) or Secret(duration) or Secret(enable) then return end
    if enable == 1 and duration and duration > 0 then
        cell.timer:SetCooldown(start, duration)
        cell.timer:Show()
    else
        cell.timer:Hide()
    end
end

-- Size, spacing, growth and how many icons a row holds before the next one starts. A bar
-- growing up or down fills columns instead, and starts each new one to the right.
local function Grid()
    return S.Get("consumableBarSize"), S.Get("consumableBarSpacing"), S.Get("consumableBarGrow"),
        math.max(1, S.Get("consumableBarPerRow") or 12)
end

local function Position(cell, parent, index, size, gap, grow, perRow)
    local step = size + gap
    local along = (index - 1) % perRow * step
    local across = math.floor((index - 1) / perRow) * step
    cell:ClearAllPoints()
    if grow == "LEFT" then cell:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -along, -across)
    elseif grow == "UP" then cell:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", across, along)
    elseif grow == "DOWN" then cell:SetPoint("TOPLEFT", parent, "TOPLEFT", across, -along)
    else cell:SetPoint("TOPLEFT", parent, "TOPLEFT", along, -across) end
end

-- The icon's piece of the background: halfway into the spacing toward each neighbouring
-- slot, so the pieces meet with no seam or overlap, and BG_PAD past an outer edge.
local function PlaceBackground(cell, index, count, gap, grow, perRow)
    local k = index - 1
    local along, lane = k % perRow, math.floor(k / perRow)
    local half = gap / 2
    local function Reach(hasNeighbour) return hasNeighbour and half or BG_PAD end
    local back, ahead = Reach(along > 0), Reach(along < perRow - 1 and k + 1 < count)
    local before, after = Reach(lane > 0), Reach(k + perRow < count)
    local left, right, top, bottom
    if grow == "LEFT" then left, right, top, bottom = ahead, back, before, after
    elseif grow == "UP" then left, right, top, bottom = before, after, ahead, back
    elseif grow == "DOWN" then left, right, top, bottom = before, after, back, ahead
    else left, right, top, bottom = back, ahead, before, after end
    cell.bg:ClearAllPoints()
    cell.bg:SetPoint("TOPLEFT", cell, "TOPLEFT", -left, top)
    cell.bg:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", right, -bottom)
    cell.bg:SetShown(S.Get("consumableBarBackground"))
    cell.bg:SetAlpha(S.Get("consumableBarBgAlpha"))
end

local function BarSize(slots, size, gap, grow, perRow)
    slots = math.max(slots, 1)
    local long = math.min(slots, perRow) * (size + gap) - gap
    local short = math.ceil(slots / perRow) * (size + gap) - gap
    if grow == "UP" or grow == "DOWN" then return short, long end
    return long, short
end

-------------------------------------------------------------------------------
--  Keybinds: the key of an action button holding the item. Blizzard's bars, and bars built
--  on their button template, register with ActionBarButtonEventsFrame; bars built on
--  LibActionButton are listed by that library. EllesmereUI takes its own buttons off that
--  list, so they are found by name, their slot read from the "action" attribute as
--  EllesmereUI itself reads it. A bar that draws its own key text is read through the
--  binding behind the button instead.
-------------------------------------------------------------------------------
local LAB_NAMES = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }
local EUI_SLOTS = 180

-- The key text a button shows, or the key bound to it.
local function ButtonKey(btn)
    local hotkey = btn.HotKey and btn.HotKey:GetText()
    if hotkey and hotkey ~= "" and hotkey ~= RANGE_INDICATOR then return hotkey end
    local name = btn.GetName and btn:GetName()
    local binding = btn.GetAttribute and btn:GetAttribute("binding")
    for _, command in ipairs({ btn.bindingAction or false, btn.commandName or false, binding or false,
        name and ("CLICK " .. name .. ":LeftButton") or false, name and ("CLICK " .. name .. ":Keybind") or false }) do
        if type(command) == "string" then
            local key = GetBindingKey(command)
            if key then return GetBindingText(key, true) end
        end
    end
end

-- An item, or one of the consumable macros, on an action slot or the cursor, as a bar entry:
-- the item ID, or "macro:<key>". Any other macro is not one.
local function Entry(kind, id)
    if kind == "item" and type(id) == "number" then return id end
    if kind == "macro" and type(id) == "number" and ns.ConsumableMacros then
        local name = GetMacroInfo(id)
        for key, info in pairs(ns.ConsumableMacros) do
            if name and info.name == name then return "macro:" .. key end
        end
    end
end

-- What an action slot holds, as a bar entry.
local function SlotEntry(slot)
    if not slot then return end
    return Entry(GetActionInfo(slot))
end

local function KeyMap()
    local keys, hidden = {}, {}
    if not S.Get("consumableBarKeybinds") then return keys end
    -- A key bound to the icon's own button comes first; then one on an action bar.
    for _, entry in ipairs(Items()) do
        local bound = GetBindingKey(ns.ConsumableBarBindAction(entry))
        if bound then keys[entry] = GetBindingText(bound, true) end
    end
    local function Note(btn, entry)
        if entry == nil then return end
        local hotkey = ButtonKey(btn)
        if not hotkey then return end
        -- A button on screen wins over one on a hidden bar or page.
        if btn:IsVisible() then keys[entry] = keys[entry] or hotkey
        else hidden[entry] = hidden[entry] or hotkey end
    end
    local frames = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
    for _, btn in pairs(frames or {}) do Note(btn, SlotEntry(btn.action)) end
    for slot = 1, EUI_SLOTS do
        local btn = _G["EABButton" .. slot]
        if btn and btn.GetAttribute then Note(btn, SlotEntry(btn:GetAttribute("action"))) end
    end
    for _, libName in ipairs(LAB_NAMES) do
        local lab = LibStub and LibStub(libName, true)
        local all = lab and lab.GetAllButtons and lab:GetAllButtons()
        for k, v in pairs(all or {}) do
            local btn = type(k) == "table" and k or v
            local kind, action = btn:GetAction()
            if kind == "action" then Note(btn, SlotEntry(action))
            elseif kind == "item" then Note(btn, tonumber(tostring(action):match("(%d+)"))) end
        end
    end
    for entry, hotkey in pairs(hidden) do keys[entry] = keys[entry] or hotkey end
    return keys
end

local function ShowKey(cell, keys)
    local key = cell.entry ~= nil and (keys[cell.entry] or (cell.itemID and keys[cell.itemID]))
    cell.key:SetText(key or "")
    cell.key:SetShown(key ~= nil)
end

-------------------------------------------------------------------------------
--  Hide After Use, read out of combat only
-------------------------------------------------------------------------------
local function Soon(seconds)
    if seconds and seconds > 0 and (not wakeAt or seconds < wakeAt) then wakeAt = seconds end
end

-- Seconds until the item is ready again, ignoring the global cooldown.
local function CooldownLeft(itemID)
    local start, duration, enable = C_Container.GetItemCooldown(itemID)
    if Secret(start) or Secret(duration) or Secret(enable) then return nil end
    if enable == 1 and duration and duration > GCD then
        local left = start + duration - GetTime()
        if left > 0 then return left end
    end
end

-- Seconds the item's effect has left on you: its buff, or a weapon enchant for oils, stones
-- and poisons. nil when it is not on, math.huge when it does not run out; the second return
-- is true when the game will not say right now.
-- Seconds left on one aura, as EffectLeft returns them.
local function AuraLeft(spell)
    local aura = C_UnitAuras.GetPlayerAuraBySpellID(spell)
    if not aura then return nil end
    local expires = aura.expirationTime
    if Secret(expires) then return nil, true end
    if not expires or expires == 0 then return math.huge end
    return expires - GetTime()
end

local function EffectLeft(itemID, flags)
    local track = flags.track or "buff"
    if track == "buff" then
        if C_Secrets.ShouldAurasBeSecret() then return nil, true end
        local spell = ItemSpell(itemID)
        if not spell then return nil end
        local left, unknown = AuraLeft(spell)
        -- Food's use spell is the eating; what it leaves on you is Well Fed, one shared aura
        -- per stat (the Buffs & Consumables reminder's list).
        local data = ns.BuffReminderData
        if not left and not unknown and data and data.FOOD_SPELLS[spell] then
            for _, fed in ipairs(data.WELL_FED) do
                left, unknown = AuraLeft(fed)
                if left or unknown then break end
            end
        end
        return left, unknown
    end
    local hasMain, mainMs, _, _, hasOff, offMs = GetWeaponEnchantInfo()
    local has, ms = hasMain, mainMs
    if track == "offhand" then has, ms = hasOff, offMs end
    if Secret(has) or Secret(ms) then return nil, true end
    if not has then return nil end
    return (ms or 0) / 1000
end

-- Whether Hide After Use hides the item now: while it is on cooldown, or while its effect has
-- more left than Show Before It Ends allows.
local function Spent(button)
    local id, flags = button.itemID, Flags(button.entry)
    if not id then return false end
    local left = CooldownLeft(id)
    local hidden = left ~= nil
    Soon(left)
    local effect, unknown = EffectLeft(id, flags)
    if unknown then
        hidden = hidden or button.spent == true
    elseif effect then
        local lead = flags.early and (flags.earlySeconds or EARLY_DEFAULT) or 0
        if effect > lead then
            hidden = true
            if effect ~= math.huge then Soon(effect - lead) end
        end
    end
    button.spent = hidden
    return hidden
end

-------------------------------------------------------------------------------
--  The bar
-------------------------------------------------------------------------------
-- Registering a driver evaluates its rule at once, and UpdateVisibility runs on every global
-- cooldown while Hide After Use is on, so a driver is only registered again when its rule
-- changes.
local function Driver(f, rule)
    if f.visRule == rule then return end
    f.visRule = rule
    if rule then
        RegisterStateDriver(f, "visibility", rule)
    else
        UnregisterStateDriver(f, "visibility")
    end
end

local function ShowTooltip(button)
    if not S.Get("consumableBarTooltip") or button.entry == nil or button.empty then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if button.itemID then GameTooltip:SetItemByID(button.itemID) else GameTooltip:SetText(EntryName(button.entry)) end
    GameTooltip:Show()
end

local function NewButton(name)
    local button = CreateFrame("Button", name, frame, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    MakeCell(button)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return button
end

-- Each entry has its own named button, made the first time it is on the bar and kept: WoW
-- never frees a frame, and the same item coming back reuses it.
local pool = {}
local function ButtonFor(entry)
    pool[entry] = pool[entry] or NewButton(ButtonName(entry))
    return pool[entry]
end

local function Retire(button)
    Driver(button, nil)
    button.entry, button.itemID, button.spent, button.slot = nil, nil, nil, nil
    button:SetAttribute("type1", nil)
    button:SetAttribute("item1", nil)
    button:SetAttribute("macro1", nil)
    button:Hide()
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverConsumableBar", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    -- Shown while its anchor is edited on screen, so it is plain which bar moves.
    frame.outline = CreateFrame("Frame", nil, frame)
    frame.outline:SetPoint("TOPLEFT", -BG_PAD - 1, BG_PAD + 1)
    frame.outline:SetPoint("BOTTOMRIGHT", BG_PAD + 1, -BG_PAD - 1)
    frame.outline:SetFrameLevel(frame:GetFrameLevel() + 30)
    ns.Border(frame.outline, T.accent)
    frame.outline:Hide()
    -- Dragging it places it on the screen again, as the Co-Tank frame does.
    frame.mover = UI.AttachMover(frame, "Consumable Bar", function(pos)
        S.Set("consumableBarPos", pos)
        S.Set("consumableBarAnchor", "UIParent")
    end, "QoL/Loot & Items", "QoL/Loot & Items:consumableBar")
end

-- Out of combat only.
local function Layout()
    local items = Items()
    local size, gap, grow, perRow = Grid()
    local inUse = {}
    for i = #buttons, 1, -1 do buttons[i] = nil end
    for i, entry in ipairs(items) do
        local button = ButtonFor(entry)
        buttons[i], inUse[button] = button, true
        local item = Resolve(entry)
        Position(button, frame, i, size, gap, grow, perRow)
        PlaceBackground(button, i, #items, gap, grow, perRow)
        StyleCell(button, entry, item, size)
        button.entry, button.itemID, button.slot = entry, item, i
        -- A macro runs by name, so the Macros module's rewrites reach it with nothing set here;
        -- one not written yet works from the moment it is.
        local info = MacroInfo(entry)
        if info then
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macro1", info.name)
            button:SetAttribute("item1", nil)
        else
            button:SetAttribute("type1", item and "item" or nil)
            button:SetAttribute("item1", item and ("item:" .. item) or nil)
            button:SetAttribute("macro1", nil)
        end
    end
    for _, button in pairs(pool) do
        if not inUse[button] and (button.entry ~= nil or button:IsShown()) then Retire(button) end
    end
    -- An empty bar keeps one icon's room, so Unlock Mode still has something to drag.
    frame:SetSize(BarSize(#items, size, gap, grow, perRow))
end

-- Anchored to another frame by name, with the chosen points and offsets; otherwise wherever
-- it was dragged. A name that matches no frame, or one that cannot take the anchor (a frame
-- anchored to the bar itself), falls back to the screen.
local function Place()
    local pos = S.Get("consumableBarPos")
    local name = S.Get("consumableBarAnchor")
    local anchor = name ~= "UIParent" and _G[name]
    frame:ClearAllPoints()
    if type(anchor) == "table" and anchor ~= frame and anchor.GetObjectType then
        local ok = pcall(frame.SetPoint, frame, S.Get("consumableBarAnchorPoint"), anchor,
            S.Get("consumableBarAnchorRelPoint"), S.Get("consumableBarX"), S.Get("consumableBarY"))
        if ok then return end
        frame:ClearAllPoints()
    end
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, -220)
    end
end

-- An icon hidden by Hide When Out takes no clicks, so it does not catch ones meant for what
-- is under it. Mouse input on a secure button only changes out of combat: one that runs out
-- in a fight stops taking clicks when it ends.
local function UpdateCounts()
    local quiet = not InCombatLockdown()
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then
            ShowCount(button, button.itemID, 0)
            if quiet then button:EnableMouse(not button.empty) end
        end
    end
end

local function UpdateCooldowns()
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then ShowCooldown(button, button.itemID) else button.timer:Hide() end
    end
end

local function HasMacros()
    for _, entry in ipairs(Items()) do
        if MacroInfo(entry) then return true end
    end
    return false
end

local RenderPreview

-- Blizzard redraws its own key text on these events too, so this waits a frame and reads it
-- after; a burst of events is read once.
local function UpdateKeys()
    keysPending = nil
    local keys = KeyMap()
    for _, button in ipairs(buttons) do ShowKey(button, keys) end
    RenderPreview()
end

local function QueueKeys()
    if keysPending then return end
    keysPending = true
    C_Timer.After(0, UpdateKeys)
end

-- How each icon shows in and out of combat, set out of combat as state drivers. The bar
-- itself follows: hidden whenever none of its icons would show.
local UpdateVisibility
local function Wake()
    wakeGen = wakeGen + 1
    if not wakeAt then return end
    local gen = wakeGen
    C_Timer.After(wakeAt + 0.1, function()
        if gen == wakeGen then UpdateVisibility() end
    end)
end

function UpdateVisibility()
    if not frame or InCombatLockdown() then return end
    wakeAt = nil
    local fight, rest = unlocked == true, unlocked == true
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then
            local flags = Flags(button.entry)
            local combat = flags.combat and not unlocked
            local used = flags.used and not unlocked and Spent(button)
            if combat and used then
                Driver(button, nil)
                button:Hide()
            elseif combat then
                Driver(button, "[combat] hide; show")
            elseif used then
                Driver(button, "[combat] show; hide")
            else
                Driver(button, nil)
                button:Show()
            end
            fight = fight or not combat
            rest = rest or not used
        end
    end
    if S.Get("consumableBarHideCombat") and not unlocked then fight = false end
    if fight and rest then
        Driver(frame, nil)
        frame:Show()
    elseif fight then
        Driver(frame, "[combat] show; hide")
    elseif rest then
        Driver(frame, "[combat] hide; show")
    else
        Driver(frame, nil)
        frame:Hide()
    end
    Wake()
end

local function AnyHideUsed()
    if unlocked then return false end
    for _, id in ipairs(Items()) do
        if Flags(id).used then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  New consumables: offered one at a time, out of combat. No means never ask about it again.
-------------------------------------------------------------------------------
local ShowAsk

local function BuildAsk()
    local St = ns.Shared.Style
    ask = ns.Shared.Parts.Panel("Consumable Bar")
    ask:SetFrameStrata("DIALOG")
    ask:SetSize(340, St.PANEL_HEADER + 36 + St.PANEL_PAD + 24 + St.PANEL_PAD + 4)
    ask.icon = CreateFrame("Button", nil, ask)
    ask.icon:SetSize(36, 36)
    ask.icon:SetPoint("TOPLEFT", St.PANEL_PAD, -St.PANEL_HEADER)
    ask.icon.tex = ask.icon:CreateTexture(nil, "ARTWORK")
    ask.icon.tex:SetAllPoints()
    ns.Border(ask.icon, { r = 0, g = 0, b = 0 })
    ask.icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetItemByID(ask.itemID)
        GameTooltip:Show()
    end)
    ask.icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ask.text = ns.Font(ask, 13, nil)
    ask.text:SetPoint("TOPLEFT", ask.icon, "TOPRIGHT", 10, 0)
    ask.text:SetPoint("RIGHT", -ROW_INSET, 0)
    ask.text:SetJustifyH("LEFT")
    ns.Button(ask, "Add", 90, 24, function()
        ask:Hide()
        AddItems({ ask.itemID })
        ShowAsk()
    end):SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -4, St.PANEL_PAD)
    local no = ns.Button(ask, "No", 90, 24, function()
        local declined = {}
        for id in pairs(S.Get("consumableBarDeclined") or {}) do declined[id] = true end
        declined[ask.itemID] = true
        ask:Hide()
        S.Set("consumableBarDeclined", declined)
        ShowAsk()
    end)
    no:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 4, St.PANEL_PAD)
    ns.Tooltip(no, "Never Ask", "The bar will not ask about this item again. Ask Again for "
        .. "Declined Items on its options page undoes it.")
    ask:Hide()
end

function ShowAsk()
    if InCombatLockdown() or not On() or not S.Get("consumableBarAskNew") then return end
    if ask and ask:IsShown() then return end
    local onBar = {}
    for _, id in ipairs(Items()) do onBar[id] = true end
    local id
    repeat id = table.remove(asking, 1) until not id or not onBar[id]
    if not id then return end
    if not ask then BuildAsk() end
    ask.itemID = id
    ask.icon.tex:SetTexture(C_Item.GetItemIconByID(id))
    ask.text:SetText(("Add %s to the Consumable Bar?"):format(ItemName(id)))
    ask:ClearAllPoints()
    if frame and frame:IsVisible() then
        ask:SetPoint("BOTTOM", frame, "TOP", 0, 14)
    else
        ask:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    ask:Show()
end

-- The first look this session only learns what the bags hold; after that, anything new asks.
local function CheckNewItems()
    if not S.Get("consumableBarAskNew") then known = nil return end
    local now = BagConsumables()
    if not known then
        known = {}
        for _, id in ipairs(now) do known[id] = true end
        return
    end
    local onBar = {}
    for _, id in ipairs(Items()) do onBar[id] = true end
    local declined = S.Get("consumableBarDeclined") or {}
    for _, id in ipairs(now) do
        if not known[id] and not onBar[id] and not declined[id] and Wanted(id) then asking[#asking + 1] = id end
        known[id] = true
    end
    ShowAsk()
end

-------------------------------------------------------------------------------
--  The card's preview: the bar at its real size, a + tile to add items, and drops
-------------------------------------------------------------------------------
local OpenItemPanel
local HidePopups
local PREVIEW_HINT = "Drag consumables onto it or click + to add; right-click an icon for its settings."

-- An item or consumable macro dropped on the preview goes before the icon it lands on, or at
-- the end. False when the cursor holds nothing the bar can take; an item that is no
-- consumable stays on the cursor.
local function Drop(at)
    local entry = Entry(GetCursorInfo())
    if entry == nil then return false end
    if type(entry) == "number" and not Category(entry) then
        SayNotConsumable({ ItemName(entry) })
        return true
    end
    ClearCursor()
    PlaceEntry(entry, at)
    return true
end

local function PreviewDrop(cell)
    Drop(not cell.isPlus and cell.index or nil)
end

local function PreviewClick(cell, mouse)
    if Drop(not cell.isPlus and cell.index or nil) then return end
    if cell.isPlus then ns.AddConsumableBarItems()
    elseif mouse == "RightButton" then OpenItemPanel(cell) end
end

local function PreviewEnter(cell)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    if cell.isPlus then
        GameTooltip:SetText("Add Items")
        GameTooltip:AddLine("Consumables by item ID or name, separated by commas. Or drag one from "
            .. "your bags onto the preview.", 1, 1, 1, true)
    else
        if cell.itemID then GameTooltip:SetItemByID(cell.itemID) else GameTooltip:SetText(EntryName(cell.entry)) end
        local flags, a, m = Flags(cell.entry), T.accent, T.muted
        if MacroInfo(cell.entry) then
            GameTooltip:AddLine("Runs the " .. MacroInfo(cell.entry).name .. " macro from Macros", a.r, a.g, a.b)
        end
        if flags.combat then GameTooltip:AddLine("Hidden in combat", a.r, a.g, a.b) end
        if flags.used then GameTooltip:AddLine("Hidden after use, out of combat", a.r, a.g, a.b) end
        GameTooltip:AddLine("Right-click for its settings", m.r, m.g, m.b)
    end
    GameTooltip:Show()
end

local function PreviewCell(i)
    local cell = preview.cells[i]
    if cell then return cell end
    cell = CreateFrame("Button", nil, preview.bar)
    MakeCell(cell)
    cell.plus = ns.Font(cell.overlay, 24, "OUTLINE", T.accent)
    cell.plus:SetPoint("CENTER")
    cell.plus:SetText("+")
    cell:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    cell:SetScript("OnClick", PreviewClick)
    cell:SetScript("OnReceiveDrag", PreviewDrop)
    cell:SetScript("OnEnter", PreviewEnter)
    cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    preview.cells[i] = cell
    return cell
end

-- On the card's studio stage, which is its background and edge.
local function NewPreview(parent)
    local box = CreateFrame("Frame", nil, parent)
    box.hint = ns.Font(box, 12, nil, T.muted)
    box.hint:SetPoint("TOPLEFT", 10, -8)
    box.hint:SetText(PREVIEW_HINT)
    -- The whole box takes a drop; the icons in it take one at their own place.
    box:EnableMouse(true)
    box:SetScript("OnReceiveDrag", function() Drop() end)
    box:SetScript("OnMouseUp", function() Drop() end)
    -- The bar at its real size; one wider than the page scrolls sideways with the wheel.
    box.view = CreateFrame("ScrollFrame", nil, box)
    box.view:SetPoint("TOPLEFT", 10, -PREVIEW_TOP)
    box.view:SetPoint("BOTTOMRIGHT", -10, PREVIEW_PAD - BG_PAD)
    box.child = CreateFrame("Frame", nil, box.view)
    box.view:SetScrollChild(box.child)
    box.view:SetScript("OnMouseWheel", function(self, delta)
        local range = self:GetHorizontalScrollRange() or 0
        self:SetHorizontalScroll(math.max(0, math.min(range, (self:GetHorizontalScroll() or 0) - delta * 40)))
    end)
    -- The card is laid out after the first draw, so it is drawn again once it has its width:
    -- drawn at 0 wide, the bar sat left of centre until the next change.
    box.view:SetScript("OnSizeChanged", function() RenderPreview() end)
    box.bar = CreateFrame("Frame", nil, box.child)
    box.cells = {}
    -- Counts follow the bags while the page is open.
    box:SetScript("OnShow", function(self) self:RegisterEvent("BAG_UPDATE_DELAYED") end)
    box:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        if panel then panel:Hide() end
        HidePopups()
    end)
    box:SetScript("OnEvent", function() RenderPreview() end)
    box:RegisterEvent("BAG_UPDATE_DELAYED")
    return box
end

-- How tall the preview box is for the bar as it is set now, + tile included.
local function PreviewHeight()
    local size, gap, grow, perRow = Grid()
    local _, h = BarSize(#Items() + 1, size, gap, grow, perRow)
    return PREVIEW_TOP + h + 2 * BG_PAD + PREVIEW_PAD
end

-- `force` draws it while the options page is still laying the card out, before it shows.
function RenderPreview(force)
    if not (preview and (force or preview:IsVisible())) then return end
    local items = Items()
    local size, gap, grow, perRow = Grid()
    local keys = KeyMap()
    for i, entry in ipairs(items) do
        local cell = PreviewCell(i)
        local item = Resolve(entry)
        cell.isPlus, cell.entry, cell.itemID, cell.index = nil, entry, item, i
        Position(cell, preview.bar, i, size, gap, grow, perRow)
        PlaceBackground(cell, i, #items, gap, grow, perRow)
        StyleCell(cell, entry, item, size)
        ShowCount(cell, item, 0.35)
        ShowCooldown(cell, item)
        ShowKey(cell, keys)
        cell.plus:Hide()
        cell:Show()
    end
    local plus = PreviewCell(#items + 1)
    plus.isPlus, plus.entry, plus.itemID, plus.empty, plus.index = true, nil, nil, nil, nil
    Position(plus, preview.bar, #items + 1, size, gap, grow, perRow)
    plus:SetSize(size, size)
    plus:SetAlpha(1)
    plus.icon:SetColorTexture(T.panel.r, T.panel.g, T.panel.b, 1)
    plus.icon:SetDesaturated(false)
    plus.count:Hide()
    plus.custom:Hide()
    plus.none:Hide()
    plus.key:Hide()
    plus.timer:Hide()
    plus.plus:SetFont(UI.FontPath(S.Get("consumableBarFont")), math.max(10, math.floor(size * 0.6)), "OUTLINE")
    plus.plus:Show()
    -- The + tile is not on the real bar, so it has no background.
    plus.bg:Hide()
    plus:Show()
    for i = #items + 2, #preview.cells do preview.cells[i]:Hide() end

    -- Always at its real size: centred when it fits, scrolled sideways when it does not.
    local w, h = BarSize(#items + 1, size, gap, grow, perRow)
    preview.bar:SetSize(w, h)
    local viewW = (preview:GetWidth() or 0) - 20
    if viewW <= 0 then viewW = 480 end
    local fullW = w + 2 * BG_PAD
    local wide = fullW > viewW
    preview.child:SetSize(math.max(fullW, viewW), h + 2 * BG_PAD)
    preview.bar:ClearAllPoints()
    preview.bar:SetPoint("CENTER", preview.child, "CENTER")
    preview.view:EnableMouseWheel(wide)
    if not wide then preview.view:SetHorizontalScroll(0) end
    preview.hint:SetText(wide and "Scroll the mouse wheel to see the rest; right-click an icon for its settings."
        or PREVIEW_HINT)
end

-------------------------------------------------------------------------------
--  An item's settings, opened by right-clicking it in the preview
-------------------------------------------------------------------------------
local PANEL_W, ROW_H = 320, 30

local function Item() return panel and panel.itemID end
local function Get(key) return Flags(Item())[key] end
local function Set(key) return function(value) SetFlag(Item(), key, value) end end

-- A popup's text box in the panel grey, a shade lighter than its own, as the dropdowns are.
local function PanelGrey(box)
    ns.Solid(box, "BORDER", T.panel, 1):SetAllPoints()
end

local function NewRow(owner, label, visible)
    local row = CreateFrame("Frame", nil, owner)
    row:SetHeight(ROW_H)
    row.label = ns.Font(row, 12, nil)
    row.label:SetPoint("LEFT", ROW_INSET, 0)
    row.label:SetText(label)
    row.visible = visible
    owner.rows[#owner.rows + 1] = row
    return row
end

local function Row(label, visible) return NewRow(panel, label, visible) end

-- Shows the rows that apply, top to bottom from `y`, and sizes the panel to them.
local function LayoutRows(owner, y)
    for _, row in ipairs(owner.rows) do
        if not row.visible or row.visible() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, y)
            row:SetPoint("TOPRIGHT", 0, y)
            row:Show()
            local c = row.control
            if c and c._refreshValue then c._refreshValue() end
            y = y - ROW_H
        else
            row:Hide()
        end
    end
    owner:SetHeight(-y + 8)
end

-- A popup panel in the house look: dark fill, accent border, a title and an X.
-- The Shared kit's panel (Parts.Panel): its hairline edge, the title in the accent and its x.
-- Rows start under its header.
local function NewPopup(width)
    local p = ns.Shared.Parts.Panel("")
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(200)
    p:SetToplevel(true)
    p:SetWidth(width)
    p.rows = {}
    p.top = -ns.Shared.Style.PANEL_HEADER
    return p
end

local function ToggleRow(label, key, visible)
    local row = Row(label, visible)
    row.control = UI.BuildToggleControl(row, nil, function() return Get(key) end, Set(key))
    row.control:SetPoint("RIGHT", -ROW_INSET, 0)
    return row
end

local function DropdownRow(label, key, values, order, fallback, visible)
    local row = Row(label, visible)
    row.control = UI.BuildDropdownControl(row, 150, nil, values, order,
        function() return Get(key) or fallback end, Set(key))
    row.control:SetPoint("RIGHT", -ROW_INSET, 0)
    return row
end

local function SliderRow(label, key, min, max, fallback, visible)
    local row = Row(label, visible)
    local track, box = UI.BuildSliderCore(row, 100, 4, 12, 40, 20, 11, 1, min, max, 1,
        function() return Get(key) or fallback end, Set(key))
    PanelGrey(box)
    box:SetPoint("RIGHT", -ROW_INSET, 0)
    track:SetPoint("RIGHT", box, "LEFT", -8, 0)
    row.control = track
    return row
end

local function HasCustom() return Item() ~= nil and CustomOn(Flags(Item())) end
local function UsesEffect() return Get("used") == true end

local function BuildPanel()
    panel = NewPopup(PANEL_W)
    -- The item's icon before the panel's title.
    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(16, 16)
    panel.icon:SetPoint("TOPLEFT", ROW_INSET, -ROW_INSET + 2)
    panel.title:ClearAllPoints()
    panel.title:SetPoint("LEFT", panel.icon, "RIGHT", 6, 0)
    panel.title:SetPoint("RIGHT", -34, 0)

    -- A key bound to the icon's own button, so it needs no action bar slot.
    local keyRow = Row("Key")
    keyRow.control = UI.KeyField(keyRow, function() return ns.ConsumableBarBindAction(Item()) end,
        function() return EntryName(Item()) .. " on the Consumable Bar" end,
        "Click, then press a key to use this icon with it. Escape cancels; right-click clears. "
            .. "The key stays with it wherever it sits on the bar.")
    keyRow.control:ClearAllPoints()
    keyRow.control:SetPoint("RIGHT", -ROW_INSET, 0)
    ToggleRow("Hide in Combat", "combat")
    ToggleRow("Hide After Use", "used", function()
        local item = Resolve(Item())
        return item ~= nil and ItemSpell(item) ~= nil
    end)
    DropdownRow("Tracks", "track", TRACK_VALUES, TRACK_ORDER, "buff", UsesEffect)
    ToggleRow("Show Before It Ends", "early", UsesEffect)
    -- The lead time: 15 second steps, from 0:15 to 30:00.
    local step = Row("Show With", function() return UsesEffect() and Get("early") == true end)
    step.value = ns.Font(step, 13, "OUTLINE", T.accent)
    local function Lead() return Get("earlySeconds") or EARLY_DEFAULT end
    local function Nudge(by)
        SetFlag(Item(), "earlySeconds", math.max(EARLY_MIN, math.min(EARLY_MAX, Lead() + by)))
    end
    local plus = ns.Button(step, "+", 24, 22, function() Nudge(EARLY_STEP) end)
    plus:SetPoint("RIGHT", -ROW_INSET, 0)
    step.value:SetPoint("RIGHT", plus, "LEFT", -10, 0)
    step.value:SetWidth(70)
    step.value:SetJustifyH("CENTER")
    local minus = ns.Button(step, "-", 24, 22, function() Nudge(-EARLY_STEP) end)
    minus:SetPoint("RIGHT", step.value, "LEFT", -10, 0)
    step.control = { _refreshValue = function() step.value:SetText(Clock(Lead()) .. " left") end }

    local head = Row("Custom Text")
    head.label:SetTextColor(T.accent.r, T.accent.g, T.accent.b, 1)
    head.control = UI.BuildToggleControl(head, nil, HasCustom, function(on) SetFlag(Item(), "textOn", on) end)
    head.control:SetPoint("RIGHT", -ROW_INSET, 0)
    local textRow = Row("Text", HasCustom)
    local box = ns.NewEditBox(textRow)
    PanelGrey(box)
    box:SetSize(180, 24)
    box:SetPoint("RIGHT", -ROW_INSET, 0)
    box:SetMaxLetters(20)
    -- Saved to the item it was typed for, even when another item's panel opens first.
    box:SetScript("OnEditFocusGained", function(self) self.editing = Item() end)
    local function Commit()
        local id = box.editing
        box.editing = nil
        if not id then return end
        local text = strtrim(box:GetText())
        if text ~= (Flags(id).text or "") then SetFlag(id, "text", text) end
        box:ClearFocus()
    end
    box:SetScript("OnEnterPressed", Commit)
    box:SetScript("OnEditFocusLost", Commit)
    box:SetScript("OnEscapePressed", function(self)
        self.editing = nil
        self:SetText(Get("text") or "")
        self:ClearFocus()
    end)
    textRow.control = { _refreshValue = function()
        if not box:HasFocus() then box:SetText(Get("text") or "") end
    end }

    panel.font = DropdownRow("Font", "textFont", {}, {}, "", HasCustom)
    SliderRow("Font Size", "textSize", 6, 40, 12, HasCustom)
    local colorRow = Row("Colour", HasCustom)
    colorRow.control = UI.BuildColorSwatchControl(colorRow, function()
        local c = Get("textColor") or WHITE
        return c.r, c.g, c.b
    end, function(r, g, b) SetFlag(Item(), "textColor", { r = r, g = g, b = b }) end)
    colorRow.control:SetPoint("RIGHT", -ROW_INSET, 0)
    DropdownRow("Position", "textPoint", POINT_VALUES, POINT_ORDER, "TOP", HasCustom)
    ToggleRow("Outside the Icon", "textOutside", HasCustom)
    SliderRow("X Offset", "textX", -50, 50, 0, HasCustom)
    SliderRow("Y Offset", "textY", -50, 50, 0, HasCustom)

    local remove = Row("")
    remove.control = ns.Button(remove, "Remove From Bar", 130, 24, function()
        local id = Item()
        panel:Hide()
        RemoveItem(id)
    end)
    remove.control:SetPoint("CENTER")
    panel:Hide()
end

-- Shows the rows that apply to this item, top to bottom, and sizes the panel to them.
local function LayoutPanel()
    if not (panel and panel:IsShown() and Item()) then return end
    local fonts, order = UI.FontChoices(Get("textFont"))
    fonts[""] = "Same as Count"
    local dd = panel.font.control
    dd._values, dd._order = fonts, order
    LayoutRows(panel, panel.top)
end

function OpenItemPanel(cell)
    if not panel then BuildPanel() end
    panel.itemID = cell.entry
    panel.icon:SetTexture(EntryIcon(cell.entry, cell.itemID))
    panel.title:SetText(EntryName(cell.entry))
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", cell, "BOTTOMLEFT", 0, -6)
    panel:Show()
    panel:Raise()
    LayoutPanel()
end

-------------------------------------------------------------------------------
--  Small settings popups, each opened under its cog on the card: Scan Filters, Count Text and
--  Keybind Text. A second click on the same cog closes it, and one open closes the others.
-------------------------------------------------------------------------------
local POPUP_W = 260
local popups = {}

local function Bound(key) return function() return S.Get(key) end, function(v) S.Set(key, v) end end

-- A row: { label, kind = "toggle" | "slider" | "colour" | "choice", get, set }, a slider's
-- min and max, and a choice's values() returning its values and order.
local function BuildPopup(title, specs)
    local p = NewPopup(POPUP_W)
    p.title:SetText(title)
    p.choices = {}
    for _, spec in ipairs(specs) do
        local row = NewRow(p, spec.label)
        local control
        if spec.kind == "toggle" then
            control = UI.BuildToggleControl(row, nil, spec.get, spec.set)
            control:SetPoint("RIGHT", -ROW_INSET, 0)
        elseif spec.kind == "slider" then
            local track, box = UI.BuildSliderCore(row, 90, 4, 12, 40, 20, 11, 1, spec.min, spec.max, 1,
                spec.get, spec.set)
            PanelGrey(box)
            box:SetPoint("RIGHT", -ROW_INSET, 0)
            track:SetPoint("RIGHT", box, "LEFT", -8, 0)
            control = track
        elseif spec.kind == "colour" then
            control = UI.BuildColorSwatchControl(row, function()
                local c = spec.get()
                return c.r, c.g, c.b
            end, function(r, g, b) spec.set({ r = r, g = g, b = b }) end)
            control:SetPoint("RIGHT", -ROW_INSET, 0)
        else
            control = UI.BuildDropdownControl(row, 140, nil, {}, {}, spec.get, spec.set)
            control:SetPoint("RIGHT", -ROW_INSET, 0)
            p.choices[control] = spec.values
        end
        row.control = control
    end
    p:Hide()
    return p
end

function HidePopups()
    for _, p in pairs(popups) do p:Hide() end
end

-- Opens the popup under `cog`, made the first time from title and specs().
local function TogglePopup(name, cog, title, specs)
    local p = popups[name]
    if not p then
        p = BuildPopup(title, specs())
        popups[name] = p
    end
    if p:IsShown() and p.owner == cog then p:Hide() return end
    for _, other in pairs(popups) do if other ~= p then other:Hide() end end
    p.owner = cog
    p.title:SetText(title)
    for dd, values in pairs(p.choices) do dd._values, dd._order = values() end
    p:ClearAllPoints()
    p:SetPoint("TOP", cog, "BOTTOM", 0, -4)
    p:Show()
    p:Raise()
    LayoutRows(p, p.top)
end
ns.ToggleConsumableBarPopup = TogglePopup

local function Points() return POINT_VALUES, POINT_ORDER end

-- The text settings both texts share: font, size, colour, where on the icon, and offsets.
local function TextSpecs(font, fonts, size, sizeMin, colour, point, outside, x, y)
    local function Spec(label, kind, key, extra)
        local get, set = Bound(key)
        local spec = { label = label, kind = kind, get = get, set = set }
        for k, v in pairs(extra or {}) do spec[k] = v end
        return spec
    end
    return {
        Spec("Font", "choice", font, { values = fonts }),
        Spec("Font Size", "slider", size, { min = sizeMin, max = 32 }),
        Spec("Colour", "colour", colour),
        Spec("Position", "choice", point, { values = Points }),
        Spec("Outside the Icon", "toggle", outside),
        Spec("X Offset", "slider", x, { min = -50, max = 50 }),
        Spec("Y Offset", "slider", y, { min = -50, max = 50 }),
    }
end

local function CountFonts() return UI.FontChoices(S.Get("consumableBarFont")) end

local function KeyFonts()
    local values, order = UI.FontChoices(S.Get("consumableBarKeyFont"))
    values[""] = "Same as Count"
    return values, order
end

function ns.ToggleConsumableBarKeyText(cog)
    TogglePopup("keys", cog, "Keybind Text", function()
        return TextSpecs("consumableBarKeyFont", KeyFonts, "consumableBarKeySize", 6, "consumableBarKeyColor",
            "consumableBarKeyPoint", "consumableBarKeyOutside", "consumableBarKeyX", "consumableBarKeyY")
    end)
end

function ns.ToggleConsumableBarCountText(cog)
    TogglePopup("count", cog, "Count Text", function()
        return TextSpecs("consumableBarFont", CountFonts, "consumableBarFontSize", 8, "consumableBarTextColor",
            "consumableBarTextPoint", "consumableBarTextOutside", "consumableBarTextX", "consumableBarTextY")
    end)
end

-- Which kinds Scan Bags adds and Ask to Add New Consumables asks about.
function ns.ToggleConsumableBarFilters(cog)
    TogglePopup("filters", cog, "Scan Filters", function()
        local specs = {}
        for _, category in ipairs(CATEGORY_ORDER) do
            specs[#specs + 1] = { label = CATEGORY_NAMES[category], kind = "toggle",
                get = function() return not (S.Get("consumableBarSkip") or {})[category] end,
                set = function(v)
                    local skip = {}
                    for k in pairs(S.Get("consumableBarSkip") or {}) do skip[k] = true end
                    skip[category] = not v or nil
                    S.Set("consumableBarSkip", skip)
                end }
        end
        return specs
    end)
end

-------------------------------------------------------------------------------
--  The anchor picker: the options window steps aside, the frame under the cursor is lit
--  with its name, and a click anchors the bar to it. A name can be typed instead.
-------------------------------------------------------------------------------
-- The nearest named frame at or above `focus` the bar can anchor to, and its name. Not the
-- screen itself, the bar, or the picker; frames the addon may not look at are skipped.
local function NamedFrame(focus)
    local node = focus
    while node and node ~= UIParent and node ~= WorldFrame do
        if node == frame or node == picker or node == picker.highlight then return nil end
        if node.IsForbidden and node:IsForbidden() then return nil end
        local n = node:GetName()
        if n and _G[n] == node then return node, n end
        node = node:GetParent()
    end
end

-- `keepAside` leaves the options window put away, for the on-screen editor to bring back.
local function StopPicking(keepAside)
    picker:SetScript("OnUpdate", nil)
    picker.box:ClearFocus()
    picker.highlight:Hide()
    picker:Hide()
    local stashed = picker.stashed
    picker.stashed = nil
    if stashed and not keepAside then ns.OpenOptionsWindow() end
    return stashed
end

local function Choose(name)
    local target = _G[name]
    if name ~= "UIParent" and not (type(target) == "table" and target.GetObjectType) then
        ns.Print("No frame called " .. name .. ". Frame names are case sensitive.")
        return
    end
    S.Set("consumableBarAnchor", name)
    if name == "UIParent" then
        ns.Print("Consumable Bar is back on the screen.")
        StopPicking()
        return
    end
    ns.Print("Consumable Bar anchored to " .. name .. ".")
    -- Set its points and offsets on screen next, where you can see them.
    ns.EditConsumableBarAnchor(StopPicking(true))
end

local function PickerUpdate(self)
    local target, name
    if not self:IsMouseOver() then
        local focus = GetMouseFoci()[1]
        if focus then target, name = NamedFrame(focus) end
    end
    if target ~= self.target then
        local light = self.highlight
        light:ClearAllPoints()
        if target and pcall(light.SetAllPoints, light, target) then
            light.text:SetText(name)
            light:Show()
        else
            light:Hide()
            target, name = nil, nil
        end
        self.target, self.name = target, name
    end
    local down = IsMouseButtonDown("LeftButton")
    if down and not self.down and self.target then Choose(self.name) end
    self.down = down
end

local function BuildPicker()
    local St = ns.Shared.Style
    picker = ns.Shared.Parts.Panel("Anchor the Consumable Bar")
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetSize(440, St.PANEL_HEADER + 14 + 10 + 26 + St.PANEL_PAD + 4)
    picker:SetPoint("TOP", UIParent, "TOP", 0, -120)
    -- Its x cancels, as Esc does.
    picker.close:SetScript("OnClick", function() StopPicking() end)
    local hint = ns.Font(picker, 12, nil, T.muted)
    hint:SetPoint("TOPLEFT", St.PANEL_PAD, -St.PANEL_HEADER)
    hint:SetText("Click a frame on screen, or type its name. Esc cancels.")
    picker.box = ns.NewEditBox(picker)
    picker.box:SetSize(220, 26)
    picker.box:SetPoint("BOTTOMLEFT", St.PANEL_PAD, St.PANEL_PAD)
    local function Typed()
        local text = strtrim(picker.box:GetText())
        if text ~= "" then Choose(text) end
    end
    picker.box:SetScript("OnEnterPressed", Typed)
    picker.box:SetScript("OnEscapePressed", function() StopPicking() end)
    ns.Button(picker, "Anchor", 86, 26, Typed):SetPoint("LEFT", picker.box, "RIGHT", 8, 0)
    ns.Button(picker, "Cancel", 86, 26, function() StopPicking() end):SetPoint("BOTTOMRIGHT", -ROW_INSET, ROW_INSET)
    picker:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        self:SetPropagateKeyboardInput(key ~= "ESCAPE")
        if key == "ESCAPE" then StopPicking() end
    end)

    local light = CreateFrame("Frame", nil, UIParent)
    light:SetFrameStrata("TOOLTIP")
    ns.Solid(light, "BACKGROUND", T.accent, 0.25):SetAllPoints()
    ns.Border(light, T.accent)
    light.text = ns.Font(light, 13, "OUTLINE", T.accent)
    light.text:SetPoint("BOTTOM", light, "TOP", 0, 4)
    light:Hide()
    picker.highlight = light
    picker:Hide()
end

function ns.PickConsumableBarAnchor()
    if not picker then BuildPicker() end
    picker.stashed = ns.StashOptionsWindow() or picker.stashed
    picker.target, picker.name = nil, nil
    picker.down = IsMouseButtonDown("LeftButton")
    local current = S.Get("consumableBarAnchor")
    picker.box:SetText(current ~= "UIParent" and current or "")
    if not InCombatLockdown() then
        picker:EnableKeyboard(true)
        picker:SetPropagateKeyboardInput(true)
    end
    picker:Show()
    picker:SetScript("OnUpdate", PickerUpdate)
end

-- The Macros module rewrote a macro: its icon shows the new item. Nothing protected changes.
local function RefreshMacros()
    local size = Grid()
    for _, button in ipairs(buttons) do
        if MacroInfo(button.entry) then
            button.itemID = Resolve(button.entry)
            StyleCell(button, button.entry, button.itemID, size)
        end
    end
    UpdateCounts()
    UpdateCooldowns()
    UpdateVisibility()
    RenderPreview()
end

-- The bar runs these macros, so they are switched on in Macros; the module then writes them,
-- and keeps one the bar uses even with its switch or the module off.
local function SyncMacros()
    local M = ns.MacroSettings
    if M and On() then
        for _, entry in ipairs(Items()) do
            local key = MacroKey(entry)
            if key and not M.Get(key) then M.Set(key, true) end
        end
    end
    if ns.UpdateManagedMacros then ns.UpdateManagedMacros() end
end

-------------------------------------------------------------------------------
--  Editing the anchor on screen: the options window steps aside, and a small panel next to
--  the bar sets its points and offsets while you watch it move. Done keeps them, Cancel puts
--  back what they were, and either brings the options window back.
-------------------------------------------------------------------------------
local ANCHOR_KEYS = { "consumableBarAnchorPoint", "consumableBarAnchorRelPoint", "consumableBarX", "consumableBarY" }
local anchorEditor

local function FinishAnchorEdit(keep)
    local e = anchorEditor
    if not (e and e.editing) then return end
    e.editing = nil
    if frame then frame.outline:Hide() end
    if not keep then
        for key, value in pairs(e.before) do S.Set(key, value) end
    end
    e:Hide()
    if e.stashed then
        e.stashed = nil
        ns.OpenOptionsWindow()
    end
end

local function BuildAnchorEditor()
    local function Spec(label, kind, key, extra)
        local spec = { label = label, kind = kind,
            get = function() return S.Get(key) end, set = function(v) S.Set(key, v) end }
        for k, v in pairs(extra or {}) do spec[k] = v end
        return spec
    end
    local points = function() return POINT_VALUES, POINT_ORDER end
    anchorEditor = BuildPopup("Anchor", {
        Spec("Bar Point", "choice", "consumableBarAnchorPoint", { values = points }),
        Spec("Frame Point", "choice", "consumableBarAnchorRelPoint", { values = points }),
        Spec("X Offset", "slider", "consumableBarX", { min = -500, max = 500 }),
        Spec("Y Offset", "slider", "consumableBarY", { min = -500, max = 500 }),
    })
    local e = anchorEditor
    e.done = ns.Button(e, "Done", 100, 24, function() FinishAnchorEdit(true) end)
    e.done:SetPoint("BOTTOMRIGHT", -ROW_INSET, ROW_INSET)
    e.cancel = ns.Button(e, "Cancel", 100, 24, function() FinishAnchorEdit(false) end)
    e.cancel:SetPoint("RIGHT", e.done, "LEFT", -8, 0)
    -- Its X keeps the changes, as Done does.
    e:HookScript("OnHide", function() FinishAnchorEdit(true) end)
end

-- `stashed` is true when the options window was already put away (by the anchor picker).
function ns.EditConsumableBarAnchor(stashed)
    if S.Get("consumableBarAnchor") == "UIParent" then return end
    if not anchorEditor then BuildAnchorEditor() end
    local e = anchorEditor
    if e.editing then return end
    e.before = {}
    for _, key in ipairs(ANCHOR_KEYS) do e.before[key] = S.Get(key) end
    e.stashed = ns.StashOptionsWindow() or stashed or false
    e.editing = true
    e.title:SetText("Anchored to " .. S.Get("consumableBarAnchor"))
    for dd, values in pairs(e.choices) do dd._values, dd._order = values() end
    e:ClearAllPoints()
    if frame then
        e:SetPoint("LEFT", frame, "RIGHT", 16, 0)
        frame.outline:Show()
    else
        e:SetPoint("CENTER")
    end
    e:Show()
    e:Raise()
    LayoutRows(e, e.top)
    e:SetHeight(e:GetHeight() + 36)
end

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local Apply

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        if pending then
            Apply()
        else
            UpdateCounts()
            UpdateVisibility()
        end
        ShowAsk()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Another addon's frame may only exist now, so the anchor is looked up again.
        Apply()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        UpdateVisibility()
    elseif event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then UpdateVisibility() end
    elseif event == "UPDATE_MACROS" then
        RefreshMacros()
    elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED"
        or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
        QueueKeys()
    else
        UpdateCounts()
        UpdateCooldowns()
        CheckNewItems()
    end
end)

function Apply()
    if InCombatLockdown() then
        pending = true
        events:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = nil
    events:UnregisterAllEvents()
    wakeGen = wakeGen + 1
    if not On() then
        known = nil
        if ask then ask:Hide() end
        if frame then
            Driver(frame, nil)
            frame:Hide()
        end
        SyncMacros()
        return
    end
    if not frame then Build() end
    Layout()
    Place()
    frame.mover:SetShown(unlocked == true)
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if HasMacros() then events:RegisterEvent("UPDATE_MACROS") end
    local hideUsed = AnyHideUsed()
    if S.Get("consumableBarCooldown") or hideUsed then events:RegisterEvent("BAG_UPDATE_COOLDOWN") end
    if hideUsed then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
    end
    if S.Get("consumableBarKeybinds") then
        events:RegisterEvent("UPDATE_BINDINGS")
        events:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        events:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
        events:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    end
    UpdateCounts()
    UpdateCooldowns()
    UpdateVisibility()
    QueueKeys()
    CheckNewItems()
    SyncMacros()
end

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or (key:find("^consumableBar") and key ~= "consumableBarPos") then
        Apply()
        RenderPreview()
        LayoutPanel()
    end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowRaidReminderAnchorConfig", function()
    unlocked = true
    Apply()
end)
hooksecurefunc(ns, "HideRaidReminderAnchorConfig", function()
    unlocked = false
    Apply()
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

-------------------------------------------------------------------------------
--  Its card on QoL > Loot & Items: the bar itself as its live preview, to add items to and
--  right-click for their settings, and its settings under it.
-------------------------------------------------------------------------------
local Settings = ns.Shared and ns.Shared.Settings
if not Settings then return end
local Group = Settings.Group
local DIRECTION = { { RIGHT = "Right", LEFT = "Left", UP = "Up", DOWN = "Down" }, { "RIGHT", "LEFT", "UP", "DOWN" } }
local POINT = { POINT_VALUES, POINT_ORDER }

-- The live preview is the bar's own editor: one moment, so no tabs.
local STATES = { { key = "bar", label = "Your Bar" } }

local function NewStudioPreview(stage)
    preview = NewPreview(stage)
    preview:SetAllPoints()
    return preview
end

local function PaintStudioPreview()
    RenderPreview(true)
end

-- The stage is the preview's own height, so the bar always shows at its real size.
local studio = setmetatable({ states = STATES, new = NewStudioPreview, paint = PaintStudioPreview }, {
    __index = function(_, k) if k == "height" then return PreviewHeight() end end,
})

local function BarSummary()
    local n = #Items()
    if n == 0 then return "No items yet" end
    return ("%d item%s"):format(n, n == 1 and "" or "s")
end

-- The Health cog's settings: a popup like the others, with the one dropdown. Picking a
-- priority closes it, and so does a second click on the cog.
local function ToggleHealthPriority(cog)
    local M, choices = ns.MacroSettings, ns.HealthOrderChoices
    if not (M and choices) then return end
    ns.ToggleConsumableBarPopup("health", cog, "Health Priority", function()
        return { { label = "Use First", kind = "choice",
            values = function() return choices.values, choices.order end,
            get = function() return M.Get("healthOrder") end,
            set = function(v)
                M.Set("healthOrder", v)
                HidePopups()
            end } }
    end)
end

local function MacroRow(key, label, help, cog)
    local name = ns.ConsumableMacros and ns.ConsumableMacros[key] and ns.ConsumableMacros[key].name or key
    return { label = label, toggle = true, cog = cog,
        help = help .. " Runs the " .. name .. " macro from Macros, which is switched on with it and stays "
            .. "while the bar uses it. Bind a key to it from its icon's right-click settings.",
        get = function() return ns.ConsumableBarHasMacro(key) end,
        set = function(v) ns.SetConsumableBarMacro(key, v) end }
end

local function Anchored() return S.Get("consumableBarAnchor") ~= "UIParent" end
local BACK_ICON = ns.Shared.Style.RESET
local NOT_ANCHORED = "Anchor it to a frame first"

local function Rows()
    local rows = {
        Group("Items"),
        { label = "Scan Bags", button = ns.ScanBagsForConsumableBar, buttonText = "Scan",
          cog = { tip = "Scan Filters: which kinds of consumable Scan Bags adds and Ask to Add asks about.",
                  open = function(cog) ns.ToggleConsumableBarFilters(cog) end },
          help = "Adds every consumable in your bags that is not on the bar yet. The cog picks which kinds: "
              .. "potions, elixirs, food and so on." },
        { label = "Remove All Items", button = ns.ClearConsumableBar, buttonText = "Clear",
          help = "Takes every item off the bar, after asking." },
        { key = "consumableBarAskNew", label = "Ask to Add New Consumables", toggle = true,
          help = "When a consumable you did not have lands in your bags, a small popup asks whether to add "
              .. "it. Out of combat only. No means it never asks about that item again." },
        { label = "Ask Again for Declined Items", button = ns.ForgetConsumableBarDeclined, buttonText = "Reset",
          help = "Ask to Add New Consumables asks again about the items you said no to." },
    }
    -- The macros are the Macros addon's: their rows only while it is loaded.
    if ns.ConsumableMacros then
        for _, row in ipairs({
            Group("Consumable Macros"),
            MacroRow("health", "Health", "The best healthstone or healing potion.",
                { tip = "Priority: healthstone or potion first. Shared with the NF Health macro.",
                  open = ToggleHealthPriority }),
            MacroRow("mana", "Mana Potion", "The best mana potion."),
            MacroRow("food", "Food & Drink", "The best food and drink, conjured first. One click eats and drinks."),
            MacroRow("bandage", "Bandage", "The best bandage, used on yourself."),
        }) do rows[#rows + 1] = row end
    end
    for _, row in ipairs({
        Group("Layout"),
        { key = "consumableBarSize", label = "Icon Size", slider = { 20, 64, 1 } },
        { key = "consumableBarSpacing", label = "Spacing", slider = { 0, 20, 1 } },
        { key = "consumableBarGrow", label = "Growth Direction", choice = DIRECTION },
        { key = "consumableBarPerRow", label = "Icons Per Row", slider = { 1, 24, 1 },
          help = "How many icons a row holds before a new row starts below it. A bar growing up or down "
              .. "fills columns instead, each new one to the right." },
        { key = "consumableBarCooldown", label = "Show Cooldowns", toggle = true,
          help = "The item's cooldown sweeps over its icon, as on an action button." },
        { key = "consumableBarTooltip", label = "Item Tooltips", toggle = true,
          help = "Hover an icon for the item's tooltip." },
        { key = "consumableBarShowCount", label = "Show Count", toggle = true,
          cog = { tip = "Count text: font, size, colour and position.",
                  open = function(cog) ns.ToggleConsumableBarCountText(cog) end },
          help = "How many you carry, on each icon. The cog sets its font, size, colour and position." },
        { key = "consumableBarHideEmpty", label = "Hide When Out", toggle = true,
          help = "An item you have none of left hides instead of showing NONE. It keeps its place, and comes "
              .. "back as soon as you have one again." },
        { key = "consumableBarKeybinds", label = "Show Keybinds", toggle = true,
          cog = { tip = "Keybind text: font, size, colour and position.",
                  open = function(cog) ns.ToggleConsumableBarKeyText(cog) end },
          help = "The key that uses the item: one bound to its icon (from its right-click settings), or the "
              .. "key of a button holding it on your action bars, from Blizzard's bars, EllesmereUI, and bars "
              .. "built on Blizzard's buttons or LibActionButton. The cog sets the key's font, size, colour "
              .. "and position." },
        { key = "consumableBarHideCombat", label = "Hide Bar in Combat", toggle = true,
          help = "Hides the whole bar while you are in combat, whatever each icon's own settings say." },
        { key = "consumableBarBackground", label = "Show Background", toggle = true,
          help = "A dark panel behind the icons." },
        { key = "consumableBarBgAlpha", label = "Background Opacity", slider = { 0, 100, 5 }, unit = "%",
          scale = 0.01, needs = "consumableBarBackground" },
        Group("Anchor"),
        { label = "Anchor to a Frame", button = function() ns.PickConsumableBarAnchor() end, buttonText = "Choose",
          icons = {
              { texture = BACK_ICON, enabled = Anchored, open = function() S.Set("consumableBarAnchor", "UIParent") end,
                tip = "Back to the screen. Dragging the bar in Unlock Mode does this as well." },
              { enabled = Anchored, open = function() ns.EditConsumableBarAnchor() end,
                tip = "Edit on screen: the options step aside and a small panel next to the bar sets its "
                    .. "points and offsets while you watch." },
          },
          help = "Steps the options window aside so you can click a frame on screen, such as your player frame, "
              .. "or type a frame's name; then set its points and offsets next to the bar." },
        { key = "consumableBarAnchor", label = "Anchored To", text = true,
          help = "The frame's name, or UIParent for the screen. A name that matches no frame puts the bar back "
              .. "on the screen." },
        { key = "consumableBarAnchorPoint", label = "Bar Point", choice = POINT, needs = Anchored, why = NOT_ANCHORED,
          help = "The point of the bar that attaches." },
        { key = "consumableBarAnchorRelPoint", label = "Frame Point", choice = POINT, needs = Anchored,
          why = NOT_ANCHORED, help = "The point of the anchor frame it attaches to." },
        { key = "consumableBarX", label = "X Offset", slider = { -500, 500, 1 }, needs = Anchored, why = NOT_ANCHORED },
        { key = "consumableBarY", label = "Y Offset", slider = { -500, 500, 1 }, needs = Anchored, why = NOT_ANCHORED },
    }) do rows[#rows + 1] = row end
    return rows
end

Settings.Page("QoL/Loot & Items", S):Card({
    id = "consumableBar", name = "Consumable Bar", order = 55, switch = "consumableBar",
    help = "The consumables you pick as a row of icons with how many are in your bags; click one to use it. "
        .. "An item you are out of turns grey with NONE in red. Changes made in combat apply when the fight "
        .. "ends. Move it in Unlock Mode.",
    summary = BarSummary,
    studio = studio,
    rows = Rows,
})
