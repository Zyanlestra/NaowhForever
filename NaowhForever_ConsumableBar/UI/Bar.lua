-- Bar.lua: the Consumable Bar on screen: one secure item button per entry, laid out, placed and shown or hidden out of combat.
local ns = _G.NaowhForever

local InCombatLockdown = InCombatLockdown
local GetTime = GetTime

local CB = ns.ConsumableBar
local S, C = CB.S, CB.C
local ItemBar, ActionKeys = ns.Shared.ItemBar, ns.Shared.ActionKeys

local MOVER_LABEL = "Consumable Bar"
local FLAGS = "consumableBarItemFlags"
local QUIET = { consumableBarPos = true, consumableBarDeclined = true, consumableBarSkip = true,
    consumableBarTooltip = true }
local LOOK = { consumableBarFont = true, consumableBarFontSize = true, consumableBarTextColor = true,
    consumableBarTextPoint = true, consumableBarTextOutside = true, consumableBarTextX = true,
    consumableBarTextY = true, consumableBarKeyFont = true, consumableBarKeySize = true,
    consumableBarKeyColor = true, consumableBarKeyPoint = true, consumableBarKeyOutside = true,
    consumableBarKeyX = true, consumableBarKeyY = true, consumableBarBackground = true,
    consumableBarBgAlpha = true, consumableBarShowCount = true }
local BAR_NAME = "NaowhForeverConsumableBar"
local RULE_COMBAT_HIDE = "[combat] hide; show"
local RULE_COMBAT_SHOW = "[combat] show; hide"

local frame, pending, wakeDue
local buttons = {}
local pool = {}
local events

local UpdateVisibility

local function Driver(f, rule)
    if f.visRule == rule then return end
    f.visRule = rule
    if rule then
        RegisterStateDriver(f, "visibility", rule)
    else
        UnregisterStateDriver(f, "visibility")
    end
end

local function TipOff(button)
    return not S.Get("consumableBarTooltip") or (button.itemID == nil and not button.emptyTip) or button.empty
end

local function ButtonFor(entry)
    local button = pool[entry]
    if not button then
        button = CB.Decorate(ItemBar.SecureButton(frame, CB.ButtonName(entry)))
        button.tipOff = TipOff
        pool[entry] = button
    end
    return button
end

local function Retire(button)
    Driver(button, nil)
    ItemBar.SetItem(button, nil)
    button.entry, button.spent, button.slot = nil, nil, nil
    button:Hide()
end

local function SavePosition(pos)
    S.Set("consumableBarPos", pos)
    if ItemBar.Anchored(S, CB.PREFIX) then S.Set("consumableBarAnchor", "UIParent") end
end

local function Build()
    frame = ItemBar.Frame(BAR_NAME, MOVER_LABEL, SavePosition, "Consumable Bar/Settings", "Consumable Bar/Settings:bar")
    ItemBar.Outline(frame, C.BG_PAD)
end

function CB.BarFrame()
    return frame
end

