-- Offline behavior checks for the QoL Consumable Bar; these do not emulate client taint,
-- secure clicks, state drivers' secure side or rendering.
local checks = 0
local function check(label, ok) assert(ok, label); checks = checks + 1 end

-- itemID -> { icon, classID, use spell }
local KNOWN = {
    [13446] = { 134830, 0, 17534, 1 },   -- Major Healing Potion
    [5512] = { 135230, 0, 6262, 8 },     -- Healthstone
    [20007] = { 134735, 0, 17535, 2 },   -- an elixir
    [12404] = { 135249, 0, 16138 },   -- a sharpening stone
    [2589] = { 132889, 7, nil, 0 },   -- Linen Cloth, not a consumable
    [18641] = { 133714, 7, 23063, 2 }, -- Dense Dynamite: Trade Goods, Explosives
    [10587] = { 133001, 7, 12543, 3 }, -- Goblin Bomb Dispenser: Trade Goods, Devices
    [4359] = { 133594, 7, nil, 1 },   -- Handful of Bronze Bolts: Trade Goods, Parts
    [10307] = { 134937, 0, 12178, 4 }, -- Scroll of Stamina IV
    [8932] = { 133948, 0, 433, 5 },   -- Alterac Swiss
    [14530] = { 133690, 0, 18610, 7 }, -- Heavy Runecloth Bandage
    [2862] = { 135248, 7, 2828, 0 },  -- Rough Sharpening Stone, filed as a trade good here
    [5509] = { 135230, 0, 6263, 8 },  -- Healthstone, Other Consumables
    [21023] = { 134021, 0, 24869, 5 }, -- Dirge's Kickin' Chimaerok Chops: eating, then Well Fed
}

