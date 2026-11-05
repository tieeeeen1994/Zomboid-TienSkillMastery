--[[
Tien's Skill Mastery: furniture pick-up and dismantling (shared/Moveables/ISMoveableSpriteProps.lua, 42.21).

Where it runs: picking up and scrapping are `ISMoveablesAction:complete` (shared/Moveables/ISMoveablesAction.lua
~236: `pickUpMoveableViaCursor` / `scrapObjectViaCursor`; also server/TransactionProcessor.lua ~13 / ~35), i.e. the
MP server or single player, where the break and scrap rolls are made. `getBreakChance` is also read on the client
for the info panel (~945), which then shows the mastery value too (a client knows its own mastery).
ISThumpableSpriteProps (~4202) inherits these methods through its metatable, so wrapping ISMoveableSpriteProps
covers it.

- `Woodwork.WindowBreak` / `MetalWelding.WindowBreak`: `getBreakChance(player)` (~327) = 0 with the movables cheat,
  else by the pick-up tool definition's perk (ISMoveableDefinitions.lua ~311: Hammer / Crowbar / Cutter /
  Screwdriver = Woodwork, "Metal" = MetalWelding, Electrician = Electricity, Wrench = none): windows
  5 + (10 - level) x 5 (5 % at level 10), other furniture (10 - level) x 7.5 (0 at 10, so nothing to take off there).
  For a window the `<tool perk>.WindowBreak` points come off (never below 0); `doBreakTest` (~350) rolls
  ZombRand(1, 101) <= chance.
- `<Perk>.Dismantle` (each crafting skill): deviation from the design note. `getChanceByDef(scrapDef, chr)` (~3834) =
  10 + 10 x level + baseChance clamped to 0..100 is already 100 from level 9 for every vanilla scrap definition
  (baseChance >= 0), and `addScrapItemToList` (~3350) only scales by it while 0 < chance <= 100, so points added
  there would change nothing. The bonus goes on the per-roll chance instead: `getScrapItemsList(chr)` (~3304) calls
  `getChanceByDef` once per material, then `addScrapItemToList(list, item, max, chancePerRoll, chance, sizeMod)` per
  return item, which keeps each roll when ZombRandFloat(0, 101) < chancePerRoll / 100 x chance (80 % / 70 % for
  most items at level 10). During a `getScrapItemsList` call the material's perk is noted in `getChanceByDef`, and
  `addScrapItemToList` gets vanilla's effective per-roll chance plus `<perk>.Dismantle` points (passed with no
  skill factor, which vanilla then uses as is). Materials of other perks (Strength for Stone) get nothing.
- `Electricity.Scrap` (electrical furniture): the "Electric" scrap material (ISMoveableDefinitions.lua ~403, perk
  Electricity, ElectronicsScrap and ElectricWire at 80 per roll). After `getScrapItemsList`, one more
  Base.ElectronicsScrap joins the usable list on a `M.roll`; vanilla then adds the list to the square or inventory
  (`addAllScrapItemsToSquare` / `addAllScrapItemsToInventory`, which send it themselves). Electronics dismantled by
  recipe are in TienSkillMastery_Crafting.
]]

require "TienSkillMastery"
require "Moveables/ISMoveableSpriteProps"
local M = TienSkillMastery

if not ISMoveableSpriteProps then
    print("[TienSkillMastery] ISMoveableSpriteProps not found, pick-up and dismantle bonuses not applied")
    return
end

-- ---------------------------------------------------------------------------------------------------------------
-- Window break chance
-- ---------------------------------------------------------------------------------------------------------------

local vanillaGetBreakChance = ISMoveableSpriteProps.getBreakChance
if vanillaGetBreakChance then
    local function lowered(self, player, chance, ...)
        if type(chance) == "number" and chance > 0 and player and self.type == "Window" and self.pickUpTool then
            local toolDef = ISMoveableDefinitions:getInstance().getToolDefinition(self.pickUpTool)
            local perkId = toolDef and toolDef.perk and M.perkId(toolDef.perk)
            if perkId then
                chance = math.max(0, chance - M.val(player, perkId .. ".WindowBreak"))
            end
        end
        return chance, ...
    end

    function ISMoveableSpriteProps:getBreakChance(player, ...)
        return lowered(self, player, vanillaGetBreakChance(self, player, ...))
    end
else
    print("[TienSkillMastery] ISMoveableSpriteProps:getBreakChance not found, window break bonuses not applied")
end

-- ---------------------------------------------------------------------------------------------------------------
-- Dismantling
-- ---------------------------------------------------------------------------------------------------------------

local vanillaGetScrapItemsList = ISMoveableSpriteProps.getScrapItemsList
local vanillaGetChanceByDef = ISMoveableSpriteProps.getChanceByDef
local vanillaAddScrapItemToList = ISMoveableSpriteProps.addScrapItemToList
if not (vanillaGetScrapItemsList and vanillaGetChanceByDef and vanillaAddScrapItemToList) then
    print("[TienSkillMastery] ISMoveableSpriteProps scrap functions not found, dismantle bonuses not applied")
    return
end

local scrapCtx = nil   -- { chr = character, bonus = points for the material being listed } during getScrapItemsList

function ISMoveableSpriteProps:getChanceByDef(scrapDef, chr, ...)
    local chance = vanillaGetChanceByDef(self, scrapDef, chr, ...)
    if scrapCtx then
        scrapCtx.bonus = 0
        if scrapDef and scrapDef.perk and scrapCtx.chr then
            local ok, v = pcall(M.val, scrapCtx.chr, M.perkId(scrapDef.perk) .. ".Dismantle")
            if ok and v then scrapCtx.bonus = v end
        end
    end
    return chance
end

function ISMoveableSpriteProps:addScrapItemToList(list, item, max, chance, skillMod, doSizeMod, ...)
    if scrapCtx and scrapCtx.bonus > 0 and item and max and chance then
        local perRoll = chance
        if skillMod and skillMod > 0 and skillMod <= 100 then
            perRoll = (perRoll / 100) * skillMod
        end
        return vanillaAddScrapItemToList(self, list, item, max, perRoll + scrapCtx.bonus, nil, doSizeMod, ...)
    end
    return vanillaAddScrapItemToList(self, list, item, max, chance, skillMod, doSizeMod, ...)
end

local function hasElectricMaterial(self)
    return self.material == "Electric" or self.material2 == "Electric" or self.material3 == "Electric"
end

local function finishScrapList(self, chr, ok, items, ...)
    scrapCtx = nil
    if not ok then error(items, 0) end
    if type(items) == "table" and type(items.usable) == "table" and chr and hasElectricMaterial(self) then
        local def = ISMoveableDefinitions:getInstance().getScrapDefinition("Electric")
        if def and def.perk == Perks.Electricity and M.roll(chr, "Electricity.Scrap") then
            table.insert(items.usable, "Base.ElectronicsScrap")
        end
    end
    return items, ...
end

function ISMoveableSpriteProps:getScrapItemsList(chr, ...)
    scrapCtx = { chr = chr, bonus = 0 }
    return finishScrapList(self, chr, pcall(vanillaGetScrapItemsList, self, chr, ...))
end
