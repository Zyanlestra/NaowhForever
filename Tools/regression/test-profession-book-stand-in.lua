-- Run with Lua 5.1 from the repository root: the overview's stand-ins in combat. Each card gets a still,
-- dimmed picture of the game's ability buttons on it (their icons and words, where they sit), so the card
-- keeps them while the real buttons are back on the game's window. Hidden parts, hover highlights and the
-- unlearn button are left out, and a second picture reuses the first one's pieces.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Region(kind, fields)
    local r = { kind = kind, shown = true, alpha = 1, layer = "ARTWORK" }
    for k, v in pairs(fields or {}) do r[k] = v end
    function r:GetObjectType() return self.kind end
    function r:IsShown() return self.shown end
    function r:GetAlpha() return self.alpha end
    function r:GetDrawLayer() return self.layer, 0 end
    function r:GetLeft() return self.left end
    function r:GetTop() return self.top end
    function r:GetWidth() return self.w or 10 end
    function r:GetHeight() return self.h or 10 end
    function r:GetAtlas() return self.atlas end
    function r:GetTexture() return self.file end
    function r:GetTexCoord() return 0, 1, 0, 1 end
    function r:GetVertexColor() return 1, 1, 1, 1 end
    function r:GetFont() return "font", 12, "" end
    function r:GetTextColor() return 1, 0.82, 0, 1 end
    function r:GetJustifyH() return "LEFT" end
    function r:GetText() return self.text end
    return r
end

local function Copy(kind)
    local c = { kind = kind, shown = true, points = {} }
    function c:ClearAllPoints() self.points = {} end
    function c:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function c:SetSize(w, h) self.w, self.h = w, h end
    function c:Show() self.shown = true end
    function c:Hide() self.shown = false end
    function c:SetAtlas(a) self.atlas = a end
    function c:SetTexture(f) self.file = f end
    function c.SetTexCoord() end
    function c.SetVertexColor() end
    function c:SetDrawLayer(layer) self.layer = layer end
    function c.SetFont() end
    function c.SetTextColor() end
    function c.SetJustifyH() end
    function c:SetText(t) self.text = t end
    return c
end

_G.CreateFrame = function()
    local f = Copy("frame")
    f.created = {}
    function f:SetAllPoints() self.all = true end
    function f:SetFrameLevel(n) self.level = n end
    function f:SetAlpha(a) self.alpha = a end
    function f:CreateTexture() local t = Copy("texture"); self.created[#self.created + 1] = t; return t end
    function f:CreateFontString() local t = Copy("font"); self.created[#self.created + 1] = t; return t end
    return f
end

local function Button(regions, shown)
    local b = Region("Button")
    b.shown = shown ~= false
    function b:IsObjectType(kind) return kind == "Button" end
    function b:GetRegions() return unpack(regions) end
    function b:GetChildren() end
    return b
end

local function Plain(children)
    local f = Region("Frame")
    function f.IsObjectType() return false end
    function f:GetChildren() return unpack(children) end
    return f
end

local icon = Region("Texture", { file = 134708, left = 112, top = 488, w = 36, h = 36 })
local name = Region("FontString", { text = "Smelting", left = 152, top = 484, w = 80, h = 12 })
local glow = Region("Texture", { atlas = "glow", left = 112, top = 488, layer = "HIGHLIGHT" })
local gone = Region("Texture", { file = 1, left = 112, top = 488, shown = false })
local spell = Button({ icon, name, glow, gone })
local deep = Region("Texture", { atlas = "profession-icon", left = 112, top = 430 })
local nested = Plain({ Button({ deep }) })
local hidden = Button({ Region("Texture", { file = 2, left = 0, top = 0 }) }, false)
local unlearn = Button({ Region("Texture", { atlas = "cross", left = 400, top = 480 }) })
local blizz = Plain({ spell, nested, hidden, unlearn })
blizz.UnlearnButton = unlearn
local card = { left = 100, top = 500 }
function card:GetLeft() return self.left end
function card:GetTop() return self.top end
function card:GetFrameLevel() return 5 end

_G.NaowhForever = { Professions = { Style = { STAND_IN_ALPHA = 0.7 } } }
dofile("NaowhForever_Professions/UI/BookStandIn.lua")
local StandIn = _G.NaowhForever.Professions.BookStandIn

local function Find(created, key, value)
    for _, c in ipairs(created) do if c[key] == value and c.shown then return c end end
end

local frames = {}
local real = _G.CreateFrame
_G.CreateFrame = function(...)
    local f = real(...)
    frames[#frames + 1] = f
    return f
end
StandIn.Show(card, blizz)
local h = frames[1]
check("the picture sits over the card, dimmed so it reads as not clickable", h and h.all and h.level == 9
    and h.alpha == 0.7 and h.shown)
local iconCopy = Find(h.created, "file", 134708)
check("the button's icon, where it sits on the card, at its size", iconCopy and iconCopy.points[1][1] == "TOPLEFT"
    and iconCopy.points[1][4] == 12 and iconCopy.points[1][5] == -12 and iconCopy.w == 36 and iconCopy.h == 36)
local nameCopy = Find(h.created, "text", "Smelting")
check("and its words", nameCopy and nameCopy.points[1][4] == 52 and nameCopy.points[1][5] == -16)
check("a button inside a plain frame is found too", Find(h.created, "atlas", "profession-icon") ~= nil)
check("no hover highlight, hidden part, hidden button or unlearn cross", not Find(h.created, "atlas", "glow")
    and not Find(h.created, "file", 1) and not Find(h.created, "file", 2) and not Find(h.created, "atlas", "cross"))
local count = #h.created
StandIn.Show(card, blizz)
check("a second picture reuses the pieces", #h.created == count)
StandIn.Hide()
check("after combat the pictures go", not h.shown and not iconCopy.shown and not nameCopy.shown)

print(checks .. " profession overview stand-in checks passed")
