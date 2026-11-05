--[[
Tien's Skill Mastery: First Aid medical check time (Doctor.TreatTime). The other treatments are in
shared/TienSkillMastery_WorkshopFirstAid.lua.

ISMedicalCheckAction (client/TimedActions/ISMedicalCheckAction.lua, 42.21) is a client-only action: it has no
`complete`, so `LuaTimedActionNew` runs it with `useCustomRemoteTimedActionSync` and nothing reaches the server; a
dedicated server does not even load the client folder. `new` ~80 sets `maxTime = 150 - 2.5 x Doctor` (~85; 1 with
Timed Action Instant) and `perform` opens the patient's health window. The time is scaled in `create` (client and
single player), before vanilla's `adjustMaxTime` (see shared/TienSkillMastery_Workshop.lua, "stored" actions).
]]

require "TienSkillMastery"
require "TienSkillMastery_Workshop"
local M = TienSkillMastery

M.Workshop.wrapStoredDuration(ISMedicalCheckAction, "Doctor.TreatTime")
