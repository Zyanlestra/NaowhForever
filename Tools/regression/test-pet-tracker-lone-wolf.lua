local file = assert(io.open("NaowhForever_QoL/Combat/PetTracker.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n"); file:close()
local first = assert(source:find("local function ShouldHavePet()", 1, true))
local last = assert(source:find("local function Update()", first, true))
local known, hasPet, passive = {}, false, false
local env = {
 class = "HUNTER", CALL_PET = 883, LONE_WOLF = 415370, LONE_WOLF_TAUGHT = 409979,
 S = { Get = function() return true end },
 C_SpellBook = { IsSpellKnown = function(id) return known[id] == true end },
 UnitIsDeadOrGhost = function() return false end,
 UnitOnTaxi = function() return false end,
 UnitAffectingCombat = function() return true end,
 IsInInstance = function() return true end,
 UnitExists = function() return hasPet end,
 PetHasActionBar = function() return true end,
 NUM_PET_ACTION_SLOTS = 1,
 GetPetActionInfo = function() return "PET_MODE_PASSIVE", nil, nil, passive end,
}
local chunk = assert(loadstring(source:sub(first, last - 1) .. "return Warning"))
setfenv(chunk, env)
local warning = chunk()
known[883] = true
assert(warning() == "petMissingText", "hunter without a pet must be warned")
known[415370] = true
assert(warning() == nil, "Lone Wolf hunter without a pet must not be warned")
known[415370] = nil; known[409979] = true
assert(warning() == nil, "either Lone Wolf ID must count")
hasPet, passive = true, true
assert(warning() == "petPassiveText", "Lone Wolf hunter must still get the passive warning")
passive = false
local key, low = warning()
assert(key == "petLowHealthText" and low, "Lone Wolf hunter must still get the low health warning")
print("5 pet tracker Lone Wolf checks passed")
