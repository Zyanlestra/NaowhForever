-- Run with Lua 5.1 from the repository root: the profession window in the Forever skin. It wears the
-- game's portrait frame (Parts.ForeverFrame) over the rock and Naowh's window art, its logo in the
-- portrait and the game's red close in place of ours, and the game's background card for the open
-- profession behind the recipe. With the skin off it stays as it was. Title-bar buttons sit above the
-- frame's art.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local function Noop() end

local function Frame(kind)
    local f = { kind = kind, shown = true, points = {} }
    return setmetatable(f, { __index = function(_, key)
        if not key:find("^%u") then return nil end
        if key == "SetShown" then return function(self, on) self.shown = on end end
        if key == "Show" then return function(self) self.shown = true end end
        if key == "Hide" then return function(self) self.shown = false end end
        if key == "SetAlpha" then return function(self, a) self.alpha = a end end
        if key == "SetText" then return function(self, text) self.text = text end end
        if key == "SetJustifyH" then return function(self, h) self.justify = h end end
        if key == "ClearAllPoints" then return function(self) self.points = {} end end
        if key == "SetPoint" then return function(self, ...) self.points[#self.points + 1] = { ... } end end
        if key == "SetAllPoints" then return function(self, to) self.all = to or true end end
        if key == "CreateTexture" then return function() return Frame("texture") end end
        return Noop
    end })
end

local function Stub(fields)
    return setmetatable(fields or {}, { __index = function() return Noop end })
end

local calls, prof
local function Load(skin)
    calls = { painted = {} }
    prof = { id = 171, name = "Alchemy", skill = 10, max = 75 }
    local Parts = {
        Logo = function()
            local logo = Frame("logo")
            logo.icon = Frame("icon")
            return logo
        end,
        Backdrop = function(frame)
            calls.backdrop = frame
            return { Paint = function(_, alpha) calls.backdropAlpha = alpha end }
        end,
        ForeverWindowArt = function(frame) calls.art = frame end,
        ForeverFrame = function(window, opts)
            local chrome = Frame("chrome")
            chrome.portrait = Frame("portrait")
            chrome.close = Frame("red close")
            chrome.title = Frame("bar title")
            chrome.opts = opts
            window.forever = chrome
            return chrome
        end,
        ForeverCard = function() return Frame("card") end,
        ForeverBox = function(frame) calls.boxed = frame end,
        ForeverSearch = function(box, fill) calls.searchArt = { box, fill } end,
        PaintForeverCard = function(texture, name, fallback)
            calls.painted[#calls.painted + 1] = { texture, name, fallback }
            texture.shown = true
            return true
        end,
    }
    _G.NaowhForever = {
        THEME = { bg = {}, panel = {}, muted = {}, accent = {} },
        L = function(s) return s end,
        foreverSkin = skin,
        Shared = { Parts = Parts },
        Solid = function() calls.solid = (calls.solid or 0) + 1; return Frame("solid") end,
        Border = function() return { _frame = Frame("border") } end,
        Font = function(_, size)
            local font = Frame("font")
            if size == "title" then calls.ownTitle = font end
            return font
        end,
        Button = function(_, text)
            local b = Frame("button")
            b.label = text
            if text == "X" then calls.ownClose = b end
            return b
        end,
        NewEditBox = function()
            local box = Frame("edit")
            box._fill = Frame("fill")
            return box
        end,
        SetButtonText = Noop,
        Professions = {
            Settings = Stub(), State = {}, Prices = Stub(), Filters = Stub({ Active = function() return 0 end }), Entries = Stub(), Orders = Stub(),
            Widgets = Stub({ SetColor = Noop }), Recipes = Stub({ Profession = function() return prof end }),
            Style = setmetatable({ CARD_ALPHA = 0.8, FOREVER_PORTRAIT_ROOM = 64, FOREVER_TITLE_LEFT = 58, PAD = 8, WINDOW_W = 780,
                LEFT_W = 340, MID_W = 400, MID_X = 356, TOP_Y = -68, FILTER_W = 76, FILTER_GAP = 6,
                FONT_TITLE = "title" },
                { __index = function() return 1 end }),
            SkillBar = {
                New = function(_, ends)
                    local bar = Frame("skill bar")
                    bar.ends = ends
                    bar.top = Frame("bar top")
                    calls.skillBar = bar
                    return bar
                end,
                Paint = function(bar, key) calls.barPainted = { bar, key } end,
            },
            List = Stub(), Detail = Stub(), Learn = Stub(), OrderPanel = Stub(), Book = Stub(),
        },
    }
    dofile("NaowhForever_Professions/Constants.lua")
    _G.CreateFrame = function(kind) return Frame(kind) end
    _G.UIParent = Frame("UIParent")
    _G.C_TradeSkillUI = { GetAllRecipeIDs = function() return {} end }
    dofile("NaowhForever_Professions/UI/Window.lua")
    local P = _G.NaowhForever.Professions
    return P.Window.Build(), P.Window
end

local win, Window = Load(true)
check("the rock, at full strength, under Naowh's window art", calls.backdrop == win and calls.backdropAlpha == 1
    and calls.art == win)
check("the game's portrait frame round it", win.forever ~= nil and win.forever.opts.onClose ~= nil)
check("its red close is the window's close, ours hidden", win.close == win.forever.close
    and calls.ownClose.shown == false)
check("the profession's name on the title bar in place of the addon's, from the left",
    win.title == win.forever.title and win.title.justify == "LEFT" and calls.ownTitle.shown == false)
local nudge = win.title.points[#win.title.points]
check("a little clear of the portrait's ring", nudge[1] == "LEFT" and nudge[2] == win.forever and nudge[4] > 58)
check("a background card behind the recipe, a little see-through", win.mid.card and win.mid.card.alpha == 0.8)
check("no straight line round the recipe pane: the card has its own frame", calls.boxed == nil)
check("the search box on the game's input art", calls.searchArt and calls.searchArt[1] == win.search
    and calls.searchArt[2] == win.search._fill)

Window.Render()
local paint = calls.painted[#calls.painted]
check("the open profession's background card", paint and paint[1] == win.mid.card
    and paint[2] == "profession-background-card-alchemy-c60" and paint[3] == nil)
check("its name on the title bar", win.forever.title.text == "Alchemy")
check("the game's skill bar with its ends, painted for the open profession", win.rank == calls.skillBar
    and win.rank.ends == true and win.rank.points[1][1] == "TOPLEFT" and win.rank.points[1][2] == 130
    and calls.barPainted[1] == win.rank and calls.barPainted[2] == "alchemy")
prof.id = 185
Window.Render()
check("Cooking's own card", calls.painted[#calls.painted][2] == "profession-background-card-cooking-c60")
prof.id = 999
local before = #calls.painted
Window.Render()
check("no card for a profession the game has none for", #calls.painted == before and not win.mid.card.shown)

win = Load(false)
check("with the skin off: no frame, art or card", win.forever == nil and calls.art == nil and calls.backdrop == nil
    and win.mid.card == nil and calls.solid ~= nil and calls.boxed == nil)
check("and its own flat skill bar", win.rank.kind == "StatusBar" and calls.skillBar == nil
    and calls.barPainted == nil)
check("and its own search box", calls.searchArt == nil)
check("and its own close", win.close == calls.ownClose and win.close.shown)

local source = Read("NaowhForever_Professions/UI/Window.lua")
check("the logo moves into the portrait and keeps its click", source:find("logo:SetAllPoints(win.forever.portrait)", 1,
    true) and source:find("logo.icon:Hide()", 1, true))

-- The title-bar buttons are the window's children, under the frame's art unless raised above it.
local level
local button = setmetatable({ hooks = {} }, { __index = function() return Noop end })
function button:GetParent() return { forever = { GetFrameLevel = function() return 20 end }, close = Frame("close") } end
function button:SetFrameLevel(n) level = n end
function button:HookScript() end
_G.NaowhForever = { Professions = { Window = { Render = Noop } } }
_G.hooksecurefunc = function(t, key, fn)
    local old = t[key]
    t[key] = function(...) old(...); fn(...) end
end
dofile("NaowhForever_Professions/UI/TitleButtons.lua")
_G.NaowhForever.Professions.TitleButtons.Add(button, 1)
check("a title-bar button sits above the Forever frame", level and level > 20)

-- These cards are not found by name in game, so each is drawn from its file, cut to its size.
local style = Read("Shared/Style.lua")
local filed, wanted = 0, 0
dofile("NaowhForever_Professions/Constants.lua")
for _, key in pairs(_G.NaowhForever.Professions.C.ART_KEYS) do
    wanted = wanted + 1
    local w, h, l, r, t, b = style:match('%["profession%-background%-card%-' .. key .. '%-c60"%] = { file = %d+, '
        .. "w = (%d+), h = (%d+),%s*l = (%d+) / %d+, r = (%d+) / %d+, t = (%d+) / %d+, b = (%d+) / %d+ }")
    if w and r - l == tonumber(w) and b - t == tonumber(h) then filed = filed + 1 end
end
check("every profession's background card is drawn from its file", wanted == 14 and filed == wanted)

check("the number boxes on the game's input art with the skin", Read("NaowhForever_Professions/View/Widgets.lua"):find(
    "    if ns.foreverSkin then ns.Shared.Parts.ForeverSearch(qty, qty._fill) end", 1, true))

print(checks .. " profession Forever window checks passed")
