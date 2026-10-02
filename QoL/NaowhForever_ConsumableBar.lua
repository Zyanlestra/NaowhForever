-------------------------------------------------------------------------------
--  NaowhForever_ConsumableBar.lua -- the QoL consumable bar: a row of the items the player
--  picks, each showing how many are in the bags, click to use. An item the bags are out of
--  turns grey with NONE in red, or hides. The options page draws a preview of it to add
--  items to, by ID or by dropping them on it, and open each item's settings from, and a
--  picker to anchor it to a frame on screen.
--  A new consumable in the bags can ask to be added. An entry can also be a consumable
--  pick (Health, Mana Potion, Food & Drink, Bandage), which uses the best item of its kind in
--  the bags through macro text.
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
local BG_PAD = 3          -- how far the background reaches past the icons
local GCD = 1.5           -- a cooldown this short is the global cooldown, not the item's own
local CONSUMABLE_CLASS = 0
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
-- them under different subclasses, so the classic ones are also known by ID.
local CATEGORY_ORDER = { "potion", "elixir", "flask", "scroll", "food", "bandage", "weapon",
    "healthstone", "other" }
local CATEGORY_NAMES = { potion = "Potions", elixir = "Elixirs", flask = "Flasks", scroll = "Scrolls",
    food = "Food & Drink", bandage = "Bandages", weapon = "Weapon Enhancements",
    healthstone = "Healthstones", other = "Other Consumables" }
local SUBCLASS_CATEGORY = { [1] = "potion", [2] = "elixir", [3] = "flask", [4] = "scroll",
    [5] = "food", [6] = "weapon", [7] = "bandage" }
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

-------------------------------------------------------------------------------
--  Consumable picks: the best item of a kind in the bags, used through macro text on the
--  icon's button. Classic-era item IDs, best first.
-------------------------------------------------------------------------------
local MANA_POTIONS = { 13444, 13443, 6149, 3827, 3385, 2455 }
local BANDAGES = { 14530, 14529, 8545, 8544, 6451, 6450, 3531, 3530, 2581, 1251 }
local CONJURED = {
    [8079] = true, [8078] = true, [8077] = true, [3772] = true, [2136] = true, [2288] = true,
    [5350] = true, [22895] = true, [8076] = true, [8075] = true, [1487] = true, [1114] = true,
    [1113] = true, [5349] = true,
}
local FOOD_SPELL, DRINK_SPELL = 433, 430
local HEALTH_ORDER_VALUES = { stone = "Healthstone First", potion = "Potion First" }
local HEALTH_ORDER_ORDER = { "stone", "potion" }
-- The options page's Health cog offers the same choice.
ns.ConsumableBarHealthOrder = { values = HEALTH_ORDER_VALUES, order = HEALTH_ORDER_ORDER }

local function FirstCarried(list)
    for _, id in ipairs(list or {}) do
        if C_Item.GetItemCount(id) > 0 then return id end
    end
end

-- Best food and best drink in the bags: conjured first, then the highest required level.
local function BestFoodAndDrink()
    local foodName, drinkName = C_Spell.GetSpellName(FOOD_SPELL), C_Spell.GetSpellName(DRINK_SPELL)
    local best, score = {}, {}
    for bag = 0, NUM_BAG_SLOTS do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local id = C_Container.GetContainerItemID(bag, slot)
            local spell = id and C_Item.GetItemSpell(id)
            local kind = (spell == foodName and "food") or (spell == drinkName and "drink")
            if kind then
                local s = (CONJURED[id] and 1000 or 0) + (select(5, C_Item.GetItemInfo(id)) or 0)
                if not score[kind] or s > score[kind] then best[kind], score[kind] = id, s end
            end
        end
    end
    return best.food, best.drink
end

