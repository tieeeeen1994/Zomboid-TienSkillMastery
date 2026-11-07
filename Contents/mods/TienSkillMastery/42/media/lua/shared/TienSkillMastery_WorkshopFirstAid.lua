--[[
Tien's Skill Mastery: First Aid (perk Doctor) bonuses. Bonuses belong to the doctor (`self.character`); the patient
(`self.otherPlayer`, whose body part `self.bodyPart` is) may be another player.

FieldMedicine.TreatTime ("less"). Every vanilla medical action reads the doctor's level for its time (42.21, shared/
TimedActions unless noted). `new` stores `o.doctorLevel = character:getPerkLevel(Perks.Doctor)` on whichever side
builds the action, so the server's copy uses the server's level.
- computed (`new` sets `maxTime = o:getDuration()`): ISApplyBandage:getDuration ~153 (120 - 4L, also removing a
  bandage; 0 while someone else treats that part), ISDisinfect ~289 (120 - 4L), ISComfreyCataplasm ~86,
  ISGarlicCataplasm ~84, ISPlantainCataplasm ~87 (120 - 4L), ISStitch ~141 (200 or 150 with a suture needle /
  holder, - 4L), ISCleanBurn ~80 and ISRemoveBullet ~78 (250 - 6L), ISRemoveGlass ~82 (150, 300 with hand pain,
  - 4L; 1 with CanMedicalCheat).
- stored: ISSplint:new ~152 `maxTime = 140 - 4L`, getDuration ~130 returns it. ISMedicalCheckAction (client folder,
  client-only action: no `complete`) `new` ~85 `150 - 2.5L`, see client/TienSkillMastery_WorkshopFirstAid.lua.
See shared/TienSkillMastery_Workshop.lua for why these wrappers work on every side.

FieldMedicine.TreatStrength ("pct"). What each `complete` derives from the doctor level (complete runs on the server, or
single player; never on an MP client), scaled after vanilla set it, then re-sent with vanilla's own
`syncBodyPart(part, mask)` (server only; single player has nothing to send). The whole value is scaled:
- ISApplyBandage:complete ~112 bandage life = ZombRandFloat((L+1) x 0.5, (L+1) x 1) + bandage power (dirty: 0),
  sync ~148 mask 0xc001966b8e (includes BD_bandageLife). Life is worn down in `BodyPart.update` (~194-391).
- Cataplasms ~72 power = ZombRandFloat((L+1) x 0.5, (L+1)) + 10 -> set{Comfrey,Garlic,Plantain}Factor (Java clamps
  0..100, comfrey decays at ~447); masks 0x1000000000 / 0x2000000000 / 0x800000000.
- ISSplint:complete ~90 factor (L+1)/2 (`IsoGameCharacter` ~9776: penalty - min(factor / 10, 0.8)); mask 0x430000000.
- ISStitch:complete ~119 stitch time ((1+L)/2) x ZombRandFloat(2, 5); `BodyPart.update` ~415 counts it up to 50
  (healed), so a higher start heals sooner. Kept under 50. Mask 0x00570188.
- ISRemoveBullet:complete ~69 `setHaveBullet(false, L)` = Java `BodyPart.setHaveBullet` ~1184: deep wound time
  Rand(17, 23) - L/2 (int division; healer traits shift it, injury severity scales it). Reachable after all: the
  time is read back and divided by the bonus factor (shorter wound). Mask 0x40460108 (includes BD_deepWoundTime).
- Not scaled: ISDisinfect, ISCleanBurn, ISRemoveGlass use the level only for pain (pain was not taken) and Stitch's
  pain and wound-infection chance stay vanilla.
]]

require "TienSkillMastery"
require "TienSkillMastery_Workshop"
local M = TienSkillMastery
local W = M.Workshop

local TIME = "FieldMedicine.TreatTime"
local STRENGTH = "FieldMedicine.TreatStrength"

-- ---------------------------------------------------------------------------------------------------------------
-- Treatment time
-- ---------------------------------------------------------------------------------------------------------------

W.wrapComputedDuration(ISApplyBandage, TIME)
W.wrapComputedDuration(ISDisinfect, TIME)
W.wrapComputedDuration(ISComfreyCataplasm, TIME)
W.wrapComputedDuration(ISGarlicCataplasm, TIME)
W.wrapComputedDuration(ISPlantainCataplasm, TIME)
W.wrapComputedDuration(ISStitch, TIME)
W.wrapComputedDuration(ISCleanBurn, TIME)
W.wrapComputedDuration(ISRemoveBullet, TIME)
W.wrapComputedDuration(ISRemoveGlass, TIME)
W.wrapStoredDuration(ISSplint, TIME)

-- ---------------------------------------------------------------------------------------------------------------
-- Treatment strength (server / single player)
-- ---------------------------------------------------------------------------------------------------------------

