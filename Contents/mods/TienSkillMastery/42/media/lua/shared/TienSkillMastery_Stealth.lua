--[[
Tien's Skill Mastery: Stealth, quieter (user, 2026-11-11; its sneak speed became Freerunning's crouch speed the same
day). Traced in the 42.21 Java (decompiled).

What zombies hear is a world sound (`WorldSoundManager.addSound`: radius, volume, source). Its fields have no getters
and it goes straight to the zombies, the population manager and (from a client) the server, with no Lua event, so
only noises made through Lua or from a value Lua can set can be turned down. Out of reach: footsteps
(`IsoGameCharacter.DoFootstepSound`, Java, reads the Lightfoot level itself), hitting or breaking doors, windows and
walls (`IsoDoor` / `IsoWindow` / `IsoThumpable`), vaulting. Opening and closing doors makes no world sound at all.

- Stealth.QuietWork: about 25 vanilla actions make their noise through the Lua global `addSound(source, x, y, z,
  radius, volume)` (building, multi-stage builds, barricading and unbarricading, sledgehammering, digging, plowing,
  pickaxing rocks, picking up glass, clearing bushes and grass, moving furniture, fishing rods and nets), on whichever
  side runs that part of the action (the server's `complete` / `animEvent`, `ISBuildAction:update` on the client),
  always with the acting character as the source and at the character's own square. The global is wrapped: a noise
  whose source is a master and which is made on the master's own square gets its radius cut by the effect's share
  (at least 1). Admin "Make noise" tools pass the admin at a clicked square, so they keep their full radius.
- Stealth.QuietSwings: a melee swing makes its noise when it starts (`IsoLivingCharacter` ~131: `addSound(this, ...,
  useHandWeapon.getSoundRadius(), getSoundVolume())`, 6 arguments = sent to the server), on the attacker's own game,
  with that game's copy of the weapon; the server makes none for melee (`fields/hit/Player.attack` only handles
  firearms there). `HandWeapon.soundRadius` is a plain per-item field with a public setter, copied from the script
  when the item is made and neither saved nor in any packet. So each update the melee weapon in a local master's hand
  gets its radius cut by the share, and any weapon cut here gets the radius it had back as soon as it is no longer
  in a master's hand (switched, dropped, mastery lost). Guns are left alone (their shots are made elsewhere, and
  silent gunfire would be far too strong).
]]

require "TienSkillMastery"
local M = TienSkillMastery

local S = {}
M.Stealth = S

local WORK = "Stealth.QuietWork"
local SWINGS = "Stealth.QuietSwings"

--- `radius` cut by `share` percent, never under 1.
function S.cut(radius, share)
    return math.max(1, math.floor(radius * (1 - math.min(100, share) / 100) + 0.5))
end

-- ---------------------------------------------------------------------------------------------------------------
-- Quiet work: the Lua global `addSound`
-- ---------------------------------------------------------------------------------------------------------------

local function workRadius(source, x, y, z, radius)
    if type(radius) ~= "number" or radius <= 1 or not source then return nil end
    if not instanceof(source, "IsoPlayer") or instanceof(source, "IsoAnimal") or source:isDead() then return nil end
    if math.floor(x) ~= math.floor(source:getX()) or math.floor(y) ~= math.floor(source:getY())
        or math.floor(z) ~= math.floor(source:getZ()) then
        return nil
    end
    local share = M.val(source, WORK)
    if share <= 0 then return nil end
    return S.cut(radius, share)
end

if type(addSound) == "function" and not S.vanillaAddSound then
    S.vanillaAddSound = addSound
    addSound = function(source, x, y, z, radius, volume, ...)
        local ok, r = pcall(workRadius, source, x, y, z, radius)
        if ok and r then radius = r end
        return S.vanillaAddSound(source, x, y, z, radius, volume, ...)
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Quiet swings: the melee weapon in a local master's hand (every game but a dedicated server)
-- ---------------------------------------------------------------------------------------------------------------

S.cutWeapons = {}   -- [weapon] = its radius before the cut

local function heldMelee(player)
    local w = player:getPrimaryHandItem()
    if w and instanceof(w, "HandWeapon") and not w:isRanged() then return w end
    return nil
end

function S.updateSwings()
    local keep = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then
            local w = heldMelee(p)
            local share = w and M.val(p, SWINGS) or 0
            if w and share > 0 then
                if S.cutWeapons[w] == nil then S.cutWeapons[w] = w:getSoundRadius() end
                local target = S.cut(S.cutWeapons[w], share)
                if S.cutWeapons[w] <= 1 then target = S.cutWeapons[w] end
                if w:getSoundRadius() ~= target then w:setSoundRadius(target) end
                keep[w] = true
            end
        end
    end
    local back = {}
    for w in pairs(S.cutWeapons) do
        if not keep[w] then table.insert(back, w) end
    end
    for _, w in ipairs(back) do
        pcall(function() w:setSoundRadius(S.cutWeapons[w]) end)
        S.cutWeapons[w] = nil
    end
end

if not isServer() then
    Events.OnTick.Add(S.updateSwings)
end
