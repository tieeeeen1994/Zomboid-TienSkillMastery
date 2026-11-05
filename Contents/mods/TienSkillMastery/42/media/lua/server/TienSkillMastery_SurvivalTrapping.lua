--[[
Tien's Skill Mastery: Trapping catch chance (Trapping.Catch). Vanilla 42.21 Lua.

Vanilla: placing a trap runs `TrapBO:create` (server/Traps/BuildingObjects/TrapBO.lua ~3; on a server in MP, where the
build action is completed, locally in single player), which calls `TrapSystem.initObjectModData(isoObject, trapDef,
north, player)` (shared/Traps/TrapSystem.lua ~29); that stores modData.trappingSkill = the placer's Trapping level
(~46; map traps get 5, MOTrap.lua ~96) before `transmitCompleteItemToClients` and the `OnObjectAdded` that builds the
server's `STrapGlobalObject` from the modData (`stateFromIsoObject` ~507 reads `trappingSkill`). Every hourly check
(`STrapGlobalObject:testForAnimal`, server/Traps/STrapGlobalObject.lua ~370) rolls, per animal,
ZombRand(100) < trap + bait + 1.5 x trappingSkill and ZombRand(100) < zone + 1.5 x trappingSkill (~375 / ~378).

The check runs on the server long after placement, often with the placer offline (no player object, so no mastery
lookup), so the bonus is taken at placement like the skill itself: the stored trappingSkill is raised by
points / 1.5, which adds exactly the bonus points to both of vanilla's skill-driven rolls. It is a plain number in the
trap's modData (saved, part of STrapSystem's synced fields ~22, only read by those rolls), so a fraction is fine.

Server / single player only (`TrapBO:create` is the server's; media/lua/server also loads on clients, hence the guard).
]]

if isClient() then return end

require "TienSkillMastery"
require "Traps/TrapSystem"

local M = TienSkillMastery

local function pack(...)
    return { n = select("#", ...), ... }
end

if TrapSystem and TrapSystem.initObjectModData then
    local origInit = TrapSystem.initObjectModData
    TrapSystem.initObjectModData = function(isoObject, trapDef, north, player, ...)
        local r = pack(origInit(isoObject, trapDef, north, player, ...))
        if player and isoObject then
            local v = M.val(player, "Trapping.Catch")
            if v > 0 then
                local modData = isoObject:getModData()
                if type(modData.trappingSkill) == "number" then
                    modData.trappingSkill = modData.trappingSkill + v / 1.5
                end
            end
        end
        return unpack(r, 1, r.n)
    end
end
