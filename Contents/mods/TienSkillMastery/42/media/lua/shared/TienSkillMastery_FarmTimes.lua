--[[
Tien's Skill Mastery: action times of Butchering and Animal Care (shearing).

Provisioning.ButcherTime. The vanilla 42.21 butchering actions that read the skill (shared/TimedActions/Animals) store
`o.perkLevel = Butchering` in `new` and set `o.maxTime = o:getDuration()`:
  ISButcherAnimal:getDuration (~62)            900 - 20 x level   (corpse on the ground)
  ISPutAnimalOnHook:getDuration (~96)          250 - 10 x level
  ISRemoveAnimalFromHook:getDuration (~78)     250 - 10 x level
  ISRemoveHeadFromAnimal:getDuration (~157)    250 - 10 x level
  ISCutAnimalOnHook:getDuration (~76)          150 - 10 x level
  ISRemoveLeatherFromAnimal:getDuration (~121) 400 - 15 x level
  ISRemoveMeatFromAnimal:getDuration (~140)    450 - 15 x level
each returning 1 with `isTimedActionInstant`. None uses emulated anim events for its timing (their `serverStart`s only
claim the hook). `getDuration` is looked up through the class, so one wrapper covers the client's `new` (progress bar
and the client's copy) and the server's `NetTimedAction` (end = `adjustMaxTime(getDuration())` x 20 ms, the table
rebuilt by `Type.new`, which runs the client `new` code again with the server's objects). Both sides compute the same
reduction (a client knows the mastery of its local players). Left alone: `ISGatherBloodFromAnimal` (time does not
use the skill), `ISGetAnimalBones` / `ISKillAnimal` (fixed), instant actions (1).

Homesteading.ShearTime. `ISShearAnimal:new(character, animal, shear)` (~151) sets `timePerLiter` = 100 (60 electric)
- 2 x Husbandry; `getDuration` (~138) = wool x timePerLiter + 1, `serverStart` (~133) emulates an "update" event every
timePerLiter x 20 ms (one shearing step each), and single player's `update` steps every timePerLiter of the game
timer. So the per-litre time is what has to shrink: `new` is wrapped (keeping vanilla's parameter names, which
`NetTimedAction.set` reads from the prototype's locvars to rebuild the action on the server, so the server's `new`
shortens it the same way) and maxTime is taken again from the shortened time.

Homesteading.MilkTime (user, 2026-11-09). `ISMilkAnimal:new(character, animal, bucket, right, all)` (~254) sets
`timePerLiter` = 40, read by `serverStart` (~214: an "update" event every timePerLiter x 20 ms, one `milkAnimal` step
each) and single player's `update` (~129); `getDuration` is -1 (it ends when the milk or the bucket runs out). So the
same wrap as shearing, without the maxTime. On a server the emulator rounds a period up to the next 100 ms update, so
800 ms at 15% off (680) really runs at 700.
]]

require "TienSkillMastery"
require "TimedActions/ISBaseTimedAction"
local M = TienSkillMastery

local BUTCHERING = {
    { "TimedActions/Animals/ISButcherAnimal", function() return ISButcherAnimal end },
    { "TimedActions/Animals/ISPutAnimalOnHook", function() return ISPutAnimalOnHook end },
    { "TimedActions/Animals/ISRemoveAnimalFromHook", function() return ISRemoveAnimalFromHook end },
    { "TimedActions/Animals/ISRemoveHeadFromAnimal", function() return ISRemoveHeadFromAnimal end },
    { "TimedActions/Animals/ISCutAnimalOnHook", function() return ISCutAnimalOnHook end },
    { "TimedActions/Animals/ISRemoveLeatherFromAnimal", function() return ISRemoveLeatherFromAnimal end },
    { "TimedActions/Animals/ISRemoveMeatFromAnimal", function() return ISRemoveMeatFromAnimal end },
}

local function shortenDuration(class, bonusId)
    if not class or type(class.getDuration) ~= "function" or class.__tsmFarmTime then return end
    class.__tsmFarmTime = true
    local original = class.getDuration
    class.getDuration = function(self, ...)
        local results = { original(self, ...) }
        local d = results[1]
        local chr = self.character
        if type(d) == "number" and d > 1 and chr and not chr:isTimedActionInstant() then
            local f = M.less(chr, bonusId)
            if f < 1 then results[1] = d * f end
        end
        return unpack(results)
    end
end

for _, entry in ipairs(BUTCHERING) do
    require(entry[1])
    shortenDuration(entry[2](), "Provisioning.ButcherTime")
end

require "TimedActions/Animals/ISShearAnimal"
if ISShearAnimal and ISShearAnimal.new and not ISShearAnimal.__tsmShearTime then
    ISShearAnimal.__tsmShearTime = true
    local originalNew = ISShearAnimal.new
    -- Parameter names must stay vanilla's (character, animal, shear): the server rebuilds the action from them.
    function ISShearAnimal:new(character, animal, shear, ...)
        local o = originalNew(self, character, animal, shear, ...)
        if o and character and type(o.timePerLiter) == "number" and o.timePerLiter > 0 then
            local f = M.less(character, "Homesteading.ShearTime")
            if f < 1 then
                o.timePerLiter = o.timePerLiter * f
                o.maxTime = o:getDuration()
            end
        end
        return o
    end
end

require "TimedActions/Animals/ISMilkAnimal"
if ISMilkAnimal and ISMilkAnimal.new and not ISMilkAnimal.__tsmMilkTime then
    ISMilkAnimal.__tsmMilkTime = true
    local originalNew = ISMilkAnimal.new
    -- Parameter names must stay vanilla's: the server rebuilds the action from them.
    function ISMilkAnimal:new(character, animal, bucket, right, all, ...)
        local o = originalNew(self, character, animal, bucket, right, all, ...)
        if o and character and type(o.timePerLiter) == "number" and o.timePerLiter > 0 then
            local f = M.less(character, "Homesteading.MilkTime")
            if f < 1 then o.timePerLiter = o.timePerLiter * f end
        end
        return o
    end
end
