-- Run with Lua 5.1 from the repository root: the overview's profession cards. With the Forever skin each
-- card is drawn on the game's own card art for its profession (Parts.ForeverCard, the shared card part),
-- falling back to the game's plain card and then to our flat card when this client lacks the art; with
-- the skin off they stay our flat cards. The rank-ready strip is gone from them.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

-- The shared part: a hidden texture over the frame, shown with the first atlas this client has.
local forever = Read("Shared/UI/Forever.lua")
local first = assert(forever:find("function Parts.ForeverCard(frame)", 1, true))
local last = assert(forever:find("\nend\n", assert(forever:find("function Parts.PaintForeverCard(", first, true)), true))
local have = {}
local function Texture()
    local t = { shown = true }
    function t:SetAllPoints() self.all = true end
    function t:Hide() self.shown = false end
    function t:SetShown(on) self.shown = on end
    return t
end
local Parts = {}
local partsEnv = setmetatable({
    Parts = Parts,
    CARD_SUBLEVEL = 1,
    Atlas = function(texture, name)
        if not have[name] then return false end
        texture.atlas = name
        return true
    end,
}, { __index = _G })
local load = assert(loadstring(forever:sub(first, last + 4)))
setfenv(load, partsEnv)
load()

local layers = {}
local holder = { CreateTexture = function(_, _, layer, _, sub) layers[#layers + 1] = { layer, sub }; return Texture() end }
local art = Parts.ForeverCard(holder)
check("the card art is a texture across the card, hidden until painted",
    art.all and not art.shown and layers[1][1] == "BACKGROUND" and layers[1][2] == 1)
have["card-a"], have["plain"] = true, true
check("painted with the art this client has", Parts.PaintForeverCard(art, "card-a", "plain") and art.atlas == "card-a" and art.shown)
check("or its fallback", Parts.PaintForeverCard(art, "card-missing", "plain") and art.atlas == "plain" and art.shown)
have["plain"] = nil
check("with neither it hides and says so", not Parts.PaintForeverCard(art, "card-missing", "plain") and not art.shown)
check("a fallback is optional", not Parts.PaintForeverCard(art, "card-missing") and not art.shown)

-- The overview: Book.lua with the game's profession calls stubbed.
local function Frame()
    local f = { shown = true }
    return setmetatable(f, { __index = function(_, key)
        if not key:find("^%u") then return nil end
        if key == "SetShown" then return function(self, on) self.shown = on end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "SetText" then return function(self, text) self.text = text end end
        return function() end
    end })
end
local painted = {}
local profs = { 1, 2, 3 }
local info = {
    [1] = { "Alchemy", 171 }, [2] = { "Research", 999 }, [3] = { "Cooking", 185 },
}
local function LoadBook(skin, atlases)
    painted = {}
    _G.NaowhForever = {
        THEME = { panel = {}, bg = {}, muted = {} },
        L = function(s) return s end,
        foreverSkin = skin,
        Solid = function() return Frame() end,
        Border = function() return { _frame = Frame() } end,
        Font = function() return Frame() end,
        Professions = { C = {}, Style = { PAD = 8, WINDOW_W = 780 }, Widgets = { StyleBar = function() end },
            SkillBar = {
                HEIGHT = 23,
                New = function()
                    local bar = Frame()
                    bar.top = Frame()
                    bar.game = true
                    return bar
                end,
                Paint = function(bar, key) bar.key = key end,
            } },
        Shared = { Parts = {
            ForeverCard = function() return Frame() end,
            PaintForeverCard = function(texture, name, fallback)
                painted[#painted + 1] = { texture, name, fallback }
                return atlases[name] or (fallback ~= nil and atlases[fallback]) or false
            end,
        } },
    }
    dofile("NaowhForever_Professions/Constants.lua")
    _G.CreateFrame = function() return Frame() end
    _G.GetProfessions = function() return profs[1], profs[2], nil, nil, profs[3] end
    _G.GetProfessionInfo = function(i)
        local p = info[i]
        return p[1], nil, 10, 75, nil, nil, p[2], 0
    end
    dofile("NaowhForever_Professions/UI/Book.lua")
    local win = Frame()
    win.title = Frame()
    local Book = _G.NaowhForever.Professions.Book
    Book.Build(win)
    Book.Render()
    return win.book.cards
end

local ALL = { ["profession-overview-card-alchemy-c60"] = true, ["profession-overview-card-c60"] = true,
    ["profession-overview-card-generic-cooking-c60"] = true, ["profession-overview-card-generic-fishing-c60"] = true,
    ["profession-overview-card-generic-firstaid-c60"] = true }
local cards = LoadBook(true, ALL)
local function Painted(card)
    for _, p in ipairs(painted) do
        if p[1] == card.art then return p[2], p[3] end
    end
end
local name, fallback = Painted(cards[1])
check("a primary profession wears its own card art", name == "profession-overview-card-alchemy-c60"
    and fallback == "profession-overview-card-c60")
check("which takes the place of our flat card", not cards[1].fill.shown and not cards[1].border._frame.shown)
check("each learned card on the game's skill bar with its profession's fill", cards[1].bar.game
    and cards[1].bar.key == "alchemy" and cards[3].bar.key == "cooking")
check("one the game has no card for wears its plain card", Painted(cards[2]) == "profession-overview-card-c60")
check("Cooking wears its own", Painted(cards[3]) == "profession-overview-card-generic-cooking-c60")
check("an unlearned Fishing card wears Fishing's", Painted(cards[4]) == "profession-overview-card-generic-fishing-c60")
check("and an unlearned First Aid card First Aid's", Painted(cards[5]) == "profession-overview-card-generic-firstaid-c60")
check("each unlearned card's name matches its art", cards[4].name.text == "Fishing" and cards[5].name.text == "First Aid")
profs[2] = nil
cards = LoadBook(true, ALL)
check("an empty primary slot wears the plain card", Painted(cards[2]) == "profession-overview-card-c60")
profs[2] = 2

cards = LoadBook(true, {})
check("without the art the card stays our flat card", cards[1].fill.shown and cards[1].border._frame.shown)
cards = LoadBook(false, ALL)
check("with the skin off there is no card art", cards[1].art == nil and #painted == 0 and cards[1].fill.shown)
check("and the cards keep their flat skill bars", not cards[1].bar.game)

local book = Read("NaowhForever_Professions/UI/Book.lua")

-- The client cannot look these card atlases up by name (GetAtlasInfo is nil for them in game), so every
-- one the overview asks for is drawn from its file: an entry in St.FOREVER_ART_FILES whose cut matches
-- its size.
local style = Read("Shared/Style.lua")
local atlasFormat = book:match('local CARD_ATLAS = "([^"]+)"')
local secondaryFormat = book:match('local CARD_SECONDARY = "([^"]+)"')
local secondary = {}
for key in book:match("local SECONDARIES = (%b{})"):gmatch('card = "([^"]+)"') do secondary[key] = true end
local wanted = { book:match('local CARD_FALLBACK = "([^"]+)"') }
for _, key in pairs(_G.NaowhForever.Professions.C.ART_KEYS) do
    wanted[#wanted + 1] = atlasFormat:format(secondary[key] and secondaryFormat:format(key) or key)
end
check("the overview asks for the plain card and fourteen professions", #wanted == 15)
local filed = 0
for _, atlas in ipairs(wanted) do
    local w, h, l, r, t, b = style:match('%["' .. atlas:gsub("%-", "%%-") .. '"%] = { file = %d+, w = (%d+), h = (%d+),%s*'
        .. "l = (%d+) / %d+, r = (%d+) / %d+, t = (%d+) / %d+, b = (%d+) / %d+ }")
    if w and tonumber(r) - tonumber(l) == tonumber(w) and tonumber(b) - tonumber(t) == tonumber(h) then
        filed = filed + 1
    end
end
check("each card the overview asks for is drawn from its file, cut to its size", filed == #wanted)

check("the rank-ready strip is gone", not book:find("rankStrip", 1, true) and not book:find("Strip", 1, true))
check("the recipe window keeps the rank lines for its banner", book:find("function Book.RankLines(a)", 1, true)
    and Read("NaowhForever_Professions/UI/Window.lua"):find("P.Book.RankLines(a)", 1, true))

print(checks .. " profession overview card checks passed")
