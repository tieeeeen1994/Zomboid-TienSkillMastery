--[[
Tien's Skill Mastery: maker's marks in item tooltips (user, 2026-11-08), and "Throwable" on what a Stealth master
can lob with Distraction Throw (2026-11-11). One line per mark an item carries
("Maker's marks" in shared/TienSkillMastery_Crafting.lua): the whole item, a hafted tool's head, its handle, with the
kind (Masterwork, Craftsmanship) and the maker's name (no wear share since 2026-11-08, user). Marks are modData, synced to the
owner with the item (`syncItemFields`), so the client reads them directly.

Drawn the way Tien's Bag Upgrades draws its lines (its TienBagUpgrades_Tooltip.lua): under the finished tooltip,
after the whole render chain (vanilla's and every other mod's), the box extended down, its border drawn again, then
the ObjectTooltip's height set to the extended box so Plysken Attachments Reborn's slot box (drawn at that height
as the next frame begins) starts under these lines. Each mod doing this stacks under the previous one, in any order.
]]

require "ISUI/ISToolTipInv"

local LINE_R, LINE_G, LINE_B = 0.95, 0.8, 0.45

local function kindName(kind)
    return getTextOrNull("IGUI_TienSkillMastery_MarkKind_" .. tostring(kind)) or tostring(kind)
end

local function markLines(item)
    local md = item:getModData()
    local lines = nil
    local main = tonumber(md.TSM_Mark) or 0
    if main > 0 then
        local key = md.TSM_MarkPart == "head" and "IGUI_TienSkillMastery_MarkHead" or "IGUI_TienSkillMastery_MarkWhole"
        lines = { getText(key, kindName(md.TSM_MarkKind), tostring(md.TSM_MarkBy or "?")) }
    end
    local handle = tonumber(md.TSM_HandleMark) or 0
    if handle > 0 then
        lines = lines or {}
        lines[#lines + 1] = getText("IGUI_TienSkillMastery_MarkHandle", kindName(md.TSM_HandleMarkKind),
            tostring(md.TSM_HandleMarkBy or "?"))
    end
    -- Stealth's Distraction Throw (user, 2026-11-11): "Throwable" on what a master could lob (TienSkillMastery_Distraction.lua).
    local D = TienSkillMastery and TienSkillMastery.Distraction
    local player = getSpecificPlayer(0)
    if D and player and D.canThrow(player, item) then
        lines = lines or {}
        lines[#lines + 1] = getText("IGUI_TienSkillMastery_Throwable")
    end
    return lines
end

local originalRender = ISToolTipInv.render

function ISToolTipInv:render()
    local item = self.item
    local lines = item and instanceof(item, "InventoryItem") and markLines(item) or nil
    originalRender(self)
    if not lines then return end
    -- Vanilla draws nothing while a context menu is open.
    if ISContextMenu.instance and ISContextMenu.instance.visibleCheck then return end
    local tooltip = self.tooltip
    if not tooltip then return end

    local font = UIFont[getCore():getOptionTooltipFont()]
    -- Vanilla's padding (`ObjectTooltip.checkFont`): the width of "0" in the tooltip font left and right, half of it
    -- at the bottom; the title and every row start at that left padding (fixed 5 px here until 2026-11-08).
    local pad = getTextManager():MeasureStringX(font, "0")
    local spacing = tooltip:getLineSpacing()
    local top = self.height
    local extra = #lines * spacing + math.floor(pad / 2)
    local bg, border = self.backgroundColor, self.borderColor
    -- Widen the box when a line is longer than the tooltip (the part above is filled to the new edge).
    local need = 0
    for i = 1, #lines do need = math.max(need, pad + getTextManager():MeasureStringX(font, lines[i]) + pad) end
    if need > self.width then
        self:drawRect(self.width - 1, 0, need - self.width + 1, top, bg.a, bg.r, bg.g, bg.b)
        self:setWidth(need)
    end
    -- Over the old bottom border row too, then the border again around the taller box.
    self:drawRect(0, top - 1, self.width, extra + 1, bg.a, bg.r, bg.g, bg.b)
    self:setHeight(top + extra)
    self:drawRectBorder(0, 0, self.width, self.height, border.a, border.r, border.g, border.b)
    for i = 1, #lines do
        tooltip:DrawText(font, lines[i], pad, top + spacing * (i - 1), LINE_R, LINE_G, LINE_B, 1)
    end
    tooltip:setHeight(self.height)
end