local function finish(self, mult, state, after, ...)
    local ok = ...
    if ok ~= false and self.bodyPart then after(self, mult, state) end
    return ...
end

--- after(self, mult, state) runs when vanilla's complete did not refuse; before(self) gives its state.
local function wrapComplete(class, before, after)
    if not class or not class.complete then return end
    local orig = class.complete
    class.complete = function(self, ...)
        if isClient() or not self.character then return orig(self, ...) end
        local mult = M.more(self.character, STRENGTH)
        if mult <= 1 then return orig(self, ...) end
        local state = before and before(self) or nil
        return finish(self, mult, state, after, orig(self, ...))
    end
end

wrapComplete(ISApplyBandage, nil, function(self, mult)
    local part = self.bodyPart
    local life = part:getBandageLife()
    if not self.doIt or not part:bandaged() or life <= 0 then return end
    part:setBandageLife(life * mult)
    syncBodyPart(part, 0xc001966b8e)
end)

local function cataplasm(class, getter, setter, mask)
    wrapComplete(class, nil, function(self, mult)
        local part = self.bodyPart
        local v = part[getter](part)
        if v <= 0 then return end
        part[setter](part, v * mult)
        syncBodyPart(part, mask)
    end)
end
cataplasm(ISComfreyCataplasm, "getComfreyFactor", "setComfreyFactor", 0x0000001000000000)
cataplasm(ISGarlicCataplasm, "getGarlicFactor", "setGarlicFactor", 0x0000002000000000)
cataplasm(ISPlantainCataplasm, "getPlantainFactor", "setPlantainFactor", 0x0000000800000000)

wrapComplete(ISSplint, nil, function(self, mult)
    local part = self.bodyPart
    local f = part:getSplintFactor()
    if not self.doIt or f <= 0 then return end
    part:setSplintFactor(f * mult)
    syncBodyPart(part, 0x430000000)
end)

wrapComplete(ISStitch, nil, function(self, mult)
    local part = self.bodyPart
    local t = part:getStitchTime()
    if not self.doIt or t <= 0 or t >= 49 then return end
    part:setStitchTime(math.min(t * mult, 49))
    syncBodyPart(part, 0x00570188)
end)

wrapComplete(ISRemoveBullet, function(self)
    return self.bodyPart and self.bodyPart:haveBullet()
end, function(self, mult, hadBullet)
    local part = self.bodyPart
    if not hadBullet or part:haveBullet() or not part:isDeepWounded() then return end
    local t = part:getDeepWoundTime()
    if t <= 0 then return end
    part:setDeepWoundTime(t / mult)
    syncBodyPart(part, 0x40460108)
end)

-- ---------------------------------------------------------------------------------------------------------------
-- FieldMedicine.Disinfectant (phase 2): sparing disinfectant. `ISDisinfect:complete` (~68, server / single player)
-- raises the part's alcohol level by the alcohol's strength (fluid: 4 x its alcohol share; drainable: its alcohol
-- power), not by the amount used, so using less does not weaken it. Then a fluid container loses 0.15 L
-- (`adjustAmount(amount - 0.15)` + `sendItemStats`; nothing at all at 0.15 L or less, a vanilla quirk) and a
-- drainable one use (`UseAndSync`). Afterwards the bonus share of the fluid used is put back (`adjustAmount` sets the
-- amount) and sent, or the used use comes back on a roll of the bonus (`setCurrentUses` + `syncItemFields`).
-- ---------------------------------------------------------------------------------------------------------------

if ISDisinfect and ISDisinfect.complete then
    local vanillaDisinfect = ISDisinfect.complete
    function ISDisinfect:complete(...)
        local doctor, alcohol = self.character, self.alcohol
        local share = doctor and M.val(doctor, "FieldMedicine.Disinfectant") / 100 or 0
        if share <= 0 or not alcohol then return vanillaDisinfect(self, ...) end
        local fluid = alcohol:hasComponent(ComponentType.FluidContainer) and alcohol:getFluidContainer() or nil
        local amountBefore = fluid and fluid:getAmount()
        local usesBefore = instanceof(alcohol, "DrainableComboItem") and alcohol:getCurrentUses() or nil
        local results = { vanillaDisinfect(self, ...) }
        local ok, err = pcall(function()
            if fluid and amountBefore then
                local used = amountBefore - fluid:getAmount()
                if used > 0 then
                    fluid:adjustAmount(fluid:getAmount() + used * share)
                    sendItemStats(alcohol)
                end
            elseif usesBefore and alcohol:getContainer() then
                local now = alcohol:getCurrentUses()
                if now < usesBefore and ZombRandFloat(0, 1) < share then
                    alcohol:setCurrentUses(now + 1)
                    alcohol:syncItemFields()
                end
            end
        end)
        if not ok then print("[TienSkillMastery] sparing disinfectant failed: " .. tostring(err)) end
        return unpack(results)
    end
end
