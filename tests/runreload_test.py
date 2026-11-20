"""Runs the real RunReload file against mocks: the RightHandMask set on a master reloading in the run or sprint state
and nowhere else, set again after the game clears it, cleared once the reload or the run ends (only when it is ours),
remote masters from the server's list, the server's list itself; then checks the generated maskingright nodes.

Breaks: noclear (the mask is never cleared), noremote (remote masters ignored), nostate (any action state)."""
import os
import re
import sys
from pathlib import Path

here = Path(__file__).resolve().parent
repo = here.parent
sys.path.insert(0, str(here / '.lupa'))
import lupa

src = (repo / 'Contents/mods/TienSkillMastery/42/media/lua/shared/TienSkillMastery_RunReload.lua') \
    .read_bytes().decode('utf-8').replace('\r\n', '\n')

m = sys.argv[1] if len(sys.argv) > 1 else ''
if m == 'noclear':
    src = src.replace('p:clearVariable("RightHandMask")', '')
if m == 'noremote':
    src = src.replace('return R.remote[p:getOnlineID()] == true', 'return false')
if m == 'nostate':
    src = src.replace('if not STATES[p:getCurrentActionContextStateName()] then return false end', '')

lua = lupa.LuaRuntime()
lua.globals().runreload_source = src
result = lua.execute(r'''
local out = {}
local now = 0
function require() end
function getTimestampMs() return now end

local function list(t)
    return { size = function() return #t end, get = function(_, i) return t[i + 1] end }
end

local function player(id, opts)
    opts = opts or {}
    local p = { id = id, master = opts.master, localPlayer = opts.localPlayer, state = "idle", vars = {} }
    function p.getOnlineID() return p.id end
    function p.isDead() return false end
    function p.isLocalPlayer() return p.localPlayer == true end
    function p.getCurrentActionContextStateName() return p.state end
    function p.getVariableBoolean(_, k) return p.vars[k] == "true" end
    function p.getVariableString(_, k) return p.vars[k] or "" end
    function p.setVariable(_, k, v) p.vars[k] = v end
    function p.clearVariable(_, k) p.vars[k] = nil end
    return p
end
local function reload(p, what)
    p.vars.IsPerformingAnAction = "true"
    p.vars.PerformingAction = what or "Reload"
end
local function stop(p)
    p.vars.IsPerformingAnAction = "false"
    p.vars.PerformingAction = nil
end

local sent = {}
function sendServerCommand(a, b, c, d)
    if type(a) == "string" then sent[#sent + 1] = { to = "all", command = b, args = c }
    else sent[#sent + 1] = { to = a, command = c, args = d } end
end
function sendClientCommand(_, _, command, args) sent[#sent + 1] = { to = "server", command = command, args = args } end

local online, locals = {}, {}
function getOnlinePlayers() return list(online) end
function getNumActivePlayers() return #locals end
function getSpecificPlayer(i) return locals[i + 1] end
function getPlayer() return locals[1] end
function getPlayerByOnlineID(id) for _, p in ipairs(online) do if p.id == id then return p end end end

local function load_side(which)
    local h = {}
    function isServer() return which == "server" end
    function isClient() return which == "client" end
    Events = {
        OnClientCommand = { Add = function(f) h.command = f end },
        OnServerCommand = { Add = function(f) h.serverCommand = f end },
        OnTick = { Add = function(f) h.tick = f end },
    }
    TienSkillMastery = { MODULE = "TSM" }
    TienSkillMastery.sig = function(p, id)
        assert(id == "Firearms.SigRunReload")
        if which == "client" and not p.localPlayer then return false end
        return p.master == true
    end
    assert(load(runreload_source))()
    return h
end
local function tick(h, ms) now = now + (ms or 100); h.tick() end
local MASK = "TsmRunReload"
local function masked(p) return p.vars.RightHandMask == MASK end

-- ---- Server: the list to everyone once, and to a client that asks; no mask work there.
local sm, sp = player(3, { master = true }), player(4)
online, locals = { sm, sp }, {}
local sv = load_side("server")
reload(sm); sm.state = "run"
tick(sv, 1000); tick(sv, 1000)
local n = 0
for _, s in ipairs(sent) do if s.to == "all" and s.command == "runReloadMasters" and s.args.list == "3" then n = n + 1 end end
out[#out + 1] = "serverBroadcastOnce=" .. n
sent = {}
sv.command("TSM", "runReloadMastersRequest", sp, {})
out[#out + 1] = "serverAnswers=" .. tostring(sent[1] and sent[1].to == sp and sent[1].args.list == "3")
out[#out + 1] = "serverSetsNoMask=" .. tostring(not masked(sm))

-- ---- Client: own master.
now, sent = 0, {}
local me = player(5, { localPlayer = true, master = true })
local them = player(3, { master = true })
local plain = player(7)
online, locals = { me, them, plain }, { me }
local cl = load_side("client")
tick(cl, 1000)
out[#out + 1] = "clientAsks=" .. tostring(sent[1] and sent[1].command == "runReloadMastersRequest")

reload(me)
me.state = "movement"
tick(cl)
out[#out + 1] = "walkingLeftToActions=" .. tostring(not masked(me))
me.state = "run"
tick(cl)
out[#out + 1] = "runningMasked=" .. tostring(masked(me))
me.vars.RightHandMask = nil      -- a hand model rebuild (ModelManager.update)
tick(cl)
out[#out + 1] = "setAgainAfterClear=" .. tostring(masked(me))
me.state = "sprint"
reload(me, "InsertBullets")
tick(cl)
out[#out + 1] = "sprintMagazineMasked=" .. tostring(masked(me))
me.state = "movement"
tick(cl)
out[#out + 1] = "clearedOnSlowing=" .. tostring(not masked(me))
me.state = "run"
tick(cl)
stop(me)
tick(cl)
out[#out + 1] = "clearedAfterReload=" .. tostring(not masked(me))
reload(me, "Eat")
tick(cl)
out[#out + 1] = "otherActionsLeft=" .. tostring(not masked(me))
-- Someone else's mask value is never cleared.
reload(me); tick(cl)
me.vars.RightHandMask = "holdingbagright"
stop(me); tick(cl)
out[#out + 1] = "otherMaskKept=" .. tostring(me.vars.RightHandMask == "holdingbagright")
me.vars.RightHandMask = nil

-- Not a master: nothing.
local notMaster = player(8, { localPlayer = true })
locals = { me, notMaster }
reload(notMaster); notMaster.state = "run"
tick(cl)
out[#out + 1] = "nonMasterLeft=" .. tostring(not masked(notMaster))
locals = { me }

-- ---- Client: remote masters from the server's list.
reload(them); them.state = "run"
reload(plain); plain.state = "run"
tick(cl)
out[#out + 1] = "remoteUnknownLeft=" .. tostring(not masked(them))
cl.serverCommand("TSM", "runReloadMasters", { list = "3" })
tick(cl)
out[#out + 1] = "remoteMasterMasked=" .. tostring(masked(them))
out[#out + 1] = "remotePlainLeft=" .. tostring(not masked(plain))
cl.serverCommand("TSM", "runReloadMasters", { list = "" })
tick(cl)
out[#out + 1] = "clearedWhenOffList=" .. tostring(not masked(them))
sent = {}
tick(cl, 4000)
out[#out + 1] = "stopsAskingOnceAnswered=" .. tostring(#sent == 0)

-- ---- Single player.
now, sent = 0, {}
local solo = player(0, { localPlayer = true, master = true })
online, locals = {}, { solo }
local sp1 = load_side("sp")
reload(solo); solo.state = "run"
tick(sp1)
out[#out + 1] = "singlePlayerMasked=" .. tostring(masked(solo))
out[#out + 1] = "singlePlayerSendsNothing=" .. tostring(#sent == 0)

return table.concat(out, "\n")
''')

