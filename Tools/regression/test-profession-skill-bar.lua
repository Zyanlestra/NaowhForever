-- Run with Lua 5.1 from the repository root: the profession skill bar in the Forever skin. It is the game's
-- bar with the profession's moving fill cut at the skill reached, its flare inside the bar at the tip, and
-- on the window a gryphon (Alliance) or wyvern (Horde) at each end. The fill steps through its picture's
-- own frames (two columns of 34px rows), only while the bar shows. A profession without art keeps a plain
-- fill. Every picture is drawn from its file.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local function Noop() end

local function Region(kind)
    local r = { kind = kind, shown = true, points = {}, alpha = 1 }
    function r:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function r:SetSize(w, h) self.w, self.h = w, h end
    function r:SetWidth(w) self.w = w end
    function r:SetHeight(h) self.h = h end
    function r:GetWidth() return self.w end
    function r:SetShown(on) self.shown = on end
    function r:SetAlpha(a) self.alpha = a end
    function r:SetTexCoord(...) self.coords = { ... } end
    function r:IsVisible() return self.visible end
    return setmetatable(r, { __index = function(_, key) if key:find("^%u") then return Noop end end })
end

local function Frame(kind)
    local f = Region(kind)
    rawset(f, "scripts", {})
    rawset(f, "level", 1)
    function f.CreateTexture() return Region("texture") end
    function f:SetScript(event, fn) self.scripts[event] = fn end
    function f:SetClipsChildren(on) self.clips = on end
    function f:GetFrameLevel() return self.level end
    function f:SetFrameLevel(n) self.level = n end
    function f:SetAllPoints() self.all = true end
    function f:SetStatusBarTexture() self.barTexture = Region("bar texture") end
    function f:GetStatusBarTexture() return self.barTexture end
    local function Fire(self, event) if self.scripts[event] then self.scripts[event](self) end end
    function f:SetMinMaxValues(lo, hi) self.lo, self.hi = lo, hi; Fire(self, "OnMinMaxChanged") end
    function f:GetMinMaxValues() return self.lo or 0, self.hi or 1 end
    function f:SetValue(v) self.value = v; Fire(self, "OnValueChanged") end
    function f:GetValue() return self.value or 0 end
    return f
end

local drawn = {}
local faction = "Alliance"
_G.NaowhForever = {
    Shared = { Parts = { ForeverAtlas = function(texture, name)
        drawn[texture] = name
        return true
    end } },
    Professions = {},
}
_G.CreateFrame = function(kind) return Frame(kind) end
_G.UnitFactionGroup = function() return faction end
local St = { FOREVER_ART_FILES = {} }
local style = Read("Shared/Style.lua")
for name, w, h, l, lw, r, t, th, b in style:gmatch('%["([^"]+)"%] = { file = %d+, w = (%d+), h = (%d+),%s*'
    .. "l = (%d+) / (%d+), r = (%d+) / %d+, t = (%d+) / (%d+), b = (%d+) / %d+ }") do
    St.FOREVER_ART_FILES[name] = { w = tonumber(w), h = tonumber(h), l = l / lw, r = r / lw, t = t / th, b = b / th }
end
_G.NaowhForever.Professions.Style = setmetatable({ WHITE = "white", GOLD_RGB = { r = 1, g = 0.82, b = 0 } },
    { __index = St })
dofile("NaowhForever_Professions/Constants.lua")
dofile("NaowhForever_Professions/UI/SkillBar.lua")
local SkillBar = _G.NaowhForever.Professions.SkillBar

local bar = SkillBar.New(Frame("window"), true)
bar.w = 520
check("the game's bar and its frame", drawn[bar.bg] == "profession-progressbar-bg-c60"
    and drawn[bar.frame] == "profession-progressbar-frame-c60" and bar.h == SkillBar.HEIGHT)
check("the frame, flare and ends sit above the fill", bar.top.level > bar.level and bar.clip.clips)
check("the flare fits inside the bar", bar.flare.h <= SkillBar.HEIGHT - 6 and bar.flare.points[1][1] == "RIGHT"
    and bar.flare.points[1][2] == bar.clip)
check("and is cut at the bar's inner edge, under the frame", bar.glow.clips and bar.glow.level > bar.level
    and bar.glow.level < bar.top.level and bar.glow.points[1][2] == 4 and bar.glow.points[2][2] == -4)

bar.visible = true
bar:SetMinMaxValues(0, 100)
bar:SetValue(50)
SkillBar.Paint(bar, "alchemy")
check("the open profession's fill and flare", drawn[bar.fill] == "naowh:skillbar-fill-alchemy"
    and drawn[bar.flare] == "naowh:skillbar-flare-alchemy")
