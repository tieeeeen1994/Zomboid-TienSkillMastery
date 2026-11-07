--[[
Tien's Skill Mastery: Angling's signature, the fish finder (client only, 42.21).

While a master aims a fishing rod at water (`Fishing.Utils.isPlayerAimOnWater`, the aim square from
`Fishing.Utils.getAimCoords`, the same square vanilla casts to), a small readout beside the cursor shows that square's
fish (`Fishing.Utils.getFishNumParams(x, y)`: the count and the bite factor it gives, in words: fished out / few /
good / rich for x0.1 / 0.5 / 1.0 / 1.5) and its trash share (`FishSchoolManager.getInstance():getTrashAbundance`,
percent), the numbers vanilla's `FishingDebugWindow` reads. The bite is rolled on the angler's own game from its own
`FishSchoolManager` (`Bobber:attractFish` is client side), so the readout shows what the master's bites will use.
Not checked: whether two clients' fish counts agree in MP. Drawn in `OnPreUIDraw` with the text manager (player 0,
mouse only: the readout follows the cursor).
]]

if isServer() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local WORDS = {
    [0.1] = "IGUI_TienSkillMastery_FishNone", [0.5] = "IGUI_TienSkillMastery_FishFew",
    [1.0] = "IGUI_TienSkillMastery_FishGood", [1.5] = "IGUI_TienSkillMastery_FishRich",
}

local function readout(player)
    local rod = player:getPrimaryHandItem()
    if not rod or not rod:hasTag(ItemTag.FISHING_ROD) then return nil end
    if not Fishing or not Fishing.Utils or not Fishing.Utils.isPlayerAimOnWater(player) then return nil end
    local x, y = Fishing.Utils.getAimCoords(player)
    if not x then return nil end
    x, y = math.floor(x), math.floor(y)
    local fish = Fishing.Utils.getFishNumParams(x, y)
    local trash = FishSchoolManager.getInstance():getTrashAbundance(x, y) or 0
    local word = getText(WORDS[fish.coeff] or "IGUI_TienSkillMastery_FishGood")
    return getText("IGUI_TienSkillMastery_FishFinder", word, string.format("%d", math.floor(fish.value)),
        string.format("%d", math.floor(trash * 100 + 0.5)))
end

local function onPreUIDraw()
    local player = getSpecificPlayer(0)
    if not player or player:isDead() or player:getJoypadBind() ~= -1 then return end
    if not M.sig(player, "Angling.SigFishFinder") then return end
    local ok, text = pcall(readout, player)
    if not ok or not text then return end
    local tm = getTextManager()
    local x, y = getMouseX() + 24, getMouseY() + 8
    tm:DrawString(UIFont.Small, x + 1, y + 1, text, 0, 0, 0, 0.9)   -- shadow
    tm:DrawString(UIFont.Small, x, y, text, 0.75, 0.95, 1, 1)
end
Events.OnPreUIDraw.Add(onPreUIDraw)
