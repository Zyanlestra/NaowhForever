-- AspectReminder.lua: the QoL aspect reminder, a warning while a hunter has none of their aspects up.
local ns = _G.NaowhForever

local issecretvalue = issecretvalue

local S = ns.QoLSettings
local Parts, St = ns.Shared.Parts, ns.Shared.Style

local ASPECTS = { 25296, 14322, 14321, 14320, 14319, 14318, 13165, 13163, 5118, 13159,
    1299447, 1299446, 1299445, 13161, 20190, 20043 }
local HAWK = 13165
local HUNTER = "HUNTER"
local PLAYER = "player"
local WIDTH, ICON_GAP = 220, 8
local ICON_CROP_LOW, ICON_CROP_HIGH = ns.QoLConstants.ICON_CROP_TIGHT, ns.QoLConstants.ICON_CROP_TIGHT_HIGH
local FONT_SIZE = 20
local STACK_ORDER = 7
local PAGE = "QoL/Combat"
local CARD = PAGE .. ":aspectReminder"
local TEXT_ALERT = "Aspect Reminder"
local ICON_GROW, HEIGHT_ROOM = 12, 16
local TEXT_RANGE = { 12, 48, 1 }
local EVENTS = { "SPELLS_CHANGED", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_MOUNT_DISPLAY_CHANGED",
    "PLAYER_UPDATE_RESTING", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_CONTROL_LOST",
    "PLAYER_CONTROL_GAINED", "PLAYER_ENTERING_WORLD" }

local frame, unlocked, inCombat, class
local events = CreateFrame("Frame")

local function On()
    return S.Get("enabled") and S.Get("aspectReminder") and class == HUNTER
end

local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function Build()
    frame = CreateFrame("Frame", "NaowhForeverAspectReminder", UIParent)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetTexCoord(ICON_CROP_LOW, ICON_CROP_HIGH, ICON_CROP_LOW, ICON_CROP_HIGH)
    frame.text = ns.Font(frame, FONT_SIZE, "OUTLINE")
    frame.backdrop = Parts.HudBackdrop(frame, { mode = "none" })
    frame:Hide()
    ns.AlertStack(frame, STACK_ORDER, TEXT_ALERT, PAGE, CARD)
end

local function Restyle()
    local size = S.Get("aspectFontSize")
    frame.mode = frame.backdrop:SetMode(S.Get("aspectBackground"))
    Parts.HudFont(frame.text, S.Get("aspectFont"), size, S.Get("aspectOutline"), frame.mode)
    local c = S.Get("aspectClassColor") and RAID_CLASS_COLORS[HUNTER] or S.Get("aspectColor")
    frame.text:SetTextColor(c.r, c.g, c.b, 1)
    frame.text:ClearAllPoints()
    frame.icon:ClearAllPoints()
    if S.Get("aspectShowIcon") then
        local icon = size + ICON_GROW
        frame.icon:SetSize(icon, icon)
        frame.text:SetPoint("CENTER", frame, "CENTER", (icon + ICON_GAP) / 2, 0)
        frame.icon:SetPoint("RIGHT", frame.text, "LEFT", -ICON_GAP, 0)
        frame.icon:Show()
    else
        frame.icon:Hide()
        frame.text:SetPoint("CENTER")
    end
    frame:SetSize(WIDTH, size + HEIGHT_ROOM)
end

local function Fit()
    if frame.mode == "none" then return end
    local w = frame.text:GetStringWidth() + 2 * St.CARD_PAD
    if frame.icon:IsShown() then w = w + frame.icon:GetWidth() + ICON_GAP end
    frame:SetWidth(w)
end

local function Known()
    for _, id in ipairs(ASPECTS) do
        if C_SpellBook.IsSpellKnown(id) then return id end
    end
end

local function OwnAspectUp()
    for _, id in ipairs(ASPECTS) do
        local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
        if aura and not Secret(aura.sourceUnit) and aura.sourceUnit == PLAYER then return true end
    end
    return false
end

local function Missing()
    if inCombat or C_Secrets.ShouldAurasBeSecret() then return end
    if UnitIsDeadOrGhost(PLAYER) or IsMounted() or UnitOnTaxi(PLAYER) then return end
    if S.Get("aspectHideResting") and IsResting() then return end
    local known = Known()
    if known and not OwnAspectUp() then return known end
end

local function Update()
    if not frame then return end
    local spell
    if unlocked then
        spell = Known() or HAWK
    elseif On() then
        spell = Missing()
    end
    if not spell then
        frame:Hide()
        return
    end
    frame.icon:SetTexture(C_Spell.GetSpellTexture(spell))
    frame.text:SetText(S.Get("aspectText"))
    Fit()
    frame:Show()
end

local function OnEvent(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    end
    Update()
end

local function Apply()
    events:UnregisterAllEvents()
    class = select(2, UnitClass(PLAYER))
    if not (On() or unlocked) then
        if frame then frame:Hide() end
        return
    end
    if not frame then Build() end
    Restyle()
    if On() then
        inCombat = UnitAffectingCombat(PLAYER)
        for _, event in ipairs(EVENTS) do events:RegisterEvent(event) end
        events:RegisterUnitEvent("UNIT_AURA", PLAYER)
    end
    Update()
end

events:SetScript("OnEvent", OnEvent)

hooksecurefunc(S, "Set", function(key)
    if key == "enabled" or key:find("^aspect") then Apply() end
end)
hooksecurefunc(ns, "Apply", Apply)
hooksecurefunc(ns, "ShowUnlockMode", function()
    unlocked = On() == true
    Apply()
end)
hooksecurefunc(ns, "HideUnlockMode", function()
    unlocked = false
    if frame then Apply() end
end)

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", Apply)

local Group = ns.Shared.Settings.Group

local function OwnColour() return not S.Get("aspectClassColor") end

ns.Shared.Settings.Page(PAGE, S):Card({
    id = "aspectReminder", name = "Aspect Reminder", order = 101, switch = "aspectReminder",
    help = "A warning while a hunter has none of their aspects up, out of combat.",
    rows = {
        Group("When"),
        { key = "aspectHideResting", label = "Hide While Resting", toggle = true,
          help = "No warning in an inn or a city." },
        Group("Messages"),
        { key = "aspectText", label = "Text", text = true, help = "What the warning says." },
        { key = "aspectShowIcon", label = "Show Icon", toggle = true },
        ns.Shared.Settings.Look("aspect", { text = true, size = TEXT_RANGE, background = "card" }),
        Group("Colors"),
        { key = "aspectClassColor", label = "Class Color", toggle = true },
        { key = "aspectColor", label = "Color", colour = true, needs = OwnColour, why = "Class color is on" },
    },
})
