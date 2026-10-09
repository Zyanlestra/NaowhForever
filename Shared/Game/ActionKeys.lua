-- ActionKeys.lua: the keys on action buttons, the game's, LibActionButton bars' and EllesmereUI's (ns.Shared.ActionKeys).
local ns = _G.NaowhForever

local LAB_NAMES = { "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }
local EUI_PREFIX = "EABButton"
local EUI_SLOTS = 180
local CLICK = "CLICK %s:%s"
local CLICK_LEFT, CLICK_KEYBIND = "LeftButton", "Keybind"

local ActionKeys = {}
ns.Shared.ActionKeys = ActionKeys

function ActionKeys.Bound(command)
    local key = GetBindingKey(command)
    return key and GetBindingText(key, true)
end

local function Try(command)
    if type(command) ~= "string" then return nil end
    return ActionKeys.Bound(command)
end

function ActionKeys.OfButton(btn)
    local hotkey = btn.HotKey and btn.HotKey:GetText()
    if hotkey and hotkey ~= "" and hotkey ~= RANGE_INDICATOR then return hotkey end
    local name = btn.GetName and btn:GetName()
    return Try(btn.bindingAction) or Try(btn.commandName) or Try(btn.GetAttribute and btn:GetAttribute("binding"))
        or (name and (Try(CLICK:format(name, CLICK_LEFT)) or Try(CLICK:format(name, CLICK_KEYBIND))))
end

function ActionKeys.Each(visit)
    local frames = ActionBarButtonEventsFrame and ActionBarButtonEventsFrame.frames
    for _, btn in pairs(frames or {}) do visit(btn, btn.action) end
    for slot = 1, EUI_SLOTS do
        local btn = _G[EUI_PREFIX .. slot]
        if btn and btn.GetAttribute then visit(btn, btn:GetAttribute("action")) end
    end
    for _, libName in ipairs(LAB_NAMES) do
        local lab = LibStub and LibStub(libName, true)
        local all = lab and lab.GetAllButtons and lab:GetAllButtons()
        for k, v in pairs(all or {}) do
            local btn = type(k) == "table" and k or v
            local kind, action = btn:GetAction()
            if kind == "action" then
                visit(btn, action)
            elseif kind == "item" then
                visit(btn, nil, tonumber(tostring(action):match("(%d+)")))
            end
        end
    end
end