-- Macro text that uses each item given, nil when there is none.
local function UseLines(...)
    local lines = { "#showtooltip" }
    for i = 1, select("#", ...) do
        local line = select(i, ...)
        if line then lines[#lines + 1] = line end
    end
    if #lines == 1 then return end
    return table.concat(lines, "\n")
end

local function ItemLine(id, prefix)
    return id and ("/use " .. (prefix or "") .. "item:" .. id)
end

local PICKS = {
    health = { label = "Health", icon = 134829, body = function()
        local stone, potion = FirstCarried(ns.HEALTHSTONES), FirstCarried(ns.HEALING_POTIONS)
        if S.Get("consumableBarHealthOrder") == "potion" then return UseLines(ItemLine(potion or stone)) end
        return UseLines(ItemLine(stone or potion))
    end },
    mana = { label = "Mana Potion", icon = 134855, body = function()
        return UseLines(ItemLine(FirstCarried(MANA_POTIONS)))
    end },
    food = { label = "Food & Drink", icon = 133971, body = function()
        local food, drink = BestFoodAndDrink()
        return UseLines(ItemLine(food), ItemLine(drink))
    end },
    bandage = { label = "Bandage", icon = 133682, body = function()
        return UseLines(ItemLine(FirstCarried(BANDAGES), "[@player] "))
    end },
}

-- An entry is an item ID, or "macro:<key>" for a consumable pick.
local function MacroInfo(entry)
    local key = type(entry) == "string" and entry:match("^macro:(%a+)$")
    return key and PICKS[key]
end

-- The item an entry uses now, nil when the bags hold none of a macro's items; for a macro,
-- its text as well.
local function Resolve(entry)
    local info = MacroInfo(entry)
    if not info then
        if type(entry) == "number" then return entry end
        return nil
    end
    local body = info.body()
    return body and tonumber(body:match("item:(%d+)")), body
end

local function EntryName(entry)
    local info = MacroInfo(entry)
    if info then return info.label .. " (Best in Bags)" end
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

function ns.AddConsumableBarItems()
    ns.PromptText("Item IDs or names, separated by commas", "", 0, function(text)
        local ids, missing = ns.ParseConsumableBarItems(text)
        if ids then AddItems(ids) end
        if missing and #missing > 0 then
            ns.Print("No item called " .. table.concat(missing, ", ") .. " in your bags or loaded by "
                .. "the game. Try its ID, or shift-click it into the box.")
        elseif not ids then
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

-- Switched from the options page: the pick joins the end of the bar, or leaves it.
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
    cell.count:SetShown(count > 0)
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
    if hotkey and not Secret(hotkey) and hotkey ~= "" and hotkey ~= RANGE_INDICATOR then return hotkey end
    local name = btn.GetName and btn:GetName()
    if Secret(name) then name = nil end
    local binding = btn.GetAttribute and btn:GetAttribute("binding")
    for _, command in ipairs({ btn.bindingAction or false, btn.commandName or false, binding or false,
        name and ("CLICK " .. name .. ":LeftButton") or false, name and ("CLICK " .. name .. ":Keybind") or false }) do
        if type(command) == "string" and not Secret(command) then
            local key = GetBindingKey(command)
            if key then return GetBindingText(key, true) end
        end
    end
end

-- An item on an action slot or the cursor, as a bar entry: its ID.
local function Entry(kind, id)
    if kind == "item" and type(id) == "number" then return id end
end

-- What an action slot holds, as a bar entry.
local function SlotEntry(slot)
    if not slot or Secret(slot) then return end
    local kind, id = GetActionInfo(slot)
    if Secret(id) then return end
    return Entry(kind, id)
end

local function KeyMap()
    local keys, hidden = {}, {}
    if not S.Get("consumableBarKeybinds") then return keys end
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
        local ok, all = pcall(function() return lab and lab.GetAllButtons and lab:GetAllButtons() end)
        for k, v in pairs(ok and type(all) == "table" and all or {}) do
            local btn = type(k) == "table" and k or v
            local got, kind, action = pcall(function() return btn:GetAction() end)
            if got and kind == "action" then Note(btn, SlotEntry(action))
            elseif got and kind == "item" then Note(btn, tonumber(tostring(action):match("(%d+)"))) end
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
local function EffectLeft(itemID, flags)
    local track = flags.track or "buff"
    if track == "buff" then
        if C_Secrets.ShouldAurasBeSecret() then return nil, true end
        local spell = ItemSpell(itemID)
        local aura = spell and C_UnitAuras.GetPlayerAuraBySpellID(spell)
        if not aura then return nil end
        local expires = aura.expirationTime
        if Secret(expires) then return nil, true end
        if not expires or expires == 0 then return math.huge end
        return expires - GetTime()
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
local function ShowTooltip(button)
    if not S.Get("consumableBarTooltip") or button.entry == nil or button.empty then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    if button.itemID then GameTooltip:SetItemByID(button.itemID) else GameTooltip:SetText(EntryName(button.entry)) end
    GameTooltip:Show()
end

local function Button(i)
    local button = buttons[i]
    if button then return button end
    button = CreateFrame("Button", nil, frame, "SecureActionButtonTemplate")
    button:RegisterForClicks("AnyUp", "AnyDown")
    MakeCell(button)
    button:SetScript("OnEnter", ShowTooltip)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    buttons[i] = button
    return button
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverConsumableBar", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    -- Dragging it places it on the screen again, as the Co-Tank frame does.
    frame.mover = UI.AttachMover(frame, "Consumable Bar", function(pos)
        S.Set("consumableBarPos", pos)
        S.Set("consumableBarAnchor", "UIParent")
    end)
end

-- Out of combat only.
local function Layout()
    local items = Items()
    local size, gap, grow, perRow = Grid()
    for i, entry in ipairs(items) do
        local button = Button(i)
        local item, body = Resolve(entry)
        Position(button, frame, i, size, gap, grow, perRow)
        PlaceBackground(button, i, #items, gap, grow, perRow)
        StyleCell(button, entry, item, size)
        button.entry, button.itemID = entry, item
        -- A macro pick runs the macro's own text, so it needs no macro slot of its own.
        if body then
            button:SetAttribute("type1", "macro")
            button:SetAttribute("macrotext1", body)
            button:SetAttribute("item1", nil)
        else
            button:SetAttribute("type1", item and "item" or nil)
            button:SetAttribute("item1", item and ("item:" .. item) or nil)
            button:SetAttribute("macrotext1", nil)
        end
    end
    for i = #items + 1, #buttons do
        local button = buttons[i]
        UnregisterStateDriver(button, "visibility")
        button.entry, button.itemID, button.spent = nil, nil, nil
        button:SetAttribute("type1", nil)
        button:SetAttribute("item1", nil)
        button:SetAttribute("macrotext1", nil)
        button:Hide()
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

local function UpdateCounts()
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then ShowCount(button, button.itemID, 0) end
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

local function Driver(f, rule)
    if rule then
        RegisterStateDriver(f, "visibility", rule)
    else
        UnregisterStateDriver(f, "visibility")
    end
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
    ask = CreateFrame("Frame", nil, UIParent)
    ask:SetFrameStrata("DIALOG")
    ask:SetSize(340, 86)
    ask:SetClampedToScreen(true)
    ask:EnableMouse(true)
    ns.Solid(ask, "BACKGROUND", T.bg, 0.96):SetAllPoints()
    ns.Border(ask, T.accent)
    ask.icon = CreateFrame("Button", nil, ask)
    ask.icon:SetSize(36, 36)
    ask.icon:SetPoint("TOPLEFT", 12, -12)
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
    ask.text:SetPoint("RIGHT", -12, 0)
    ask.text:SetJustifyH("LEFT")
    ns.Button(ask, "Add", 90, 24, function()
        ask:Hide()
        AddItems({ ask.itemID })
        ShowAsk()
    end):SetPoint("BOTTOMRIGHT", ask, "BOTTOM", -4, 10)
    local no = ns.Button(ask, "No", 90, 24, function()
        local declined = {}
        for id in pairs(S.Get("consumableBarDeclined") or {}) do declined[id] = true end
        declined[ask.itemID] = true
        ask:Hide()
        S.Set("consumableBarDeclined", declined)
        ShowAsk()
    end)
    no:SetPoint("BOTTOMLEFT", ask, "BOTTOM", 4, 10)
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
--  The options page preview
-------------------------------------------------------------------------------
local OpenItemPanel
local keyPanel
local PREVIEW_HINT = "Preview. Drag items onto it or click + to add; right-click an icon for its settings."

-- An item dropped on the preview goes before the icon it lands on, or at the end. False when
-- the cursor holds no item.
local function Drop(at)
    local entry = Entry(GetCursorInfo())
    if entry == nil then return false end
    ClearCursor()
    PlaceEntry(entry, at)
    return true
end

local function PreviewDrop(cell)
    Drop(not cell.isPlus and cell.index or nil)
end

local function PreviewClick(cell)
    if Drop(not cell.isPlus and cell.index or nil) then return end
    if cell.isPlus then ns.AddConsumableBarItems() else OpenItemPanel(cell) end
end

local function PreviewEnter(cell)
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    if cell.isPlus then
        GameTooltip:SetText("Add Items")
        GameTooltip:AddLine("Item IDs or names, separated by commas. Or drag an item from your "
            .. "bags onto the preview.", 1, 1, 1, true)
    else
        if cell.itemID then GameTooltip:SetItemByID(cell.itemID) else GameTooltip:SetText(EntryName(cell.entry)) end
        local flags, a, m = Flags(cell.entry), T.accent, T.muted
        if MacroInfo(cell.entry) then
            GameTooltip:AddLine("The best " .. MacroInfo(cell.entry).label .. " item in your bags", a.r, a.g, a.b)
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

local function NewPreview(parent)
    local box = CreateFrame("Frame", nil, parent)
    ns.Solid(box, "BACKGROUND", T.bg, 0.6):SetAllPoints()
    ns.Border(box, T.line)
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
    box.bar = CreateFrame("Frame", nil, box.child)
    box.cells = {}
    -- Counts follow the bags while the page is open.
    box:SetScript("OnShow", function(self) self:RegisterEvent("BAG_UPDATE_DELAYED") end)
    box:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        if panel then panel:Hide() end
        if keyPanel then keyPanel:Hide() end
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

-- A bar that grew or shrank needs the page laid out again around the box; once per frame.
local relayoutQueued
local function QueueRelayout()
    if relayoutQueued then return end
    relayoutQueued = true
    C_Timer.After(0, function()
        relayoutQueued = nil
        if preview and preview:IsVisible() and UI.RefreshPage then UI:RefreshPage(true) end
    end)
end

function RenderPreview()
    if not (preview and preview:IsVisible()) then return end
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
    preview.hint:SetText(wide and "Preview. Scroll the mouse wheel to see the rest; right-click an icon for its settings."
        or PREVIEW_HINT)
    if math.abs((preview:GetHeight() or 0) - PreviewHeight()) > 0.5 then QueueRelayout() end
end

-- The preview block for the options page, between its rows; returns the height it takes.
function ns.BuildConsumableBarPreview(parent, y)
    if UI.searchScan then return 0 end
    local box = UI.Keep(parent, "consumableBarPreview", NewPreview)
    if parent._nsuiCollapsed then box:Hide() return 0 end
    box:SetPoint("TOPLEFT", parent, "TOPLEFT", UI.CONTENT_PAD + 20, y - 4)
    box:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -UI.CONTENT_PAD - 20, y - 4)
    local height = PreviewHeight()
    box:SetHeight(height)
    preview = box
    RenderPreview()
    return height + 12
end

-------------------------------------------------------------------------------
--  An item's settings, opened by right-clicking it in the preview
-------------------------------------------------------------------------------
local PANEL_W, ROW_H = 320, 30

local function Item() return panel and panel.itemID end
local function Get(key) return Flags(Item())[key] end
local function Set(key) return function(value) SetFlag(Item(), key, value) end end

local function NewRow(owner, label, visible)
    local row = CreateFrame("Frame", nil, owner)
    row:SetHeight(ROW_H)
    row.label = ns.Font(row, 12, nil)
    row.label:SetPoint("LEFT", 12, 0)
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
local function NewPopup(width)
    local p = CreateFrame("Frame", nil, UIParent)
    p:SetFrameStrata("DIALOG")
    p:SetFrameLevel(200)
    p:SetToplevel(true)
    p:SetWidth(width)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    ns.Solid(p, "BACKGROUND", T.bg, 0.98):SetAllPoints()
    ns.Border(p, T.accent)
    p.rows = {}
    p.title = ns.Font(p, 14, "OUTLINE")
    p.title:SetPoint("TOPLEFT", 12, -14)
    p.title:SetPoint("RIGHT", -40, 0)
    p.title:SetJustifyH("LEFT")
    p.title:SetWordWrap(false)
    ns.Button(p, "X", 22, 22, function() p:Hide() end):SetPoint("TOPRIGHT", -8, -8)
    return p
end

local function ToggleRow(label, key, visible)
    local row = Row(label, visible)
    row.control = UI.BuildToggleControl(row, nil, function() return Get(key) end, Set(key))
    row.control:SetPoint("RIGHT", -12, 0)
    return row
end

local function DropdownRow(label, key, values, order, fallback, visible)
    local row = Row(label, visible)
    row.control = UI.BuildDropdownControl(row, 150, nil, values, order,
        function() return Get(key) or fallback end, Set(key))
    row.control:SetPoint("RIGHT", -12, 0)
    return row
end

local function SliderRow(label, key, min, max, fallback, visible)
    local row = Row(label, visible)
    local track, box = UI.BuildSliderCore(row, 100, 4, 12, 40, 20, 11, 1, min, max, 1,
        function() return Get(key) or fallback end, Set(key))
    box:SetPoint("RIGHT", -12, 0)
    track:SetPoint("RIGHT", box, "LEFT", -8, 0)
    row.control = track
    return row
end

local function HasCustom() return Item() ~= nil and CustomOn(Flags(Item())) end
local function UsesEffect() return Get("used") == true end

local function BuildPanel()
    panel = NewPopup(PANEL_W)
    panel.icon = panel:CreateTexture(nil, "ARTWORK")
    panel.icon:SetSize(24, 24)
    panel.icon:SetPoint("TOPLEFT", 12, -10)
    panel.title:ClearAllPoints()
    panel.title:SetPoint("LEFT", panel.icon, "RIGHT", 8, 0)
    panel.title:SetPoint("RIGHT", -40, 0)

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
    plus:SetPoint("RIGHT", -12, 0)
    step.value:SetPoint("RIGHT", plus, "LEFT", -10, 0)
    step.value:SetWidth(70)
    step.value:SetJustifyH("CENTER")
    local minus = ns.Button(step, "-", 24, 22, function() Nudge(-EARLY_STEP) end)
    minus:SetPoint("RIGHT", step.value, "LEFT", -10, 0)
    step.control = { _refreshValue = function() step.value:SetText(Clock(Lead()) .. " left") end }

    local head = Row("Custom Text")
    head.label:SetTextColor(T.accent.r, T.accent.g, T.accent.b, 1)
    head.control = UI.BuildToggleControl(head, nil, HasCustom, function(on) SetFlag(Item(), "textOn", on) end)
    head.control:SetPoint("RIGHT", -12, 0)
    local textRow = Row("Text", HasCustom)
    local box = ns.NewEditBox(textRow)
    -- The panel color, a shade lighter than the edit box's own, as the dropdowns are.
    ns.Solid(box, "BORDER", T.panel, 1):SetAllPoints()
    box:SetSize(180, 24)
    box:SetPoint("RIGHT", -12, 0)
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
    colorRow.control:SetPoint("RIGHT", -12, 0)
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
    LayoutRows(panel, -42)
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
--  The keybind text's settings, opened from the cog on Show Keybinds
-------------------------------------------------------------------------------
local KEY_W = 260

local function KeySetting(key) return function() return S.Get(key) end, function(v) S.Set(key, v) end end

local function BuildKeyPanel()
    keyPanel = NewPopup(KEY_W)
    keyPanel.title:SetText("Keybind Text")
    local function Add(label, build)
        local row = NewRow(keyPanel, label)
        row.control = build(row)
        return row
    end
    keyPanel.font = Add("Font", function(row)
        local get, set = KeySetting("consumableBarKeyFont")
        local dd = UI.BuildDropdownControl(row, 140, nil, {}, {}, get, set)
        dd:SetPoint("RIGHT", -12, 0)
        return dd
    end)
    local function Slider(label, key, min, max)
        Add(label, function(row)
            local get, set = KeySetting(key)
            local track, box = UI.BuildSliderCore(row, 90, 4, 12, 40, 20, 11, 1, min, max, 1, get, set)
            box:SetPoint("RIGHT", -12, 0)
            track:SetPoint("RIGHT", box, "LEFT", -8, 0)
            return track
        end)
    end
    Slider("Font Size", "consumableBarKeySize", 6, 32)
    Add("Colour", function(row)
        local swatch = UI.BuildColorSwatchControl(row, function()
            local c = S.Get("consumableBarKeyColor")
            return c.r, c.g, c.b
        end, function(r, g, b) S.Set("consumableBarKeyColor", { r = r, g = g, b = b }) end)
        swatch:SetPoint("RIGHT", -12, 0)
        return swatch
    end)
    Add("Position", function(row)
        local get, set = KeySetting("consumableBarKeyPoint")
        local dd = UI.BuildDropdownControl(row, 140, nil, POINT_VALUES, POINT_ORDER, get, set)
        dd:SetPoint("RIGHT", -12, 0)
        return dd
    end)
    Add("Outside the Icon", function(row)
        local get, set = KeySetting("consumableBarKeyOutside")
        local toggle = UI.BuildToggleControl(row, nil, get, set)
        toggle:SetPoint("RIGHT", -12, 0)
        return toggle
    end)
    Slider("X Offset", "consumableBarKeyX", -50, 50)
    Slider("Y Offset", "consumableBarKeyY", -50, 50)
    keyPanel:Hide()
end

-- Opens under the cog; a second click on the same cog closes it.
function ns.ToggleConsumableBarKeyText(cog)
    if not keyPanel then BuildKeyPanel() end
    if keyPanel:IsShown() and keyPanel.owner == cog then keyPanel:Hide() return end
    keyPanel.owner = cog
    local fonts, order = UI.FontChoices(S.Get("consumableBarKeyFont"))
    fonts[""] = "Same as Count"
    local dd = keyPanel.font.control
    dd._values, dd._order = fonts, order
    keyPanel:ClearAllPoints()
    keyPanel:SetPoint("TOP", cog, "BOTTOM", 0, -4)
    keyPanel:Show()
    keyPanel:Raise()
    LayoutRows(keyPanel, -42)
end

-------------------------------------------------------------------------------
--  The anchor picker: the options window steps aside, the frame under the cursor is lit
--  with its name, and a click anchors the bar to it. A name can be typed instead.
-------------------------------------------------------------------------------
-- The nearest named frame at or above `focus` the bar can anchor to, and its name. Not the
-- screen itself, the bar, or the picker; frames the addon may not look at are skipped.
local function NamedFrame(focus)
    local ok, target, name = pcall(function()
        local node = focus
        while node and node ~= UIParent and node ~= WorldFrame do
            if node == frame or node == picker or node == picker.highlight then return nil end
            if node.IsForbidden and node:IsForbidden() then return nil end
            local n = node:GetName()
            if n and not Secret(n) and _G[n] == node then return node, n end
            node = node:GetParent()
        end
    end)
    if ok then return target, name end
end

local function StopPicking()
    picker:SetScript("OnUpdate", nil)
    picker.box:ClearFocus()
    picker.highlight:Hide()
    picker:Hide()
    if picker.stashed then
        picker.stashed = nil
        ns.OpenOptionsWindow()
    end
end

local function Choose(name)
    local target = _G[name]
    if name ~= "UIParent" and not (type(target) == "table" and target.GetObjectType) then
        ns.Print("No frame called " .. name .. ". Frame names are case sensitive.")
        return
    end
    S.Set("consumableBarAnchor", name)
    ns.Print(name == "UIParent" and "Consumable Bar is back on the screen."
        or ("Consumable Bar anchored to " .. name .. "."))
    StopPicking()
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
    picker = CreateFrame("Frame", nil, UIParent)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")
    picker:SetSize(440, 116)
    picker:SetPoint("TOP", UIParent, "TOP", 0, -120)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    ns.Solid(picker, "BACKGROUND", T.bg, 0.96):SetAllPoints()
    ns.Border(picker, T.accent)
    local title = ns.Font(picker, 14, "OUTLINE", T.accent)
    title:SetPoint("TOP", 0, -12)
    title:SetText("Anchor the Consumable Bar")
    local hint = ns.Font(picker, 12, nil, T.muted)
    hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
    hint:SetText("Click a frame on screen, or type its name. Esc cancels.")
    picker.box = ns.NewEditBox(picker)
    picker.box:SetSize(220, 26)
    picker.box:SetPoint("BOTTOMLEFT", 14, 14)
    local function Typed()
        local text = strtrim(picker.box:GetText())
        if text ~= "" then Choose(text) end
    end
    picker.box:SetScript("OnEnterPressed", Typed)
    picker.box:SetScript("OnEscapePressed", StopPicking)
    ns.Button(picker, "Anchor", 86, 26, Typed):SetPoint("LEFT", picker.box, "RIGHT", 8, 0)
    ns.Button(picker, "Cancel", 86, 26, StopPicking):SetPoint("BOTTOMRIGHT", -14, 14)
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

-------------------------------------------------------------------------------
--  Wiring
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
local Apply

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        -- A macro pick whose item changed mid-fight is rebuilt now.
        if pending or HasMacros() then Apply() else UpdateVisibility() end
        ShowAsk()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Another addon's frame may only exist now, so the anchor is looked up again.
        Apply()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        UpdateVisibility()
    elseif event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then UpdateVisibility() end
    elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED"
        or event == "ACTIONBAR_PAGE_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR" then
        QueueKeys()
    else
        -- A macro pick follows the bags, but its button can only change out of combat.
        if HasMacros() and not InCombatLockdown() then
            Layout()
            UpdateVisibility()
            QueueKeys()
        end
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
        return
    end
    if not frame then Build() end
    Layout()
    Place()
    frame.mover:SetShown(unlocked == true)
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
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