local function fixture(settings)
    local s = { frames = {}, combat = false, counts = {}, cooldowns = {}, auras = {},
        settings = settings or {}, built = 0, blocked = 0, now = 100, timers = {},
        secretAuras = false, auraReads = 0, bags = {}, focus = {}, mouseDown = false,
        enchant = {}, actions = {}, actionButtons = {}, bindings = {}, macros = {}, labButtons = nil,
        refreshes = 0, registers = 0, macroBodies = {}, macroSettings = {}, macroUpdates = 0 }
    local G = {}
    local function Evaluate(f)
        local rule = rawget(f, 'driver')
        if rule == '[combat] hide; show' then f.shown = not s.combat
        elseif rule == '[combat] show; hide' then f.shown = s.combat end
    end
    local function frame(kind, name, parent, template)
        local f = { kind = kind, scripts = {}, events = {}, shown = true, parent = parent,
            template = template, attrs = {}, level = 1, alpha = 1, mouse = true, scale = 1 }
        -- Methods the bar does not care about are no-ops; a missing field is nil, as on a frame.
        setmetatable(f, { __index = function(_, k) if k:match('^%u') then return function() end end end })
        function f:SetScript(k, fn) self.scripts[k] = fn end
        function f:RegisterEvent(k) self.events[k] = true end
        function f:RegisterUnitEvent(k) self.events[k] = true end
        function f:UnregisterAllEvents() self.events = {} end
        function f:Show() self.shown = true end
        function f:Hide()
            local was = self.shown
            self.shown = false
            if was and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function f:SetShown(v) self.shown = v and true or false end
        function f:IsShown() return self.shown end
        function f:IsVisible() return self.shown end
        function f:SetSize(w, h) assert(type(w) == 'number' and type(h) == 'number'); self.w, self.h = w, h end
        function f:SetHeight(h) self.h = h end
        function f:GetWidth() return self.w or 0 end
        function f:GetFrameLevel() return self.level end
        function f:SetFrameLevel(v) self.level = v end
        function f:GetParent() return self.parent end
        function f:GetName() return name end
        function f:IsMouseOver() return self.over == true end
        function f:HasFocus() return self.focused == true end
        function f:ClearFocus()
            local was = self.focused
            self.focused = false
            if was and self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
        end
        function f:SetFocus()
            self.focused = true
            if self.scripts.OnEditFocusGained then self.scripts.OnEditFocusGained(self) end
        end
        function f:ClearAllPoints() self.point = nil; self.points = {} end
        function f:SetPoint(...)
            local relative = select(2, ...)
            if type(relative) == 'table' and relative.dependsOn == self then error('dependent anchor') end
            self.point = { ... }
            self.points = rawget(self, 'points') or {}
            self.points[(...)] = { ... }
        end
        function f:SetAllPoints(target) self.point = { 'ALL', target } end
        function f:SetAttribute(k, v)
            if self.template == 'SecureActionButtonTemplate' and s.combat then s.blocked = s.blocked + 1 end
            self.attrs[k] = v
        end
        function f:EnableMouse(v) self.mouse = v end
        function f:GetAttribute(k) return self.attrs[k] end
        function f:SetAlpha(v) self.alpha = v end
        function f:SetScale(v) self.scale = v end
        function f:GetHeight() return self.h or 0 end
        function f:EnableMouseWheel(v) self.wheel = v end
        function f:SetHorizontalScroll(v) self.hscroll = v end
        function f:GetHorizontalScroll() return self.hscroll or 0 end
        function f:GetHorizontalScrollRange() return self.hrange or 0 end
        function f:SetText(t) self.text = t end
        function f:GetText() return self.text end
        function f:SetTextColor(r, g, b) self.color = { r, g, b } end
        function f:SetFont(path, size) assert(type(path) == 'string' and type(size) == 'number'); self.fontSize = size; self.font = path end
        function f:GetStringWidth() return #tostring(self.text or '') * (self.fontSize or 10) * 0.6 end
        function f:SetJustifyH(v) self.justify = v end
        function f:SetTexture(t) self.texture = t end
        function f:SetColorTexture() self.texture = 'color' end
        function f:SetDesaturated(v) self.desaturated = v end
        function f:SetCooldown(start, dur) self.cooldown = { start, dur } end
        function f:CreateTexture() return frame('Texture', nil, self) end
        s.frames[#s.frames + 1] = f
        if name then G[name] = f end
        if kind == 'Frame' and name == 'NaowhForeverConsumableBar' then s.built = s.built + 1 end
        return f
    end
    s.frame = frame
    -- An action bar button: its slot, the key text it shows, and whether it is on screen.
    function s.actionButton(slot, hotkey, shown)
        local b = frame('Button')
        b.action, b.shown = slot, shown ~= false
        b.HotKey = frame('FontString', nil, b)
        b.HotKey:SetText(hotkey)
        s.actionButtons[#s.actionButtons + 1] = b
        return b
    end
    local function Control(kind, parent, get, set)
        local c = frame(kind, nil, parent)
        c.get, c.set = get, set
        c._refreshValue = function() c.value = get() end
        return c
    end
    local ns = { THEME = { bg = {}, line = {}, panel = { r = 0, g = 0, b = 0 }, muted = { r = 0.5, g = 0.5, b = 0.5 },
            accent = { r = 0, g = 0.6, b = 1 } },
        Print = function(msg) s.printed = msg end,
        Apply = function() end, ShowRaidReminderAnchorConfig = function() end,
        HideRaidReminderAnchorConfig = function() end,
        Font = function(parent, _, _, c)
            local fs = frame('FontString', nil, parent)
            if c then fs.color = { c.r, c.g, c.b } end
            return fs
        end,
        Border = function() return frame('Border') end,
        Solid = function(parent, layer, color)
            local t = frame('Texture', nil, parent); t.layer, t.solidColor = layer, color; return t
        end,
        Tooltip = function() end,
        NewEditBox = function(parent) return frame('EditBox', nil, parent) end,
        Button = function(parent, text, _, _, fn) local b = frame('Button', nil, parent); b.label = text; b.onClick = fn; return b end,
        PromptText = function(_, _, _, accept) s.prompt = accept end,
        Confirm = function(_, yes) s.confirm = yes end,
        StashOptionsWindow = function() s.windowOpen = false; return true end,
        OpenOptionsWindow = function() s.windowOpen = true end,
        HEALTHSTONES = { 5509, 5510, 5511, 5512 },
        ConsumableMacros = {
            health = { label = 'Health', name = 'NF Health', icon = 134829 },
            mana = { label = 'Mana Potion', name = 'NF Mana', icon = 134855 },
        },
        MacroSettings = {
            Get = function(k) return s.macroSettings[k] end,
            Set = function(k, v) s.macroSettings[k] = v end,
        },
        UpdateManagedMacros = function() s.macroUpdates = s.macroUpdates + 1 end,
        BuffReminderData = { FOOD_SPELLS = { [24869] = true }, WELL_FED = { 19705, 24870 } },
        UI = { CONTENT_PAD = 20, RefreshPage = function() s.refreshes = s.refreshes + 1 end, FontPath = function(key) return key ~= '' and key or 'font.ttf' end,
            AttachMover = function(_, _, onMoved) local m = frame('Mover'); m.onMoved = onMoved; m:Hide(); return m end,
            Keep = function(parent, key, create)
                parent.kept = rawget(parent, 'kept') or {}
                local el = parent.kept[key] or create(parent)
                parent.kept[key] = el; el:Show(); return el
            end,
            FontChoices = function() return { [''] = 'Addon Font', Naowh = 'Naowh' }, { '', 'Naowh' } end,
            BuildToggleControl = function(parent, _, get, set) return Control('Toggle', parent, get, set) end,
            BuildDropdownControl = function(parent, _, _, values, order, get, set)
                local c = Control('Dropdown', parent, get, set); c._values, c._order = values, order; return c
            end,
            BuildSliderCore = function(parent, _, _, _, _, _, _, _, _, _, _, get, set)
                local c = Control('Slider', parent, get, set); return c, frame('EditBox', nil, parent)
            end,
            BuildColorSwatchControl = function(parent, get, set) return Control('Swatch', parent, get, set) end,
            -- A key field: what it binds and is called, read when it refreshes.
            KeyField = function(parent, action, label)
                local f = frame('KeyField', nil, parent)
                f.action, f.labelFn = action, label
                f._refreshValue = function() f.bound = action() end
                s.keyField = f
                return f
            end },
    }
    local defaults = { enabled = true, consumableBar = false, consumableBarItems = {}, consumableBarItemFlags = {},
        consumableBarSize = 36, consumableBarSpacing = 4, consumableBarGrow = 'RIGHT',
        consumableBarCooldown = true, consumableBarTooltip = true,
        consumableBarBackground = false, consumableBarBgAlpha = 0.6, consumableBarHideEmpty = false,
        consumableBarAskNew = false, consumableBarDeclined = {},
        consumableBarFont = '', consumableBarFontSize = 14, consumableBarTextColor = { r = 1, g = 1, b = 1 },
        consumableBarTextPoint = 'BOTTOMRIGHT', consumableBarTextOutside = false,
        consumableBarTextX = 0, consumableBarTextY = 0,
        consumableBarAnchor = 'UIParent', consumableBarAnchorPoint = 'CENTER',
        consumableBarAnchorRelPoint = 'CENTER', consumableBarX = 0, consumableBarY = 0,
        consumableBarKeyFont = '', consumableBarKeySize = 10, consumableBarKeyColor = { r = 0.85, g = 0.85, b = 0.85 },
        consumableBarKeyPoint = 'TOPRIGHT', consumableBarKeyOutside = false, consumableBarKeyX = 0, consumableBarKeyY = 0 }
    ns.QoLSettings = {
        Get = function(k) if s.settings[k] ~= nil then return s.settings[k] end return defaults[k] end,
        Set = function(k, v) s.settings[k] = v end,
    }
    G.NaowhForever = ns
    local env = { _G = G, CreateFrame = frame, GameTooltip = frame('Tooltip'),
        NUM_BAG_SLOTS = 4, WorldFrame = frame('WorldFrame'),
        InCombatLockdown = function() return s.combat end,
        GetTime = function() return s.now end,
        issecretvalue = function(v) return type(v) == 'table' and v.secret == true end,
        strtrim = function(t) return (t:gsub('^%s+', ''):gsub('%s+$', '')) end,
        RegisterStateDriver = function(f, _, rule)
            if s.combat then s.blocked = s.blocked + 1 end
            s.registers = s.registers + 1
            f.driver = rule; Evaluate(f)
        end,
        UnregisterStateDriver = function(f) f.driver = nil end,
        GetMouseFoci = function() return s.focus end,
        RANGE_INDICATOR = 'RANGE',
        tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end,
        GetBindingKey = function(command) return s.bindings[command] end,
        GetBindingText = function(key, short) return short and ('*' .. key) or key end,
        GetMacroInfo = function(index) return s.macros[index] end,
        GetMacroBody = function(name) return s.macroBodies[name] end,
        GetCursorInfo = function() if s.cursor then return s.cursor[1], s.cursor[2] end end,
        ClearCursor = function() s.cursor = nil end,
        LibStub = function(name)
            if name == 'LibActionButton-1.0' and s.labButtons then
                return { GetAllButtons = function() return s.labButtons end }
            end
        end,
        ActionBarButtonEventsFrame = { frames = s.actionButtons },
        GetActionInfo = function(slot) local a = s.actions[slot]; if a then return a[1], a[2] end end,
        IsMouseButtonDown = function() return s.mouseDown end,
        GetWeaponEnchantInfo = function()
            local e = s.enchant
            return e.main ~= nil, e.main, 0, 1, e.off ~= nil, e.off, 0, 2
        end,
        C_Secrets = { ShouldAurasBeSecret = function() return s.secretAuras end },
        C_UnitAuras = { GetPlayerAuraBySpellID = function(id) s.auraReads = s.auraReads + 1; return s.auras[id] end },
        C_Timer = { After = function(delay, fn) s.timers[#s.timers + 1] = { at = s.now + delay, fn = fn } end },
        C_Item = { GetItemInfoInstant = function(id) local k = KNOWN[id]; if k then return id, nil, nil, nil, k[1], k[2], k[4] end end,
            GetItemIconByID = function(id) return KNOWN[id] and KNOWN[id][1] end,
            GetItemNameByID = function(id) return 'Item' .. id end,
            GetItemSpell = function(id) local k = KNOWN[id]; if k and k[3] then return 'Spell', k[3] end end,
            RequestLoadItemDataByID = function() end,
            GetItemCount = function(id) return s.counts[id] or 0 end },
        C_Container = {
            GetItemCooldown = function(id)
                local c = s.cooldowns[id]
                if c then return c[1], c[2], c[3] end
                return 0, 0, 1
            end,
            GetContainerNumSlots = function(bag) return s.bags[bag] and #s.bags[bag] or 0 end,
            GetContainerItemID = function(bag, slot) return s.bags[bag] and s.bags[bag][slot] end,
            GetContainerItemInfo = function(bag, slot)
                local id = s.bags[bag] and s.bags[bag][slot]
                if id then return { itemID = id } end
            end },
        hooksecurefunc = function(t, k, fn) local old = t[k]; t[k] = function(...) old(...); fn(...) end end,
    }
    env.UIParent = frame('Parent', 'UIParent')
    setmetatable(G, { __index = env })
    setmetatable(env, { __index = _G })
    local chunk = assert(loadfile('QoL/NaowhForever_ConsumableBar.lua')); setfenv(chunk, env); chunk()
    s.ns, s.G = ns, G
    for _, f in ipairs(s.frames) do if f.events.PLAYER_LOGIN then s.boot = f end end
    function s.fire(event, unit)
        local all = {}; for i, f in ipairs(s.frames) do all[i] = f end
        for _, f in ipairs(all) do if f.events[event] then f.scripts.OnEvent(f, event, unit) end end
    end
    -- Combat starts and ends the way the client runs it: drivers first, then the events.
    function s.fight(on)
        s.combat = on
        for _, f in ipairs(s.frames) do Evaluate(f) end
        s.fire(on and 'PLAYER_REGEN_DISABLED' or 'PLAYER_REGEN_ENABLED')
    end
    function s.advance(dt)
        s.now = s.now + dt
        local again = true
        while again do
            again = false
            for i, t in ipairs(s.timers) do
                if t.at <= s.now then table.remove(s.timers, i); t.fn(); again = true; break end
            end
        end
    end
    function s.set(k, v) ns.QoLSettings.Set(k, v) end
    function s.listens(event)
        for _, f in ipairs(s.frames) do if f ~= s.boot and f.events[event] then return true end end
        return false
    end
    function s.buttons()
        local out = {}
        for _, f in ipairs(s.frames) do
            if f.template == 'SecureActionButtonTemplate' and f.entry ~= nil then out[#out + 1] = f end
        end
        table.sort(out, function(x, y) return x.slot < y.slot end)
        return out
    end
    s.fire('PLAYER_LOGIN')
    s.bar = G.NaowhForeverConsumableBar
    return s
end

local function driver(f) return rawget(f, 'driver') end

do
    local s = fixture()
    check('disabled builds no bar', s.built == 0)
    check('disabled registers no bag events', not s.listens('BAG_UPDATE_DELAYED'))
    s.set('consumableBarSize', 40)
    check('a setting change while disabled still builds nothing', s.built == 0)
end

do
    local s = fixture({ consumableBar = true })
    check('an empty bar stays hidden', not s.bar.shown)
    s.ns.ShowRaidReminderAnchorConfig()
    check('an empty bar shows in Unlock Mode', s.bar.shown and s.bar.mover.shown and s.bar.w == 36)
    s.ns.HideRaidReminderAnchorConfig()
    check('leaving Unlock Mode hides the empty bar again', not s.bar.shown)
end

do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 5512 } })
    s.counts[13446] = 7
    s.fire('BAG_UPDATE_DELAYED')
    local b = s.buttons()
    check('one button per item', #b == 2)
    check('item buttons use the item on left click', b[1].attrs.type1 == 'item' and b[1].attrs.item1 == 'item:13446')
    check('a carried item shows its count', b[1].count.shown and b[1].count.text == 7 and not b[1].none.shown)
    check('an item the bags are out of shows NONE', b[2].none.shown and not b[2].count.shown)
    check('NONE is red and centered', b[2].none.color[1] == 1 and b[2].none.point[1] == 'CENTER')
    check('an item the bags are out of is grey', b[2].icon.desaturated == true)

    for _, size in ipairs({ 20, 36, 64 }) do
        s.set('consumableBarSize', size)
        local width = b[2].none:GetStringWidth()
        check('NONE fits inside a ' .. size .. 'px icon', width <= size - 4)
        check('NONE reaches toward the edges of a ' .. size .. 'px icon', width >= size - 7)
    end
    local noneSize = b[2].none.fontSize
    s.set('consumableBarFontSize', 30)
    check('NONE follows the icon, not the font size', b[2].none.fontSize == noneSize)

    s.set('consumableBarHideEmpty', true)
    check('Hide When Out hides an empty icon instead of NONE', b[2].alpha == 0 and not b[2].none.shown)
    check('Hide When Out leaves a carried item alone', b[1].alpha == 1)
    s.fight(true)
    s.counts[13446] = 0
    s.fire('BAG_UPDATE_DELAYED')
    check('the last one used in combat hides at once', b[1].alpha == 0)
    s.counts[13446] = 3
    s.fire('BAG_UPDATE_DELAYED')
    check('one looted in combat comes back at once', b[1].alpha == 1 and b[1].count.text == 3)
    s.fight(false)

    s.fight(true)
    local blocked = s.blocked
    s.set('consumableBarItems', { 13446, 5512, 20007 })
    check('a change in combat touches no secure button', s.blocked == blocked and #s.buttons() == 2)
    s.fight(false)
    check('the change applies when combat ends', #s.buttons() == 3)

    s.set('consumableBar', false)
    check('disabling hides the bar', not s.bar.shown)
    check('disabling unregisters bag events', not s.listens('BAG_UPDATE_DELAYED'))
end

do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446 } })
    local count = s.buttons()[1].count
    check('default count sits inside the bottom right corner',
        count.point[1] == 'BOTTOMRIGHT' and count.point[4] == -2 and count.point[5] == 2)
    s.set('consumableBarTextOutside', true)
    check('outside the bottom right corner hangs below it', count.point[1] == 'TOPRIGHT' and count.point[3] == 'BOTTOMRIGHT')
end

-- Hide in Combat
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 5512 },
        consumableBarItemFlags = { [13446] = { combat = true } } })
    local b = s.buttons()
    check('hide in combat puts a state driver on that icon', driver(b[1]) == '[combat] hide; show' and not driver(b[2]))
    s.fight(true)
    check('it hides in a fight, the other stays', not b[1].shown and b[2].shown and s.bar.shown)
    s.fight(false)
    s.set('consumableBarItemFlags', { [13446] = { combat = true }, [5512] = { combat = true } })
    check('every icon hidden in combat hides the bar too', driver(s.bar) == '[combat] hide; show')
    s.ns.ShowRaidReminderAnchorConfig()
    check('Unlock Mode shows every icon', not driver(b[1]) and not driver(s.bar) and b[1].shown)
