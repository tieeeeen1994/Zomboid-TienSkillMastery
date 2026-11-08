--[[
Tien's Skill Mastery: Cooking bonuses for adding an ingredient to an evolved-recipe dish (ISAddItemInRecipe,
shared/TimedActions/ISAddItemInRecipe.lua, 42.21). Crafting time of handcraft recipes is not here (ISHandcraftAction
belongs to the shared crafting hooks).

Provisioning.AddTime ("less"): `getDuration` ~224 = 100 - 2.5 x Cooking (1 with Timed Action Instant); `new` ~236 sets
`maxTime = o:getDuration()`, so wrapping getDuration covers the client, single player and the server's rebuild
(shared/TienSkillMastery_Workshop.lua, "computed" actions).

Provisioning.Nutrition ("pct"): `complete` ~66 (server, or single player; never on an MP client) calls Java
`EvolvedRecipe.addItem(base, used, chr)` (~228). That may first replace a base that is not the result item with a
new result item (nutrients copied from the old one when it was Food, else 0; sent with
`sendReplaceItemInContainer`), then adds to the dish, with nutritionBoost = 1 + Cooking / 15 and
percentageUsed = the share of the ingredient used (~392): calories, proteins, carbohydrates, lipids
(+ ingredient x boost x share) and, for ingredients not tagged DriedFood, the unmodified thirst change (same
factor); spices go through `useSpice` (~538) with the same boost on calories / proteins. The dish's hunger takes the
plain used hunger, not boosted by the skill (the skill only lets the ingredient lose less of itself, a saving the
user dropped), so hunger is left alone, which also keeps the dish's weight (Food weight follows hunger).
The bonus scales what this one addition put into those values (dish after - dish before), so the extra is the same
share of vanilla's own boosted gain. Thirst: only a quenching gain (negative change) is scaled; a salty ingredient
is not made saltier. The ingredient keeps vanilla's values.
Sync: after addItem, `complete` calls `ISAddItemInRecipe.checkTemperature` (~78, a table field looked up at call
time) and then, on a server, `sendItemStats(self.baseItem)` (~81). The scaling runs inside that checkTemperature
call, so vanilla's own ItemStats packet (calories, proteins, lipids, carbohydrates, thirst, hunger...; reliable
ordered, to the owner's connection when the dish is in a player's inventory, `GameServer.sendItemStats` ~3162)
carries the final values; ItemStats is applied to the client copy by `applyItemStats`. Should another mod's
complete skip checkTemperature, the values are scaled after it and sent again with `sendItemStats`.
]]

require "TienSkillMastery"
require "TienSkillMastery_Workshop"
local M = TienSkillMastery
local W = M.Workshop

W.wrapComputedDuration(ISAddItemInRecipe, "Provisioning.AddTime")

if not ISAddItemInRecipe then return end

local NUTRIENTS = {
    { "getCalories", "setCalories" },
    { "getProteins", "setProteins" },
    { "getCarbohydrates", "setCarbohydrates" },
    { "getLipids", "setLipids" },
}

local current -- the addition being completed: { action, mult, before, applied }

local function snapshot(item)
    local s = { isFood = item ~= nil and instanceof(item, "Food") }
    for i, f in ipairs(NUTRIENTS) do
        s[i] = s.isFood and item[f[1]](item) or 0
    end
    if s.isFood then
        s.item = item
        s.thirst = item:getThirstChangeUnmodified()
        -- A replacement result item copies the old dish's modified thirst (halved when cooked, a fifth when burnt).
        s.thirstCopied = item:getThirstChange()
    end
    return s
end

local function apply(ctx, item)
    if ctx.applied then return false end
    ctx.applied = true
    if not item or not instanceof(item, "Food") then return false end
    local k = ctx.mult - 1
    local changed = false
    for i, f in ipairs(NUTRIENTS) do
        local now = item[f[1]](item)
        local added = now - ctx.before[i]
        if added ~= 0 then
            item[f[2]](item, now + added * k)
            changed = true
        end
    end
    -- A base that was not Food has no thirst to compare with (the result item keeps its script's value).
    if ctx.before.thirst then
        local now = item:getThirstChangeUnmodified()
        local before = ctx.before.item == item and ctx.before.thirst or ctx.before.thirstCopied
        local added = now - before
        if added < 0 then
            item:setThirstChange(now + added * k)
            changed = true
        end
    end
    return changed
end

local origCheckTemperature = ISAddItemInRecipe.checkTemperature
ISAddItemInRecipe.checkTemperature = function(baseItem, ...)
    local ctx = current
    if ctx and not ctx.applied and ctx.action.baseItem == baseItem then
        apply(ctx, baseItem)
    end
    return origCheckTemperature(baseItem, ...)
end

local origComplete = ISAddItemInRecipe.complete
function ISAddItemInRecipe:complete(...)
    current = nil
    if isClient() or not self.character then return origComplete(self, ...) end
    local mult = M.more(self.character, "Provisioning.Nutrition")
    if mult <= 1 then return origComplete(self, ...) end
    local ctx = { action = self, mult = mult, before = snapshot(self.baseItem) }
    current = ctx
    local results = W.pack(origComplete(self, ...))
    current = nil
    if not ctx.applied and results[1] ~= false then
        if apply(ctx, self.baseItem) and isServer() then
            sendItemStats(self.baseItem)
        end
    end
    return W.unpack(results)
end

-- Provisioning.LastingFood (phase 2): an evolved dish a master starts or adds to stays fresh longer. Once per dish
-- (modData `TSM_Lasting`), so adding more ingredients never stacks it: after `ISAddItemInRecipe:complete` (server /
-- single player) the dish's `setOffAge` / `setOffAgeMax` are stretched and the dish is re-sent whole (spoil times are
-- saved per item but not in SyncItemFieldsPacket). Wraps the nutrition wrapper above.
local nutritionComplete = ISAddItemInRecipe.complete
function ISAddItemInRecipe:complete(...)
    local results = W.pack(nutritionComplete(self, ...))
    if results[1] ~= false and not isClient() and self.character then
        local dish = self.baseItem
        local f = M.more(self.character, "Provisioning.LastingFood")
        if f > 1 and dish and instanceof(dish, "Food") and not dish:getModData().TSM_Lasting then
            if M.stretchFood(dish, f) then
                dish:getModData().TSM_Lasting = true
                M.resendItem(dish)
            end
        end
    end
    return W.unpack(results)
