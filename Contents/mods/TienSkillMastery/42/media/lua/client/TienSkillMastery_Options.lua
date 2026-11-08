--[[
Tien's Skill Mastery: the mod's own entries in Options > Mods (client only, saved per computer in ModOptions.ini).

- Throw outline colour (user, 2026-11-08): the colour of the outline on what a thrown axe or spear would reach
  (shared/TienSkillMastery_Throw.lua), default `M.OUTLINE_COLOR`. A `PZAPI.ModOptions` colour picker; its value is
  `{ r, g, b, a }`, read every frame by the outline. Saved values are read back by `PZAPI.ModOptions:load()`, which
  vanilla runs when it builds the options screen (main menu, and its own `OnGameStart` in game), so the saved colour
  is in use from then on. Names and tooltips are translation keys: `MainOptions:addModOptionsPanel` runs `getText`
  on them itself.
- Line length (user, 2026-11-08): how many characters a line of text may have in the Mastery tab and in the Skills
  tab's effect lists before it wraps at a word break, the rest indented (`M.wrapText`, `M.WRAP_INDENT`). In characters,
  not pixels, so it reads the same at any font size; a slider value (`getValue`) is a plain number, read each frame.
  The top of the slider is past the longest line in English, which is the same as no wrapping.
]]

if isServer() then return end

require "TienSkillMastery"
local M = TienSkillMastery

M.WRAP_DEFAULT = 80
M.WRAP_INDENT = 20   -- pixels, for the lines after the first

local lineLength = nil   -- the slider, when mod options exist
local wrapCache, wrapCacheLimit, wrapCacheSize = {}, nil, 0

--- Characters a line may have, as set in the mod options.
function M.wrapLimit()
    local v = lineLength and lineLength:getValue()
    return type(v) == "number" and v or M.WRAP_DEFAULT
end

--- A text as a list of lines of at most the limit, broken between words. A single word longer than the limit keeps its
--- own line. The gaps inside a line are kept. Called per line per frame while a list is open, so results are kept.
function M.wrapText(text)
    local limit = M.wrapLimit()
    if limit ~= wrapCacheLimit or wrapCacheSize > 300 then
        wrapCache, wrapCacheLimit, wrapCacheSize = {}, limit, 0
    end
    local cached = wrapCache[text]
    if cached then return cached end
    local lines, current = {}, nil
    for gap, word in string.gmatch(text, "(%s*)(%S+)") do
        if not current then
            current = word
        elseif #current + #gap + #word <= limit then
            current = current .. gap .. word
        else
            lines[#lines + 1] = current
            current = word
        end
    end
    lines[#lines + 1] = current or ""
    wrapCache[text] = lines
    wrapCacheSize = wrapCacheSize + 1
    return lines
end

if not (PZAPI and PZAPI.ModOptions) then return end

local options = PZAPI.ModOptions:create("TienSkillMastery", "UI_TienSkillMastery_Options")
lineLength = options:addSlider("lineLength", "UI_TienSkillMastery_Option_LineLength", 40, 300, 10, M.WRAP_DEFAULT,
    "UI_TienSkillMastery_Option_LineLength_tooltip")
local c = M.OUTLINE_COLOR
local throwOutline = options:addColorPicker("throwOutline", "UI_TienSkillMastery_Option_ThrowOutline",
    c.r, c.g, c.b, c.a, "UI_TienSkillMastery_Option_ThrowOutline_tooltip")

--- The colour of the throw's target outline, as set in the mod options.
function M.throwOutlineColor()
    local v = throwOutline:getValue()
    if type(v) == "table" and v.r and v.g and v.b then return v end
    return M.OUTLINE_COLOR
end