end

-- Hide After Use: out of combat only; a fight brings the icon back.
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 20007, 12404 },
        consumableBarItemFlags = { [13446] = { used = true }, [20007] = { used = true },
            [12404] = { used = true, track = 'mainhand' } } })
    local potion, elixir, stone = s.buttons()[1], s.buttons()[2], s.buttons()[3]
    check('hide after use listens for buffs and weapon enchants',
        s.listens('UNIT_AURA') and s.listens('UNIT_INVENTORY_CHANGED') and s.listens('BAG_UPDATE_COOLDOWN'))
    check('a ready item shows', potion.shown and elixir.shown and stone.shown)

    s.cooldowns[13446] = { s.now, 120, 1 }
    s.fire('BAG_UPDATE_COOLDOWN')
    check('a potion on cooldown hides out of combat', not potion.shown and driver(potion) == '[combat] show; hide')
    s.fight(true)
    check('a fight brings it back, with its cooldown', potion.shown and potion.timer.shown)
    s.fight(false)
    check('after the fight it hides again', not potion.shown)
    s.advance(121)
    check('it comes back when its cooldown ends', potion.shown)
    s.cooldowns[13446] = { s.now, 1, 1 }
    s.fire('BAG_UPDATE_COOLDOWN')
    check('the global cooldown does not count as used', potion.shown)

    s.auras[17535] = { expirationTime = s.now + 1800 }
    s.fire('UNIT_AURA', 'player')
    check('an elixir hides while its buff is on you', not elixir.shown)
    s.fight(true)
    local reads, blocked = s.auraReads, s.blocked
    s.fire('UNIT_AURA', 'player')
    s.fire('BAG_UPDATE_COOLDOWN')
    check('no aura is read in combat', s.auraReads == reads)
    check('nothing protected changes in combat', s.blocked == blocked)
    check('the elixir shows in the fight', elixir.shown)
    s.fight(false)
    check('and hides after it while the buff lasts', not elixir.shown)
    s.advance(1801)
    check('it comes back when the buff runs out', elixir.shown)

    s.enchant.main = 1800 * 1000
    s.fire('UNIT_INVENTORY_CHANGED', 'player')
    check('a sharpening stone hides while the weapon is enchanted', not stone.shown)
    s.enchant.main = nil
    s.fire('UNIT_INVENTORY_CHANGED', 'player')
    check('it shows once the enchant is gone', stone.shown)
end

