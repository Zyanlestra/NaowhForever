-- Book.lua: the overview tab: a card for each of your professions, with its skill, on the game's card art with the Forever skin.
local ns = _G.NaowhForever

local T = ns.THEME

local P = ns.Professions
local C = P.C
local Style = P.Style
local Widgets = P.Widgets
local Parts = ns.Shared.Parts

local BOOK_TOP = -40
local PRIMARY_H, CARD_GAP = 128, 8
local SECONDARY_COLUMNS = 3
local PRIMARIES = 2
local NAME_X, NAME_DROP = 12, 10
local SECONDARY_NAME_DROP = 12
local BAR_X, BAR_DROP, BAR_RIGHT = 250, 52, 44
local SECONDARY_BAR_DROP = 38
local SECONDARY_BAR_ROOM = 24
local BAR_H = 18
local MISSING_DROP = 8
local MISSING_ROOM = 40
local BOOK_ORDER = { "PrimaryProfession1", "PrimaryProfession2", "SecondaryProfession1",
    "SecondaryProfession2", "SecondaryProfession3" }
local SECONDARIES = {
    { name = PROFESSIONS_COOKING or "Cooking", card = "generic-cooking" },
    { name = PROFESSIONS_FISHING or "Fishing", card = "generic-fishing" },
    { name = PROFESSIONS_FIRST_AID or "First Aid", card = "generic-firstaid" },
}
local CARD_ATLAS = "profession-overview-card-%s-c60"
local CARD_FALLBACK = "profession-overview-card-c60"
local CARD_KEYS = { [171] = "alchemy", [164] = "blacksmithing", [333] = "enchanting", [202] = "engineering",
    [182] = "herbalism", [165] = "leatherworking", [186] = "mining", [393] = "skinning", [197] = "tailoring",
    [633] = "lockpicking", [40] = "poisons", [185] = "generic-cooking", [356] = "generic-fishing",
    [129] = "generic-firstaid" }
local TEXT_TITLE = TRADE_SKILLS or ns.L("Professions")
local TEXT_PRIMARY = PROFESSIONS_FIRST_PROFESSION or ns.L("Primary Profession")
local TEXT_NO_PRIMARY = PROFESSIONS_MISSING_PROFESSION or ns.L("Visit a profession trainer to learn one.")
local TEXT_NOT_LEARNED = ns.L("Not learned yet.")
local TEXT_READY = ns.L("%s%s|r is ready to learn.")
local TEXT_WHERE = "%s - %s %.1f, %.1f"
local TEXT_NO_TEACHER = ns.L("No teacher recorded for your faction.")
local TEXT_SKILL = "%d/%d%s"
local TEXT_BONUS = " (+%d)"

local win

local Book = {}
P.Book = Book
Book.ORDER = BOOK_ORDER

local function Where(npc)
    return TEXT_WHERE:format(npc[C.NPC_NAME], ns.RecipeFinder.ZoneName(npc[C.NPC_MAP]), npc[C.NPC_X], npc[C.NPC_Y])
end

function Book.RankLines(a)
    local npc = a.npc
    return TEXT_READY:format(ns.RecipeFinder.Hex(Style.GOLD_RGB), a.rankName), a.how .. ".",
        npc and Where(npc) or TEXT_NO_TEACHER
end

local function Indices()
    local prof1, prof2, firstAid, fishing, cooking = GetProfessions()
    return { prof1, prof2, cooking, fishing, firstAid }
end

local function PlaceCard(card, book, i, innerW, cardW)
    if card.primary then
        card:SetPoint("TOPLEFT", 0, -(i - 1) * (PRIMARY_H + CARD_GAP))
        card:SetSize(innerW, PRIMARY_H)
        return
    end
    local x = (i - PRIMARIES - 1) * (cardW + CARD_GAP)
    card:SetPoint("TOPLEFT", x, -PRIMARIES * (PRIMARY_H + CARD_GAP))
    card:SetPoint("BOTTOMLEFT", book, "BOTTOMLEFT", x, 0)
    card:SetWidth(cardW)
end

