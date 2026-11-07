--[[
Tien's Skill Mastery: Reloading mastery, reload and rack speed.

Vanilla 42.21 `ISReloadWeaponAction.setReloadSpeed(character, rack)` (shared/TimedActions/ISReloadWeaponAction.lua
~75) sets the anim variable `ReloadSpeed` = 0.8 + 0.1 x Reloading (racking 0.04 x Reloading; panic -0.05 per level
when not racking), x1.15 with an ammo strap, x0.8 for a driver. Every reload action calls it through the table
(`ISEjectMagazine`, `ISInsertMagazine`, `ISLoadBulletsInMagazine`, `ISRackFirearm`, `ISReloadWeaponAction`), on the
client (the clip plays at `ReloadSpeed`) and on the server (`ISReloadWeaponAction.getReloadTime` = base /
`ReloadSpeed` for the emulated anim events; the bullet loops read it too). Gunworks calls the same function and reads
the variable (`ReloadAnim.getReloadSpeed`). So the wrapper multiplies the variable it set, on both sides alike.
`IsoGameCharacter.getReloadingMod` has no callers in 42.21.
]]

require "TienSkillMastery"
require "TimedActions/ISReloadWeaponAction"
local M = TienSkillMastery

local original = ISReloadWeaponAction.setReloadSpeed
if original and not ISReloadWeaponAction.__tsmReload then
    ISReloadWeaponAction.__tsmReload = true
    ISReloadWeaponAction.setReloadSpeed = function(character, rack, ...)
        local results = { original(character, rack, ...) }
        if character then
            local f = M.more(character, "Firearms.ReloadSpeed")
            if f > 1 then
                character:setVariable("ReloadSpeed", character:getVariableFloat("ReloadSpeed", 1.0) * f)
            end
        end
        return unpack(results)
    end
end
