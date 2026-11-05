--[[
Tien's Skill Mastery: what each level of the physical and combat skills gives in vanilla 42.21 (shown in the Skills
tab). Sources (decompiled 42.21; IsoGameCharacter = IGC):

Fitness: attack speed +0.02 / level (IGC.calculateCombatSpeed ~9641); endurance regeneration x getRecoveryMod
(IGC ~4600: 0.7 .. 1.6; IsoPlayer ~3065, ~3198); endurance used running / sprinting x getPacingMod (IGC ~4519: 0.9 ..
0.43; IsoPlayer.updateEndurance ~3245); endurance per swing x getFatigueMod (IGC ~4469: 1.0 .. 0.75;
CombatManager ~1269 / ~3864); fall damage x max(0.1, 1 - 0.05 L) (IGC ~2446); fall injury roll -1.5 per level above 4
(~2497); fending off a zombie from the front +2 / level (IGC.testDefense ~13492); falling when a crawler lunges -2 /
level (~14034); climbing check +2 / level (getClimbingFailChanceFloat ~16442); falling when vaulting a fence -1 / level
(ClimbOverFenceState ~552); getting free through a window while a zombie grabs you: 1 - 1 / (5 + L)
(ClimbThroughWindowState ~235); staying up when bumping someone while running +1 / level (IsoMovingObject ~1273);
effort opening windows (OpenWindowState.exert ~210: 0.011 .. 0.002) and hitting doors (IsoDoor ~1312); rope climbing
uses the higher of Strength and Fitness (IGC.getClimbRopeSpeed ~16529, ClimbSheetRopeState ~95).
Strength: carrying capacity = maxWeightBase 8 x getWeightMod (IGC ~4683: 0.8 .. 2.5; BodyDamage ~2066, before traits);
melee damage x getHittingMod (IGC ~4553: 0.75 .. 1.25; CombatManager ~961); shove and knockback x getShovingMod (IGC
~4578; HandWeapon ~2492, IGC ~6154); shove knockdown chance 35 + 2 / level (IsoPlayer.calculateCritChance ~3848);
stomp damage +0.2 / level (CombatManager ~1039); muscle strain from fighting x (15 - L) / 10 (IGC ~16296..16370);
fending off +2 / level; climbing +2 / level; staying up when bumping +1 / level; forcing a locked window: 4 / 6 / 10 / 20
in 100 from levels 2 / 4 / 6 / 8 (OpenWindowState ~182); door damage with a weapon x 0.5 .. 1.7 (IsoDoor ~1279, level 5
= 1.0); firearm recoil delay x (1 - (2 L - 10) / 40) (HandWeapon.getRecoilDelay ~1296); heaviest animal you can pick up
40 + 7 L (IsoAnimal ~3172); dismantling 200 - 10 L (ISDismantleAction ~102, ISMoveableSpriteProps ~4308), sledgehammer
300 - 10 L (ISDestroyStuffAction ~356), rocks / stumps 300 - 10 L (ISPickAxeGroundCoverItem ~210); reeling a fish
x (L + 2.5) / 5 (FishingRod ~186).
Sprinting: run speed +0.05 / level (IGC.calculateWalkSpeed ~9804; capped at 1).
Lightfooted: footstep noise x getLightfootMod (IGC ~4494: 0.99 .. 0.2; DoFootstepSound ~5633); while sneaking a step
makes a zombie-audible sound 1 in min(12, 4 + L) (~5656); animals notice you / ((L + 2) x 0.25)
(BaseAnimalBehavior ~1585).
Nimble: footstep noise x (2 - getNimbleMod) (~5634); fall damage x max(0.1, 1 - 0.05 L) (~2447); fall injury roll
-1.5 / level (~2500); tripping into the dirt after falling on your knees 1 in 4 + L (IGC.fallenOnKnees ~13797);
crawler lunge fall -1 / level; climbing +2 / level; strafe speed min(0.9 + L / 10, 1.5) (~9834); firearm moving
penalty x (1 - (Aiming + Nimble) / 40) (CombatManager.getMovePenalty ~2525); animals notice you / ((L + 2) x 0.25)
(~1586); wall climbing strain uses (Nimble + 2 x Strength) / 3 (ClimbOverWallState ~95).
Sneaking: while sneaking, zombie spotting chance and footstep noise x getSneakSpotMod (IGC ~4397: 0.95 .. 0.4, x 1.2;
IsoZombie ~2168 / ~2618, ~5636); animals notice you / ((L + 2) x 0.3) (~1584).
Melee skills (with a weapon of that skill, `getWeaponLevel`): damage x (0.3 + 0.1 L) (CombatManager
.applyWeaponLevelDamageModifier ~3826, CombatConfig 0.3 / 0.1); attack speed +0.03 / level (~9640); crit +3 / level
(IsoPlayer ~3904); fending off +3 / level (~13491); zombie hits that miss (thump): 16 + getMeleeCombatMod in 100
(BodyDamage ~1258; IGC ~11087: -5, -2, 0, 1, 2, 3, 4, 5, 5, 6, 7); weapon wear roll + L / 2 (getMaintenanceMod ~11165).
Axe / Long Blunt / Spear: damage x1.1 at 3-6, x1.2 from 7 (HandWeapon.getDamageMod ~470); reach x1.2 from 7
(getRangeMod); endurance per swing x0.8 from 8 (getFatigueMod). Axe: knockback x2 from 6 (getKnockbackMod ~538).
Short Blade: the knife stays in the zombie's jaw 1 in (8 + 2 (L + 1)) (3 + ... against an attacking zombie)
(CombatManager ~4024); while you knife a zombie its attack lands 1 in max(0, 9 - 2 (L + 1)), never from level 4
(AttackState ~164; Rand.NextBool(0) is always true).
Maintenance: weapon wear roll 1 in (weapon chance + L + weapon skill / 2) (CombatManager ~528, InventoryItem ~4689).
Aiming (firearm in hand): hit chance + the gun's aiming modifier x L (CombatManager ~2641); crit + crit modifier x L
(IsoPlayer ~3859); range + range modifier x L / 2 (HandWeapon ~899); sight band x (1 + L / 30) far, x (1 - L / 30) near
(HandWeapon ~1606 / ~1621); recoil delay x (1 - L / 40) (~1295); aim-in speed x (1 + 0.05 L) (IGC.updateAimingDelay
~11063); wind penalty (6 - 0.2 L) per wind (CombatManager ~2580); moving penalty x (1 - (Aiming + Nimble) / 40);
jam clearing 8 - 0.5 L (HandWeapon.checkUnJam ~2169); PVP crit from stopping power x (1 + L / 15) (CombatManager
~3291); wounded wild animals drop / (1 + L / 10) sooner (IsoAnimal ~1153).
Reloading: reload speed 0.8 + 0.1 L, racking 0.8 + 0.04 L (ISReloadWeaponAction.setReloadSpeed ~75); aim lost when
racking: aiming time x (0.15 - 0.01 L) (ISRackFirearm ~32).
Skipped as dead in 42.21: getSprintMod and IsoPlayer's getNimbleMod use (only feed isWalking), HandWeapon
getSpeedMod / getToHitMod, getHitChancesMod, getInvAimingMod, getAimingRangeMod, getReloadingMod, Fitness.java's
(strLvl - 5) / 10 (integer division), debug drawing; XP-only rules (Reloading / Aiming XP rates) and cosmetic blood.
]]