local function Layout()
    local items = CB.Items()
    local size, gap, grow, perRow = CB.Grid()
    local inUse = {}
    for i = #buttons, 1, -1 do buttons[i] = nil end
    for i, entry in ipairs(items) do
        local button = ButtonFor(entry)
        buttons[i], inUse[button] = button, true
        ItemBar.Place(button, frame, i, size, gap, grow, perRow)
        CB.PlaceBackground(button, i, #items, gap, grow, perRow)
        CB.StyleCell(button, entry, size)
        button.entry, button.slot = entry, i
        ItemBar.SetItem(button, CB.Resolve(entry))
    end
    for _, button in pairs(pool) do
        if not inUse[button] and (button.entry ~= nil or button:IsShown()) then Retire(button) end
    end
    frame:SetSize(ItemBar.Size(#items, size, gap, grow, perRow))
end

local function UpdateCounts()
    local quiet = not InCombatLockdown()
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then
            CB.ShowCount(button, button.itemID, 0)
            if quiet then button:EnableMouse(not button.empty) end
        end
    end
end

local function UpdateCooldowns()
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then CB.ShowCooldown(button, button.itemID) else button.timer:Hide() end
    end
end

local function UpdateKeys()
    local map = CB.KeyMap()
    for _, button in ipairs(buttons) do CB.ShowKey(button, map) end
    CB.Changed()
end

local QueueKeys = ActionKeys.NewQueue(UpdateKeys)

local function OnWake()
    wakeDue = nil
    UpdateVisibility()
end

local function Wake(at)
    if not at then return end
    local due = GetTime() + at + C.WAKE_LEAD
    if wakeDue and wakeDue <= due then return end
    wakeDue = due
    C_Timer.After(at + C.WAKE_LEAD, OnWake)
end

local function ShowIcon(button)
    local flags = CB.Flags(button.entry)
    local combat = flags.combat and not CB.unlocked
    local used = flags.used and not CB.unlocked and CB.Spent(button)
    if combat and used then
        Driver(button, nil)
        button:Hide()
    elseif combat then
        Driver(button, RULE_COMBAT_HIDE)
    elseif used then
        Driver(button, RULE_COMBAT_SHOW)
    else
        Driver(button, nil)
        button:Show()
    end
    return not combat, not used
end

function UpdateVisibility()
    if not frame or InCombatLockdown() or not CB.On() then return end
    CB.TakeWake()
    local fight, rest = CB.unlocked == true, CB.unlocked == true
    for _, button in ipairs(buttons) do
        if button.entry ~= nil then
            local inFight, atRest = ShowIcon(button)
            fight, rest = fight or inFight, rest or atRest
        end
    end
    if S.Get("consumableBarHideCombat") and not CB.unlocked then fight = false end
    if fight and rest then
        Driver(frame, nil)
        frame:Show()
    elseif fight then
        Driver(frame, RULE_COMBAT_SHOW)
    elseif rest then
        Driver(frame, RULE_COMBAT_HIDE)
    else
        Driver(frame, nil)
        frame:Hide()
    end
    Wake(CB.TakeWake())
end

local function AnyHideUsed()
    if CB.unlocked then return false end
    for _, entry in ipairs(CB.Items()) do
        if CB.Flags(entry).used then return true end
    end
    return false
end

local Apply

local function OnEvent(_, event, unit, _, spellID)
    if event == "PLAYER_LOGIN" then
        Apply()
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        CB.NoteCast(spellID)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if pending then
            Apply()
        else
            UpdateCounts()
            UpdateVisibility()
        end
        CB.ShowAsk()
    elseif event == "PLAYER_ENTERING_WORLD" then
        Apply()
    elseif event == "BAG_UPDATE_COOLDOWN" then
        UpdateCooldowns()
        UpdateVisibility()
    elseif event == "UNIT_AURA" or event == "UNIT_INVENTORY_CHANGED" then
        if unit == "player" then UpdateVisibility() end
    elseif event == "BAG_UPDATE_DELAYED" then
        UpdateCounts()
        UpdateCooldowns()
        CB.CheckNewItems()
        CB.Changed()
    else
        QueueKeys()
    end
end

local function Listen(hideUsed)
    events:RegisterEvent("BAG_UPDATE_DELAYED")
    events:RegisterEvent("PLAYER_ENTERING_WORLD")
    events:RegisterEvent("PLAYER_REGEN_ENABLED")
    if S.Get("consumableBarCooldown") or hideUsed then events:RegisterEvent("BAG_UPDATE_COOLDOWN") end
    if hideUsed then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end
    ActionKeys.Listen(events, S.Get("consumableBarKeybinds"))
end

local function Events()
    if not events then
        events = CreateFrame("Frame")
        events:SetScript("OnEvent", OnEvent)
    end
    return events
end

function Apply()
    if InCombatLockdown() then
        pending = true
        Events():RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    pending = nil
    if events then events:UnregisterAllEvents() end
    if not CB.On() then
        CB.StopAsking()
        if frame then
            Driver(frame, nil)
            frame:Hide()
        end
        return
    end
    if not frame then Build() end
    Events()
    Layout()
    ItemBar.Put(frame, S, CB.PREFIX, C.HOME_Y)
    frame.mover:SetShown(CB.unlocked == true)
    Listen(AnyHideUsed())
    UpdateCounts()
    UpdateCooldowns()
    UpdateVisibility()
    QueueKeys()
end

local function Restyle()
    if not (frame and CB.On()) then return end
    if InCombatLockdown() then
        Apply()
        return
    end
    local size, gap, grow, perRow = CB.Grid()
    for i, button in ipairs(buttons) do
        CB.StyleCell(button, button.entry, size)
        CB.PlaceBackground(button, i, #buttons, gap, grow, perRow)
    end
    UpdateCounts()
    QueueKeys()
end

local function OnSettingChanged(key)
    if not key:find("^consumableBar") then return end
    if key == "consumableBarWindowAlpha" then
        ns.Shared.Parts.RepaintSidePanels()
    elseif key == "consumableBarAskNew" then
        if not S.Get(key) then CB.StopAsking() end
    elseif LOOK[key] or (key == FLAGS and CB.lookOnly) then
        Restyle()
    elseif not QUIET[key] then
        Apply()
    end
    CB.Changed()
end

local function Unlock()
    CB.unlocked = true
    Apply()
end

local function Lock()
    CB.unlocked = false
    Apply()
end

hooksecurefunc(S, "Set", OnSettingChanged)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", Unlock)
hooksecurefunc(ns, "HideUnlockMode", Lock)

if CB.On() then Events():RegisterEvent("PLAYER_LOGIN") end