end

-- Provisioning's signature, Savory Meals (user, 2026-11-08): food a master finishes with heat (oven, stove, campfire...)
-- causes 80% less unhappiness when eaten (flat, from the pick; not scaled; boredom untouched). Not evolved dishes as
-- they are put together and not recipes (user, same day), only the moment of cooking.
-- Eating adds `Food.getUnhappyChange()` x the share eaten (`BodyDamage` ~613), which is the saved `unhappyChange` field
-- plus flat burnt, frozen, stale and rotten penalties computed on read (Food ~1664). The field is what is reduced, so
-- those penalties build on the reduced value (user's rule): a master's rat is 6 fresh, 16 stale, 26 rotten.
-- Nothing ties a heating food to a timed action, but `Food.update` (~470, server / SP) calls the food's `OnCooked`
-- function at the moment it turns cooked, just before vanilla's cooking XP and `sendItemStats` (~506), so the new value
-- reaches clients by itself. The cook is the same `chef` vanilla pays that XP to: set on every item transaction
-- (`Transaction` ~166, username; TienSkillMastery_DeftTransfer sets it too) and in single player by
-- `ISInventoryTransferAction` (~672, full name). `onCooked` is copied from the script at `InstanceItem` (not saved) and
-- `Item` has no getter, so at world load every food script gets ours through `DoParam` and the value it had is read from
-- a throwaway instance and called first (vanilla: canned food, cake prep; other mods' too). Server / SP only: a client's
-- copy never needs the call. `ReplaceOnCooked` foods (bread to toast) become a new item with no callback; none of
-- vanilla's has an unhappiness penalty. `BadInMicrowave` (~479, after OnCooked) still sets a flat 5.
-- An evolved dish cooked by a master counts like any other food. Butchering is not cooking: a skinned rat stays at its
-- 30 until the master cooks it. An ingredient's own penalty never carries into a dish, even in vanilla (`addItem` ~380).
local ON_COOKED = "TienSkillMastery.SavoryOnCooked"
local chainedOnCooked = {} -- [full type] = the OnCooked the food's script had

local function callChained(name, food)
    local fn
    local tableName, field = string.match(name, "^([^.]+)%.(.+)$")
    if tableName then
        local t = _G[tableName]
        fn = t and t[field]
    else
        fn = _G[name]
    end
    if not fn then return end
    local ok, err = pcall(fn, food)
    if not ok then print("[TienSkillMastery] OnCooked " .. name .. " failed: " .. tostring(err)) end
end

--- The online player `food:getChef()` names: a username on a server, a full name in single player.
local function chefOf(food)
    local name = food:getChef()
    if not name or name == "" then return nil end
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p:getUsername() == name then return p end
        end
        return nil
    end
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        if p and (p:getFullName() == name or p:getUsername() == name) then return p end
    end
    return nil
end

--- Called by Java (`Food.update`) when a food turns cooked; looked up by name, so it must stay on the global table.
function M.SavoryOnCooked(food)
    local chained = chainedOnCooked[food:getFullType()]
    if chained then callChained(chained, food) end
    if isClient() then return end
    local chef = chefOf(food)
    if chef then M.savorFood(food, chef) end
end

Events.OnLoadMapZones.Add(function()
    if isClient() then return end
    local hooked = 0
    local items = getScriptManager():getAllItems()
    for i = 0, items:size() - 1 do
        local script = items:get(i)
        if script:isItemType(ItemType.FOOD) then
            local fullType = script:getFullName()
            local ok, instance = pcall(instanceItem, fullType)
            if ok and instance and instanceof(instance, "Food") then
                local current = instance:getOnCooked()
                -- Already ours when the scripts were not reset since the last world load: keep what was chained.
                if current ~= ON_COOKED then
                    chainedOnCooked[fullType] = (current ~= nil and current ~= "") and current or nil
                    script:DoParam("OnCooked", ON_COOKED)
                    hooked = hooked + 1
                end
            end
        end
    end
    print("[TienSkillMastery] Savory Meals: OnCooked set on " .. string.format("%d", hooked) .. " food scripts")
end)
