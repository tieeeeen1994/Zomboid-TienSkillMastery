--[[
Tien's Skill Mastery: helpers for the timed-action time bonuses of the workshop skills (Cooking, First Aid,
Mechanics, Welding; files TienSkillMastery_Workshop*.lua). Loads before them (`.` sorts before letters) and is
required by each.

Where a vanilla timed action's time is read (42.21):
- Client and single player: `ISBaseTimedAction:begin` -> `create()` (shared/TimedActions/ISBaseTimedAction.lua ~78)
  runs `self.maxTime = self:adjustMaxTime(self.maxTime)` and builds the Java `LuaTimedActionNew`, whose constructor
  reads `maxTime` from the table as an Integer. Nothing on these sides calls `getDuration` except the action's own
  `new` (`o.maxTime = o:getDuration()` in most actions).
- MP server: `NetTimedAction` rebuilds the action with `Type.new(...)` from the client's values of `new`'s parameter
  names, then reads `getDuration()` (Java `NetTimedAction.getDuration` ~71) and sets end = start + adjusted duration x
  20 ms. `create` never runs there. The client's own bar runs on its `maxTime` and ends on the server's Done.
So two kinds of action:
- "computed": `getDuration` works the time out from the skill and `new` sets `maxTime = o:getDuration()`. Wrapping
  `getDuration` covers every side at once (client `new`, single player `new`, the server's `new` and its Java read),
  and never compounds because the wrapped function computes from scratch each call.
- "stored": `new` writes `maxTime` itself and `getDuration` returns `self.maxTime` (ISSplint, ISInstallVehiclePart,
  ISMedicalCheckAction through the base class). Then `getDuration` is wrapped on the server only and `create` on the
  client / single player only, so each side scales once.
Left alone: any value <= 1 (instant, "someone else is treating that part" 0, looped / negative), and every action of
a character with `isTimedActionInstant()` (or an extra per-action test, e.g. the mechanics cheat).
Each side uses its own copy of the mastery level (`M.less`); the server's time is the one that counts.
]]

require "TienSkillMastery"
local M = TienSkillMastery

M.Workshop = M.Workshop or {}
local W = M.Workshop

--- The duration `d` of `action` with a "less" bonus applied, or `d` unchanged when it must be left alone.
function W.scaledDuration(action, d, bonusId, extraSkip)
    if type(d) ~= "number" or d <= 1 then return d end
    local chr = action and action.character
    if not chr or chr:isTimedActionInstant() then return d end
    if extraSkip and extraSkip(action) then return d end
    local f = M.less(chr, bonusId)
    if f >= 1 then return d end
    return math.max(2, math.floor(d * f + 0.5))
end

local function adjusted(action, bonusId, extraSkip, d, ...)
    return W.scaledDuration(action, d, bonusId, extraSkip), ...
end

--- "computed" actions: getDuration works the time out and `new` stores it.
function W.wrapComputedDuration(class, bonusId, extraSkip)
    if not class or not class.getDuration then return end
    local orig = class.getDuration
    class.getDuration = function(self, ...)
        return adjusted(self, bonusId, extraSkip, orig(self, ...))
    end
end

--- "stored" actions: `new` writes maxTime, getDuration returns it.
function W.wrapStoredDuration(class, bonusId, extraSkip)
    if not class then return end
    if isServer() and class.getDuration then
        local orig = class.getDuration
        class.getDuration = function(self, ...)
            return adjusted(self, bonusId, extraSkip, orig(self, ...))
        end
    end
    local ownCreate = rawget(class, "create")
    class.create = function(self, ...)
        if not self.tsmTimeScaled then
            self.tsmTimeScaled = true
            self.maxTime = W.scaledDuration(self, self.maxTime, bonusId, extraSkip)
        end
        -- No own create: call the base class's at call time, so later wrappers of it still run.
        return (ownCreate or ISBaseTimedAction.create)(self, ...)
    end
end

--- Packs results so a wrapper can return all of them.
function W.pack(...)
    return { n = select("#", ...), ... }
end

function W.unpack(t)
    return unpack(t, 1, t.n)
end