require "TienSkillMastery_SkillEffects"
local M = TienSkillMastery

local function tbl(t) return function(L) return t[math.max(0, math.min(10, L)) + 1] end end
local function rel(t, base) return function(L) return (t[math.max(0, math.min(10, L)) + 1] / base - 1) * 100 end end
local function firearm(player)
    local w = player and player:getPrimaryHandItem()
    if w and instanceof(w, "HandWeapon") and w:isAimedFirearm() then return w end
    return nil
end

local RECOVERY = { 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.55, 1.6 }
local PACING = { 0.9, 0.8, 0.75, 0.7, 0.65, 0.6, 0.57, 0.53, 0.49, 0.46, 0.43 }
local FATIGUE = { 1.0, 0.95, 0.92, 0.89, 0.87, 0.85, 0.83, 0.81, 0.79, 0.77, 0.75 }
local WINDOW_EFFORT = { 0.011, 0.01, 0.009, 0.008, 0.007, 0.006, 0.005, 0.004, 0.003, 0.0025, 0.002 }
local WEIGHT = { 0.8, 0.9, 1.07, 1.24, 1.41, 1.58, 1.75, 1.92, 2.09, 2.26, 2.5 }
local HITTING = { 0.75, 0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.2, 1.25 }
local DOOR = { 0.5, 0.63, 0.76, 0.89, 1.02, 1.0, 1.15, 1.27, 1.3, 1.45, 1.7 }
local LIGHTFOOT = { 0.99, 0.9, 0.79, 0.71, 0.65, 0.59, 0.52, 0.45, 0.37, 0.3, 0.2 }
local NIMBLE = { 1.0, 1.1, 1.14, 1.18, 1.22, 1.26, 1.3, 1.34, 1.38, 1.42, 1.5 }
local SNEAK = { 0.95, 0.9, 0.8, 0.75, 0.7, 0.65, 0.6, 0.55, 0.5, 0.45, 0.4 }
local MELEE_MOD = { -5, -2, 0, 1, 2, 3, 4, 5, 5, 6, 7 }

