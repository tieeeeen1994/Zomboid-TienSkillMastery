--[[
Tien's Skill Mastery: registry of what each skill level gives in vanilla 42.21, shown when a skill is clicked in the
vanilla Skills tab (client/TienSkillMastery_SkillsTab.lua). Mastery is not listed there (it has its own tab).

Data files (`TienSkillMastery_SkillEffects<Group>.lua`, loading after this one) call `M.addSkillEffects(perkId, list)`.
Each entry:
- `name`: the label is the translation `IGUI_TienSkillMastery_Effect_<perkId>_<name>`.
- `value = function(level, player) return number end`: what the level gives; nil hides the line. `format` says how
  to print it: "pts" signed points ("+21"), "pct" signed percent ("+20%", "-15%"), "mult" a multiplier ("x1.20"),
  "chance" an unsigned percent ("45%"), "num" a signed plain number ("+3"), "plain" an unsigned number ("20").
- or `unlock = n`: a feature gained at level n (no value); shown as gained, or greyed with the level it needs.
- optional `note`: a translation key appended in brackets (e.g. "with a weapon of this skill").
Formulas follow the 42.21 jar and Lua (each data file's header cites them).
]]

require "TienSkillMastery"
local M = TienSkillMastery

M.SkillEffects = M.SkillEffects or {}

function M.addSkillEffects(perkId, list)
    M.SkillEffects[perkId] = M.SkillEffects[perkId] or {}
    for _, e in ipairs(list) do
        table.insert(M.SkillEffects[perkId], e)
    end
end

local function trim(n)
    local s = string.format("%.2f", n)
    s = s:gsub("0+$", "")
    s = s:gsub("%.$", "")
    if s == "-0" then s = "0" end
    return s
end

local function signed(n)
    local s = trim(n)
    if n > 0 then s = "+" .. s end
    return s
end

--- The printed value of an entry at `level`, or nil when the line is hidden.
function M.formatEffect(e, level, player)
    if e.unlock then return nil end
    local ok, v = pcall(e.value, level, player)
    if not ok or type(v) ~= "number" then return nil end
    if e.format == "pct" then return signed(v) .. "%" end
    if e.format == "mult" then return "x" .. string.format("%.2f", v) end
    if e.format == "chance" then return trim(v) .. "%" end
    if e.format == "plain" then return trim(v) end
    return signed(v)
end

--- Lines for a skill: { text, gained } in the registered order.
function M.skillEffectLines(perkId, level, player)
    local lines = {}
    for _, e in ipairs(M.SkillEffects[perkId] or {}) do
        local label = getText("IGUI_TienSkillMastery_Effect_" .. (e.labelPerk or perkId) .. "_" .. e.name)
        local note = e.note and (" (" .. getText(e.note) .. ")") or ""
        if e.unlock then
            local gained = level >= e.unlock
            local text = label .. note
            if not gained then
                text = text .. " (" .. getText("IGUI_TienSkillMastery_FromLevel", string.format("%d", e.unlock)) .. ")"
            end
            table.insert(lines, { text = text, gained = gained })
        else
            local shown = M.formatEffect(e, level, player)
            if shown then table.insert(lines, { text = label .. ": " .. shown .. note, gained = true }) end
        end
    end
    return lines
end
