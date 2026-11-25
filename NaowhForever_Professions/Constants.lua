-- Constants.lua: the numbers several Professions files share.
local ns = _G.NaowhForever

ns.Professions.C = {
    SEARCH_TIMEOUT = 5,
    BUY_TIMEOUT = 15,
    SEARCH_GAP = 0.3,
    OVERPRICED = 1.25,
    MAX_CRAFTS = 999,
    MAX_ITEMS = 9999,
    COPPER_PER_GOLD = 10000,
    COPPER_PER_SILVER = 100,
    NPC_NAME = 2,
    NPC_FACTION = 3,
    NPC_MAP = 4,
    NPC_X = 5,
    NPC_Y = 6,
    NPC_PRICE = 7,
    ROUND = 0.5,
    PERCENT = 100,
    SKILL_LINE_INDEX = 7,
    QUEUE_DELAY = 0.2,
    FIND_SPELL = { herb = 2383, ore = 2580 },
    SKILL_ORANGE = 25, SKILL_YELLOW = 50, SKILL_GREEN = 100,
    ART_KEYS = { [171] = "alchemy", [164] = "blacksmithing", [333] = "enchanting", [202] = "engineering",
        [182] = "herbalism", [165] = "leatherworking", [186] = "mining", [393] = "skinning", [197] = "tailoring",
        [633] = "lockpicking", [40] = "poisons", [185] = "cooking", [356] = "fishing", [129] = "firstaid" },
}
