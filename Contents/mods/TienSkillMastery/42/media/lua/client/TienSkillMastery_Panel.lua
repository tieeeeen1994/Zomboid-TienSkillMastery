--[[
Tien's Skill Mastery: the Mastery tab of the character window (next to Skills).

`ISCharacterInfoWindow:createChildren` (42.21) builds its tabs as views of an ISTabPanel (`self.panel:addView`); the
wrapper adds this view after vanilla's and moves it right after Skills in `viewList` (tabs are drawn and cycled in
that order; `activateViewById` looks views up by their `id` field, so moving the entry is safe). Each view sizes the
window while it is shown (`setWidthAndParentWidth` / `setHeightAndParentHeight` from its render, as ISCharacterInfo
does). The window's layout save only records vanilla's tabs, so a torn-off Mastery tab is not restored.

v2 (docs/v2-draft.md): the 22 masteries by group, styled like the vanilla Skills tab (collapsible groups with the
tree arrow and SkillBarSeparator). Each row: the mastery's name, then its state: ten SkillUnit boxes in vanilla's
gold for a picked one (the level in progress filled by its progress, prestige past 10 as +n in a deeper gold,
grey while inactive), a Pick button when every member is at 10 and a slot is free, else "Locked" / "Closed"; then
the member skills, each in green once at 10. A slot counter heads the tab. Click a row to list its effects now and
at mastery 10. Picking asks for confirmation (permanent) and is checked again on the server.
]]

require "ISUI/ISPanelJoypad"
require "ISUI/ISModalDialog"
require "XpSystem/ISUI/ISCharacterInfoWindow"
require "TienSkillMastery"
local M = TienSkillMastery

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local ROW_HGT = FONT_HGT_SMALL + 6          -- vanilla's BUTTON_HGT, one row
local PAD = 10                               -- vanilla's UI_BORDER_SPACING
local SCROLL_BAR_WIDTH = 13
local SKILL_POINT = math.floor(ROW_HGT / 2)  -- ISSkillProgressBar's SKILL_POINT_HGT
local TAR = { 1, 0.89, 0.38 }                -- vanilla's colour for gained levels
local PRESTIGE = { 1, 0.83, 0 }              -- vanilla's colour for a x3 boost, used here for prestige
local WHITE = { 1, 1, 1 }
local GREY = { 0.54, 0.54, 0.54 }
local GREEN = { 0.55, 0.85, 0.45 }
local AMBER = { 0.9, 0.6, 0.3 }

TienSkillMasteryPanel = ISPanelJoypad:derive("TienSkillMasteryPanel")

local function fmt(n)
    local s = string.format("%.1f", n)
    s = s:gsub("%.0$", "")
    return s
end

local function bonusValueText(d, v)
    local n = fmt(v)
    local kind = d.kind == "step" and d.unit or d.kind
    if kind == "pct" then return "+" .. n .. "%" end
    if kind == "less" then return "-" .. n .. "%" end
    if kind == "ptsoff" then return "-" .. n end
    return "+" .. n
end

local function bonusLabel(d)
    return getTextOrNull("IGUI_TienSkillMastery_Bonus_" .. d.mastery .. "_" .. d.name)
        or getTextOrNull("IGUI_TienSkillMastery_Bonus_" .. d.name) or d.name
end

local function masteryName(id)
    return M.masteryName and M.masteryName(id) or id
end

local function groupName(g)
    return getTextOrNull("IGUI_TienSkillMastery_Group_" .. g) or g
end

local function memberName(perkId)
    local perk = M.perk(perkId)
    return perk and perk:getName() or perkId
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
    o.pickButtons = {}
    o.joypadIndex = 1
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
    local tm = getTextManager()
    local groups, byGroup = {}, {}
    for _, g in ipairs(M.GROUPS) do
        byGroup[g] = { key = g, masteries = {} }
        table.insert(groups, byGroup[g])
    end
    self.nameLen = 0
    for _, m in ipairs(M.masteries) do
        local g = byGroup[m.group]
        if g then table.insert(g.masteries, m) end
        self.nameLen = math.max(self.nameLen, tm:MeasureStringX(UIFont.Small, masteryName(m.id)))
    end
    self.groups = groups
    -- The state column: wide enough for the boxes, the Pick button and the state words.
    self.pickText = getText("IGUI_TienSkillMastery_Pick")
    self.pickWidth = tm:MeasureStringX(UIFont.Small, self.pickText) + PAD * 2
    self.stateWords = {
        locked = getText("IGUI_TienSkillMastery_StateLocked"),
        closed = getText("IGUI_TienSkillMastery_StateClosed"),
    }
    self.stateLen = self.pickWidth
    for _, w in pairs(self.stateWords) do self.stateLen = math.max(self.stateLen, tm:MeasureStringX(UIFont.Small, w)) end
    -- One collapse button per group, made like vanilla's (ISCharacterInfo:createChildren): an ISButton with the
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

