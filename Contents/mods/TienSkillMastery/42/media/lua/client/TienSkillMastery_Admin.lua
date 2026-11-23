--[[
Tien's Skill Mastery: the Mastery admin window (user, 2026-11-23: "an admin module to grant XP to mastery to other
people"). Pick any player the server knows (everyone with mastery data, plus everyone online; offline players too),
see their picks and levels, and pick a mastery for them, add or remove points, set the level, clear it or remove the
pick. The server applies it (server/TienSkillMastery_Server.lua M.adminChange / M.adminState) and checks
`Capability.AddXP` again, like /addxp; single player: -debug, and the client calls those functions directly (the
server Lua is loaded there).

Opened from the Mastery tab's right-click menu ("Mastery admin (any player)..."; no world menu entry, user
2026-11-24). An admin's pick takes a free slot without the member check
(putting back a pick lost to a restored backup, for one); a pick whose members are not all at 10 earns nothing until
they are, as for anyone.
]]

require "ISUI/ISCollapsableWindow"
require "ISUI/ISScrollingListBox"
require "ISUI/ISComboBox"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
require "TienSkillMastery"
local M = TienSkillMastery

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local BUTTON_HGT = FONT_HGT_SMALL + 6
local PAD = 10
local TAR = { 1, 0.89, 0.38 }
local GREY = { 0.54, 0.54, 0.54 }
local WHITE = { 1, 1, 1 }

TienSkillMasteryAdmin = ISCollapsableWindow:derive("TienSkillMasteryAdmin")

--- Who may use it: MP roles with AddXP (checked again on the server), single player with -debug.
function M.canAdmin(player)
    if not player then return false end
    if isClient() then
        local role = player:getRole()
        return role ~= nil and role:hasCapability(Capability.AddXP)
    end
    return isDebugEnabled()
end

local function masteryName(id)
    return M.masteryName and M.masteryName(id) or id
end

local function fmt(n)
    local s = string.format("%.1f", n or 0)
    s = s:gsub("%.0$", "")
    return s
end

-- ---------------------------------------------------------------------------------------------------------------
-- Talking to the server (single player: the server functions directly)
-- ---------------------------------------------------------------------------------------------------------------

function TienSkillMasteryAdmin:request(args)
    local player = getSpecificPlayer(self.playerNum)
    if not player then return end
    if isClient() then
        if args.op then
            sendClientCommand(player, M.MODULE, "adminChange", args)
        else
            sendClientCommand(player, M.MODULE, "adminState", args)
        end
        return
    end
    if args.op and M.adminChange then
        M.adminChange(player, args)
        M.version = (M.version or 0) + 1
    end
    if M.adminState then self:setState(M.adminState(player, args.target)) end
end

