--[[
Tien's Skill Mastery: Foraging found item size (PlantScavenging.Size). Vanilla 42.21 Lua.

Vanilla: `forageSystem.doWildFoodSpawn(character, inventory, itemDef, items)` (shared/Foraging/forageSystem.lua ~2266)
gives every foraged wild food a size: sizeModifier = (ZombRand(45) + 5) / 100 + (ZombRand(level) + 1) x 0.05, applied
to base hunger / hunger change (only when that stays above 1 hunger point) and to carbohydrates, lipids, proteins and
calories. Food weight follows hunger (`Food.getActualWeight`), so it grows with it.

Where it runs: it is a spawn function, stored **by reference** in each definition's `spawnFuncs` list
(shared/Foraging/Categories/*.lua, e.g. Berries.lua ~13), and called with the forager as `character`:
- MP: `forageServer.buildItems` (server/Foraging/forageServer.lua ~366, server only) when the server's
  `ISForageAction:complete` runs `forageServer.onPickup`; the items then reach the owner through
  `forageSystem.addOrDropItems` (item bytes carry the nutrition and hunger).
- Single player: `ISBaseIcon:getItemList` (client/Foraging/ISBaseIcon.lua ~454) when the icon is spotted; that list is
  what `ISForageAction:complete` adds.
- An MP client also builds a preview list in `getItemList` (halo, icon); scaling it there changes nothing real.

Because the references are taken when the definition files load, replacing `forageSystem.doWildFoodSpawn` would reach
no one. So once `forageSystem.init` has built `forageSystem.itemDefs` (it runs on `OnLoadedMapZones`, registered by
vanilla before this file, so it has run when our handler does; `importDef` keeps the definition tables themselves),
every `spawnFuncs` entry that is vanilla's function is swapped for a wrapper that calls it and then scales the same
values by `M.more(character, "PlantScavenging.Size")`. Poison and freshness are left alone (user's decision).
]]

require "TienSkillMastery"
require "Foraging/forageSystem"

local M = TienSkillMastery

if not forageSystem then return end

local origWildFood = forageSystem.doWildFoodSpawn

local function scaleFood(item, m)
    if not (item and instanceof(item, "Food")) then return end
    if item:getBaseHunger() <= -0.01 then
        item:setBaseHunger(item:getBaseHunger() * m)
        item:setHungChange(item:getHungChange() * m)
    end
    item:setCarbohydrates(item:getCarbohydrates() * m)
    item:setLipids(item:getLipids() * m)
    item:setProteins(item:getProteins() * m)
    item:setCalories(item:getCalories() * m)
end

local function wildFoodSpawn(character, inventory, itemDef, items, ...)
    local result = origWildFood(character, inventory, itemDef, items, ...)
    local list = result or items
    local m = character and M.more(character, "PlantScavenging.Size") or 1
    if m > 1 and list then
        for i = 0, list:size() - 1 do
            scaleFood(list:get(i), m)
        end
    end
    return result
end

local function swapSpawnFuncs()
    local defs = forageSystem.itemDefs
    if type(defs) ~= "table" or type(origWildFood) ~= "function" then return end
    for _, def in pairs(defs) do
        local funcs = type(def) == "table" and def.spawnFuncs
        if type(funcs) == "table" then
            for i, f in ipairs(funcs) do
                if f == origWildFood then funcs[i] = wildFoodSpawn end
            end
        end
    end
end

Events.OnLoadedMapZones.Add(swapSpawnFuncs)