--- Ten boxes drawn the way ISSkillProgressBar:renderPerkRect draws a skill: gained levels filled in `colour`, the
--- level in progress as a grey border filled by its progress, the rest dark borders.
function TienSkillMasteryPanel:drawBoxes(x, y, level, progress, colour)
    local gap = getCore():getOptionFontSizeReal()
    for i = 1, M.BONUS_LEVELS do
        if i <= level then
            self:drawTextureScaled(self.unitFill, x, y, SKILL_POINT, SKILL_POINT, 1, colour[1], colour[2], colour[3])
            self:drawTextureScaled(self.unitBorder, x, y, SKILL_POINT, SKILL_POINT, 1, colour[1], colour[2], colour[3])
        elseif i == level + 1 then
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

function TienSkillMasteryPanel:boxesWidth()
    return M.BONUS_LEVELS * (SKILL_POINT + getCore():getOptionFontSizeReal())
end

function TienSkillMasteryPanel:tooltipFor(player, m, state)
    local level, into, cost = M.levelInfo(M.getPoints(player, m.id))
    local text = masteryName(m.id) .. " <LINE> "
    if state == "inactive" then text = text .. getText("IGUI_TienSkillMastery_Inactive") .. " <LINE> " end
    if level >= M.BONUS_LEVELS then
        text = text .. getText("IGUI_TienSkillMastery_Prestige", string.format("%d", level - M.BONUS_LEVELS))
    else
        text = text .. getText("IGUI_TienSkillMastery_Level", string.format("%d", level))
    end
    return text .. " <LINE> " .. getText("IGUI_TienSkillMastery_Points", fmt(into), fmt(cost))
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
    local stateX = left + PAD * 3 + self.nameLen  -- where vanilla puts the skill bar
    local stateW = math.max(self:boxesWidth() + tm:MeasureStringX(UIFont.Small, "+00") + 4, self.stateLen)
    local membersX = stateX + stateW + PAD * 2
    local fontOffset = (ROW_HGT - FONT_HGT_SMALL) / 2
    local mouseY, mouseX = self:getMouseY(), self:getMouseX()
    local mouseIn = self:isMouseOver()
    local maxRight = membersX
    local tipText = nil
    self.rows, self.catRows, self.pickButtons = {}, {}, {}

    local picked = #M.picks(player)
    local intro = getText("IGUI_TienSkillMastery_Intro", string.format("%d", M.MAX_PICKS))
    local intro2 = getText("IGUI_TienSkillMastery_Intro2")
    local slots = getText("IGUI_TienSkillMastery_Slots", string.format("%d", picked), string.format("%d", M.MAX_PICKS))
    for _, line in ipairs({ intro, intro2 }) do
        self:drawText(line, PAD, y, 0.8, 0.8, 0.8, 1, UIFont.Small)
        maxRight = math.max(maxRight, PAD + tm:MeasureStringX(UIFont.Small, line))
        y = y + FONT_HGT_SMALL
    end
    y = y + 4
    self:drawText(slots, PAD, y, TAR[1], TAR[2], TAR[3], 1, UIFont.Small)
    y = y + FONT_HGT_SMALL + PAD

    for _, g in ipairs(self.groups) do
        local closed = self.collapsed[g.key]
        if g.button then g.button:setY(y) end
        self:drawText(groupName(g.key), left, y + fontOffset, 1, 1, 1, 1, UIFont.Small)
        table.insert(self.catRows, { y = y, h = ROW_HGT, key = g.key })
        y = y + ROW_HGT
        if not closed then
            if self.separator then self:drawTexture(self.separator, 0, y + PAD, 1, 1, 1, 1) end
            y = y + PAD
            for _, m in ipairs(g.masteries) do
                local state = M.state(player, m.id)
                local level, into, cost = M.levelInfo(M.getPoints(player, m.id))
                local isPicked = state == "picked" or state == "inactive"
                local prestige = isPicked and level > M.BONUS_LEVELS
                table.insert(self.rows, { y = y, h = ROW_HGT, id = m.id })
                local hovered = mouseIn and mouseY >= y and mouseY < y + ROW_HGT
                if hovered and mouseX < stateX then
                    self:drawRect(left, y, stateX - left, ROW_HGT, 0.08, 1, 1, 1)
                end
                local c = GREY
                if state == "picked" then c = prestige and PRESTIGE or WHITE
                elseif state == "inactive" then c = AMBER
                elseif state == "available" then c = GREEN end
                self:drawText(masteryName(m.id), nameX, y + fontOffset, c[1], c[2], c[3], 1, UIFont.Small)

                if isPicked then
                    local boxY = y + (ROW_HGT - SKILL_POINT) / 2
                    local colour = state == "inactive" and GREY or (prestige and PRESTIGE or TAR)
                    local w = self:drawBoxes(stateX, boxY, math.min(level, M.BONUS_LEVELS),
                        cost > 0 and into / cost or 0, colour)
                    if prestige then
                        local p = "+" .. string.format("%d", level - M.BONUS_LEVELS)
                        self:drawText(p, stateX + w + 4, y + fontOffset, PRESTIGE[1], PRESTIGE[2], PRESTIGE[3], 1, UIFont.Small)
                    end
                    if hovered and mouseX >= stateX and mouseX < stateX + w then
                        tipText = self:tooltipFor(player, m, state)
                    end
                elseif state == "available" then
                    local bx, by, bw, bh = stateX, y + 1, self.pickWidth, ROW_HGT - 2
                    local over = hovered and mouseX >= bx and mouseX < bx + bw
                    self:drawRect(bx, by, bw, bh, over and 0.6 or 0.35, 0.2, 0.45, 0.2)
                    self:drawRectBorder(bx, by, bw, bh, 0.9, 0.55, 0.85, 0.45)
                    self:drawTextCentre(self.pickText, bx + bw / 2, y + fontOffset, 1, 1, 1, 1, UIFont.Small)
                    table.insert(self.pickButtons, { x = bx, y = by, w = bw, h = bh, id = m.id })
                    if over then tipText = getText("IGUI_TienSkillMastery_PickTip") end
                else
                    self:drawText(self.stateWords[state] or "", stateX, y + fontOffset, GREY[1], GREY[2], GREY[3], 1, UIFont.Small)
                end

                -- Members, each green once at 10.
                local x = membersX
                for i, perkId in ipairs(m.members) do
                    local text = memberName(perkId) .. (i < #m.members and ", " or "")
                    local mc = M.memberAt10(player, perkId) and GREEN or GREY
                    self:drawText(text, x, y + fontOffset, mc[1], mc[2], mc[3], 1, UIFont.Small)
                    x = x + tm:MeasureStringX(UIFont.Small, text)
                end
                maxRight = math.max(maxRight, x)
                y = y + ROW_HGT

                if self.expanded[m.id] then
                    local shown = 0
                    for _, d in ipairs(m.defs) do
                        if M.enabled(d) then
                            local now = M.val(player, d.id)
                            local line
                            local cr, cg, cb
                            if d.kind == "sig" then
                                -- Signature: an unlock, in full from the pick.
                                line = getText("IGUI_TienSkillMastery_Signature", bonusLabel(d)) .. "   ("
                                    .. getText(now > 0 and "IGUI_TienSkillMastery_SigOn" or "IGUI_TienSkillMastery_SigOff") .. ")"
                                if now > 0 then cr, cg, cb = TAR[1], TAR[2], TAR[3] else cr, cg, cb = 0.5, 0.5, 0.5 end
                            else
                                local max = M.valueAt(d, M.BONUS_LEVELS) * M.scale(d.mastery)
                                line = bonusLabel(d) .. ": " .. bonusValueText(d, now) .. "   ("
                                    .. getText("IGUI_TienSkillMastery_AtMax", bonusValueText(d, max)) .. ")"
                                local g2 = now > 0 and 0.85 or 0.5
                                cr, cg, cb = g2, g2, g2
                            end
                            self:drawText(line, nameX + PAD, y + fontOffset, cr, cg, cb, 1, UIFont.Small)
                            maxRight = math.max(maxRight, nameX + PAD + tm:MeasureStringX(UIFont.Small, line))
                            y = y + ROW_HGT
                            shown = shown + 1
                        end
                    end
                    if shown == 0 then
                        self:drawText(getText("IGUI_TienSkillMastery_NoBonus"), nameX + PAD, y + fontOffset, 0.7, 0.7, 0.7, 1, UIFont.Small)
                        y = y + ROW_HGT
                    end
                end
            end
        end
        y = y + PAD
    end
    y = y + 1

    self:showTooltip(tipText)
    local wantWidth = maxRight + PAD * 2 + SCROLL_BAR_WIDTH + 1
    -- Fit the content: shrinks again when effect lists close. Never below the width the view was made with (the
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

-- ---------------------------------------------------------------------------------------------------------------
-- Picking (permanent; checked again on the server, server/TienSkillMastery_Server.lua M.pick)
-- ---------------------------------------------------------------------------------------------------------------

local function sendPick(player, masteryId)
    if isClient() then
        sendClientCommand(player, M.MODULE, "pick", { mastery = masteryId })
    elseif M.pick then
        M.pick(player, masteryId)
        M.version = (M.version or 0) + 1
    end
end

function TienSkillMasteryPanel:askPick(masteryId)
    local player = getSpecificPlayer(self.playerNum)
    if not player or M.state(player, masteryId) ~= "available" then return end
    local slot = #M.picks(player) + 1
    -- ISModalDialog draws its text as one line (`drawTextCentre`, no rich text, no wrapping), so each line is its own
    -- string and drawn on its own line below.
    local lines = {
        getText("IGUI_TienSkillMastery_PickConfirm", masteryName(masteryId), string.format("%d", slot),
            string.format("%d", M.MAX_PICKS)),
        getText("IGUI_TienSkillMastery_PickConfirm2"),
        getText("IGUI_TienSkillMastery_PickConfirm3"),
    }
    local tm = getTextManager()
    local w = 300
    for _, line in ipairs(lines) do w = math.max(w, tm:MeasureStringX(UIFont.Small, line) + PAD * 4) end
    local h = 20 + #lines * FONT_HGT_SMALL + PAD + ROW_HGT + PAD * 3
    local x = getCore():getScreenWidth() / 2 - w / 2
    local y = getCore():getScreenHeight() / 2 - h / 2
    local modal = ISModalDialog:new(x, y, w, h, "", true, self, function(_, button)
        if button.internal == "YES" then sendPick(player, masteryId) end
    end)
    local vanillaRender = modal.render
    modal.render = function(m)
        vanillaRender(m)
        for i, line in ipairs(lines) do
            m:drawTextCentre(line, m:getWidth() / 2, 20 + (i - 1) * FONT_HGT_SMALL, 1, 1, 1, 1, UIFont.Small)
        end
    end
    modal:initialise()
    modal:addToUIManager()
end

function TienSkillMasteryPanel:onMouseDown(x, y)
    for _, b in ipairs(self.pickButtons or {}) do
        if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
            getSoundManager():playUISound("UIActivateButton")
            self:askPick(b.id)
            return true
        end
    end
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
-- Admin cheat (right-click a picked mastery): add / remove points, set the level, clear, remove the pick. Own
-- character only. MP: roles with Capability.AddXP, sent as "adminChange" and checked again on the server. Single
-- player: -debug, applied directly (server/TienSkillMastery_Server.lua M.adminChange).
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
        M.version = (M.version or 0) + 1
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

--- Opens the mastery cheat menu for `masteryId` at the mouse, if the player may use it. Returns true when shown.
function M.showCheatMenu(playerNum, masteryId)
    local player = getSpecificPlayer(playerNum)
    if not M.masteryById[masteryId] or not canCheat(player) then return false end
    local context = ISContextMenu.get(playerNum, getMouseX(), getMouseY())
    local picked = M.isPicked(player, masteryId)
    local name = masteryName(masteryId)
    local function opt(key, fn)
        local o = context:addOption(getText(key), nil, fn)
        if not picked then
            o.notAvailable = true
            local tip = ISWorldObjectContextMenu.addToolTip()
            tip.description = getText("IGUI_TienSkillMastery_NotPicked")
            o.toolTip = tip
        end
        return o
    end
    opt("IGUI_TienSkillMastery_Cheat_Add", function()
        askNumber(nil, getText("IGUI_TienSkillMastery_Cheat_AddTitle", name), 100, function(n)
            applyCheat(player, { mastery = masteryId, op = "add", amount = n })
        end)
    end)
    opt("IGUI_TienSkillMastery_Cheat_Remove", function()
        askNumber(nil, getText("IGUI_TienSkillMastery_Cheat_RemoveTitle", name), 100, function(n)
            applyCheat(player, { mastery = masteryId, op = "remove", amount = n })
        end)
    end)
    opt("IGUI_TienSkillMastery_Cheat_Level", function()
        askNumber(nil, getText("IGUI_TienSkillMastery_Cheat_LevelTitle", name), M.fullLevel(player, masteryId), function(n)
            applyCheat(player, { mastery = masteryId, op = "level", level = n })
        end)
    end)
    opt("IGUI_TienSkillMastery_Cheat_Clear", function()
        applyCheat(player, { mastery = masteryId, op = "clear" })
    end)
    opt("IGUI_TienSkillMastery_Cheat_Unpick", function()
        applyCheat(player, { mastery = masteryId, op = "unpick" })
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

-- Joypad: up / down picks a mastery, A expands it (or picks it when available).
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
        local player = getSpecificPlayer(self.playerNum)
        if r and player and M.state(player, r.id) == "available" then
            self:askPick(r.id)
        elseif r then
            self.expanded[r.id] = not self.expanded[r.id]
        end
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