-- Hide After Use re-registers a driver only when its rule changes
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 20007 },
        consumableBarItemFlags = { [13446] = { used = true } } })
    local potion = s.buttons()[1]
    s.cooldowns[13446] = { s.now, 120, 1 }
    s.fire('BAG_UPDATE_COOLDOWN')
    local before = s.registers
    for _ = 1, 5 do s.fire('BAG_UPDATE_COOLDOWN') end
    check('a global cooldown with nothing changed registers nothing', s.registers == before)
    s.advance(121)
    check('a rule that changes is registered', potion.shown and driver(potion) == nil)
end

-- Food: hidden while eating and while Well Fed, not only while eating
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 21023 },
        consumableBarItemFlags = { [21023] = { used = true } } })
    s.counts[21023] = 3
    local chops = s.buttons()[1]
    s.auras[24869] = { expirationTime = s.now + 30 }
    s.fire('UNIT_AURA', 'player')
    check('hidden while eating', not chops.shown)
    s.auras[24869] = nil
    s.auras[24870] = { expirationTime = s.now + 900 }
    s.fire('UNIT_AURA', 'player')
    check('still hidden once you stand up Well Fed', not chops.shown)
    s.advance(901)
    check('back when Well Fed runs out', chops.shown)
    s.auras[24870] = { expirationTime = s.now + 900 }
    s.set('consumableBarItemFlags', { [20007] = { used = true } })
    s.set('consumableBarItems', { 20007 })
    check('Well Fed does not hide an item that is not food', s.buttons()[1].shown)
end

-- Hide When Out leaves no button to catch clicks
do
    local s = fixture({ consumableBar = true, consumableBarHideEmpty = true, consumableBarItems = { 13446, 20007 } })
    s.counts[13446], s.counts[20007] = 0, 2
    s.fire('BAG_UPDATE_DELAYED')
    local out, have = s.buttons()[1], s.buttons()[2]
    check('an icon hidden when out takes no clicks', out.alpha == 0 and out.mouse == false and have.mouse == true)
    s.counts[13446] = 1
    s.fire('BAG_UPDATE_DELAYED')
    check('it takes them again once you have one', out.alpha == 1 and out.mouse == true)
    s.fight(true)
    s.counts[13446] = 0
    s.fire('BAG_UPDATE_DELAYED')
    check('in combat it can only fade', out.alpha == 0 and out.mouse == true)
    s.fight(false)
    check('after the fight it stops taking clicks', out.mouse == false)
    s.set('consumableBarHideEmpty', false)
    check('with Hide When Out off, NONE stays clickable', out.mouse == true)
end

-- Show Before It Ends
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 20007 },
        consumableBarItemFlags = { [20007] = { used = true, early = true, earlySeconds = 120 } } })
    local elixir = s.buttons()[1]
    s.auras[17535] = { expirationTime = s.now + 600 }
    s.fire('UNIT_AURA', 'player')
    check('the buff with ten minutes left keeps it hidden', not elixir.shown)
    s.advance(479)
    check('still hidden just over two minutes out', not elixir.shown)
    s.advance(2)
    check('it shows two minutes before the buff ends', elixir.shown)
    s.auras[17535] = { expirationTime = 0 }
    s.fire('UNIT_AURA', 'player')
    check('a buff that never runs out keeps it hidden', not elixir.shown)
end

-- Icons Per Row
do
    local items = {}
    for i = 1, 7 do items[i] = 13446 + i - 1 end
    local s = fixture({ consumableBar = true, consumableBarItems = items, consumableBarPerRow = 3,
        consumableBarSize = 30, consumableBarSpacing = 2 })
    local b = s.buttons()
    check('a full row starts a new one below', s.bar.w == 3 * 32 - 2 and s.bar.h == 3 * 32 - 2)
    check('the fourth icon starts the second row', b[4].point[1] == 'TOPLEFT' and b[4].point[4] == 0 and b[4].point[5] == -32)
    check('the third icon ends the first row', b[3].point[4] == 64 and b[3].point[5] == 0)
    s.set('consumableBarGrow', 'LEFT')
    check('growing left fills rows from the right', b[2].point[1] == 'TOPRIGHT' and b[2].point[4] == -32)
    s.set('consumableBarGrow', 'DOWN')
    check('growing down fills columns, new ones to the right', b[4].point[1] == 'TOPLEFT' and b[4].point[4] == 32
        and b[4].point[5] == 0 and b[2].point[5] == -32)
    check('a column bar is as wide as its columns', s.bar.w == 3 * 32 - 2 and s.bar.h == 3 * 32 - 2)
    s.set('consumableBarGrow', 'UP')
    check('growing up fills columns from the bottom', b[2].point[1] == 'BOTTOMLEFT' and b[2].point[5] == 32)
    s.set('consumableBarPerRow', 12)
    s.set('consumableBarGrow', 'RIGHT')
    check('one row when they all fit', s.bar.h == 30 and s.bar.w == 7 * 32 - 2)
end

-- Show Keybinds
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 5512, 20007 } })
    s.actions[1] = { 'item', 13446 }
    s.actions[25] = { 'item', 5512 }
    s.actions[61] = { 'item', 5512 }
    s.actions[2] = { 'spell', 20007 }
    s.actionButton(1, 'S1')
    s.actionButton(25, 'RANGE')
    s.actionButton(61, 'F3', false)
    s.actionButton(2, '2')
    local b = s.buttons()
    s.advance(0)
    check('keybinds are off by default', not b[1].key.shown)
    check('off, nothing listens for binding changes', not s.listens('UPDATE_BINDINGS'))
    s.set('consumableBarKeybinds', true)
    s.advance(0)
    check('an item on a bound button shows its key', b[1].key.shown and b[1].key.text == 'S1')
    check('the key sits in the top right corner', b[1].key.point[1] == 'TOPRIGHT')
    check('an unbound button is skipped, a bar off screen still counts', b[2].key.text == 'F3')
    check('a spell with the same ID is not the item', not b[3].key.shown)
    s.actionButton(26, 'C5')
    s.actions[26] = { 'item', 5512 }
    s.fire('ACTIONBAR_SLOT_CHANGED')
    check('it waits a frame for the game to redraw its own keys', b[2].key.text == 'F3')
    s.advance(0)
    check('a button on screen wins over one off it', b[2].key.text == 'C5')
    s.fight(true)
    s.actions[1] = nil
    s.fire('ACTIONBAR_SLOT_CHANGED')
    s.advance(0)
    check('keys follow the bars in combat too', not b[1].key.shown)
    s.fight(false)
    s.set('consumableBarKeybinds', false)
    s.advance(0)
    check('switching it off clears the keys and stops listening', not b[2].key.shown and not s.listens('ACTIONBAR_SLOT_CHANGED'))
end

-- Hide Bar in Combat
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 5512 },
        consumableBarItemFlags = { [13446] = { used = true } } })
    s.set('consumableBarHideCombat', true)
    check('the bar hides in combat as a whole', driver(s.bar) == '[combat] hide; show')
    s.fight(true)
    check('a fight hides it, whatever the icons say', not s.bar.shown)
    s.fight(false)
    check('it is back after the fight', s.bar.shown)
    s.ns.ShowRaidReminderAnchorConfig()
    check('Unlock Mode still shows it', not driver(s.bar) and s.bar.shown)
end

-- Custom text set before the switch existed
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446 },
        consumableBarItemFlags = { [13446] = { text = 'OLD' } } })
    check('an item that already had text keeps showing it', s.buttons()[1].custom.shown and s.buttons()[1].custom.text == 'OLD')
end

