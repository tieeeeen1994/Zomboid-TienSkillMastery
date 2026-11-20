--[[
Tien's Skill Mastery: milking a stressed animal uses the chance vanilla works out (user, 2026-11-20; always on).

`ISMilkAnimal:stress` (shared/TimedActions/Animals, 42.22.2 ~14) runs once per litre milked (`ISMilkAnimal:milk`,
from `update` in single player, from the emulated "update" anim event on a server every timePerLiter x 20 ms). For an
animal above 40 stress, milked by someone at Animal Care 7 or below, it computes stress - 5 x Animal Care - 5 x the
animal's acceptance level, then overwrites it with `chance = 120;`, so `ZombRand(100) < chance` always passes: the
animal flees, the milk is spilt and the bucket goes on the ground, whatever the skill. `ISShearAnimal:stress` has the
same computation without the override. So Animal Care did nothing for milking below 8, while the Skills tab line
"Chance a stressed animal fights back" (SkillEffectsField.lua) says -5% a level. This is vanilla's stress() with that
line left out; the rest (extra stress, flee, spilt bucket on the ground, sound) is unchanged. It runs where vanilla's
runs: on the server in multiplayer (the client's update skips milk()), locally in single player.

Zomboid Fixes B42 has the same fix behind its sandbox option MilkingStressFix (off by default). Both replace the
function; this one never calls the one it replaced, and Zomboid Fixes' calls what it replaced while its option is
off, so either loading order gives the fixed roll.
]]

require "TimedActions/Animals/ISMilkAnimal"

if not ISMilkAnimal or not ISMilkAnimal.stress then return end

function ISMilkAnimal:stress()
    -- stress can make the animal break from the milking
    if self.animal:getStress() > 40 and self.character:getPerkLevel(Perks.Husbandry) <= 7 then
        local chance = self.animal:getStress()
        chance = chance - (self.character:getPerkLevel(Perks.Husbandry) * 5)
        chance = chance - (self.animal:getAcceptanceLevel(self.character) * 5)

        if ZombRand(100) < chance then
            self.animal:changeStress((ZombRand(3, 8) / 5))

            local sq
            if self.animal:getDZone() then
                sq = self.animal:getRandomSquareInZone()
            end
            if not sq then
                local asq = self.animal:getSquare()
                sq = getSquare(ZombRand(asq:getX() - 5, asq:getX() + 5), ZombRand(asq:getY() - 5, asq:getY() + 5),
                    asq:getZ())
            end
            self.animal:fleeTo(sq)

            self.bucket:getFluidContainer():removeFluid()

            self.character:getInventory():Remove(self.bucket)
            sendRemoveItemFromContainer(self.character:getInventory(), self.bucket)
            self.animal:getSquare():AddWorldInventoryItem(self.bucket, 0, 0, 0)
            self.character:getInventory():setDrawDirty(true)

            self.animal:playStressedSound()
            return true
        end
    end

    return false
end
