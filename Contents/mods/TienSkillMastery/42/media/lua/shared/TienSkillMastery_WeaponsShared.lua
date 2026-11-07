--[[
Tien's Skill Mastery: weapon effects decided wherever vanilla Lua calls them (both sides), 42.21.

- Firearms.JamChance ("less"): a jam is rolled by `HandWeapon.checkJam(player, racking)` (~2132: jam chance x sandbox
  FirearmJamMultiplier, plus a limp-wrist share and wear, then `setJammed(true)` on a roll), called only from
  vanilla Lua: `ISReloadWeaponAction.onShoot` feeding a round and `ISRackFirearm.rackBullet` closing the bolt
  (Gunworks calls vanilla's onShoot). The method is wrapped in HandWeapon's class table
  (`__classmetatables[HandWeapon.class].__index`): a jam this very call made is cleared on a roll of the bonus,
  so jams come that much less often. Lua callers go through the table; Java callers (none in 42.21) would not.
- Axemanship.TreeDamage ("pct"): chopping is `ISChopTreeAction`, whose server copy emulates `ChopTree` every 1500 ms
  (`serverStart` ~109); `animEvent` (~65, not on a client) calls `IsoTree.WeaponHit(character, axe)`, which takes
  `weapon:getTreeDamage()` (x1.5 Ax-pert) off the tree's health and topples it at 0. `getTreeDamage()` is the raw
  value x sharpness and the script has no getter, so the axe cannot be raised and put back exactly; instead the bonus
  share of `getTreeDamage()` comes off the tree (`IsoTree:setHealth`, never below 1) right before vanilla's hit, which
  then fells it as usual. The server's tree is the one that counts. Attacking a tree outside the action is Java only (`CombatManager.processTreeHit`), not covered.
  A shorter emulator period would desync the client's chop animation, so the damage per chop is what grows.
]]

require "TienSkillMastery"
require "TimedActions/ISChopTreeAction"
local M = TienSkillMastery

-- ---------------------------------------------------------------------------------------------------------------
-- Jams
-- ---------------------------------------------------------------------------------------------------------------

local function wrapCheckJam()
    local cmt = __classmetatables and HandWeapon and __classmetatables[HandWeapon.class]
    local index = cmt and cmt.__index
    if type(index) ~= "table" or type(index.checkJam) ~= "function" or index.__tsmCheckJam then return end
    index.__tsmCheckJam = true
    local vanilla = index.checkJam
    index.checkJam = function(self, player, racking, ...)
        local was = self:isJammed()
        local jammed = vanilla(self, player, racking, ...)
        if jammed and not was and player and ZombRandFloat(0, 100) < M.val(player, "Firearms.JamChance") then
            self:setJammed(false)
            return false
        end
        return jammed
    end
end
wrapCheckJam()

-- ---------------------------------------------------------------------------------------------------------------
-- Tree damage
-- ---------------------------------------------------------------------------------------------------------------

if ISChopTreeAction and ISChopTreeAction.animEvent then
    local vanilla = ISChopTreeAction.animEvent
    function ISChopTreeAction:animEvent(event, parameter, ...)
        local axe = self.axe
        if isClient() or event ~= "ChopTree" or not axe or not self.character then
            return vanilla(self, event, parameter, ...)
        end
        local f = M.more(self.character, "Axemanship.TreeDamage")
        if f <= 1 or M.weaponMastery(axe) ~= "Axemanship" then return vanilla(self, event, parameter, ...) end
        local tree = self.tree
        if tree and tree.getHealth then
            local extra = math.floor(axe:getTreeDamage() * (f - 1) + 0.5)
            if extra > 0 then tree:setHealth(math.max(1, tree:getHealth() - extra)) end
        end
        return vanilla(self, event, parameter, ...)
    end
else
    print("[TienSkillMastery] ISChopTreeAction:animEvent not found, Axemanship.TreeDamage not applied")
end
