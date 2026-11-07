--[[
Tien's Skill Mastery: Construction.QuietWork ("less"), building noise that draws zombies (42.21).

`client/BuildingObjects/TimedActions/ISBuildAction.lua` `update` (~73-104), every build-menu build and barricade:
hammering calls the global `addSound(character, x, y, z, radius, volume)` with 20 x `getHammerSoundMod()` (8 from
Carpentry 4), sawing and a recipe's `craftingBank` with 15. A client's world sound reaches the server through
`WorldSoundManager`, so what this client sends is what zombies hear. While a master's `update` runs, `addSound` is
swapped for one that lowers radius and volume by the bonus (8 -> 4, 15 -> 8 at mastery 10). The sound the player
hears is unchanged.
]]

if isServer() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local function wrap()
    if not ISBuildAction or not ISBuildAction.update or ISBuildAction.__tsmQuiet then return end
    ISBuildAction.__tsmQuiet = true
    local vanilla = ISBuildAction.update
    function ISBuildAction:update(...)
        local chr = self.character
        local f = chr and M.less(chr, "Construction.QuietWork") or 1
        if f >= 1 then return vanilla(self, ...) end
        local original = addSound
        addSound = function(source, x, y, z, radius, volume, ...)
            return original(source, x, y, z, math.max(1, math.ceil((radius or 0) * f)),
                math.max(1, math.ceil((volume or 0) * f)), ...)
        end
        local results = { pcall(vanilla, self, ...) }
        addSound = original
        if not results[1] then error(results[2], 0) end
        return unpack(results, 2)
    end
end
wrap()
Events.OnGameStart.Add(wrap)