local art = St.FOREVER_ART_FILES["naowh:skillbar-fill-alchemy"]
local c = bar.fill.coords
check("its first frame: the top left of its own picture", bar.rows == 30 and bar.frames == 60
    and math.abs(c[1] - art.l) < 1e-9 and math.abs(c[2] - (art.l + (art.r - art.l) / 2)) < 1e-9
    and math.abs(c[3] - art.t) < 1e-9 and math.abs(c[4] - (art.t + (art.b - art.t) / 30)) < 1e-9)
check("it moves while the bar shows", bar.scripts.OnUpdate ~= nil)
bar.scripts.OnUpdate(bar, 0.031)
c = bar.fill.coords
check("the next frame is the right column of the same row", bar.step == 1
    and math.abs(c[1] - (art.l + (art.r - art.l) / 2)) < 1e-9 and math.abs(c[3] - art.t) < 1e-9)
bar.scripts.OnUpdate(bar, 0.03 * 2)
c = bar.fill.coords
check("then down a row", bar.step == 3 and math.abs(c[3] - (art.t + (art.b - art.t) / 30)) < 1e-9)
bar.scripts.OnUpdate(bar, 1.8)
check("and round again, never past its last frame", bar.step < 60)
check("cut at the skill reached, the flare at its tip", bar.clip.w == 256 and bar.clip.shown and bar.flare.shown)
check("the plain fill is hidden behind the art", bar.plain.alpha == 0 and bar.clip.alpha == 1)
check("gryphons for the Alliance", drawn[bar.left] == "naowh:gryphon-left" and drawn[bar.right] == "naowh:gryphon-right")
SkillBar.Paint(bar, "enchanting")
check("Enchanting's taller flipbook has more frames", bar.rows == 37 and bar.frames == 74)

bar:SetValue(100)
check("no flare on a full bar", not bar.flare.shown and bar.clip.w == 512)
bar:SetValue(150)
check("a skill past the cap never fills past the bar", bar.clip.w == 512)
bar:SetValue(0)
check("nothing filled at zero", not bar.clip.shown and not bar.flare.shown)
bar.w = 300
bar:SetValue(50)
check("a narrower bar cuts at its own width", bar.clip.w == 146)

faction = "Horde"
SkillBar.Paint(bar, "enchanting")
check("wyverns for the Horde", drawn[bar.left] == "naowh:wyvern-left" and drawn[bar.right] == "naowh:wyvern-right")

bar.visible = false
bar.scripts.OnHide(bar)
check("the fill stops while the window is closed", bar.scripts.OnUpdate == nil)
bar.visible = true
bar.scripts.OnShow(bar)
check("and moves again when it opens", bar.scripts.OnUpdate ~= nil)

SkillBar.Paint(bar, nil)
check("a profession without art keeps a plain fill, still", bar.plain.alpha == 1 and bar.clip.alpha == 0
    and bar.scripts.OnUpdate == nil and not bar.flare.shown)

local card = SkillBar.New(Frame("card"))
card.w = 200
check("a card's bar has no beasts at its ends", card.left == nil and card.right == nil)
SkillBar.Paint(card, "mining")
check("and still the profession's fill", drawn[card.fill] == "naowh:skillbar-fill-mining")

local missing = {}
for _, key in pairs(_G.NaowhForever.Professions.C.ART_KEYS) do
    for _, part in ipairs({ "fill", "flare" }) do
        local name = ("naowh:skillbar-%s-%s"):format(part, key)
        if not St.FOREVER_ART_FILES[name] then missing[#missing + 1] = name end
    end
end
for _, name in ipairs({ "naowh:gryphon-left", "naowh:gryphon-right", "naowh:wyvern-left", "naowh:wyvern-right",
    "profession-progressbar-bg-c60", "profession-progressbar-frame-c60" }) do
    if not St.FOREVER_ART_FILES[name] then missing[#missing + 1] = name end
end
check("every fill, flare and end is drawn from its file", #missing == 0)

local window, takeover = Read("NaowhForever_Professions/UI/Window.lua"), Read("NaowhForever_Professions/UI/Takeover.lua")
check("the window builds it with ends with the skin, the skill text above its frame",
    window:find("P.SkillBar.New(win, true)", 1, true) and window:find("ns.Font(win.rank.top or win.rank,", 1, true))
check("each render paints the open profession's art",
    window:find("if win.forever then P.SkillBar.Paint(win.rank, P.C.ART_KEYS[prof.id]) end", 1, true))
check("a wider window keeps the bar its own width",
    takeover:find("if not win.forever then win.rank:SetWidth(", 1, true))
check("it loads before the overview and the window", Read("NaowhForever_Professions/Professions.xml"):find(
    'UI\\SkillBar.lua"/>%s*<Script file="UI\\Book.lua"/>%s*<Script file="UI\\BookStandIn.lua"/>%s*'
    .. '<Script file="UI\\Window.lua'))

print(checks .. " profession skill bar checks passed")