M.addSkillEffects("Fitness", {
    { name = "AttackSpeed", format = "pct", value = function(L) return 2 * L end },
    { name = "EnduranceRegen", format = "mult", value = tbl(RECOVERY) },
    { name = "RunEndurance", format = "mult", value = tbl(PACING) },
    { name = "SwingEndurance", format = "mult", value = tbl(FATIGUE) },
    { name = "FallDamage", format = "pct", value = function(L) return -math.min(90, 5 * L) end },
    { name = "FallInjury", format = "pts", value = function(L) if L > 4 then return -(L - 4) * 1.5 end end },
    { name = "FendOff", format = "pts", value = function(L) return 2 * L end },
    { name = "LungeFall", format = "pts", value = function(L) return -2 * L end },
    { name = "Climbing", format = "pts", value = function(L) return 2 * L end },
    { name = "FenceFall", format = "pts", value = function(L) return -L end },
    { name = "WindowEscape", format = "chance", value = function(L) return (1 - 1 / (5 + L)) * 100 end },
    { name = "Bump", format = "pts", value = function(L) return L end },
    { name = "WindowEffort", format = "pct", value = rel(WINDOW_EFFORT, 0.011) },
    { name = "Rope", unlock = 0 },
})

M.addSkillEffects("Strength", {
    { name = "Capacity", format = "plain", value = function(L) return math.floor(8 * WEIGHT[math.min(10, L) + 1]) end },
    { name = "Damage", format = "mult", value = tbl(HITTING) },
    { name = "Shove", format = "mult", value = tbl(HITTING) },
    { name = "ShoveKnockdown", format = "chance", value = function(L) return 35 + 2 * L end },
    { name = "Stomp", format = "pct", value = function(L) return 20 * L end },
    { name = "Strain", format = "mult", value = function(L) return (15 - L) / 10 end },
    { name = "FendOff", format = "pts", value = function(L) return 2 * L end },
    { name = "Climbing", format = "pts", value = function(L) return 2 * L end },
    { name = "Bump", format = "pts", value = function(L) return L end },
    { name = "ForceWindow", format = "chance", value = function(L)
        if L > 7 then return 20 elseif L > 5 then return 10 elseif L > 3 then return 6 elseif L > 1 then return 4 end
        return 0
    end },
    { name = "DoorDamage", format = "mult", value = tbl(DOOR) },
    { name = "Recoil", format = "mult", value = function(L) return 1 - (2 * L - 10) / 40 end },
    { name = "PickUpAnimal", format = "plain", value = function(L) return 40 + 7 * L end },
    { name = "Dismantle", format = "pct", value = function(L) return -5 * L end },
    { name = "Sledgehammer", format = "pct", value = function(L) return -10 * L / 3 end },
    { name = "Reeling", format = "mult", value = function(L) return (L + 2.5) / 2.5 end },
    { name = "Rope", unlock = 0 },
})

M.addSkillEffects("Sprinting", {
    { name = "RunSpeed", format = "pct", value = function(L) return 5 * L end },
})

M.addSkillEffects("Lightfoot", {
    { name = "Footsteps", format = "mult", value = tbl(LIGHTFOOT) },
    { name = "SneakSound", format = "chance", value = function(L) return 100 / math.min(12, 4 + L) end },
    { name = "Animals", format = "mult", value = function(L) return 0.5 / ((L + 2) * 0.25) end },
})

M.addSkillEffects("Nimble", {
    { name = "StrafeSpeed", format = "mult", value = function(L) return math.min(0.9 + L / 10, 1.5) end },
    { name = "Footsteps", format = "mult", value = function(L) return 2 - NIMBLE[math.min(10, L) + 1] end },
    { name = "FallDamage", format = "pct", value = function(L) return -math.min(90, 5 * L) end },
    { name = "FallInjury", format = "pts", value = function(L) return -1.5 * L end },
    { name = "KneeFall", format = "chance", value = function(L) return 100 / (4 + L) end },
    { name = "LungeFall", format = "pts", value = function(L) return -L end },
    { name = "Climbing", format = "pts", value = function(L) return 2 * L end },
    { name = "MovePenalty", format = "pct", value = function(L) return -2.5 * L end },
    { name = "Animals", format = "mult", value = function(L) return 0.5 / ((L + 2) * 0.25) end },
})