-- Scan Filters
do
    local cat = function(s, id) return s.ns.ConsumableBarCategory(id) end
    local s = fixture({ consumableBar = true })
    check('potions, elixirs and scrolls by subclass', cat(s, 13446) == 'potion' and cat(s, 20007) == 'elixir'
        and cat(s, 10307) == 'scroll')
    check('food and bandages by subclass', cat(s, 8932) == 'food' and cat(s, 14530) == 'bandage')
    check('a stone is a weapon enhancement, whatever class the game gives it', cat(s, 2862) == 'weapon')
    check('a healthstone has its own kind', cat(s, 5509) == 'healthstone')
    check('cloth is no consumable', cat(s, 2589) == nil)
    check('explosives and devices count, filed as Trade Goods', cat(s, 18641) == 'explosive'
        and cat(s, 10587) == 'device')
    check('other Trade Goods do not', cat(s, 4359) == nil)
    s.bags[0] = { 13446, 2862, 8932, 5509, 2589 }
    s.set('consumableBarSkip', { food = true, weapon = true })
    s.ns.ScanBagsForConsumableBar()
    local items = s.settings.consumableBarItems
    check('scan skips the kinds switched off', #items == 2 and items[1] == 13446 and items[2] == 5509)
    s.set('consumableBarSkip', {})
    s.ns.ScanBagsForConsumableBar()
    check('switched back on, the next scan adds them', #s.settings.consumableBarItems == 4)
end

do
    local s = fixture({ consumableBar = true, consumableBarAskNew = true, consumableBarSkip = { food = true } })
    -- A potion and a food land together; only the potion is a kind still switched on.
    s.bags[0] = { 13446, 8932 }
    s.fire('BAG_UPDATE_DELAYED')
    local ask
    for _, f in ipairs(s.frames) do
        local icon = rawget(f, 'icon')
        if type(icon) == 'table' and rawget(icon, 'tex') then ask = f end
    end
    check('the potion asks', ask and ask.shown and ask.itemID == 13446)
    for _, f in ipairs(s.frames) do
        if f.parent == ask and f.label == 'Add' then f.onClick() end
    end
    check('a kind switched off is never asked about', not ask.shown and #s.settings.consumableBarItems == 1)
end

-- Every icon's button is named after what it holds, so a bound key follows it
do
    local s = fixture({ consumableBar = true, consumableBarKeybinds = true,
        consumableBarItems = { 13446, 20007, 'macro:health' } })
    local potion = s.G.NaowhForeverConsumableBarItem13446
    check('an item\'s button is named by its ID', potion ~= nil and s.buttons()[1] == potion)
    check('the bind action names that button',
        s.ns.ConsumableBarBindAction(13446) == 'CLICK NaowhForeverConsumableBarItem13446:LeftButton'
        and s.ns.ConsumableBarBindAction('macro:health') == 'CLICK NaowhForeverConsumableBarHealth:LeftButton')
    s.bindings['CLICK NaowhForeverConsumableBarItem13446:LeftButton'] = 'CTRL-1'
    s.fire('UPDATE_BINDINGS')
    s.advance(0)
    check('a key bound to it shows on it', potion.key.text == '*CTRL-1')
    s.set('consumableBarItems', { 20007, 13446 })
    s.advance(0)
    check('moved, the same button and key go with it', s.buttons()[2] == potion and potion.slot == 2
        and potion.key.text == '*CTRL-1')
    s.set('consumableBarItems', { 20007 })
    check('taken off the bar, its button is cleared and hidden', potion.entry == nil
        and potion.attrs.type1 == nil and not potion.shown)
    s.set('consumableBarItems', { 20007, 13446 })
    check('back on the bar, it gets the same button', s.buttons()[2] == potion and potion.shown)

    local page = s.frame('Frame', nil, nil)
    page._nsuiCollapsed = false
    s.ns.BuildConsumableBarPreview(page, 0)
    local cells = page.kept.consumableBarPreview.cells
    cells[2].scripts.OnClick(cells[2], 'RightButton')
    local field = s.keyField
    check('an icon\'s settings have a Key row for its button', field and field.action()
        == 'CLICK NaowhForeverConsumableBarItem13446:LeftButton' and field.bound ~= nil)
    check('named after the item', field.labelFn() == 'Item13446 on the Consumable Bar')
    cells[1].scripts.OnClick(cells[1], 'RightButton')
    check('opened for another icon, it binds that one', field.bound
        == 'CLICK NaowhForeverConsumableBarItem20007:LeftButton')
end

-- Consumable macros on the bar: the button runs the Macros module's macro by name
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446 } })
    s.counts[5509] = 1
    s.ns.SetConsumableBarMacro('health', true)
    check('the options page adds it to the end of the bar', s.settings.consumableBarItems[2] == 'macro:health'
        and s.ns.ConsumableBarHasMacro('health') and s.ns.ConsumableBarUsesMacro('health'))
    check('and switches the macro on in Macros', s.macroSettings.health == true and s.macroUpdates > 0)
    local b = s.buttons()[2]
    check('the button runs the macro by name', b.attrs.type1 == 'macro' and b.attrs.macro1 == 'NF Health'
        and b.attrs.item1 == nil and b.attrs.macrotext1 == nil)
    check('its button has a name to bind a key to', s.G.NaowhForeverConsumableBarHealth == b)
    check('not written yet: NONE and the macro icon', b.none.shown and b.icon.texture == 134829 and b.itemID == nil)

    s.macroBodies['NF Health'] = '#showtooltip\n/use item:5509'
    s.fire('UPDATE_MACROS')
    check('once the Macros module writes it, it shows the item', b.itemID == 5509 and b.icon.texture == 135230
        and b.count.text == 1 and not b.none.shown)
    s.fight(true)
    local blocked = s.blocked
    s.counts[13446] = 4
    s.macroBodies['NF Health'] = '#showtooltip\n/use item:13446'
    s.fire('UPDATE_MACROS')
    check('a rewrite needs nothing protected, so it shows even in combat', b.itemID == 13446
        and b.count.text == 4 and s.blocked == blocked and b.attrs.macro1 == 'NF Health')
    s.fight(false)
    s.counts[13446] = 0
    s.fire('BAG_UPDATE_DELAYED')
    check('out of the item the macro still names: NONE', b.none.shown and b.icon.texture == 134830)

    s.ns.SetConsumableBarMacro('health', false)
    check('switching it off takes it off the bar', not s.ns.ConsumableBarHasMacro('health') and #s.buttons() == 1)
    check('its button is cleared and hidden', b.entry == nil and b.attrs.type1 == nil and b.attrs.macro1 == nil
        and not b.shown)
    check('the macro stays switched on in Macros', s.macroSettings.health == true)
    check('and the bar no longer counts as using it', not s.ns.ConsumableBarUsesMacro('health'))
end

do
    local s = fixture({ consumableBar = true, consumableBarItems = { 'macro:mana', 13446, 'macro:health' } })
    local b = s.buttons()
    check('items and macros keep their order on the bar', b[1].entry == 'macro:mana' and b[2].entry == 13446
        and b[3].entry == 'macro:health')
    check('the bar switches on every macro it carries', s.macroSettings.mana and s.macroSettings.health)
    check('the bar listens for macro rewrites', s.listens('UPDATE_MACROS'))
    s.set('consumableBar', false)
    check('a bar switched off uses no macro', not s.ns.ConsumableBarUsesMacro('mana'))
end

-- Keybinds from every kind of bar
do
    local s = fixture({ consumableBar = true, consumableBarKeybinds = true,
        consumableBarItems = { 13446, 5512, 20007, 'macro:health', 'macro:mana' } })
    s.bindings['CLICK NaowhForeverConsumableBarMana:LeftButton'] = 'ALT-M'
    s.actions[3] = { 'item', 13446 }
    local blizz = s.actionButton(3, '')
    blizz.commandName = 'ACTIONBUTTON3'
    s.bindings.ACTIONBUTTON3 = 'SHIFT-3'
    s.actions[40] = { 'item', 5512 }
    local own = s.actionButton(40, 'RANGE')
    own.GetName = function() return 'EUI_Bar2Button4' end
    s.bindings['CLICK EUI_Bar2Button4:Keybind'] = 'F'
    s.actions[90] = { 'item', 20007 }
    local lab = s.frame('Button')
    lab.HotKey = s.frame('FontString', nil, lab)
    lab.HotKey:SetText('Q')
    lab.GetAction = function() return 'action', 90 end
    s.labButtons = { [lab] = true }
    s.actions[7] = { 'macro', 21 }
    s.macros[21] = 'NF Health'
    s.actionButton(7, 'E')
    s.fire('ACTIONBAR_SLOT_CHANGED')
    s.advance(0)
    local b = s.buttons()
    check('a bar that draws its own text: the key bound to the button', b[1].key.text == '*SHIFT-3')
    check('a bar bound by click: that binding', b[2].key.text == '*F')
    check('a LibActionButton bar is read too', b[3].key.text == 'Q')
    check('a macro shows the key of the macro on an action bar', b[4].key.text == 'E')
    check('or the key bound to its own button', b[5].key.text == '*ALT-M')
end

-- EllesmereUI's own buttons, off ActionBarButtonEventsFrame
do
    local s = fixture({ consumableBar = true, consumableBarKeybinds = true, consumableBarItems = { 13446, 5512 } })
    s.actions[37] = { 'item', 13446 }
    local shown = s.frame('CheckButton', 'EABButton37')
    shown.attrs.action = 37
    shown.HotKey = s.frame('FontString', nil, shown)
    shown.HotKey:SetText('S-4')
    -- Keybind text switched off in EllesmereUI: the binding command it set is read instead.
    s.actions[61] = { 'item', 5512 }
    local bare = s.frame('CheckButton', 'EABButton61')
    bare.attrs.action, bare.attrs.binding = 61, 'MULTIACTIONBAR4BUTTON1'
    bare.HotKey = s.frame('FontString', nil, bare)
    bare.HotKey:SetText('')
    s.bindings.MULTIACTIONBAR4BUTTON1 = 'CTRL-1'
    s.fire('ACTIONBAR_SLOT_CHANGED')
    s.advance(0)
    local b = s.buttons()
    check('an EllesmereUI button is found by name', b[1].key.text == 'S-4')
    check('one with its text off shows the key bound to it', b[2].key.text == '*CTRL-1')
end

-- Keybind text settings
do
    local s = fixture({ consumableBar = true, consumableBarKeybinds = true, consumableBarItems = { 13446 },
        consumableBarFont = 'Naowh' })
    local b = s.buttons()[1]
    check('the key sits top right at size 10 by default', b.key.point[1] == 'TOPRIGHT' and b.key.fontSize == 10)
    check('its font follows the count until it has its own', b.key.font == 'Naowh')
    check('and it is light grey', b.key.color[1] == 0.85)
    s.set('consumableBarKeyFont', 'Other')
    s.set('consumableBarKeySize', 16)
    s.set('consumableBarKeyColor', { r = 1, g = 0, b = 0 })
    s.set('consumableBarKeyPoint', 'BOTTOMLEFT')
    s.set('consumableBarKeyOutside', true)
    s.set('consumableBarKeyX', 3)
    check('its own font and size', b.key.font == 'Other' and b.key.fontSize == 16)
    check('its own colour', b.key.color[1] == 1 and b.key.color[2] == 0)
    check('outside the icon at its own point, with the offset', b.key.point[1] == 'TOPLEFT'
        and b.key.point[3] == 'BOTTOMLEFT' and b.key.point[4] == 3)
    local cog, other = s.frame('Button'), s.frame('Button')
    s.ns.ToggleConsumableBarKeyText(cog)
    local popup
    for _, f in ipairs(s.frames) do
        if rawget(f, 'title') and rawget(f, 'title').text == 'Keybind Text' then popup = f end
    end
    check('the cog opens the popup under itself', popup and popup.shown and popup.point[2] == cog
        and popup.point[1] == 'TOP' and popup.point[3] == 'BOTTOM')
    check('it has the text rows', #popup.rows == 7)
    s.ns.ToggleConsumableBarKeyText(cog)
    check('a second click closes it', not popup.shown)
    s.ns.ToggleConsumableBarKeyText(cog)
    s.ns.ToggleConsumableBarKeyText(other)
    check('another cog moves it instead', popup.shown and popup.point[2] == other)
end

-- Dragging onto the preview
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 5512 },
        consumableBarItemFlags = { [5512] = { combat = true } } })
    local page = s.frame('Frame', nil, nil)
    page._nsuiCollapsed = false
    s.ns.BuildConsumableBarPreview(page, 0)
    local box = page.kept.consumableBarPreview
    local cells = box.cells
    local items = function() return table.concat(s.settings.consumableBarItems, ',') end
    check('the box takes a drop', box.mouse == true and box.scripts.OnReceiveDrag ~= nil)
    s.cursor = { 'item', 20007 }
    box.scripts.OnReceiveDrag(box)
    check('an item dropped on the box goes to the end', items() == '13446,5512,20007' and s.cursor == nil)
    s.cursor = { 'item', 8932 }
    cells[2].scripts.OnReceiveDrag(cells[2])
    check('one dropped on an icon goes before it', items() == '13446,8932,5512,20007')
    s.cursor = { 'item', 5512 }
    cells[1].scripts.OnReceiveDrag(cells[1])
    check('one already on the bar moves there', items() == '5512,13446,8932,20007')
    check('and keeps its settings', s.settings.consumableBarItemFlags[5512].combat == true)
    s.cursor = { 'item', 13446 }
    cells[4].scripts.OnReceiveDrag(cells[4])
    check('moving one later lands before the icon dropped on', items() == '5512,8932,13446,20007')
    s.cursor = { 'item', 2589 }
    box.scripts.OnReceiveDrag(box)
    check('cloth is refused and stays on the cursor', items() == '5512,8932,13446,20007' and s.cursor ~= nil
        and s.printed:find('not a consumable') ~= nil)
    cells[5].scripts.OnClick(cells[5], 'LeftButton')
    check('clicking + with cloth on the cursor neither adds it nor asks', items() == '5512,8932,13446,20007'
        and s.prompt == nil)
    s.cursor = { 'item', 10307 }
    cells[5].scripts.OnClick(cells[5], 'LeftButton')
    check('clicking + with an item on the cursor adds it, no prompt', items() == '5512,8932,13446,20007,10307'
        and s.prompt == nil)
    s.macros[21] = 'NF Health'
    s.cursor = { 'macro', 21 }
    box.scripts.OnMouseUp(box)
    check('a consumable macro dropped on it is added', s.ns.ConsumableBarHasMacro('health') and s.cursor == nil)
    s.macros[22] = 'Mount'
    s.cursor = { 'macro', 22 }
    box.scripts.OnReceiveDrag(box)
    check('any other macro is left on the cursor', #s.settings.consumableBarItems == 6 and s.cursor ~= nil)
    s.cursor = { 'spell', 133 }
    cells[1].scripts.OnClick(cells[1], 'RightButton')
    check('a spell is no item: the click does what it always does', s.cursor ~= nil
        and #s.settings.consumableBarItems == 6)
end

-- The preview is always at its real size
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 5512, 20007 } })
    local page = s.frame('Frame', nil, nil)
    page._nsuiCollapsed = false
    local h1 = s.ns.BuildConsumableBarPreview(page, 0)
    local box = page.kept.consumableBarPreview
    check('the preview bar is never scaled', box.bar.scale == 1)
    check('the box fits one row of 36px icons', box.h == 30 + 36 + 6 + 12 and h1 == box.h + 12)
    s.set('consumableBarGrow', 'DOWN')
    s.advance(0)
    check('growing down makes the box taller, not the icons smaller', box.bar.scale == 1 and s.refreshes == 1)
    local h2 = s.ns.BuildConsumableBarPreview(page, 0)
    check('the page lays out the taller box', h2 > h1 and box.h == 30 + 4 * 36 + 3 * 4 + 6 + 12)
    s.set('consumableBarGrow', 'RIGHT')
    s.set('consumableBarPerRow', 24)
    s.set('consumableBarSize', 64)
    box.w = 500
    local many = {}
    for i = 1, 12 do many[i] = 13446 + i end
    s.set('consumableBarItems', many)
    check('a bar wider than the page scrolls sideways', box.view.wheel == true and box.bar.scale == 1)
    check('it says so in the hint', box.hint.text:find('Scroll') ~= nil)
    s.set('consumableBarSize', 20)
    check('one that fits does not take the wheel', box.view.wheel == false)