# ---- The generated nodes: every file under maskingright/TsmRunReload carries the mask in each OR group, extends
# nothing and points its transitions only at other generated nodes.
gen = repo / 'Contents/mods/TienSkillMastery/42/media/AnimSets/player/maskingright/TsmRunReload'
files = [Path(d) / f for d, _, fs in os.walk(gen) for f in fs if f.endswith('.xml')]
names = set()
texts = []
for f in files:
    t = f.read_bytes().decode('utf-8')
    texts.append((f, t))
    names.add(re.search(r'<m_Name>(.*?)</m_Name>', t).group(1).lower())
gen_bad = []
for f, t in texts:
    # Conditions in file order (a resolved node can have some after its events), split at OR into groups.
    groups = [[]]
    for c in re.findall(r'<m_Conditions>(.*?)</m_Conditions>', t, re.S):
        if '<m_Type>OR</m_Type>' in c:
            groups.append([])
        else:
            groups[-1].append(c)
    if any(not any('<m_Value>TsmRunReload</m_Value>' in c for c in g) for g in groups):
        gen_bad.append('mask:' + f.name)
    if 'x_extends' in t or 'x_include' in t:
        gen_bad.append('extends:' + f.name)
    if not re.search(r'<m_Name>PerformingAction</m_Name>', t):
        gen_bad.append('action:' + f.name)
    for target in re.findall(r'<m_Target>(.*?)</m_Target>', t):
        if target.lower() not in names:
            gen_bad.append('target:%s->%s' % (f.name, target))
lines = result.split('\n')
lines.append('generatedNodes=%d' % len(files))
lines.append('generatedClean=%s' % ('true' if not gen_bad else 'false'))
print('\n'.join(lines))
if gen_bad:
    print('  ' + ', '.join(gen_bad[:10]))
bad = [l for l in lines if l.endswith('=false') or l.endswith('=0')]
if 'serverBroadcastOnce=1' not in lines:
    bad.append('serverBroadcastOnce!=1')
if len(files) < 200:
    bad.append('too few generated nodes (run scripts/make_run_reload.py)')
if bad:
    print('FAILED:', bad)
    sys.exit(1)
print('OK')
