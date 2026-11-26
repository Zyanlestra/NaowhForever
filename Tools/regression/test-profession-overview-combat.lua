-- Run with Lua 5.1 from the repository root: the overview in combat. Its cards hold Blizzard's secure
-- profession buttons, which make our window protected, so no protected window may stay up through
-- combat: as combat starts (before the lockdown) each card gets a still picture of its buttons, the real
-- ones go back to the game's window and ours stays up, unprotected, until combat ends, when they dock
-- again. A secure state driver hides ours if it is somehow still protected once the lockdown starts.
local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local function Read(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a"):gsub("\r\n", "\n"); f:close()
    return s
end

local source = Read("NaowhForever_Professions/UI/Takeover.lua")

local function Slice(from)
    local first = assert(source:find(from, 1, true))
    return source:sub(first, assert(source:find("\nend\n", first, true)) + 4)
end

local function Load(chunk, env)
    local fn = assert(loadstring(chunk))
    setfenv(fn, setmetatable(env, { __index = _G }))
    return fn()
end

-- Update: an overview that stood aside as combat started stays ours; one opened in combat is the game's,
-- since only a docked overview has still pictures of its buttons.
local calls, combat, book = {}, false, true
local Update, SetPending = Load("local bookPending\n" .. Slice("local function Update()")
    .. "return Update, function(on) bookPending = on end", {
    On = function() return true end,
    ProfessionsFrame = { IsShown = function() return true end },
    TsmShown = function() return false end,
    BookOpen = function() return book end,
    InCombatLockdown = function() return combat end,
    Links = { Viewing = function() return false end },
    C_TradeSkillUI = { IsTradeSkillGuild = function() return false end },
    R = { Linked = function() return false end, Own = function() return true end, Profession = function() return {} end },
    Activate = function(mode) calls[#calls + 1] = mode end,
    Deactivate = function() calls[#calls + 1] = "off" end,
})
Update()
check("out of combat the overview is our window", calls[1] == "book" and #calls == 1)
calls, combat = {}, true
Update()
check("opened in combat, the overview is the game's", calls[1] == "off" and #calls == 1)
calls = {}
SetPending(true)
Update()
check("one that stood aside as combat started is still ours", calls[1] == "book" and #calls == 1)
SetPending(nil)
calls, book = {}, false
Update()
check("a recipe list is still ours in combat", calls[1] == "craft")

-- Combat starting: PLAYER_REGEN_DISABLED fires before the lockdown, while the cards can still move.
local regen = assert(source:find('event == "PLAYER_REGEN_DISABLED" then', 1, true))
local branch = source:sub(regen, assert(source:find("\n        return\n", regen, true)))
check("as combat starts a docked overview stands aside", branch:find("if bookDocked then StandAside() end", 1, true))
local steps = {}
local cardsOf = { { name = "card 1" }, { name = "card 2" }, { name = "card 3" } }
local StandAside, Pending = Load("local bookPending\n" .. Slice("local function StandAside()")
    .. "return StandAside, function() return bookPending end", {
    bookCards = { [1] = "blizz 1", [3] = "blizz 3" },
    win = { book = { cards = cardsOf } },
    P = { BookStandIn = { Show = function(card, blizz) steps[#steps + 1] = { card, blizz } end } },
    DockBook = function(on) steps[#steps + 1] = on end,
})
StandAside()
local shown = {}
for i = 1, 2 do if type(steps[i]) == "table" then shown[steps[i][2]] = steps[i][1] end end
check("each docked card first gets a still picture of its buttons", shown["blizz 1"] == cardsOf[1]
    and shown["blizz 3"] == cardsOf[3])
check("then the real buttons go back to the game's window", steps[3] == false)
check("and dock again once combat ends", Pending() == true)

-- The guard: a secure state driver of its own, made out of combat when the cards first dock.
local made, attributes, refs, drivers = {}, {}, {}, {}
local win = { name = "win" }
local uiParent = { name = "UIParent" }
local DockBookChunk = "local guard, bookPending\nlocal bookDocked = false\n" .. Slice("local function Guard()")
    .. Slice("local function DockBook(on)") .. "return DockBook, function() return guard end"
local order = {}
local DockBook, Guarded = Load(DockBookChunk, {
    win = win,
    UIParent = uiParent,
    GUARD_DRIVER = assert(source:match('local GUARD_DRIVER = "([^"]+)"')),
    GUARD_SNIPPET = "snippet",
    InCombatLockdown = function() return combat end,
    ProfessionsFrame = { BookPage = { ProfessionsContentFrame = {} } },
    Undock = function() order[#order + 1] = "undock" end,
    DockCards = function() order[#order + 1] = "cards" end,
    P = { BookStandIn = { Hide = function() order[#order + 1] = "pictures off" end } },
    CreateFrame = function(kind, name, parent, template)
        local f = { kind = kind, name = name, parent = parent, template = template }
        function f:SetFrameRef(label, frame) refs[label] = frame; order[#order + 1] = "guard" end
        function f:SetAttribute(key, value) attributes[key] = value end
        made[#made + 1] = f
        return f
    end,
    RegisterStateDriver = function(frame, state, driver) drivers[#drivers + 1] = { frame, state, driver } end,
})
combat = true
DockBook(true)
check("in combat nothing docks and no secure frame is made", #made == 0 and #order == 0)
combat = false
DockBook(false)
DockBook(true)
local guard = Guarded()
check("the first dock makes the guard before the cards come in", guard and order[1] == "guard" and order[2] == "cards")
check("and the still pictures go once the real buttons are back", order[3] == "pictures off")
check("a secure state handler of its own, not our window", guard.template == "SecureHandlerStateTemplate"
    and guard.parent == uiParent and guard.parent ~= win)
check("that knows our window", refs.win == win)
check("and watches combat", drivers[1] and drivers[1][1] == guard and drivers[1][2] == "combat"
    and drivers[1][3] == "[combat] on; off" and attributes["_onstate-combat"] == "snippet")
DockBook(false)
DockBook(true)
check("it is made once", #made == 1 and #drivers == 1)

-- The guard's secure snippet: it only ever hides, and only a protected window.
local snippet = assert(source:match("local GUARD_SNIPPET = %[%[(.-)%]%]"))
local run = assert(loadstring("local self, stateid, newstate = ...\n" .. snippet))
local function Window(protected)
    local w = { shown = true }
    function w:IsProtected() return protected end
    function w:Hide() self.shown = false end
    function w:Show() self.shown = true end
    return w
end
local function Handler(w)
    return { GetFrameRef = function(_, label) return label == "win" and w or nil end }
end
local held = Window(true)
run(Handler(held), "combat", "on")
check("lockdown with our window still protected hides it", not held.shown)
held = Window(false)
run(Handler(held), "combat", "on")
check("an unprotected window is left to our own code", held.shown)
held = Window(true)
held.shown = false
run(Handler(held), "combat", "off")
check("combat ending never shows it again", not held.shown)
held = Window(true)
run(Handler(held), "combat", "off")
check("and hides nothing", held.shown)
check("the snippet never shows anything", not snippet:find("Show", 1, true))

print(checks .. " profession overview combat checks passed")
