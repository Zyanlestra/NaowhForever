-- BookStandIn.lua: in combat, still pictures of the game's ability buttons on the overview cards, so the cards keep them while the real ones are handed back (P.BookStandIn).
local ns = _G.NaowhForever

local P = ns.Professions
local Style = P.Style

local STAND_IN_LEVEL = 4
local SKIP_LAYER = "HIGHLIGHT"

local StandIn = {}
P.BookStandIn = StandIn

local holders = {}

local function Holder(card)
    local holder = holders[card]
    if holder then return holder end
    holder = CreateFrame("Frame", nil, card)
    holder:SetAllPoints()
    holder:SetFrameLevel(card:GetFrameLevel() + STAND_IN_LEVEL)
    holder:SetAlpha(Style.STAND_IN_ALPHA)
    holder.textures, holder.fonts, holder.usedTextures, holder.usedFonts = {}, {}, 0, 0
    holder:Hide()
    holders[card] = holder
    return holder
end

local function Place(copy, holder, region, card)
    local left, top, cardLeft, cardTop = region:GetLeft(), region:GetTop(), card:GetLeft(), card:GetTop()
    if not (left and top and cardLeft and cardTop) then return false end
    copy:ClearAllPoints()
    copy:SetPoint("TOPLEFT", holder, "TOPLEFT", left - cardLeft, top - cardTop)
    copy:SetSize(region:GetWidth(), region:GetHeight())
    copy:Show()
    return true
end

local function CopyTexture(holder, region, card)
    local i = holder.usedTextures + 1
    local copy = holder.textures[i] or holder:CreateTexture(nil, "ARTWORK")
    holder.textures[i] = copy
    local atlas = region:GetAtlas()
    if atlas then
        copy:SetAtlas(atlas)
    else
        copy:SetTexture(region:GetTexture())
        copy:SetTexCoord(region:GetTexCoord())
    end
    copy:SetVertexColor(region:GetVertexColor())
    copy:SetDrawLayer(region:GetDrawLayer())
    if Place(copy, holder, region, card) then holder.usedTextures = i end
end

local function CopyFont(holder, region, card)
    local i = holder.usedFonts + 1
    local copy = holder.fonts[i] or holder:CreateFontString(nil, "OVERLAY")
    holder.fonts[i] = copy
    copy:SetFont(region:GetFont())
    copy:SetTextColor(region:GetTextColor())
    copy:SetJustifyH(region:GetJustifyH())
    copy:SetText(region:GetText())
    if Place(copy, holder, region, card) then holder.usedFonts = i end
end

local function Shows(region)
    return region:IsShown() and region:GetAlpha() > 0 and select(1, region:GetDrawLayer()) ~= SKIP_LAYER
end

local function CopyButton(holder, button, card)
    for _, region in ipairs({ button:GetRegions() }) do
        if Shows(region) then
            local kind = region:GetObjectType()
            if kind == "Texture" and (region:GetAtlas() or region:GetTexture()) then
                CopyTexture(holder, region, card)
            elseif kind == "FontString" and region:GetText() then
                CopyFont(holder, region, card)
            end
        end
    end
end

local function Walk(holder, frame, card, skip)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child ~= skip and child:IsShown() then
            if child:IsObjectType("Button") then
                CopyButton(holder, child, card)
            else
                Walk(holder, child, card, skip)
            end
        end
    end
end

local function Clear(holder)
    for i = 1, holder.usedTextures do holder.textures[i]:Hide() end
    for i = 1, holder.usedFonts do holder.fonts[i]:Hide() end
    holder.usedTextures, holder.usedFonts = 0, 0
end

function StandIn.Show(card, blizz)
    local holder = Holder(card)
    Clear(holder)
    Walk(holder, blizz, card, blizz.UnlearnButton)
    holder:Show()
end

function StandIn.Hide()
    for _, holder in pairs(holders) do
        Clear(holder)
        holder:Hide()
    end
end
