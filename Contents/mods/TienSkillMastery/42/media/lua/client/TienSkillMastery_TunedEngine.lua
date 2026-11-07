--[[
Tien's Skill Mastery: Engineering.TunedEngine ("pct", phase 3c): while a master drives, top speed and engine power
+15% at mastery 10 (driver's client, single player and multiplayer).

42.21 `CarController.update` / `control_ForwardNew`, `BaseVehicle`: the car's physics run on the driver's game
(`Bullet.controlVehicle` only when not the server), from that copy's `getEnginePower()` and `getMaxSpeed()`. Engine
force = power x (0.5 + rpm / 24000) x (1 - km/h / 200), faded to 0 from `maxSpeed` to `maxSpeed + 20` (Speed Demon's
x1.15 is the same kind of raise; they stack); the gears spread over `maxSpeed`, so raising it alone lengthens the
gears and weakens acceleration, hence the power raise with it. Out of reach: the hard cap (~122 km/h, Java) and in MP
the server option `SpeedLimit` (default 70 km/h), so on a default server only the acceleration shows above 70.

While a master sits in the driver's seat, `setMaxSpeed(vanilla x f)` (not saved: reset from the script at
`createPhysics`) and `setEngineFeature(quality, loudness, power x f)` + `updatePartStats()` (loudness is stored x0.37,
so vanilla's spawn loudness is passed and `updatePartStats` recomputes it from the muffler). The vanilla values are
remembered per vehicle and put back when the master leaves the seat. Engine power is saved and the server re-sends it
with the engine state, and engine overhaul raises it: a power or top speed that is not this file's own boosted value
is taken as the new vanilla value and boosted again. Single player saves the car from this copy, so the vanilla
values are put back before every save (`OnSave`) and re-applied on the next tick. Check in game: the vehicle
anti-cheat with the higher acceleration.
]]

if isServer() then return end

require "TienSkillMastery"
local M = TienSkillMastery

local tuned = {}   -- [vehicle] = { basePower, baseSpeed, power, speed }

local function loudness(vehicle)
    local script = vehicle:getScript()
    return ((script and script:getEngineLoudness()) or 100) * ((SandboxVars and SandboxVars.ZombieAttractionMultiplier) or 1)
end

local function setPower(vehicle, power)
    vehicle:setEngineFeature(vehicle:getEngineQuality(), loudness(vehicle), power)
    vehicle:updatePartStats()
end

local function restore(vehicle, t)
    if math.abs(vehicle:getEnginePower() - t.power) < 0.01 then setPower(vehicle, t.basePower) end
    if math.abs(vehicle:getMaxSpeed() - t.speed) < 0.01 then vehicle:setMaxSpeed(t.baseSpeed) end
end

local function apply(vehicle, f)
    local t = tuned[vehicle]
    local power, speed = vehicle:getEnginePower(), vehicle:getMaxSpeed()
    if not t then
        t = { basePower = power, baseSpeed = speed }
        tuned[vehicle] = t
    else
        if math.abs(power - t.power) >= 0.01 then t.basePower = power end
        if math.abs(speed - t.speed) >= 0.01 then t.baseSpeed = speed end
    end
    t.power, t.speed = t.basePower * f, t.baseSpeed * f
    if math.abs(power - t.power) >= 0.01 then setPower(vehicle, t.power) end
    if math.abs(speed - t.speed) >= 0.01 then vehicle:setMaxSpeed(t.speed) end
end

Events.OnTick.Add(function()
    local driving = {}
    for i = 0, getNumActivePlayers() - 1 do
        local p = getSpecificPlayer(i)
        local vehicle = p and p:getVehicle()
        if vehicle and vehicle:getDriver() == p then
            local f = M.more(p, "Engineering.TunedEngine")
            if f > 1 then
                driving[vehicle] = true
                local ok, err = pcall(apply, vehicle, f)
                if not ok then print("[TienSkillMastery] tuned engine failed: " .. tostring(err)) end
            end
        end
    end
    for vehicle, t in pairs(tuned) do
        if not driving[vehicle] then
            pcall(restore, vehicle, t)
            tuned[vehicle] = nil
        end
    end
end)

Events.OnSave.Add(function()
    for vehicle, t in pairs(tuned) do
        pcall(restore, vehicle, t)
        tuned[vehicle] = nil
    end
end)