M.addSkillEffects("Sneak", {
    { name = "Spotted", format = "mult", value = function(L) return SNEAK[math.min(10, L) + 1] * 1.2 end },
    { name = "Footsteps", format = "mult", value = function(L) return SNEAK[math.min(10, L) + 1] * 1.2 end },
    { name = "Animals", format = "mult", value = function(L) return 0.6 / ((L + 2) * 0.3) end },
})

local function melee(perkId, extra)
    local list = {
        { name = "WithWeapon", unlock = 0 },
        { name = "Damage", format = "mult", value = function(L) return 0.3 + 0.1 * L end },
        { name = "AttackSpeed", format = "pct", value = function(L) return 3 * L end },
        { name = "Crit", format = "pts", value = function(L) return 3 * L end },
        { name = "FendOff", format = "pts", value = function(L) return 3 * L end },
        { name = "Thump", format = "chance", value = function(L) return 16 + MELEE_MOD[math.min(10, L) + 1] end },
        { name = "Wear", format = "num", value = function(L) return math.floor(L / 2) end },
    }
    for _, e in ipairs(extra or {}) do table.insert(list, e) end
    for _, e in ipairs(list) do e.labelPerk = "Melee" end
    M.addSkillEffects(perkId, list)
end

local heavy = {
    { name = "HeavyDamage", format = "mult", value = function(L) if L >= 7 then return 1.2 elseif L >= 3 then return 1.1 end return 1.0 end },
    { name = "Reach", unlock = 7 },
    { name = "SwingEndurance", unlock = 8 },
}
local function copy(t) local r = {} for i, e in ipairs(t) do local c = {} for k, v in pairs(e) do c[k] = v end r[i] = c end return r end

local axe = copy(heavy)
table.insert(axe, { name = "AxeKnockback", unlock = 6 })
melee("Axe", axe)
melee("Blunt", copy(heavy))
melee("Spear", copy(heavy))
melee("SmallBlunt")
melee("LongBlade")
melee("SmallBlade", {
    { name = "JawStuck", format = "chance", value = function(L) return 100 / (8 + 2 * (L + 1)) end },
    { name = "KnifeKillSafe", format = "chance", value = function(L)
        local n = math.max(0, 9 - 2 * (L + 1))
        if n <= 0 then return 100 end
        return (1 - 1 / n) * 100
    end },
})

M.addSkillEffects("Maintenance", {
    { name = "Wear", format = "num", value = function(L) return L end },
})

M.addSkillEffects("Aiming", {
    { name = "HitChance", format = "pts", note = "IGUI_TienSkillMastery_EffectNote_Gun", value = function(L, p)
        local w = firearm(p) if w then return w:getAimingPerkHitChanceModifier() * L end
    end },
    { name = "Crit", format = "pts", note = "IGUI_TienSkillMastery_EffectNote_Gun", value = function(L, p)
        local w = firearm(p) if w then return w:getAimingPerkCritModifier() * L end
    end },
    { name = "Range", format = "num", note = "IGUI_TienSkillMastery_EffectNote_Gun", value = function(L, p)
        local w = firearm(p) if w then return w:getAimingPerkRangeModifier() * L / 2 end
    end },
    { name = "AimIn", format = "pct", value = function(L) return 5 * L end },
    { name = "SightBand", format = "pct", value = function(L) return 100 * L / 30 end },
    { name = "Recoil", format = "pct", value = function(L) return -2.5 * L end },
    { name = "Wind", format = "pct", value = function(L) return -100 * 0.2 * L / 6 end },
    { name = "MovePenalty", format = "pct", value = function(L) return -2.5 * L end },
    { name = "Unjam", format = "pts", value = function(L) return -0.5 * L end },
    { name = "PvpCrit", format = "mult", value = function(L) return 1 + L / 15 end },
    { name = "WildAnimals", format = "mult", value = function(L) return 1 / (1 + L / 10) end },
})

M.addSkillEffects("Reloading", {
    { name = "ReloadSpeed", format = "mult", value = function(L) return 0.8 + 0.1 * L end },
    { name = "RackSpeed", format = "mult", value = function(L) return 0.8 + 0.04 * L end },
    { name = "RackAim", format = "pct", value = function(L) return -100 * 0.01 * L / 0.15 end },
})
