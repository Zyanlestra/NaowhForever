-- SkillBar.lua: a profession skill bar in the Forever skin: the game's bar, the profession's moving fill and flare, and on the window a gryphon or wyvern at each end (P.SkillBar).
local ns = _G.NaowhForever

local P = ns.Professions
local Style = P.Style
local Parts = ns.Shared.Parts

local BAR_H = 23
local FILL_X, FILL_Y = 4, 3
local FLIP_FRAME_H = 34
local FLIP_COLUMNS = 2
local FLIP_SECONDS = 1.8
local FLARE_W, FLARE_H = 27, 17
local CAP_W, CAP_H = 86, 50
local CAP_IN = 14
local GLOW_LEVEL, TOP_LEVEL = 2, 3
local BG_ATLAS = "profession-progressbar-bg-c60"
local FRAME_ATLAS = "profession-progressbar-frame-c60"
local FILL_ART = "naowh:skillbar-fill-%s"
local FLARE_ART = "naowh:skillbar-flare-%s"
local CAP_ART = "naowh:%s-%s"
local GRYPHON, WYVERN = "gryphon", "wyvern"
local HORDE = "Horde"

local SkillBar = {}
P.SkillBar = SkillBar
SkillBar.HEIGHT = BAR_H

local function Place(bar)
    local min, max = bar:GetMinMaxValues()
    local share = max > min and (bar:GetValue() - min) / (max - min) or 0
    local width = (bar:GetWidth() - FILL_X * 2) * math.min(math.max(share, 0), 1)
    bar.clip:SetShown(width >= 1)
    bar.clip:SetWidth(math.max(width, 1))
    bar.flare:SetShown(bar.art ~= nil and width >= 1 and share < 1)
end

local function ShowFrame(bar, step)
    local art = bar.art
    local col = step % FLIP_COLUMNS
    local row = math.floor(step / FLIP_COLUMNS)
    local du, dv = (art.r - art.l) / FLIP_COLUMNS, (art.b - art.t) / bar.rows
    bar.fill:SetTexCoord(art.l + col * du, art.l + (col + 1) * du, art.t + row * dv, art.t + (row + 1) * dv)
end

local function OnUpdate(bar, elapsed)
    bar.clock = (bar.clock + elapsed) % FLIP_SECONDS
    local step = math.floor(bar.clock / FLIP_SECONDS * bar.frames)
    if step == bar.step then return end
    bar.step = step
    ShowFrame(bar, step)
end

local function Animate(bar)
    bar:SetScript("OnUpdate", bar.art and bar:IsVisible() and OnUpdate or nil)
end

local function Cap(top)
    local cap = top:CreateTexture(nil, "OVERLAY")
    cap:SetSize(CAP_W, CAP_H)
    return cap
end

function SkillBar.New(parent, ends)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetHeight(BAR_H)
    bar:SetStatusBarTexture(Style.WHITE)
    bar.plain = bar:GetStatusBarTexture()
    bar.plain:SetVertexColor(Style.GOLD_RGB.r, Style.GOLD_RGB.g, Style.GOLD_RGB.b)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    Parts.ForeverAtlas(bar.bg, BG_ATLAS)
    bar.clip = CreateFrame("Frame", nil, bar)
    bar.clip:SetClipsChildren(true)
    bar.clip:SetPoint("TOPLEFT", FILL_X, -FILL_Y)
    bar.clip:SetPoint("BOTTOMLEFT", FILL_X, FILL_Y)
    local holder = CreateFrame("Frame", nil, bar.clip)
    holder:SetPoint("TOPLEFT", bar, "TOPLEFT", FILL_X, -FILL_Y)
    holder:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -FILL_X, FILL_Y)
    bar.fill = holder:CreateTexture(nil, "ARTWORK")
    bar.fill:SetAllPoints()
    bar.clock, bar.frames, bar.rows = 0, 1, 1
    bar.top = CreateFrame("Frame", nil, bar)
    bar.top:SetAllPoints()
    bar.top:SetFrameLevel(bar:GetFrameLevel() + TOP_LEVEL)
    bar.frame = bar.top:CreateTexture(nil, "BORDER")
    bar.frame:SetAllPoints()
    Parts.ForeverAtlas(bar.frame, FRAME_ATLAS)
    local glow = CreateFrame("Frame", nil, bar)
    glow:SetPoint("TOPLEFT", FILL_X, -FILL_Y)
    glow:SetPoint("BOTTOMRIGHT", -FILL_X, FILL_Y)
    glow:SetClipsChildren(true)
    glow:SetFrameLevel(bar:GetFrameLevel() + GLOW_LEVEL)
    bar.glow = glow
    bar.flare = CreateFrame("Frame", nil, glow):CreateTexture(nil, "ARTWORK")
    bar.flare:SetSize(FLARE_W, FLARE_H)
    bar.flare:SetPoint("RIGHT", bar.clip, "RIGHT")
    bar.flare:SetBlendMode("ADD")
    if ends then
        bar.left, bar.right = Cap(bar.top), Cap(bar.top)
        bar.left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMLEFT", CAP_IN, 0)
        bar.right:SetPoint("BOTTOMLEFT", bar, "BOTTOMRIGHT", -CAP_IN, 0)
    end
    bar:SetScript("OnValueChanged", Place)
    bar:SetScript("OnMinMaxChanged", Place)
    bar:SetScript("OnSizeChanged", Place)
    bar:SetScript("OnShow", Animate)
    bar:SetScript("OnHide", Animate)
    return bar
end

local function PaintFill(bar, key)
    local name = key and FILL_ART:format(key)
    local art = name and Style.FOREVER_ART_FILES[name]
    bar.art = nil
    if not (art and Parts.ForeverAtlas(bar.fill, name)) then return false end
    bar.rows = math.floor(art.h / FLIP_FRAME_H)
    bar.frames = bar.rows * FLIP_COLUMNS
    bar.art = art
    bar.step = 0
    ShowFrame(bar, 0)
    Parts.ForeverAtlas(bar.flare, FLARE_ART:format(key))
    return true
end

function SkillBar.Paint(bar, key)
    if bar.left then
        local beast = UnitFactionGroup("player") == HORDE and WYVERN or GRYPHON
        Parts.ForeverAtlas(bar.left, CAP_ART:format(beast, "left"))
        Parts.ForeverAtlas(bar.right, CAP_ART:format(beast, "right"))
    end
    if key ~= bar.key then
        bar.key = key
        local drawn = PaintFill(bar, key)
        bar.clip:SetAlpha(drawn and 1 or 0)
        bar.plain:SetAlpha(drawn and 0 or 1)
        Animate(bar)
    end
    Place(bar)
end
