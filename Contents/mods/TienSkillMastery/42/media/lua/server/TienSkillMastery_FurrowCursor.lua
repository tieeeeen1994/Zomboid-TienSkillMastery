--[[
Tien's Skill Mastery: Homesteading's "Dig furrows" cursor (user, 2026-11-09), 42.21. Works like vanilla's rake
(`ISPickDungCursor`): a 3 x 3 square follows the mouse, green where something can be dug, red where not; each click walks
there and queues one action for the whole square (shared/TienSkillMastery_FieldAction.lua, kind "furrow"), and the
cursor stays until cancelled (Esc, or a right-click, whose context menu clears it: `ISWorldObjectContextMenu.createMenu`).

Here in media/lua/server because `ISBuildingObject` is: at the main menu only shared and client Lua are loaded, so a
client file could not derive from it at file level. MP clients load this folder too; a dedicated server has no use for it.

The squares are the ones vanilla's plow cursor accepts (`ISFarmingMenu.canDigHereSquare`: dirt, free, no grave, no
furrow or living plant; on a client `ISShovelGroundCursor.GetDirtGravelSand` also skips dirt under any plot, so dead ones
are removed first) that the character could see when clicked; the server checks again for itself. A square under
something else is left out, not refused: a click is valid when any square of the 3 x 3 can be dug.
]]

if isServer() then return end

require "BuildingObjects/ISBuildingObject"
require "TienSkillMastery"
require "TienSkillMastery_FieldAction"
local M = TienSkillMastery

TienSkillMasteryFurrowCursor = ISBuildingObject:derive("TienSkillMasteryFurrowCursor")
local C = TienSkillMasteryFurrowCursor

local SIZE = M.FIELD_BLOCK
local DIG_TIME = 110    -- one square with a tool, `ISPlowAction:getDuration`

--- The squares of the 3 x 3 from (x, y) that can be dug now: { { x, y }, ... }.
function C:targets(x, y, z)
    local list = {}
    local playerNum = self.character:getPlayerNum()
    for x2 = x, x + SIZE - 1 do
        for y2 = y, y + SIZE - 1 do
            local square = getCell():getGridSquare(x2, y2, z)
            if square and square:isCouldSee(playerNum) and ISFarmingMenu.canDigHereSquare(square) then
                list[#list + 1] = { x = x2, y = y2 }
            end
        end
    end
    return list
end

function C:isValid(square)
    if not ISFarmingMenu.getShovel(self.character) then return false end
    return #self:targets(square:getX(), square:getY(), square:getZ()) > 0
end

function C:isRunningAction()
    local queue = ISTimedActionQueue.getTimedActionQueue(self.character)
    return queue and queue.queue and queue.queue[1]
end

function C:walkTo(x, y, z)
    local chr = self.character
    if chr:isTimedActionInstant() then return true end
    local here = chr:getCurrentSquare()
    -- With actions queued the character will not be where it stands now.
    if here and not self:isRunningAction() and here:getX() >= x - 1 and here:getX() <= x + SIZE
        and here:getY() >= y - 1 and here:getY() <= y + SIZE then
        return true
    end
    local square = M.fieldStandSquare(x, y, x + SIZE - 1, y + SIZE - 1, z)
    if not square then return false end
    ISTimedActionQueue.add(ISWalkToTimedAction:new(chr, square))
    return true
end

function C:create(x, y, z)
    local chr = self.character
    local tool = ISFarmingMenu.getShovel(chr)
    local targets = self:targets(x, y, z)
    if not tool or #targets == 0 then return end
    ISInventoryPaneContextMenu.equipWeapon(tool, true, tool:isTwoHandWeapon(), self.player)
    ISTimedActionQueue.add(TienSkillMasteryFieldAction:new(chr, tool, "furrow", "", z, M.fieldEncode(targets),
        DIG_TIME))
end

function C:render(x, y, z)
    if self:isRunningAction() then return end
    local square = getCell():getGridSquare(x, y, z)
    local color = square and self:isValid(square) and getCore():getGoodHighlitedColor() or getCore():getBadHighlitedColor()
    renderIsoRect(x + 1, y + 1, z, SIZE, color:getR(), color:getG(), color:getB(), 0.5, 1)
end

function C:new(character)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o:init()
    o.character = character
    o.player = character:getPlayerNum()
    o.skipBuildAction = true
    o.noNeedHammer = true
    o.renderFloorHelper = true
    return o
end