local function PlaceBar(card, bar, innerW, cardW)
    if card.primary then
        card.name:SetPoint("TOPLEFT", NAME_X, -NAME_DROP)
        bar:SetPoint("TOPLEFT", BAR_X, -BAR_DROP)
        bar:SetSize(innerW - BAR_X - BAR_RIGHT, BAR_H)
    else
        card.name:SetPoint("TOP", 0, -SECONDARY_NAME_DROP)
        bar:SetPoint("TOP", 0, -SECONDARY_BAR_DROP)
        bar:SetSize(cardW - SECONDARY_BAR_ROOM, BAR_H)
    end
end

local function BuildCard(book, i, innerW, cardW)
    local primary = i <= PRIMARIES
    local card = CreateFrame("Frame", nil, book)
    card.fill = ns.Solid(card, "BACKGROUND", T.panel, Style.PANEL_ALPHA)
    card.fill:SetAllPoints()
    card.border = ns.Border(card, Style.BORDER_RGB)
    if ns.foreverSkin then card.art = Parts.ForeverCard(card) end
    card.primary = primary
    PlaceCard(card, book, i, innerW, cardW)
    card.name = ns.Font(card, Style.FONT_HEAD, nil, Style.GOLD_RGB)
    local bar = CreateFrame("StatusBar", nil, card)
    ns.Solid(bar, "BACKGROUND", T.bg, 1):SetAllPoints()
    Widgets.StyleBar(bar)
    PlaceBar(card, bar, innerW, cardW)
    card.bar = bar
    card.barText = ns.Font(bar, Style.FONT, "OUTLINE")
    card.barText:SetPoint("CENTER")
    card.missing = ns.Font(card, Style.FONT, nil, T.muted)
    card.missing:SetPoint("CENTER", 0, primary and -MISSING_DROP or 0)
    card.missing:SetWidth((primary and innerW or cardW) - MISSING_ROOM)
    card.missing:SetWordWrap(true)
    return card
end

function Book.Build(frame)
    win = frame
    local book = CreateFrame("Frame", nil, win)
    book:SetPoint("TOPLEFT", Style.PAD, BOOK_TOP)
    book:SetPoint("BOTTOMRIGHT", -Style.PAD, Style.PAD)
    book:Hide()
    win.book = book
    local innerW = Style.WINDOW_W - Style.PAD * 2
    local cardW = (innerW - CARD_GAP * (SECONDARY_COLUMNS - 1)) / SECONDARY_COLUMNS
    book.cards = {}
    for i = 1, #BOOK_ORDER do book.cards[i] = BuildCard(book, i, innerW, cardW) end
end

local function PaintCard(card, key)
    if not card.art then return end
    local shown = Parts.PaintForeverCard(card.art, key and CARD_ATLAS:format(key) or CARD_FALLBACK, CARD_FALLBACK)
    card.fill:SetShown(not shown)
    card.border._frame:SetShown(not shown)
end

local function RenderLearned(card, index)
    local name, _, rank, maxRank, _, _, line, modifier = GetProfessionInfo(index)
    card.name:SetText(name)
    PaintCard(card, CARD_KEYS[line])
    card.bar:SetMinMaxValues(0, math.max(maxRank or 0, 1))
    card.bar:SetValue(rank or 0)
    card.barText:SetText(TEXT_SKILL:format(rank or 0, maxRank or 0,
        (modifier or 0) > 0 and TEXT_BONUS:format(modifier) or ""))
    card.bar:Show()
    card.missing:Hide()
end

local function RenderMissing(card, i)
    local secondary = SECONDARIES[i - PRIMARIES]
    card.name:SetText(card.primary and TEXT_PRIMARY or secondary.name)
    PaintCard(card, not card.primary and secondary.card or nil)
    card.missing:SetText(card.primary and TEXT_NO_PRIMARY or TEXT_NOT_LEARNED)
    card.bar:Hide()
    card.missing:Show()
end

function Book.Render()
    win.title:SetText(TEXT_TITLE)
    local indices = Indices()
    for i, card in ipairs(win.book.cards) do
        local index = indices[i]
        if index then
            RenderLearned(card, index)
        else
            RenderMissing(card, i)
        end
    end
end