local function listOf(t)
    local list, i = {}, 1
    if type(t) ~= "table" then return list end
    -- Tables sent by the server arrive with number keys as doubles; read them in order.
    while t[i] ~= nil do
        list[#list + 1] = t[i]
        i = i + 1
    end
    return list
end

function TienSkillMasteryAdmin:setState(state)
    if type(state) ~= "table" or type(state.target) ~= "string" then return end
    self.state = {
        target = state.target,
        online = state.online == true,
        picks = {},
        points = {},
        active = {},
        maxPicks = tonumber(state.maxPicks) or M.maxPicks(),
    }
    for _, id in ipairs(listOf(state.picks)) do
        if M.masteryById[id] then
            self.state.picks[#self.state.picks + 1] = id
            self.state.picked = self.state.picked or {}
            self.state.picked[id] = true
        end
    end
    self.state.picked = self.state.picked or {}
    if type(state.points) == "table" then
        for k, v in pairs(state.points) do self.state.points[k] = tonumber(v) or 0 end
    end
    if type(state.active) == "table" then
        for k, v in pairs(state.active) do self.state.active[k] = v == true end
    end
    -- Player list: keep the selection, add names the server knows.
    local names = listOf(state.names)
    self.combo:clear()
    for _, name in ipairs(names) do self.combo:addOption(name) end
    if not self.combo:contains(state.target) then self.combo:addOption(state.target) end
    self.combo:select(state.target)
    self.target = state.target
end

local function onServerCommand(module, command, args)
    if module ~= M.MODULE or command ~= "adminState" then return end
    local window = TienSkillMasteryAdmin.instance
    if window and window:isVisible() then window:setState(args) end
end
Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------------------------------------------

function TienSkillMasteryAdmin:createChildren()
    ISCollapsableWindow.createChildren(self)
    local y = self:titleBarHeight() + PAD
    local w = self.width - PAD * 2

    self.combo = ISComboBox:new(PAD, y, w, BUTTON_HGT, self, self.onPlayerChosen)
    self.combo:initialise()
    self.combo:setEditable(true)
    self:addChild(self.combo)
    y = y + BUTTON_HGT + 6

    self.infoY = y
    y = y + FONT_HGT_SMALL + 6

    local buttonRows = 2
    local listH = self.height - y - PAD - buttonRows * (BUTTON_HGT + 6) - self:resizeWidgetHeight()
    self.list = ISScrollingListBox:new(PAD, y, w, listH)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = BUTTON_HGT
    self.list.font = UIFont.Small
    self.list.drawBorder = true
    self.list.doDrawItem = TienSkillMasteryAdmin.drawRow
    self.list.adminWindow = self
    self:addChild(self.list)
    for _, m in ipairs(M.masteries) do self.list:addItem(masteryName(m.id), m.id) end
    y = y + listH + 6

    local bw = math.floor((w - 2 * 6) / 3)
    local function button(col, row, key, fn)
        local b = ISButton:new(PAD + col * (bw + 6), y + row * (BUTTON_HGT + 6), bw, BUTTON_HGT, getText(key), self, fn)
        b:initialise()
        self:addChild(b)
        return b
    end
    self.pickBtn = button(0, 0, "IGUI_TienSkillMastery_Admin_Pick", self.onPick)
    self.addBtn = button(1, 0, "IGUI_TienSkillMastery_Cheat_Add", self.onAdd)
    self.levelBtn = button(2, 0, "IGUI_TienSkillMastery_Cheat_Level", self.onLevel)
    self.removeBtn = button(0, 1, "IGUI_TienSkillMastery_Cheat_Remove", self.onRemove)
    self.clearBtn = button(1, 1, "IGUI_TienSkillMastery_Cheat_Clear", self.onClear)
    self.unpickBtn = button(2, 1, "IGUI_TienSkillMastery_Admin_Unpick", self.onUnpick)
end

function TienSkillMasteryAdmin.drawRow(list, y, item, alt)
    local self = list.adminWindow
    local h = list.itemheight
    if y + h < -list:getYScroll() or y > -list:getYScroll() + list.height then return y + h end
    if list.selected == item.itemindex then
        list:drawRect(0, y, list:getWidth(), h, 0.3, 0.7, 0.35, 0.15)
    end
    local id = item.item
    local st = self.state
    local picked = st and st.picked[id]
    local c = picked and WHITE or GREY
    list:drawText(item.text, 8, y + 3, c[1], c[2], c[3], 1, UIFont.Small)
    local status
    if not st then
        status = ""
    elseif picked then
        local level, left, cost = M.levelInfo(st.points[id] or 0)
        status = getText("IGUI_TienSkillMastery_Admin_Level", string.format("%d", level), fmt(left), fmt(cost))
        if st.online and st.active[id] == false then
            status = status .. " " .. getText("IGUI_TienSkillMastery_Admin_Inactive")
        end
    elseif M.COMING_SOON[id] then
        status = getText("IGUI_TienSkillMastery_ComingSoon")
    else
        status = getText("IGUI_TienSkillMastery_Admin_NotPicked")
    end
    local col = picked and TAR or GREY
    local tw = getTextManager():MeasureStringX(UIFont.Small, status)
    list:drawText(status, list:getWidth() - tw - 8 - 13, y + 3, col[1], col[2], col[3], 1, UIFont.Small)
    return y + h
end

function TienSkillMasteryAdmin:selectedId()
    local row = self.list.items[self.list.selected]
    return row and row.item
end

function TienSkillMasteryAdmin:prerender()
    ISCollapsableWindow.prerender(self)
    local st = self.state
    local text
    if not st then
        text = getText("IGUI_TienSkillMastery_Admin_Waiting")
    else
        text = getText(st.online and "IGUI_TienSkillMastery_Admin_Online" or "IGUI_TienSkillMastery_Admin_Offline",
            string.format("%d", #st.picks), string.format("%d", st.maxPicks))
    end
    self:drawText(text, PAD, self.infoY, 0.8, 0.8, 0.8, 1, UIFont.Small)
    local id = self:selectedId()
    local picked = st and id and st.picked[id]
    local canPick = st and id and not picked and not M.COMING_SOON[id] and #st.picks < st.maxPicks
    self.pickBtn:setEnable(canPick and true or false)
    for _, b in ipairs({ self.addBtn, self.levelBtn, self.removeBtn, self.clearBtn, self.unpickBtn }) do
        b:setEnable(picked and true or false)
    end
end

function TienSkillMasteryAdmin:onPlayerChosen(combo)
    local name = combo:getSelectedText()
    if not name or name == "" then return end
    self.target = name
    self.state = nil
    self:request({ target = name })
end

function TienSkillMasteryAdmin:change(op, extra)
    local id = self:selectedId()
    if not id or not self.target then return end
    local args = { target = self.target, mastery = id, op = op }
    for k, v in pairs(extra or {}) do args[k] = v end
    self:request(args)
end

function TienSkillMasteryAdmin:title(key)
    return getText(key, masteryName(self:selectedId())) .. " - " .. tostring(self.target)
end

function TienSkillMasteryAdmin:onPick()
    self:change("pick")
end

function TienSkillMasteryAdmin:onAdd()
    M.askNumber(self:title("IGUI_TienSkillMastery_Cheat_AddTitle"), 100, function(n)
        self:change("add", { amount = n })
    end)
end

function TienSkillMasteryAdmin:onRemove()
    M.askNumber(self:title("IGUI_TienSkillMastery_Cheat_RemoveTitle"), 100, function(n)
        self:change("remove", { amount = n })
    end)
end

function TienSkillMasteryAdmin:onLevel()
    local id = self:selectedId()
    local level = id and self.state and (M.levelInfo(self.state.points[id] or 0)) or 0
    M.askNumber(self:title("IGUI_TienSkillMastery_Cheat_LevelTitle"), level, function(n)
        self:change("level", { level = n })
    end)
end

function TienSkillMasteryAdmin:onClear()
    self:change("clear")
end

function TienSkillMasteryAdmin:onUnpick()
    local name = masteryName(self:selectedId())
    local w, h = 360, 120
    local modal = ISModalDialog:new(getCore():getScreenWidth() / 2 - w / 2, getCore():getScreenHeight() / 2 - h / 2,
        w, h, getText("IGUI_TienSkillMastery_Admin_UnpickConfirm", name, tostring(self.target)), true, self,
        function(target, button)
            if button.internal == "YES" then target:change("unpick") end
        end)
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    modal:bringToTop()
end

function TienSkillMasteryAdmin:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    TienSkillMasteryAdmin.instance = nil
end

function TienSkillMasteryAdmin:new(x, y, w, h, playerNum)
    local o = ISCollapsableWindow.new(self, x, y, w, h)
    o.playerNum = playerNum
    o.title = getText("IGUI_TienSkillMastery_Admin_Title")
    o.resizable = false
    return o
end

--- Opens the window (one at a time) on `targetName`, or on the admin when nil.
function M.openAdmin(playerNum, targetName)
    local player = getSpecificPlayer(playerNum)
    if not M.canAdmin(player) then return end
    local window = TienSkillMasteryAdmin.instance
    if not window then
        local w, h = 540, 120 + #M.masteries * BUTTON_HGT + 3 * (BUTTON_HGT + 6)
        h = math.min(h, getCore():getScreenHeight() - 40)
        window = TienSkillMasteryAdmin:new(getCore():getScreenWidth() / 2 - w / 2,
            getCore():getScreenHeight() / 2 - h / 2, w, h, playerNum)
        window:initialise()
        window:addToUIManager()
        TienSkillMasteryAdmin.instance = window
    end
    window:setVisible(true)
    window:bringToTop()
    local name = targetName or player:getUsername()
    window.target = name
    window.state = nil
    window:request({ target = name })
end
