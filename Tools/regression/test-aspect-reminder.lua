-- Run with Lua 5.1 from the repository root: the QoL Aspect Reminder, loaded from the real file against
-- stubs. A hunter with none of their own aspects up sees it out of combat, with the best aspect they
-- know as its icon; another hunter's aspect on them does not count. It hides in combat, while auras
-- are secret, mounted, dead or resting, and nothing is built or registered for anyone else.
local Load = dofile("Tools/regression/load_files.lua")

local checks = 0
local function check(label, value) assert(value, label); checks = checks + 1 end

local NOTHING = function() end
local MONKEY, HAWK, HAWK_2, CHEETAH, PACK = 13163, 13165, 14318, 5118, 13159

local function Fixture(opts)
    local state = { class = opts.class or "HUNTER", known = opts.known or {}, auras = {}, combat = false,
        secret = false, mounted = false, dead = false, resting = false, frames = {} }
    local settings = { enabled = true, aspectReminder = opts.on ~= false, aspectHideResting = true,
        aspectShowIcon = true, aspectColor = { r = 1, g = 0, b = 0 }, aspectClassColor = false, aspectFont = "",
        aspectFontSize = 20, aspectOutline = "OUTLINE", aspectBackground = "none", aspectText = "No Aspect" }
    local hooks = {}
    local S = { Get = function(k) return settings[k] end }
    function S.Set(k, v) settings[k] = v end

    local function Frame(name)
        local f = { events = {}, scripts = {}, shown = true, name = name }
        setmetatable(f, { __index = function(_, key)
            if type(key) == "string" and key:find("^%u") then return NOTHING end
        end })
        function f:RegisterEvent(e) self.events[e] = true end
        function f:RegisterUnitEvent(e) self.events[e] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:Show() self.shown = true end
        function f:Hide() self.shown = false end
        function f:IsShown() return self.shown end
        function f:CreateTexture()
            local t = Frame()
            function t.SetTexture(_, tex) t.texture = tex end
            return t
        end
        state.frames[#state.frames + 1] = f
        return f
    end

    local ns = {
        QoLSettings = S, QoLConstants = { ICON_CROP_TIGHT = 0.1, ICON_CROP_TIGHT_HIGH = 0.9 },
        Apply = NOTHING, ShowUnlockMode = NOTHING, HideUnlockMode = NOTHING,
        Font = function()
            local fs = Frame()
            function fs:SetText(text) self.text = text end
            return fs
        end,
        AlertStack = function(frame, order, name, page, card)
            state.stacked = { frame = frame, order = order, name = name, page = page, card = card }
        end,
        Shared = {
            Parts = { HudBackdrop = function() return { SetMode = function(_, mode) return mode end } end,
                HudFont = NOTHING },
            Style = { CARD_PAD = 6 },
            Settings = { Group = function(name) return { group = name } end, Look = function() return {} end,
                Page = function() return { Card = function(_, card) state.card = card end } end },
        },
    }
    local function Hook(t, name, fn)
        if t == S then
            local set = S.Set
            S.Set = function(...) set(...); fn(...) end
        else
            local old = t[name]
            t[name] = function(...) old(...); fn(...) end
        end
        hooks[#hooks + 1] = name
    end
    local env = setmetatable({
        NaowhForever = ns, UIParent = {},
        CreateFrame = function(_, name) return Frame(name) end,
        hooksecurefunc = Hook,
        issecretvalue = function() return false end,
        UnitClass = function() return "", state.class end,
        UnitAffectingCombat = function() return state.combat end,
        UnitIsDeadOrGhost = function() return state.dead end,
        UnitOnTaxi = function() return false end,
        IsMounted = function() return state.mounted end,
        IsResting = function() return state.resting end,
        RAID_CLASS_COLORS = { HUNTER = { r = 0.67, g = 0.83, b = 0.45 } },
        C_SpellBook = { IsSpellKnown = function(id) return state.known[id] == true end },
        C_UnitAuras = { GetPlayerAuraBySpellID = function(id) return state.auras[id] end },
        C_Secrets = { ShouldAurasBeSecret = function() return state.secret end },
        C_Spell = { GetSpellTexture = function(id) return "tex:" .. id end },
    }, { __index = _G })
    env._G = env
    Load({ "NaowhForever_QoL/Combat/AspectReminder.lua" }, env)
    local events, boot
    for _, f in ipairs(state.frames) do
        if f.scripts.OnEvent and f.events.PLAYER_LOGIN then boot = f elseif f.scripts.OnEvent then events = f end
    end
    boot.scripts.OnEvent(boot, "PLAYER_LOGIN")

    function state.Fire(event, unit) events.scripts.OnEvent(events, event, unit) end
    function state.Alert()
        for _, f in ipairs(state.frames) do
            if f.name == "NaowhForeverAspectReminder" then return f end
        end
    end
    function state.Shown()
        local f = state.Alert()
        return f and f.shown and f.icon.texture or ""
    end
    state.S, state.ns, state.events = S, ns, events
    return state
end

-- Off, or not a hunter: nothing built, nothing registered.
do
    local t = Fixture({ on = false, known = { [HAWK] = true } })
    check("switched off: no frame", t.Alert() == nil)
    check("switched off: no events", next(t.events.events) == nil)
    t = Fixture({ class = "WARRIOR" })
    check("not a hunter: no frame", t.Alert() == nil)
    check("not a hunter: no events", next(t.events.events) == nil)
end

-- A hunter with no aspect up: the best aspect they know, in the Alerts group.
do
    local t = Fixture({ known = { [MONKEY] = true } })
    check("monkey before level 10", t.Shown() == "tex:" .. MONKEY)
    check("says its text", t.Alert().text.text == "No Aspect")
    check("in the Alerts group", t.stacked.order == 7 and t.stacked.card == "QoL/Combat:aspectReminder")
    check("listens for its own auras", t.events.events.UNIT_AURA == true)
    t.known[HAWK], t.known[HAWK_2] = true, true
    t.Fire("SPELLS_CHANGED")
    check("then the best hawk known", t.Shown() == "tex:" .. HAWK_2)

    t.auras[CHEETAH] = { sourceUnit = "player" }
    t.Fire("UNIT_AURA", "player")
    check("cheetah counts", t.Shown() == "")
    t.auras[CHEETAH] = nil
    t.auras[PACK] = { sourceUnit = "party1" }
    t.Fire("UNIT_AURA", "player")
    check("another hunter's pack does not", t.Shown() == "tex:" .. HAWK_2)
    t.auras[PACK] = { sourceUnit = "player" }
    t.Fire("UNIT_AURA", "player")
    check("your own pack does", t.Shown() == "")
    t.auras[PACK] = nil
    t.Fire("UNIT_AURA", "player")
    check("none up again", t.Shown() == "tex:" .. HAWK_2)
end

-- In combat, while auras are secret, mounted, dead or resting: hidden.
do
    local t = Fixture({ known = { [HAWK] = true } })
    t.combat = true
    t.Fire("PLAYER_REGEN_DISABLED")
    check("hidden at the pull", t.Shown() == "")
    t.Fire("UNIT_AURA", "player")
    check("and through the fight", t.Shown() == "")
    t.combat = false
    t.Fire("PLAYER_REGEN_ENABLED")
    check("back once the fight ends", t.Shown() == "tex:" .. HAWK)
    t.secret = true
    t.Fire("UNIT_AURA", "player")
    check("hidden while auras are secret", t.Shown() == "")
    t.secret = false
    t.mounted = true
    t.Fire("PLAYER_MOUNT_DISPLAY_CHANGED")
    check("hidden while mounted", t.Shown() == "")
    t.mounted, t.dead = false, true
    t.Fire("PLAYER_DEAD")
    check("hidden while dead", t.Shown() == "")
    t.dead, t.resting = false, true
    t.Fire("PLAYER_UPDATE_RESTING")
    check("hidden while resting", t.Shown() == "")
    t.S.Set("aspectHideResting", false)
    check("unless Hide While Resting is off", t.Shown() == "tex:" .. HAWK)
    t.S.Set("aspectReminder", false)
    check("switched off: hidden", t.Shown() == "")
    check("switched off: events dropped", next(t.events.events) == nil)
end

-- No aspect known yet: nothing to remind.
do
    local t = Fixture({ known = {} })
    check("no aspect known: hidden", t.Shown() == "")
end

-- The card, and the switch off by default.
do
    local t = Fixture({})
    check("card on the Combat page", t.card.id == "aspectReminder" and t.card.switch == "aspectReminder")
    check("one short sentence of help", not t.card.help:find("%. ") and #t.card.help < 100)
    local env = setmetatable({ NaowhForever = {} }, { __index = _G })
    env._G = env
    Load({ "Core/Features.lua" }, env)
    check("off by default", env.NaowhForever.FEATURES.qol.aspectReminder == false)
end

print(("test-aspect-reminder: %d checks passed"):format(checks))