end

-- Cooldowns
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446 } })
    local timer = s.buttons()[1].timer
    s.cooldowns[13446] = { 100, 120, 1 }
    s.fire('BAG_UPDATE_COOLDOWN')
    check('an item cooldown shows', timer.shown and timer.cooldown[2] == 120)
    s.cooldowns[13446] = { { secret = true }, { secret = true }, 1 }
    s.fire('BAG_UPDATE_COOLDOWN')
    check('a secret cooldown leaves the last one drawn', timer.shown and timer.cooldown[1] == 100)
    s.set('consumableBarCooldown', false)
    check('cooldowns off stops listening for them', not s.listens('BAG_UPDATE_COOLDOWN'))
end

-- The options page preview and an item's settings
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446, 20007, 2589 } })
    local page = s.frame('Frame', nil, nil)
    s.ns.UI.searchScan = {}
    check('the settings search builds no preview', s.ns.BuildConsumableBarPreview(page, 0) == 0 and not rawget(page, 'kept'))
    s.ns.UI.searchScan = nil
    page._nsuiCollapsed = true
    check('a closed feature takes no room', s.ns.BuildConsumableBarPreview(page, 0) == 0)
    page._nsuiCollapsed = false
    local h = s.ns.BuildConsumableBarPreview(page, -100)
    local box = page.kept.consumableBarPreview
    local cells = box.cells
    check('the preview takes room on the page', h > 0 and box.shown)
    check('one cell per item plus the + tile', cells[4].isPlus and cells[4].shown and cells[3].itemID == 2589)

    s.set('consumableBarHideEmpty', true)
    check('an empty item stays in the preview as a ghost', cells[1].alpha > 0 and cells[1].alpha < 1)
    s.set('consumableBarHideEmpty', false)

    cells[4].scripts.OnClick(cells[4], 'LeftButton')
    s.prompt('5512')
    check('the + tile adds items by ID', s.settings.consumableBarItems[4] == 5512 and cells[5].isPlus)

    cells[1].scripts.OnClick(cells[1], 'LeftButton')
    local leftOpened
    for _, f in ipairs(s.frames) do
        if rawget(f, 'rows') and rawget(f, 'icon') and f.shown then leftOpened = true end
    end
    check('a left-click on an icon opens nothing', not leftOpened)
    cells[1].scripts.OnClick(cells[1], 'RightButton')
    local panel
    for _, f in ipairs(s.frames) do if rawget(f, 'rows') then panel = f end end
    check('right-click opens the item settings', panel and panel.shown and panel.title.text == 'Item13446')
    local function row(label)
        for _, r in ipairs(panel.rows) do if r.label.text == label then return r end end
    end
    local function visible(label) local r = row(label); return r and r.shown end
    check('a potion offers Hide After Use', visible('Hide After Use'))
    check('the timer waits for Hide After Use', not visible('Tracks') and not visible('Show Before It Ends'))
    check('custom text waits for its switch', visible('Custom Text') and not visible('Text') and not visible('Font Size'))

    row('Hide in Combat').control.set(true)
    check('Hide in Combat saves per item', s.settings.consumableBarItemFlags[13446].combat == true)
    row('Hide After Use').control.set(true)
    check('Hide After Use opens Tracks and Show Before It Ends', visible('Tracks') and visible('Show Before It Ends'))
    row('Show Before It Ends').control.set(true)
    local step = row('Show With')
    check('the timer shows two minutes to start', step.shown and step.value.text == '2:00 left')
    local minus, plus
    for _, f in ipairs(s.frames) do
        if f.parent == step and f.label == '-' then minus = f end
        if f.parent == step and f.label == '+' then plus = f end
    end
    plus.onClick(); plus.onClick()
    check('+ adds 15 seconds a click', s.settings.consumableBarItemFlags[13446].earlySeconds == 150 and step.value.text == '2:30 left')
    for _ = 1, 20 do minus.onClick() end
    check('- stops at 15 seconds', s.settings.consumableBarItemFlags[13446].earlySeconds == 15)

    row('Custom Text').control.set(true)
    check('the switch shows the text box and every text setting',
        visible('Text') and visible('Font') and visible('Font Size') and visible('Colour')
        and visible('Position') and visible('Outside the Icon') and visible('X Offset') and visible('Y Offset'))
    local textRow = row('Text')
    local editBox
    for _, f in ipairs(s.frames) do if f.parent == textRow and f.kind == 'EditBox' then editBox = f end end
    editBox:SetFocus()
    editBox:SetText('HP')
    editBox.scripts.OnEnterPressed(editBox)
    check('custom text saves to the item', s.settings.consumableBarItemFlags[13446].text == 'HP')
    check('the text settings appear once there is text', visible('Font Size') and visible('Position'))
    check('the icon shows the custom text', cells[1].custom.shown and cells[1].custom.text == 'HP')
    check('custom text sits at the top by default', cells[1].custom.point[1] == 'TOP')
    row('Font Size').control.set(20)
    row('Position').control.set('BOTTOM')
    row('Outside the Icon').control.set(true)
    check('the custom text follows its own settings', cells[1].custom.fontSize == 20 and cells[1].custom.point[1] == 'TOP'
        and cells[1].custom.point[3] == 'BOTTOM')
    check('the font follows the bar unless set', row('Font').control._values[''] == 'Same as Count')
    local lighter
    for _, f in ipairs(s.frames) do
        if f.parent == editBox and f.layer == 'BORDER' and f.solidColor == s.ns.THEME.panel then lighter = f end
    end
    check('the text box has the lighter panel background', lighter ~= nil)
    row('Custom Text').control.set(false)
    check('switching it off hides the text and its settings', not cells[1].custom.shown and not visible('Text')
        and not visible('Font Size'))
    check('switching it off keeps the text for later', s.settings.consumableBarItemFlags[13446].text == 'HP'
        and s.settings.consumableBarItemFlags[13446].textOn == false)
    row('Custom Text').control.set(true)
    check('switching it back on shows it again', cells[1].custom.shown and cells[1].custom.text == 'HP')

    editBox:SetFocus()
    editBox:SetText('ELIX')
    cells[2].scripts.OnClick(cells[2], 'RightButton')
    editBox:ClearFocus()
    check('text typed for one item is not saved to the next', s.settings.consumableBarItemFlags[13446].text == 'ELIX'
        and (s.settings.consumableBarItemFlags[20007] == nil or s.settings.consumableBarItemFlags[20007].text == nil))
    check('the panel switched to the next item', panel.title.text == 'Item20007')

    cells[3].scripts.OnClick(cells[3], 'RightButton')
    check('an item with no use effect has no Hide After Use', not visible('Hide After Use'))
    cells[1].scripts.OnClick(cells[1], 'RightButton')
    row('').control.onClick()
    check('Remove takes the item off and closes the panel',
        s.settings.consumableBarItems[1] == 20007 and not panel.shown)
    check('Remove drops its settings', s.settings.consumableBarItemFlags[13446] == nil)
    cells[1].scripts.OnClick(cells[1], 'RightButton')
    box:Hide()
    check('leaving the page closes the item settings', not panel.shown)
