--[[
Tien's Skill Mastery: sandbox changes made in game reach SandboxVars in single player too.

Every value of this mod is read live from `SandboxVars.TienSkillMastery` (shared/TienSkillMastery.lua). In
multiplayer the in-game sandbox window's Apply (`ISServerSandboxOptionsUI:onButtonApply`) sends the options to the
server, whose `GameServer.receiveSandboxOptions` (42.22) runs `load`, `applySettings`, `toLua` and relays them to every
client, where `GameClient.receiveSandboxOptions` runs the same three: `SandboxVars` is rebuilt on all sides.
In single player (the window opens from the debug menu) `settingsFromUI` only calls `getSandboxOptions():set(name,
value)` on the Java options, and nothing calls `toLua()`, so `SandboxVars` kept the old values until the world was
loaded again: the Mastery tab and every effect ignored the change (reported 2026-11-20: "the UI seems to refuse to
load new values"). After the window has written its values, this runs `toLua()` the way multiplayer does, which also
refreshes every other mod's and vanilla's `SandboxVars` (the Java side already had the new values; the save keeps
them through `map_sand.bin`). Not on a client: there the server's relay does it.
]]

if not ISServerSandboxOptionsUI or not ISServerSandboxOptionsUI.settingsFromUI then return end

local vanillaSettingsFromUI = ISServerSandboxOptionsUI.settingsFromUI

function ISServerSandboxOptionsUI:settingsFromUI(options, ...)
    local results = { vanillaSettingsFromUI(self, options, ...) }
    if not isClient() then
        local ok, err = pcall(function() getSandboxOptions():toLua() end)
        if not ok then print("[TienSkillMastery] sandbox refresh failed: " .. tostring(err)) end
    end
    return unpack(results)
end
