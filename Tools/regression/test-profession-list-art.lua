-- Run with Lua 5.1 from the repository root: the recipe list in the Forever skin. A category row wears the
-- game's recipe header (its two ends and a stretched middle), the picked recipe the game's selected row
-- and the one under the mouse its hover; where this client lacks a picture the flat look stays. The
-- header's ends show and hide with the header.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local function Texture(kind)
    local t = { kind = kind, shown = true, points = {}, alpha = 0.25 }
    function t:SetPoint(...) self.points[#self.points + 1] = { ... } end
    function t:ClearAllPoints() self.points = {} end
    function t:SetWidth(w) self.w = w end
    function t:SetShown(on) self.shown = on end
    function t:SetVertexColor(r, g, b, a) self.color = { r, g, b, a } end
    function t:SetAlpha(a) self.alpha = a end
    return t
end

local source = Read("NaowhForever_Professions/UI/RecipeList.lua")
local first = assert(source:find("local function GameArt(texture, atlas)", 1, true))
local last = assert(source:find("local function NewRow(i)", first, true))
local consts = {}
for line in source:gmatch("[^\n]+") do
    if line:find("^local HEAD_CAP") or line:find("_ATLAS = ") then consts[#consts + 1] = line end
end
local heads = assert(source:match('(local HEAD_LEFT, HEAD_MIDDLE, HEAD_RIGHT = [^\n]+\n[^\n]+)'))
local have = {}
local chunk = table.concat(consts, "\n") .. "\n" .. heads .. "\n" .. source:sub(first, last - 1)
    .. "\nreturn ForeverRow, ShowHead"
local load = assert(loadstring(chunk))
setfenv(load, setmetatable({
    Parts = { ForeverAtlas = function(texture, name)
        if not have[name] then return false end
        texture.atlas = name
        return true
    end },
}, { __index = _G }))
local ForeverRow, ShowHead = load()

local function Row()
    local row = { head = Texture("head"), sel = Texture("sel"), hl = Texture("hl") }
    function row:CreateTexture() return Texture("cap") end
    return row
end

for _, name in ipairs({ "professions_recipe_active", "professions_recipe_hover", "professions-recipe-header-left",
    "professions-recipe-header-middle", "professions-recipe-header-right" }) do
    have[name] = true
end
local row = Row()
ForeverRow(row)
check("the picked recipe on the game's selected row, at full strength", row.sel.atlas == "professions_recipe_active"
    and row.sel.alpha == 1 and row.sel.color[1] == 1)
check("the one under the mouse on its hover", row.hl.atlas == "professions_recipe_hover" and row.hl.alpha == 1)
local left, right = row.headCaps and row.headCaps[1], row.headCaps and row.headCaps[2]
check("a category on the game's header: its two ends", left and right
    and left.atlas == "professions-recipe-header-left" and right.atlas == "professions-recipe-header-right"
    and left.w == 14 and right.w == 14)
check("and its middle stretched between them", row.head.atlas == "professions-recipe-header-middle"
    and row.head.points[1][2] == left and row.head.points[2][2] == right)
ShowHead(row, false)
check("the ends hide with the header", not row.head.shown and not left.shown and not right.shown)
ShowHead(row, true)
check("and show with it", row.head.shown and left.shown and right.shown)

have["professions-recipe-header-right"] = nil
have["professions_recipe_active"] = nil
row = Row()
ForeverRow(row)
check("without the header art the flat header stays", row.headCaps == nil and row.head.atlas == nil
    and #row.head.points == 0)
check("and without the selected row the flat one stays", row.sel.atlas == nil and row.sel.alpha == 0.25)
ShowHead(row, false)
check("the flat header still hides", not row.head.shown)

check("only with the skin", source:find("    if ns.foreverSkin then ForeverRow(row) end", 1, true))
check("no straight line round the list", not source:find("ForeverBox", 1, true))
check("no see-through layer under the list with the skin", source:find(
    'if not ns.foreverSkin then ns.Solid(list, "BACKGROUND", T.panel, Style.PANEL_ALPHA):SetAllPoints() end', 1, true))
check("its scroll bar on the game's art, its own track kept to hide", source:find(
    "if ns.foreverSkin then Parts.ForeverScrollArrows(bar, list, -(SCROLL_W + SCROLL_INSET), bar.thumb) end", 1, true)
    and source:find("bar.track = ns.Solid(bar,", 1, true))
check("its scroll grip bronze, not the bright accent", source:find(
    "local grip = ns.foreverSkin and Style.FOREVER_RAIL_RGB[1] or T.accent", 1, true)
    and source:find("bar.thumb:SetColorTexture(grip.r, grip.g, grip.b, THUMB_ALPHA)", 1, true))
local _, uses = source:gsub("ShowHead%(row, [tf]", "")
check("every row kind shows or hides the header through ShowHead", uses == 3
    and not source:find("row.head:Show()", 1, true) and not source:find("row.head:Hide()", 1, true))

print(checks .. " profession list art checks passed")