end

-- New consumables ask to be added
do
    local s = fixture({ consumableBar = true, consumableBarAskNew = true, consumableBarItems = { 13446 } })
    s.bags[0] = { 13446, 2589 }
    s.fire('BAG_UPDATE_DELAYED')
    local function popup()
        for _, f in ipairs(s.frames) do
            local icon = rawget(f, 'icon')
            if type(icon) == 'table' and rawget(icon, 'tex') then return f end
        end
    end
    check('what the bags held at first is not asked about', popup() == nil)
    s.bags[1] = { 5512, 2589 }
    s.fire('BAG_UPDATE_DELAYED')
    local ask = popup()
    check('a new consumable asks to be added', ask and ask.shown and ask.text.text:find('Item5512'))
    local add, no
    for _, f in ipairs(s.frames) do
        if f.parent == ask and f.label == 'Add' then add = f end
        if f.parent == ask and f.label == 'No' then no = f end
    end
    add.onClick()
    check('Add puts it on the bar', s.settings.consumableBarItems[2] == 5512 and not ask.shown)

    s.fight(true)
    s.bags[2] = { 20007 }
    s.fire('BAG_UPDATE_DELAYED')
    check('nothing asks in combat', not ask.shown)
    s.fight(false)
    check('it asks when the fight ends', ask.shown and ask.itemID == 20007)
    no.onClick()
    check('No remembers the item', s.settings.consumableBarDeclined[20007] == true and not ask.shown)
    s.bags[2] = {}
    s.fire('BAG_UPDATE_DELAYED')
    s.bags[2] = { 20007 }
    s.fire('BAG_UPDATE_DELAYED')
    check('a declined item never asks again', not ask.shown)
    check('cloth never asks', ask.itemID ~= 2589)
    s.ns.ForgetConsumableBarDeclined()
    check('Ask Again forgets the declined items', next(s.settings.consumableBarDeclined) == nil)
    s.set('consumableBarAskNew', false)
    s.bags[3] = { 12404 }
    s.fire('BAG_UPDATE_DELAYED')
    check('with the option off nothing asks', not ask.shown)
