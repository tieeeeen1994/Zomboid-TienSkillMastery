--[[
Tien's Skill Mastery: the Mastery tab of the character window (next to Skills).

`ISCharacterInfoWindow:createChildren` (42.21) builds its tabs as views of an ISTabPanel (`self.panel:addView`); the
wrapper adds this view after vanilla's and moves it right after Skills in `viewList` (tabs are drawn and cycled in
that order; `activateViewById` looks views up by their `id` field, so moving the entry is safe). Each view sizes the
window while it is shown (`setWidthAndParentWidth` / `setHeightAndParentHeight` from its render, as ISCharacterInfo
does). The window's layout save only records vanilla's tabs, so a torn-off Mastery tab is not restored.

Looks like the vanilla Skills tab (ISCharacterInfo / ISSkillProgressBar, 42.21): categories with the tree arrow
(click to collapse) and the SkillBarSeparator line, skill names in the same columns, ten SkillUnit boxes per skill in
vanilla's gold for gained mastery levels, the level in progress filled by its progress, a tooltip over the boxes with
the XP. Prestige (past mastery 10) shows as +n after the boxes and in a deeper gold. Click a skill to list its
bonuses now and at mastery 10.
]]

require "ISUI/ISPanelJoypad"
require "XpSystem/ISUI/ISCharacterInfoWindow"
require "TienSkillMastery"
local M = TienSkillMastery

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ROW_HGT = FONT_HGT_SMALL + 6          -- vanilla's BUTTON_HGT, one skill row
local PAD = 10                               -- vanilla's UI_BORDER_SPACING
local SCROLL_BAR_WIDTH = 13
local SKILL_POINT = math.floor(ROW_HGT / 2)  -- ISSkillProgressBar's SKILL_POINT_HGT
local TAR = { 1, 0.89, 0.38 }                -- vanilla's colour for gained levels
local PRESTIGE = { 1, 0.83, 0 }              -- vanilla's colour for a x3 boost, used here for prestige
local WHITE = { 1, 1, 1 }
local GREY = { 0.54, 0.54, 0.54 }

TienSkillMasteryPanel = ISPanelJoypad:derive("TienSkillMasteryPanel")

local function fmt(n)
    local s = string.format("%.1f", n)
    s = s:gsub("%.0$", "")
    return s
end

local function bonusValueText(d, v)
    local n = fmt(v)
    if d.kind == "pct" then return "+" .. n .. "%" end
    if d.kind == "less" then return "-" .. n .. "%" end
    if d.kind == "ptsoff" then return "-" .. n end
    return "+" .. n
end

local function bonusLabel(d)
    return getTextOrNull("IGUI_TienSkillMastery_Bonus_" .. d.perk .. "_" .. d.name)
        or getText("IGUI_TienSkillMastery_Bonus_" .. d.name)
end

function TienSkillMasteryPanel:new(x, y, width, height, playerNum)
    local o = ISPanelJoypad:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self
    o.playerNum = playerNum
    o:noBackground()
    o.expanded = {}
    o.collapsed = {}
    o.rows = {}
    o.catRows = {}
    o.joypadIndex = 1
    o.infoText = getTextOrNull("IGUI_TienSkillMastery_Info")
    o.unitFill = getTexture("media/ui/SkillPanel/SkillUnit_Fill.png")
    o.unitBorder = getTexture("media/ui/SkillPanel/SkillUnit_Border.png")
    o.separator = getTexture("media/ui/XpSystemUI/SkillBarSeparator.png")
    o.treeOpen = getTexture("media/ui/inventoryPanes/Button_TreeExpanded.png")
    o.treeClosed = getTexture("media/ui/inventoryPanes/Button_TreeCollapsed.png")
    return o
end

