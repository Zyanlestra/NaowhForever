-- Run with Lua 5.1 from the repository root: Death Release Protection covers Release Spirit
-- without becoming part of the death dialog. Forever's dialog sizes itself around every shown
-- child it has; a cover left on it after the death dialog closed stretched the ghost's "enter the
-- instance" dialog, which reuses it with no buttons, to fill the screen.
local settings = { deathRelease = true, deathReleaseHold = 1 }
local instance = "party"
local hook

local function Frame(parent)
    local f = { shown = true, children = {} }
    function f:SetParent(p)
        if self.parent then self.parent.children[self] = nil end
        self.parent = p
        if p then p.children[self] = true end
    end
    function f:GetParent() return self.parent end
    function f:Show() self.shown = true end
    function f:Hide() self.shown = false end
    function f:IsShown() return self.shown end
    function f:SetShown(on) self.shown = on end
    function f:ClearAllPoints() self.anchor = nil end
    function f:SetAllPoints(to) self.anchor = to or self.parent end
    function f:SetPoint() end
    function f:SetFrameLevel(level) self.level = level end
    function f:GetFrameLevel() return self.level or 1 end
    function f:SetScript() end
    function f:IsEnabled() return true end
    function f:CreateTexture() return Frame() end
    function f:SetColorTexture() end
    f:SetParent(parent)
    return f
end

local dialog = Frame()
local container = Frame(dialog)
local release = Frame(container)
function dialog:GetButton1() return release end

-- The frames the dialog sizes itself around: its own shown children.
local function LaidOut()
    local list = {}
    for child in pairs(dialog.children) do
        if child:IsShown() then list[#list + 1] = child end
    end
    return list
end

local env = setmetatable({
    NaowhForever = {
        QoLSettings = { Get = function(key) return settings[key] end },
        THEME = { accent = { r = 0, g = 0.57, b = 0.93 } },
        Tooltip = function() end,
        Shared = { Settings = { Page = function() return { Card = function() end } end } },
    },
    hooksecurefunc = function(name, fn)
        assert(name == "StaticPopup_Show")
        hook = fn
    end,
    CreateFrame = function(_, _, parent) return Frame(parent) end,
    UIParent = Frame(),
    IsInInstance = function() return true, instance end,
    StaticPopup_FindVisible = function(which) return dialog.which == which and dialog or nil end,
}, { __index = _G })
env._G = env
local chunk = assert(loadfile("NaowhForever_QoL/Combat/DeathRelease.lua"))
setfenv(chunk, env)
chunk()

local count = 0
local function Case(name, fn)
    fn()
    count = count + 1
    print("PASS " .. name)
end

local guard
Case("a death in a dungeon covers Release Spirit", function()
    dialog.which, release.shown = "DEATH", true
    hook("DEATH")
    for child in pairs(release.children) do guard = child end
    assert(guard and guard:IsShown(), "cover shown")
    assert(guard:GetParent() == release and guard.anchor == release, "on Release Spirit")
end)
Case("the cover is never one of the dialog's own children", function()
    for _, child in ipairs(LaidOut()) do
        assert(child == container, "the dialog sizes itself around the cover")
    end
end)
Case("the ghost's instance dialog reuses it with no buttons and stays its own size", function()
    dialog.which = "RECOVER_CORPSE_INSTANCE"
    release.shown, container.shown = false, false
    release:ClearAllPoints()
    hook("RECOVER_CORPSE_INSTANCE")
    assert(#LaidOut() == 0, "something of ours is still laid out on the dialog")
end)
Case("a death outside a dungeon or raid leaves the button alone", function()
    instance = "none"
    dialog.which, release.shown, container.shown = "DEATH", true, true
    hook("DEATH")
    assert(not guard:IsShown(), "cover hidden")
    instance = "party"
end)
print(count .. " death release regressions passed")
