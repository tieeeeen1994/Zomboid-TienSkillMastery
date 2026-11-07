--[[
Tien's Skill Mastery: Hunting's signature, a master's traps (42.21, server / single player global object system).

Marking: placing a trap runs `TrapSystem.initObjectModData(isoObject, trapDef, north, player)` (shared/Traps/
TrapSystem.lua ~29, from the server's `TrapBO:create`); a placer with the Hunting signature gets `tsmTrap = true` in
the object's modData. The server's `STrapGlobalObject` reads its state from that modData (`stateFromIsoObject` ->
`fromModData`) and keeps it with `toModData`, which only copy vanilla's fields, so both are wrapped to carry
`tsmTrap` and `tsmDouble`. The mark belongs to the trap: it works with its placer offline (traps are checked hourly,
long after placement) and even if the pick is later removed.

- Sturdy traps (Hunting.SigSturdyTraps): `checkDestroy(square)` (~160, every hour) takes the bait 1 in
  (trap strength + 10) and destroys an unloaded trap 1 in 40 x 1 in trap strength; skipped for a marked trap.
- Live catch (Hunting.SigLiveCatch): taking a live catch out (`addAliveAnimal` ~204, rabbit / mouse / rat / raccoon)
  runs the animal's hunger, thirst and health for rand(hours, hours + 15) updates (`animalAliveHour`, +1 an hour in
  the trap), and gives a corpse if that kills it. For a marked trap only a quarter of the stored hours count.
- Double catch (Hunting.SigDoubleCatch): on a catch (`setAnimal` ~427) a marked trap rolls 25% and keeps
  `tsmDouble`. `removeAnimal(character)` (~269) then hands over the first catch (vanilla clears the trap), the
  wrapper puts the same animal and hours back and runs the same hand-over once more. A second live animal goes into
  the hands like the first (`addAliveAnimal` calls `forceDropHeavyItems`, which sets the first one down). An animal
  that leaves the trap by itself (`removeAnimal()` with no character, ~399) takes the second with it.
]]

if isClient() then return end

require "TienSkillMastery"
require "Traps/TrapSystem"
local M = TienSkillMastery

local function pack(...) return { n = select("#", ...), ... } end

if TrapSystem and TrapSystem.initObjectModData then
    local vanillaInit = TrapSystem.initObjectModData
    TrapSystem.initObjectModData = function(isoObject, trapDef, north, player, ...)
        local r = pack(vanillaInit(isoObject, trapDef, north, player, ...))
        if player and isoObject and M.sig(player, "Hunting.SigSturdyTraps") then
            isoObject:getModData().tsmTrap = true
        end
        return unpack(r, 1, r.n)
    end
end

local T = STrapGlobalObject
if not T or not T.fromModData or not T.toModData then
    print("[TienSkillMastery] STrapGlobalObject not found, Hunting's trap signature not applied")
    return
end

local vanillaFrom, vanillaTo = T.fromModData, T.toModData
function T:fromModData(modData, ...)
    local r = pack(vanillaFrom(self, modData, ...))
    self.tsmTrap = modData and modData.tsmTrap == true or nil
    self.tsmDouble = modData and modData.tsmDouble == true or nil
    return unpack(r, 1, r.n)
end
function T:toModData(modData, ...)
    local r = pack(vanillaTo(self, modData, ...))
    if modData then
        modData.tsmTrap = self.tsmTrap or nil
        modData.tsmDouble = self.tsmDouble or nil
    end
    return unpack(r, 1, r.n)
end

if T.checkDestroy then
    local vanilla = T.checkDestroy
    function T:checkDestroy(...)
        if self.tsmTrap then return end
        return vanilla(self, ...)
    end
end

if T.addAliveAnimal then
    local vanilla = T.addAliveAnimal
    function T:addAliveAnimal(...)
        if self.tsmTrap and type(self.animalAliveHour) == "number" then
            local factor = 4
            self.animalAliveHour = math.floor(self.animalAliveHour / factor)
        end
        return vanilla(self, ...)
    end
end

if T.setAnimal then
    local vanilla = T.setAnimal
    function T:setAnimal(animal, ...)
        local r = pack(vanilla(self, animal, ...))
        if self.tsmTrap and self.animal and self.animal.type and ZombRandFloat(0, 100) < 25 then
            self.tsmDouble = true
        end
        return unpack(r, 1, r.n)
    end
end

if T.removeAnimal then
    local vanilla = T.removeAnimal
    function T:removeAnimal(character, ...)
        if not self.tsmDouble or not character then
            self.tsmDouble = nil
            return vanilla(self, character, ...)
        end
        self.tsmDouble = nil
        local animal, hours = self.animal, self.animalAliveHour
        local r = pack(vanilla(self, character, ...))
        if animal and animal.type then
            self.animal, self.animalAliveHour = animal, hours
            local ok, err = pcall(vanilla, self, character, ...)
            if not ok then print("[TienSkillMastery] double catch failed: " .. tostring(err)) end
        end
        return unpack(r, 1, r.n)
    end
end