function TienSkillMasteryPanel:createChildren()
    self:setScrollChildren(true)
    self:addScrollBars()
    -- Categories and skills in the Skills tab's order: passive (Physical) first, then by name.
    local groups, byParent = {}, {}
    self.nameLen = 0
    for _, perk in ipairs(M.perks()) do
        local parent = perk:getParent()
        local key = tostring(parent)
        if not byParent[key] then
            byParent[key] = { key = key, parent = PerkFactory.getPerk(parent), perks = {} }
            table.insert(groups, byParent[key])
        end
        table.insert(byParent[key].perks, perk)
        self.nameLen = math.max(self.nameLen, getTextManager():MeasureStringX(UIFont.Small, perk:getName()))
    end
    table.sort(groups, function(a, b)
        local pa, pb = a.parent:isPassiv(), b.parent:isPassiv()
        if pa ~= pb then return pa end
        return a.parent:getName() < b.parent:getName()
    end)
    for _, g in ipairs(groups) do
        table.sort(g.perks, function(a, b) return a:getName() < b:getName() end)
    end
    self.groups = groups
    -- One collapse button per category, made like vanilla's (ISCharacterInfo:createChildren): an ISButton with the
    -- tree texture, so it has the same box around the arrow. Moved to its row's y in render.
    for _, g in ipairs(groups) do
        local b = ISButton:new(PAD + 1, 0, ROW_HGT, ROW_HGT, "", self, TienSkillMasteryPanel.onCollapse)
        b.internal = g.key
        b:setImage(self.treeOpen)
        b:initialise()
        self:addChild(b)
        g.button = b
    end
end

function TienSkillMasteryPanel:prerender()
    ISPanelJoypad.prerender(self)
    self:setStencilRect(0, 0, self.width, self.height)
end

--- Ten boxes drawn the way ISSkillProgressBar:renderPerkRect draws a skill: gained levels filled in vanilla's gold,
--- the level in progress as a grey border filled by its progress, the rest dark borders.
function TienSkillMasteryPanel:drawBoxes(x, y, unlocked, level, progress, prestige)
    local gap = getCore():getOptionFontSizeReal()
    local colour = prestige and PRESTIGE or TAR
    for i = 1, M.BONUS_LEVELS do
        if unlocked and i <= level then
            self:drawTextureScaled(self.unitFill, x, y, SKILL_POINT, SKILL_POINT, 1, colour[1], colour[2], colour[3])
            self:drawTextureScaled(self.unitBorder, x, y, SKILL_POINT, SKILL_POINT, 1, colour[1], colour[2], colour[3])
        elseif unlocked and i == level + 1 then
            self:drawTextureScaled(self.unitBorder, x, y, SKILL_POINT, SKILL_POINT, 1, 0.4, 0.4, 0.4)
            local w = SKILL_POINT * math.max(0, math.min(1, progress))
            if w > 0 then self:drawTextureScaled(self.unitFill, x, y, w, SKILL_POINT, 1, 0.4, 0.4, 0.4) end
        else
            self:drawTextureScaled(self.unitBorder, x, y, SKILL_POINT, SKILL_POINT, 1, 0.2, 0.2, 0.2)
        end
        x = x + SKILL_POINT + gap
    end
    return M.BONUS_LEVELS * (SKILL_POINT + gap)
end

function TienSkillMasteryPanel:tooltipFor(player, perk)
    local level, into, cost = M.levelInfo(perk, M.getXp(player, perk))
    local text = perk:getName() .. " <LINE> "
    if player:getPerkLevel(perk) < 10 then
        return text .. getText("IGUI_TienSkillMastery_Locked")
    end
    if level >= M.BONUS_LEVELS then
        text = text .. getText("IGUI_TienSkillMastery_Prestige", string.format("%d", level - M.BONUS_LEVELS))
    else
        text = text .. getText("IGUI_TienSkillMastery_Level", string.format("%d", level))
    end
    return text .. " <LINE> " .. getText("IGUI_XP_tooltipxp", string.format("%d", math.floor(into)),
        string.format("%d", math.floor(cost)))
end

function TienSkillMasteryPanel:showTooltip(text)
    if not text then
        if self.tip then
            self.tip:setVisible(false)
            self.tip:removeFromUIManager()
            self.tip = nil
        end
        return
    end
    if not self.tip then
        self.tip = ISToolTip:new()
        self.tip:initialise()
        self.tip:addToUIManager()
        self.tip:setOwner(self)
    end
    self.tip.description = text
    self.tip:setDesiredPosition(getMouseX() + 16, getMouseY() + 16)
end

function TienSkillMasteryPanel:setVisible(visible)
    self.javaObject:setVisible(visible)
    if not visible then self:showTooltip(nil) end
end

