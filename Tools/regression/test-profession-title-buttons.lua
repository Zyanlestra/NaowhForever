-- Run with Lua 5.1 from the repository root: the profession window's title-bar buttons line up left of
-- the close button in their set order, whichever are shown, with no overlap and no gap for a hidden one,
-- however late each is added. The Shopping List, Crafting Queue and Disenchant buttons all use it.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local fontReady = true

local function Frame(parent, name)
    local frame = { name = name, parent = parent, shown = true, hooks = {}, w = 50 }
    frame.label = { GetStringWidth = function() return fontReady and #name * 7 or 0 end }
    function frame:GetWidth() return self.w end
    function frame:SetWidth(w) self.w = w end
    function frame:GetParent() return self.parent end
    function frame:IsShown() return self.shown end
    function frame:ClearAllPoints() self.point = nil end
    function frame:SetPoint(...) self.point = { ... } end
    function frame:HookScript(event, fn)
        self.hooks[event] = self.hooks[event] or {}
        table.insert(self.hooks[event], fn)
    end
    local function Fire(self, event)
        for _, fn in ipairs(self.hooks[event] or {}) do fn(self) end
    end
    function frame:Show() if not self.shown then self.shown = true; Fire(self, "OnShow") end end
    function frame:Hide() if self.shown then self.shown = false; Fire(self, "OnHide") end end
    function frame:SetShown(on) if on then self:Show() else self:Hide() end end
    return frame
end

local Render

local function Load()
    _G.NaowhForever = { Professions = { Window = { Render = function() end } } }
    _G.hooksecurefunc = function(t, key, fn)
        local old = t[key]
        t[key] = function(...) old(...); fn(...) end
    end
    dofile("NaowhForever_Professions/UI/TitleButtons.lua")
    Render = _G.NaowhForever.Professions.Window.Render
    local win = Frame(nil, "window")
    win.close = Frame(win, "close")
    return _G.NaowhForever.Professions.TitleButtons, win
end

local function Row(win, ...)
    local want = { ... }
    local anchor = win.close
    for _, button in ipairs(want) do
        local p = button.point
        if not (button.shown and p and p[1] == "RIGHT" and p[2] == anchor and p[3] == "LEFT"
            and p[4] < 0 and p[5] == 0) then
            return false
        end
        anchor = button
    end
    return true
end

local TitleButtons, win = Load()
local shopping, queue = Frame(win, "shopping"), Frame(win, "queue")
shopping:Hide(); queue:Hide()
TitleButtons.Add(shopping, 2)
TitleButtons.Add(queue, 3)
shopping:Show()
check("Shopping List alone sits next to the close button", Row(win, shopping))
queue:Show()
check("the Crafting Queue follows it", Row(win, shopping, queue))

local disenchant = Frame(win, "disenchant")
disenchant:Hide()
TitleButtons.Add(disenchant, 1)
check("a button added hidden moves nothing", Row(win, shopping, queue))
disenchant:Show()
check("Disenchant, added last, still takes the first place and pushes the rest left",
    Row(win, disenchant, shopping, queue))
shopping:Hide()
check("a hidden button in the middle leaves no gap", Row(win, disenchant, queue))
queue:Hide()
check("Disenchant alone sits next to the close button", Row(win, disenchant))
disenchant:Hide(); shopping:Show()
check("switching to another profession puts the Shopping List back next to the close button", Row(win, shopping))

TitleButtons, win = Load()
local only = Frame(win, "disenchant")
TitleButtons.Add(only, 1)
check("with the Shopping List off, Disenchant alone still lines up", Row(win, only))

local function Apart(window, ...)
    for _, button in ipairs({ ... }) do
        if button.w < #button.name * 7 + 16 then return false end
    end
    return Row(window, ...)
end

-- A cold font measures 0 wide, so a button keeps its made width until the window renders again.
fontReady = false
TitleButtons, win = Load()
local link, queued = Frame(win, "link"), Frame(win, "crafting queue")
TitleButtons.Add(link, 1)
TitleButtons.Add(queued, 2)
check("before the font loads the buttons keep their made width", queued.w == 50)
fontReady = true
Render()
check("the next render widens each to its label, so none overlaps", Apart(win, link, queued))
check("a button wider than its label keeps its width", link.w == 50)

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a"):gsub("\r\n", "\n"); file:close()
    return text
end
local add = Read("NaowhForever_Professions/UI/ShoppingAdd.lua")
check("the Shopping List and Crafting Queue buttons are laid out by it",
    add:find("TitleButtons.Add(opener, OPEN_ORDER)", 1, true)
    and add:find("TitleButtons.Add(queueOpener, QUEUE_ORDER)", 1, true))
check("the Disenchant button is laid out by it",
    Read("NaowhForever_Professions/UI/Disenchant.lua"):find("TitleButtons.Add(opener, OPEN_ORDER)", 1, true))
for _, path in ipairs({ "NaowhForever_Professions/UI/ShoppingAdd.lua", "NaowhForever_Professions/UI/Disenchant.lua" }) do
    check(path .. " places no title-bar button itself", not Read(path):find("\"TOPRIGHT\", -OPEN_RIGHT", 1, true))
end
-- On the overview: the buttons that need no open profession show, the others hide, whichever was
-- open before and even when the overview is the first thing opened.
local OVERVIEW = {
    { "ShoppingAdd", "ShowOpeners" }, { "ReagentsWindow", "PlaceOpener" }, { "Alts", "PlaceOpener" },
    { "Disenchant", "HideOpener" }, { "SkillUpPlan", "HideOpener" }, { "Link", "HideOpener" }, { "Tsm", "HideOpener" },
}
local xml = Read("NaowhForever_Professions/Professions.xml")
local bookAt = assert(xml:find("UI\\Book.lua", 1, true))
for _, pair in ipairs(OVERVIEW) do
    local file, fn = pair[1], pair[2]
    local text = Read("NaowhForever_Professions/UI/" .. file .. ".lua")
    check(file .. " answers the overview with " .. fn,
        text:find('hooksecurefunc(P.Book, "Render", ' .. fn .. ")", 1, true))
    check(file .. " loads after the overview", assert(xml:find("UI\\" .. file .. ".lua", 1, true)) > bookAt)
    if fn == "HideOpener" then
        check(file .. " hides its button there",
            text:find("local function HideOpener()\n    if opener then opener:Hide() end\nend", 1, true))
    end
end
check("the Shopping List and Crafting Queue show on the overview as on a recipe",
    add:find("local function ShowOpeners()\n    if opener then opener:SetShown(On()) end\n"
        .. "    if queueOpener then queueOpener:SetShown(QueueOn()) end\nend", 1, true)
    and add:find("function ns.ShoppingListRender(info, last)\n    ShowOpeners()", 1, true))

local helper = assert(xml:find("UI\\TitleButtons.lua", 1, true))
check("it loads after the window and before the buttons",
    helper > assert(xml:find("UI\\Window.lua", 1, true))
    and helper < assert(xml:find("UI\\ShoppingAdd.lua", 1, true))
    and helper < assert(xml:find("UI\\Disenchant.lua", 1, true)))

print(("Profession title buttons regression test: PASS (%d checks)"):format(checks))
