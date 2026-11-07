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