end

-- Scan Bags and Clear
do
    local s = fixture({ consumableBarItems = { 13446 } })
    s.bags[0] = { 13446, 2589, 5512 }
    s.bags[2] = { 20007, 5512 }
    s.ns.ScanBagsForConsumableBar()
    local items = s.settings.consumableBarItems
    check('scan adds the consumables in bag order, once each', #items == 3 and items[2] == 5512 and items[3] == 20007)
    s.ns.ScanBagsForConsumableBar()
    check('a second scan with nothing new says so', s.printed:find('No consumables') ~= nil)
    s.ns.ClearConsumableBar()
    check('clear waits for the confirmation', #s.settings.consumableBarItems == 3)
    s.confirm()
    check('clear removes every item', #s.settings.consumableBarItems == 0)
end

-- The anchor picker
do
    local s = fixture({ consumableBar = true, consumableBarItems = { 13446 } })
    s.windowOpen = true
    local player = s.frame('Button', 'PlayerFrame', s.G.UIParent)
    local portrait = s.frame('Texture', nil, player)
    s.ns.PickConsumableBarAnchor()
    check('picking steps the options window aside', s.windowOpen == false)
    local picker
    for _, f in ipairs(s.frames) do if f.scripts.OnUpdate and rawget(f, 'box') then picker = f end end
    s.focus = { portrait }
    picker.scripts.OnUpdate(picker)
    check('the named frame under the cursor is lit with its name',
        picker.highlight.shown and picker.highlight.text.text == 'PlayerFrame')
    s.focus = { s.bar }
    picker.scripts.OnUpdate(picker)
    check('the bar cannot pick itself', not picker.highlight.shown)
    s.focus = { portrait }
    picker.scripts.OnUpdate(picker)
    s.mouseDown = true
    picker.scripts.OnUpdate(picker)
    check('a click anchors the bar to that frame', s.settings.consumableBarAnchor == 'PlayerFrame' and s.bar.point[2] == player)
    check('picking stops and the window comes back', picker.scripts.OnUpdate == nil and s.windowOpen)
    s.mouseDown = false
    s.ns.PickConsumableBarAnchor()
    picker.box:SetText('NoSuchFrame')
    picker.box.scripts.OnEnterPressed(picker.box)
    check('a typed name that is no frame is refused', s.settings.consumableBarAnchor == 'PlayerFrame'
        and picker.scripts.OnUpdate ~= nil)
    picker.box.scripts.OnEscapePressed(picker.box)
    check('Esc cancels and brings the window back', picker.scripts.OnUpdate == nil and s.windowOpen)
end

do
    local s = fixture()
    local parse = s.ns.ParseConsumableBarItems
    local ids = parse('13446, 5512 13446')
    check('parses IDs once each, in order', #ids == 2 and ids[1] == 13446 and ids[2] == 5512)
    check('drops items the game does not know', parse('99999999') == nil)
    -- Bag items are named Item<id> by the mock.
    s.bags[0] = { 13446, 5512, 20007 }
    ids = parse('item5512')
    check('a name in the bags, case aside', ids and #ids == 1 and ids[1] == 5512)
    ids = parse('Item200')
    check('part of a name', ids and ids[1] == 20007)
    ids = parse('Item2000')
    check('a whole name wins over part of another', ids and ids[1] == 20007)
    local missing
    ids, missing = parse('13446, Item5512, |cffffffff|Hitem:20007::::::::60:::::|h[An, Elixir]|h|r, Thunderfury')
    check('IDs, names and links mixed, in order', ids and #ids == 3 and ids[1] == 13446 and ids[2] == 5512
        and ids[3] == 20007)
    check('a link with a comma in its name is still one item', #missing == 1)
    check('a name that matches nothing is reported', missing[1] == 'Thunderfury')
    s.ns.AddConsumableBarItems()
    s.prompt('Thunderfury')
    check('and the prompt says so', s.printed:find('No item called Thunderfury') ~= nil)
    s.prompt('2589, 13446, 18641')
    check('the + box adds consumables only', s.settings.consumableBarItems[1] == 13446
        and s.settings.consumableBarItems[2] == 18641 and #s.settings.consumableBarItems == 2)
    check('and names what it left out', s.printed:find('Item2589 is not a consumable') ~= nil)
    s.settings.consumableBarItems = nil
    s.prompt('Item13446, nothing')
    check('what was found is still added', s.settings.consumableBarItems[1] == 13446)
end

-- The background: each icon's own piece, so hidden icons leave no empty panel behind
do
    local s = fixture({ consumableBar = true, consumableBarBackground = true, consumableBarBgAlpha = 0.5,
        consumableBarPerRow = 2, consumableBarItems = { 13446, 5512, 20007 } })
    s.counts[13446], s.counts[5512] = 1, 1
    local b = s.buttons()
    local function reach(cell)
        local tl, br = cell.bg.points.TOPLEFT, cell.bg.points.BOTTOMRIGHT
        return -tl[4], br[4], tl[5], -br[5]
    end
    local l, r, t, bo = reach(b[1])
    check('to the edge of the bar: 3px; into the spacing: half of it', l == 3 and r == 2 and t == 3 and bo == 2)
    l, r, t, bo = reach(b[2])
    check('the end of a row reaches past it', l == 2 and r == 3 and t == 3 and bo == 3)
    l, r, t, bo = reach(b[3])
    check('a short last row has its own edges', l == 3 and r == 3 and t == 2 and bo == 3)
    check('shown at the chosen opacity', b[1].bg.shown and b[1].bg.alpha == 0.5)
    s.set('consumableBarHideEmpty', true)
    s.fire('BAG_UPDATE_DELAYED')
    check('an icon hidden when out takes its piece with it', b[3].alpha == 0 and b[1].alpha == 1)
    s.set('consumableBarGrow', 'DOWN')
    l, r, t, bo = reach(b[1])
    check('growing down: neighbours below and to the right', l == 3 and r == 2 and t == 3 and bo == 2)
    l, r, t, bo = reach(b[2])
    check('the bottom of a column reaches past it', l == 3 and r == 3 and t == 2 and bo == 3)
    s.set('consumableBarBackground', false)
    check('switched off, no piece shows', not b[1].bg.shown and not b[2].bg.shown)
    local page = s.frame('Frame', nil, nil)
    page._nsuiCollapsed = false
    s.set('consumableBarBackground', true)
    s.ns.BuildConsumableBarPreview(page, 0)
    local cells = page.kept.consumableBarPreview.cells
    check('the preview draws it the same way, the + tile without', cells[1].bg.shown and not cells[4].bg.shown)
end

print(checks .. ' consumable-bar checks passed')