function TienSkillMasteryPanel:render()
    local player = getSpecificPlayer(self.playerNum)
    if not player then return end
    local tm = getTextManager()
    local y = PAD
    local left = PAD * 2 + ROW_HGT + 1            -- vanilla's `left`, right of the collapse arrow
    local nameX = left + PAD * 2
    local boxesX = left + PAD * 3 + self.nameLen  -- where vanilla puts the skill bar
    local fontOffset = (ROW_HGT - FONT_HGT_SMALL) / 2
    local mouseY, mouseX = self:getMouseY(), self:getMouseX()
    local mouseIn = self:isMouseOver()
    local maxRight = boxesX
    local tipText = nil
    self.rows, self.catRows = {}, {}

    local intro = getText("IGUI_TienSkillMastery_Intro")
    local intro2 = getText("IGUI_TienSkillMastery_Intro2")
    self:drawText(intro, PAD, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
    y = y + FONT_HGT_SMALL
    self:drawText(intro2, PAD, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
    y = y + FONT_HGT_SMALL + PAD
    local introWidth = math.max(tm:MeasureStringX(UIFont.Small, intro), tm:MeasureStringX(UIFont.Small, intro2))

    for _, g in ipairs(self.groups) do
        local closed = self.collapsed[g.key]
        if g.button then g.button:setY(y) end
        self:drawText(g.parent:getName(), left, y + fontOffset, 1, 1, 1, 1, UIFont.Small)
        table.insert(self.catRows, { y = y, h = ROW_HGT, key = g.key })
        y = y + ROW_HGT
        if not closed then
            if self.separator then self:drawTexture(self.separator, 0, y + PAD, 1, 1, 1, 1) end
            y = y + PAD
            for _, perk in ipairs(g.perks) do
                local id = perk:getId()
                local unlocked = player:getPerkLevel(perk) >= 10
                local level, into, cost = M.levelInfo(perk, M.getXp(player, perk))
                local prestige = unlocked and level > M.BONUS_LEVELS
                table.insert(self.rows, { y = y, h = ROW_HGT, id = id })
                local hovered = mouseIn and mouseY >= y and mouseY < y + ROW_HGT
                if hovered and mouseX < boxesX then
                    self:drawRect(left, y, boxesX - left, ROW_HGT, 0.08, 1, 1, 1)
                end
                local c = prestige and PRESTIGE or (unlocked and WHITE or GREY)
                self:drawText(perk:getName(), nameX, y + fontOffset, c[1], c[2], c[3], 1, UIFont.Small)
                local boxY = y + (ROW_HGT - SKILL_POINT) / 2
                local w = self:drawBoxes(boxesX, boxY, unlocked, math.min(level, M.BONUS_LEVELS),
                    cost > 0 and into / cost or 0, prestige)
                maxRight = math.max(maxRight, boxesX + w)
                if prestige then
                    local p = "+" .. string.format("%d", level - M.BONUS_LEVELS)
                    self:drawText(p, boxesX + w + 4, y + fontOffset, PRESTIGE[1], PRESTIGE[2], PRESTIGE[3], 1, UIFont.Small)
                    maxRight = math.max(maxRight, boxesX + w + 4 + tm:MeasureStringX(UIFont.Small, p))
                end
                if hovered and mouseX >= boxesX and mouseX < boxesX + w then
                    tipText = self:tooltipFor(player, perk)
                end
                y = y + ROW_HGT

                if self.expanded[id] then
                    local defs = M.defsByPerk[id]
                    if not defs then
                        self:drawText(getText("IGUI_TienSkillMastery_NoBonus"), nameX + PAD, y + fontOffset, 0.7, 0.7, 0.7, 1, UIFont.Small)
                        y = y + ROW_HGT
                    else
                        for _, d in ipairs(defs) do
                            local now = M.val(player, d.id)
                            local max = M.enabled(d) and d.at10 * M.scale(d.perk) or 0
                            local line = bonusLabel(d) .. ": " .. bonusValueText(d, now) .. "   ("
                                .. getText("IGUI_TienSkillMastery_AtMax", bonusValueText(d, max)) .. ")"
                            local g2 = now > 0 and 0.85 or 0.5
                            self:drawText(line, nameX + PAD, y + fontOffset, g2, g2, g2, 1, UIFont.Small)
                            maxRight = math.max(maxRight, nameX + PAD + tm:MeasureStringX(UIFont.Small, line))
                            y = y + ROW_HGT
                        end
                    end
                end
            end
        end
        y = y + PAD
    end
    y = y + 1

    self:showTooltip(tipText)
    local wantWidth = math.max(maxRight + PAD * 2 + SCROLL_BAR_WIDTH + 1, introWidth + PAD * 2)
    -- Fit the content: shrinks again when bonus lists close. Never below the width the view was made with (the
    -- tab strip's), so the window does not get narrower than vanilla's.
    self.minWidth = self.minWidth or self.width
    self:setWidthAndParentWidth(math.max(self.minWidth, wantWidth))
    self:setHeightAndParentHeight(math.min(y, 800))
    self:setScrollHeight(y)

    if self.joyfocus and self.rows[self.joypadIndex] then
        local r = self.rows[self.joypadIndex]
        self:drawRectBorder(left, r.y, self.width - left - SCROLL_BAR_WIDTH, r.h, 0.4, 0.2, 1.0, 1.0)
    end
    self:clearStencilRect()
end

function TienSkillMasteryPanel:onCollapse(button)
    local key = button.internal
    self.collapsed[key] = not self.collapsed[key] or nil
    button:setImage(self.collapsed[key] and self.treeClosed or self.treeOpen)
end

function TienSkillMasteryPanel:rowAt(y)
    for i, r in ipairs(self.rows) do
        if y >= r.y and y < r.y + r.h then return i, r end
    end
end

function TienSkillMasteryPanel:onMouseDown(x, y)
    for _, c in ipairs(self.catRows or {}) do
        if y >= c.y and y < c.y + c.h then
            for _, g in ipairs(self.groups) do
                if g.key == c.key and g.button then self:onCollapse(g.button) end
            end
            getSoundManager():playUISound("UIActivateButton")
            return true
        end
    end
    local i, r = self:rowAt(y)
    if r then
        self.expanded[r.id] = not self.expanded[r.id]
        self.selectedRow = i
        getSoundManager():playUISound("UIActivateButton")
    end
    return true
end

-- ---------------------------------------------------------------------------------------------------------------
-- Admin cheat (right-click a skill): add / remove mastery XP, set the mastery level, clear it. Own character only.
-- MP: roles with Capability.AddXP, sent as "adminChange" and checked again on the server. Single player: -debug,
-- applied directly (server/TienSkillMastery_Server.lua M.adminChange). Lua cannot add XP past level 10 any other way
-- in one go: Java's AddXP caps each award at the level-10 total.
-- ---------------------------------------------------------------------------------------------------------------

local function canCheat(player)
    if not player then return false end
    if isClient() then
        local role = player:getRole()
        return role ~= nil and role:hasCapability(Capability.AddXP)
    end
    return isDebugEnabled()
end

local function applyCheat(player, args)
    if isClient() then
        sendClientCommand(player, M.MODULE, "adminChange", args)
    elseif M.adminChange then
        M.adminChange(player, args)
    end
end

local function askNumber(self, title, default, onNumber)
    local w, h = 280, 120
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local box = ISTextBox:new(x, y, w, h, title, tostring(default), self, function(_, button)
        if button.internal ~= "OK" then return end
        local n = tonumber(button.parent.entry:getText())
        if n and n >= 0 then onNumber(n) end
    end)
    box:initialise()
    box:setOnlyNumbers(true)
    box:addToUIManager()
end

--- Opens the mastery cheat menu for `perkId` at the mouse, if the player may use it. Also used by the vanilla
--- Skills tab (client/TienSkillMastery_SkillsTab.lua). Returns true when a menu was shown.
function M.showCheatMenu(playerNum, perkId)
    local player = getSpecificPlayer(playerNum)
    local perk = M.perk(perkId)
    if not perk or not canCheat(player) then return false end
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    local unlocked = player:getPerkLevel(perk) >= 10
    local function opt(key, fn)
        local o = context:addOption(getText(key), nil, fn)
        if not unlocked then
            o.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_TienSkillMastery_Locked")
            o.toolTip = tip
        end
        return o
    end
    opt("IGUI_TienSkillMastery_Cheat_Add", function()
        askNumber(nil, getText("IGUI_TienSkillMastery_Cheat_AddTitle", perk:getName()), 1000, function(n)
            applyCheat(player, { perk = perkId, op = "add", amount = n })
        end)
    end)
    opt("IGUI_TienSkillMastery_Cheat_Remove", function()
        askNumber(nil, getText("IGUI_TienSkillMastery_Cheat_RemoveTitle", perk:getName()), 1000, function(n)
            applyCheat(player, { perk = perkId, op = "remove", amount = n })
        end)
    end)
    opt("IGUI_TienSkillMastery_Cheat_Level", function()
        local current = M.levelInfo(perk, M.getXp(player, perk))
        askNumber(nil, getText("IGUI_TienSkillMastery_Cheat_LevelTitle", perk:getName()), current, function(n)
            applyCheat(player, { perk = perkId, op = "level", level = n })
        end)
    end)
    opt("IGUI_TienSkillMastery_Cheat_Clear", function()
        applyCheat(player, { perk = perkId, op = "clear" })
    end)
    return true
end

--- The vanilla Skills tab's right-click menu (client/TienSkillMastery_SkillsTab.lua): cheats on the skill itself,
--- real XP and level, never mastery. Same gate as the mastery cheat; the server runs it as "adminSkill"
--- (server/TienSkillMastery_Server.lua M.adminSkill), single player calls it directly.
local function applySkillCheat(player, args)
    if isClient() then
        sendClientCommand(player, M.MODULE, "adminSkill", args)
    elseif M.adminSkill then
        M.adminSkill(player, args)
    end
end

function M.showSkillCheatMenu(playerNum, perkId)
    local player = getSpecificPlayer(playerNum)
    local perk = M.perk(perkId)
    if not perk or not canCheat(player) then return false end
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    context:addOption(getText("IGUI_TienSkillMastery_SkillCheat_Add"), nil, function()
        askNumber(nil, getText("IGUI_TienSkillMastery_SkillCheat_AddTitle", perk:getName()), 100, function(n)
            applySkillCheat(player, { perk = perkId, op = "add", amount = n })
        end)
    end)
    context:addOption(getText("IGUI_TienSkillMastery_SkillCheat_Remove"), nil, function()
        askNumber(nil, getText("IGUI_TienSkillMastery_SkillCheat_RemoveTitle", perk:getName()), 100, function(n)
            applySkillCheat(player, { perk = perkId, op = "remove", amount = n })
        end)
    end)
    context:addOption(getText("IGUI_TienSkillMastery_SkillCheat_Level"), nil, function()
        askNumber(nil, getText("IGUI_TienSkillMastery_SkillCheat_LevelTitle", perk:getName()), player:getPerkLevel(perk), function(n)
            applySkillCheat(player, { perk = perkId, op = "level", level = math.min(10, n) })
        end)
    end)
    return true
end

function TienSkillMasteryPanel:onRightMouseUp(x, y)
    local _, r = self:rowAt(y)
    if r then M.showCheatMenu(self.playerNum, r.id) end
    return true
end

function TienSkillMasteryPanel:onMouseWheel(del)
    self:setYScroll(self:getYScroll() - del * 30)
    return true
end

-- Joypad: up / down picks a skill, A expands it.
function TienSkillMasteryPanel:onJoypadDirUp()
    self.joypadIndex = math.max(1, (self.joypadIndex or 1) - 1)
    self:ensureRowVisible()
end

function TienSkillMasteryPanel:onJoypadDirDown()
    self.joypadIndex = math.min(#self.rows, (self.joypadIndex or 1) + 1)
    self:ensureRowVisible()
end

function TienSkillMasteryPanel:onJoypadDown(button)
    if button == Joypad.AButton then
        local r = self.rows[self.joypadIndex]
        if r then self.expanded[r.id] = not self.expanded[r.id] end
    elseif button == Joypad.BButton then
        getPlayerInfoPanel(self.playerNum):toggleView(getText("IGUI_TienSkillMastery_Tab"))
        setJoypadFocus(self.playerNum, nil)
    elseif button == Joypad.LBumper or button == Joypad.RBumper then
        getPlayerInfoPanel(self.playerNum):onJoypadDown(button)
    end
end

function TienSkillMasteryPanel:ensureRowVisible()
    local r = self.rows[self.joypadIndex]
    if not r then return end
    if r.y - 40 < -self:getYScroll() then
        self:setYScroll(-(r.y - 40))
    elseif r.y + r.h + 40 > -self:getYScroll() + self:getHeight() then
        self:setYScroll(-(r.y + r.h + 40 - self:getHeight()))
    end
end

-- ---------------------------------------------------------------------------------------------------------------
-- The tab
-- ---------------------------------------------------------------------------------------------------------------

local originalCreateChildren = ISCharacterInfoWindow.createChildren
function ISCharacterInfoWindow:createChildren()
    originalCreateChildren(self)
    local ok, err = pcall(function()
        local view = TienSkillMasteryPanel:new(0, 8, self.characterView:getWidth(), self.height - 8, self.playerNum)
        view:initialise()
        self.masteryView = view
        self.panel:addView(getText("IGUI_TienSkillMastery_Tab"), view)
        local list = self.panel.viewList
        local mine = table.remove(list, #list)
        local at = #list + 1
        for i, v in ipairs(list) do
            if v.view == self.characterView then at = i + 1 break end
        end
        table.insert(list, at, mine)
    end)
    if not ok then print("[TienSkillMastery] could not add the Mastery tab: " .. tostring(err)) end
end
