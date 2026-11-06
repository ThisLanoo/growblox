--[[
    Dylano Hub — Rework V0.1
    Source: deobfuscated dari dokumen asli
    Semua system original dipertahankan:
      · ByteNet Op8/Op3/Op32 packet system
      · getgc() inventory scan
      · dropList world-state collect
      · A* pathfinding in-world
      · VirtualInputManager movement
      · hookmetamethod PosHandler
    Runtime: KRNL / Synapse X / Fluxus / Delta / Hydrogen
]]

-- ══════════════════════════════════════════════════════════════
--  CLEANUP — stop semua instance lama sebelum jalan
-- ══════════════════════════════════════════════════════════════
pcall(function() getgenv().HubStop() end)
pcall(function() getgenv().FarmStop() end)
pcall(function() getgenv().DFStop() end)
pcall(function() getgenv().CWStop() end)
pcall(function() getgenv().DG:Destroy() end)
for _, name in ipairs({"Junnzxy","Dylano","JunnzxyFarm","DFGui","CWTestGui"}) do
    pcall(function() game:GetService("CoreGui")[name]:Destroy() end)
    pcall(function() gethui()[name]:Destroy() end)
    pcall(function() game:GetService("Players").LocalPlayer.PlayerGui[name]:Destroy() end)
end

-- ══════════════════════════════════════════════════════════════
--  SERVICES & LOCALS
-- ══════════════════════════════════════════════════════════════
local Players        = game:GetService("Players")
local RS             = game:GetService("ReplicatedStorage")
local TS             = game:GetService("TweenService")
local UIS            = game:GetService("UserInputService")
local VIM            = game:GetService("VirtualInputManager")
local lp             = Players.LocalPlayer

local HUB_NAME = "Dylano Hub"
local HUB_VER  = "0.1"

-- ══════════════════════════════════════════════════════════════
--  GLOBAL POSITION STATE (ByteNet Op8 hook)
-- ══════════════════════════════════════════════════════════════
getgenv().PP = getgenv().PP or {}
local PP     = getgenv().PP
PP.seen      = PP.seen or {}

local OP_POS = 8  -- ByteNet op yang bawa posisi karakter

getgenv().PosHandler = function(re, buf)
    if typeof(buf) ~= "buffer" then return end
    local len = buffer.len(buf)
    local op  = (len > 0) and buffer.readu8(buf, 0) or -1
    local key = re.Name.."|op"..op.."|len"..len
    PP.seen[key] = (PP.seen[key] or 0) + 1
    if op == OP_POS and len >= 9 then
        PP.y = buffer.readf32(buf, 1)
        PP.x = buffer.readf32(buf, 5)
    end
end

-- hook sekali
if not getgenv().PosHook2 then
    getgenv().PosHook2 = true
    pcall(function()
        local orig
        orig = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if typeof(self) == "Instance"
                and getnamecallmethod() == "FireServer"
                and not checkcaller()
                and string.find(self.Name, "ByteNet")
            then
                local buf = ...
                pcall(getgenv().PosHandler, self, buf)
            end
            return orig(self, ...)
        end))
    end)
end

local function diagStr()
    local t = {}
    for k, v in pairs(PP.seen) do t[#t+1] = k.." x"..v end
    table.sort(t)
    return #t == 0 and "Belum ada paket ByteNet." or table.concat(t, "\n")
end

-- ══════════════════════════════════════════════════════════════
--  BYTENET PACKET BUILDERS
-- ══════════════════════════════════════════════════════════════
-- Op3: MoveTo (posisi)
local function buildOp3(facing, x, y)
    local b = buffer.create(10)
    buffer.writeu8(b, 0, 3)
    buffer.writef32(b, 1, y)
    buffer.writeu8(b, 5, facing)
    buffer.writef32(b, 6, x)
    return b
end

-- Op32: TileAction (place/break)
local function buildOp32(tx, ty, id)
    local b = buffer.create(9)
    buffer.writeu8(b, 0, 32)
    buffer.writeu16(b, 1, ty)
    buffer.writeu16(b, 3, tx)
    buffer.writeu8(b, 5, 0)
    buffer.writeu16(b, 6, id)
    buffer.writeu8(b, 8, 1)
    return b
end

-- ══════════════════════════════════════════════════════════════
--  REMOTE FINDER
-- ══════════════════════════════════════════════════════════════
local moveToRE = nil
local function getRemotes()
    if not (moveToRE and moveToRE.Parent) then
        moveToRE = nil
        for _, v in ipairs(RS:GetDescendants()) do
            if v.Name == "MoveTo" and v:IsA("RemoteEvent") then
                moveToRE = v; break
            end
        end
    end
    return RS:FindFirstChild("ByteNetReliable"), moveToRE
end

-- ══════════════════════════════════════════════════════════════
--  POSITION HELPERS
-- ══════════════════════════════════════════════════════════════
local function tileCoord(x, y)
    return math.floor(x), math.floor(y - 0.001)
end

local function sendPos(x, y)
    local _, mt = getRemotes()
    if mt then pcall(firesignal, mt.OnClientEvent, x, y) end
    PP.x, PP.y = x, y
end

-- ══════════════════════════════════════════════════════════════
--  VIRTUAL INPUT MOVEMENT
-- ══════════════════════════════════════════════════════════════
local KA, KD = Enum.KeyCode.A, Enum.KeyCode.D
local KSP    = Enum.KeyCode.Space
local curKey = nil

local function vkey(kc, down)
    pcall(function() VIM:SendKeyEvent(down, kc, false, game) end)
end
local function stopMove()
    curKey = nil; vkey(KA, false); vkey(KD, false)
end
local function holdKey(k)
    if curKey ~= k then stopMove(); vkey(k, true); curKey = k end
end
local function jump()
    vkey(KSP, true); task.wait(0.12); vkey(KSP, false)
end

-- navigate to tile (x, y) with timeout
local function navTo(tx, ty, stopFn, timeout)
    timeout = timeout or 35
    stopMove()
    local t0     = os.clock()
    local lastX  = PP.x or 0
    local lastY  = PP.y or 0
    local lastMv = os.clock()

    while not (stopFn and stopFn()) and (os.clock() - t0) < timeout do
        if not (PP.x and PP.y) then task.wait(0.05); continue end
        local cx, cy = tileCoord(PP.x, PP.y)
        local dx = (tx + 0.5) - PP.x
        if cx == tx and cy == ty and math.abs(dx) < 0.28 then
            stopMove(); task.wait(0.08)
            local cx2, cy2 = tileCoord(PP.x, PP.y)
            if cx2 == tx and cy2 == ty then return true end
        end
        if math.abs(dx) > 0.12 then
            holdKey(dx > 0 and KD or KA)
        else
            stopMove()
        end
        if cy > ty and math.abs(dx) < 1.5 then jump() end
        task.wait(0.03)
        local moved = math.abs(PP.x - lastX) + math.abs(PP.y - lastY)
        if moved > 0.03 then
            lastX, lastY, lastMv = PP.x, PP.y, os.clock()
        elseif os.clock() - lastMv > 0.55 then
            jump(); lastMv = os.clock()
        end
    end
    stopMove()
    if not (PP.x and PP.y) then return false end
    local fx, fy = tileCoord(PP.x, PP.y)
    return fx == tx and fy == ty
end

-- lightweight position send (without full nav)
local function softMove(tx, ty, stopFn, dur, targets)
    stopMove()
    dur = dur or 0.18
    local bnRE = getRemotes()
    local t0, last = os.clock(), os.clock()
    while not (stopFn and stopFn()) and (os.clock() - t0) < dur do
        if targets and #targets > 0 then
            local allGone = true
            for _, t in ipairs(targets) do
                if not (t.pending or t.picked or t.from ~= nil) then
                    allGone = false; break
                end
            end
            if allGone then break end
        end
        if os.clock() - last >= 0.06 then
            last = os.clock()
            sendPos(tx + 0.5, ty + 0.999)
        end
        task.wait(0.03)
    end
end

-- stand still at tile
local function standAt(tx, ty, stopFn)
    stopMove()
    for _ = 1, 3 do
        if stopFn and stopFn() then break end
        sendPos(tx + 0.5, ty + 0.999)
        task.wait(0.06)
    end
end

-- ══════════════════════════════════════════════════════════════
--  INVENTORY (getgc scan) — same as source v80/v81/v82
-- ══════════════════════════════════════════════════════════════
local invCache, uiCache = nil, nil

local function findInv(force)
    if not force and invCache and type(rawget(invCache, "slots")) == "table" then
        return invCache, uiCache
    end
    invCache, uiCache = nil, nil
    if not getgc then return nil, nil end
    local ok, gc = pcall(getgc, true)
    if not ok or type(gc) ~= "table" then return nil, nil end
    for _, t in ipairs(gc) do
        if type(t) == "table" then
            if rawget(t, "capacity") and type(rawget(t, "slots")) == "table" then
                local slots = rawget(t, "slots")
                if rawget(t, "selected") ~= nil or rawget(slots, 1) ~= nil then
                    invCache = t
                end
            end
            if not uiCache
                and type(rawget(t, "refresh")) == "function"
                and rawget(t, "screen") ~= nil
            then
                uiCache = t
            end
        end
    end
    return invCache, uiCache
end

local function countItem(id, force)
    local inv = findInv(force)
    if not inv then return nil end
    local slots = rawget(inv, "slots")
    if type(slots) ~= "table" then return nil end
    local n = 0
    for _, slot in pairs(slots) do
        if type(slot) == "table" and tonumber(rawget(slot, "id")) == id then
            n = n + (tonumber(rawget(slot, "n")) or 0)
        end
    end
    return n
end

local function removeItem(id, amt)
    amt = tonumber(amt) or 1
    if amt <= 0 then return end
    pcall(function()
        local inv, ui = findInv(false)
        if not inv then inv, ui = findInv(true) end
        if not inv then return end
        local slots = rawget(inv, "slots")
        if type(slots) ~= "table" then return end
        local left = amt
        for k, slot in pairs(slots) do
            if type(slot) == "table" and tonumber(rawget(slot, "id")) == id then
                local have = tonumber(rawget(slot, "n")) or 0
                if have > left then rawset(slot, "n", have - left); left = 0; break
                else left = left - have; slots[k] = nil
                    if left <= 0 then break end
                end
            end
        end
        if ui and type(rawget(ui, "refresh")) == "function" then
            task.spawn(rawget(ui, "refresh"))
        end
    end)
end

-- ══════════════════════════════════════════════════════════════
--  WORLD STATE (getgc scan) — setTile, dropList, tileData
-- ══════════════════════════════════════════════════════════════
local setTileFn, dropListFn, tileData = nil, nil, nil

local function findWorldFns(force)
    if not force and setTileFn then return setTileFn end
    pcall(function()
        local wr = RS:FindFirstChild("WorldRemotes")
        local tc = wr and wr:FindFirstChild("TileChanged")
        if tc and getconnections then
            for _, c in ipairs(getconnections(tc.OnClientEvent)) do
                if c.Function then
                    local ok, ups = pcall(debug.getupvalues, c.Function)
                    if ok and type(ups) == "table" and type(ups[2]) == "function" then
                        setTileFn = ups[2]
                    end
                end
            end
        end
    end)
    if getgc then
        pcall(function()
            for _, v in ipairs(getgc(true)) do
                if type(v) == "function" then
                    local ok, src, name = pcall(function()
                        local s, _, n = debug.info(v, "sln"); return s, tostring(n or "")
                    end)
                    if ok and src and tostring(src):find("GameGui.Game") then
                        if name == "setTile" and not setTileFn then setTileFn = v
                        elseif name == "dropList" then dropListFn = v
                        elseif name == "hit" or name == "act" then
                            local ok2, ups = pcall(debug.getupvalues, v)
                            if ok2 and type(ups) == "table" then
                                for _, u in pairs(ups) do
                                    if type(u) == "table"
                                        and type(rawget(u, "fg")) == "table"
                                        and type(rawget(u, "w")) == "number"
                                    then tileData = u end
                                end
                            end
                        end
                    elseif type(v) == "table" then
                        if not tileData
                            and type(rawget(v, "fg")) == "table"
                            and type(rawget(v, "w")) == "number"
                        then tileData = v end
                    end
                end
            end
        end)
    end
    return setTileFn
end

local function getTileFG(tx, ty)
    if not tileData then return nil end
    local fg = rawget(tileData, "fg")
    local w  = rawget(tileData, "w")
    if type(fg) ~= "table" or type(w) ~= "number" or w <= 0 then return nil end
    local cell = fg[(ty * w) + tx + 1]
    if type(cell) == "number" then return cell end
    if type(cell) == "table" then return tonumber(rawget(cell, "id")) or 0 end
    return nil
end

local function setTileLocal(action, tx, ty, id, noRemove)
    local fn = findWorldFns(false) or findWorldFns(true)
    if fn then
        if noRemove ~= nil then pcall(fn, action, tx, ty, id, noRemove)
        else pcall(fn, action, tx, ty, id) end
        return true
    end
    return false
end

-- ══════════════════════════════════════════════════════════════
--  DROP LIST READER
-- ══════════════════════════════════════════════════════════════
local dropCache = nil

local function isDropGone(d)
    if rawget(d, "pending") or rawget(d, "picked") then return true end
    if rawget(d, "from") ~= nil then return true end
    local fr = rawget(d, "frame")
    if fr ~= nil and typeof(fr) == "Instance" and fr.Parent == nil then return true end
    return false
end

local function isDropEntry(t)
    if type(t) ~= "table" or isDropGone(t) then return false end
    local x = rawget(t,"x") or rawget(t,"X") or rawget(t,"px")
    local y = rawget(t,"y") or rawget(t,"Y") or rawget(t,"py")
    if type(x) == "number" and type(y) == "number"
        and x >= 0 and x <= 200 and y >= 0 and y <= 200
    then
        if rawget(t,"id") or rawget(t,"item") or rawget(t,"itemId")
            or rawget(t,"count") or rawget(t,"n") or rawget(t,"uid")
        then
            if not rawget(t,"capacity") and not rawget(t,"slots") and not rawget(t,"fg") then
                return true
            end
        end
    end
    local pos = rawget(t,"pos") or rawget(t,"position") or rawget(t,"p")
    local pt  = typeof(pos)
    if (pt == "Vector2" or pt == "Vector3")
        and pos.X >= 0 and pos.X <= 200 and pos.Y >= 0 and pos.Y <= 200
    then
        if rawget(t,"id") or rawget(t,"item") or rawget(t,"count") or rawget(t,"n") then
            return true
        end
    end
    return false
end

local function dropPos(d)
    local x = rawget(d,"x") or rawget(d,"X") or rawget(d,"px")
    local y = rawget(d,"y") or rawget(d,"Y") or rawget(d,"py")
    if type(x) == "number" and type(y) == "number" then return x, y end
    local pos = rawget(d,"pos") or rawget(d,"position") or rawget(d,"p")
    local pt  = typeof(pos)
    if pt == "Vector2" or pt == "Vector3" then return pos.X, pos.Y end
    return nil, nil
end

local function getDropsNear(cx, cy, radius)
    radius = radius or 4.5
    local out, seen = {}, {}
    local function scan(tbl)
        if type(tbl) ~= "table" then return end
        for _, v in pairs(tbl) do
            if type(v) == "table" and not seen[v] and isDropEntry(v) then
                local dx, dy = dropPos(v)
                if dx and dy
                    and math.abs(dx - (cx+0.5)) <= radius
                    and math.abs(dy - (cy+0.5)) <= radius
                then
                    seen[v] = true
                    out[#out+1] = {
                        raw=v, x=dx, y=dy,
                        cx=math.floor(dx),
                        cy=math.floor(dy - 0.001)
                    }
                end
            end
        end
    end
    findWorldFns(false)
    if dropListFn then
        local ok, res = pcall(dropListFn)
        if ok and type(res) == "table" then
            scan(res); if #out > 0 then return out end
            local ok2, ups = pcall(debug.getupvalues, dropListFn)
            if ok2 and type(ups) == "table" then
                for _, u in pairs(ups) do
                    if type(u) == "table" then scan(u) end
                end
            end
        end
    end
    if #out == 0 and dropCache then scan(dropCache) end
    if #out == 0 and getgc then
        local ok, gc = pcall(getgc, true)
        if ok then
            for _, v in ipairs(gc) do
                if type(v) == "table" then
                    local dl = rawget(v,"drops") or rawget(v,"dropList")
                    if type(dl) == "table" then
                        local before = #out
                        scan(dl)
                        if #out > before then dropCache = dl end
                    end
                end
            end
        end
    end
    return out
end

local function getAllDrops()
    findWorldFns(false)
    local wd = tileData and rawget(tileData, "state")
    local dl = wd and rawget(wd, "dropList")
    if type(dl) ~= "table" then return nil end
    local out = {}
    for _, v in pairs(dl) do
        if type(v) == "table" then
            local x, y = dropPos(v)
            if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 60 then
                out[#out+1] = {x=x, y=y}
            end
        end
    end
    return out
end

-- ══════════════════════════════════════════════════════════════
--  TILE SOLID CHECK & A* PATHFINDING
-- ══════════════════════════════════════════════════════════════
local itemDefs = nil
local function getItemDefs()
    if itemDefs then return itemDefs end
    if getgc then
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" then
                local t2 = rawget(v, 2)
                if type(t2) == "table" and rawget(t2,"name") and rawget(t2,"solid") then
                    itemDefs = v; break
                end
            end
        end
    end
    return itemDefs
end

local function isSolid(tx, ty)
    if not tileData then return true end
    local fg = getTileFG(tx, ty)
    if not fg then return false end
    if fg == 0 then return false end
    local defs = getItemDefs()
    if not defs then return true end
    local def = defs[fg]
    if not def then return true end
    return def.solid == true or def.hurts == true
end

local function astar(sx, sy, ex, ey)
    local function key(x, y) return y * 256 + x end
    local open    = {{sx, sy}}
    local parent  = {[key(sx,sy)] = false}
    local dirs    = {{1,0},{-1,0},{0,1},{0,-1}}
    local head    = 1
    while head <= #open and head < 6000 do
        local cur = open[head]; head = head + 1
        if cur[1] == ex and cur[2] == ey then
            local path, node = {}, cur
            while node do
                table.insert(path, 1, node)
                node = parent[key(node[1], node[2])]
            end
            return path
        end
        for _, d in ipairs(dirs) do
            local nx, ny = cur[1]+d[1], cur[2]+d[2]
            local k = key(nx, ny)
            if parent[k] == nil and not isSolid(nx, ny) then
                parent[k] = cur
                open[#open+1] = {nx, ny}
            end
        end
    end
    return nil
end

-- ══════════════════════════════════════════════════════════════
--  FARM ACTIONS (place / break tile)
-- ══════════════════════════════════════════════════════════════
local function placeTile(re, tx, ty, id, noRemove)
    if re then re:FireServer(buildOp32(tx, ty, id)) end
    task.wait(0.02)
    if re then re:FireServer(buildOp3(id, tx+0.5, ty+0.5)) end
    task.wait(0.025)
    setTileLocal("fg", tx, ty, id, true)
    if not noRemove then removeItem(id, 1) end
end

local function breakTile(re, tx, ty, hits, stopFn)
    hits = math.clamp(math.floor(hits or 3), 1, 15)
    for _ = 1, hits do
        if stopFn and stopFn() then return end
        if re then re:FireServer(buildOp3(6, tx+0.5, ty+0.483)) end
        task.wait(0.025)
        if re then re:FireServer(buildOp3(1, tx+0.551, ty+0.483)) end
        task.wait(0.165)
    end
    task.wait(0.08)
    setTileLocal("fg", tx, ty, 0)
    if re then re:FireServer(buildOp32(tx, ty, 0)) end
end

-- collect drops around tile
local function collectAround(cx, cy, delay, maxVerify, stopFn)
    delay     = math.clamp(delay or 0.16, 0.08, 1)
    maxVerify = math.clamp(maxVerify or 3, 1, 10)
    findWorldFns(false); task.wait(0.22)

    -- gather drops
    local drops = getDropsNear(cx, cy, 4.5)
    local byKey = {}
    for _, d in ipairs(drops) do
        local k = d.cx..","..d.cy
        if not byKey[k] then byKey[k] = {x=d.x,y=d.y,items={d.raw}}
        else table.insert(byKey[k].items, d.raw) end
    end

    for _, d in ipairs(drops) do
        if stopFn and stopFn() then break end
        local k  = d.cx..","..d.cy
        local bg = byKey[k]
        if bg then softMove(d.cx, d.cy, stopFn, delay, bg.items)
        else softMove(d.cx, d.cy, stopFn, delay) end
    end

    -- verify passes
    for pass = 1, maxVerify do
        if stopFn and stopFn() then break end
        task.wait(0.12)
        local remaining = getDropsNear(cx, cy, 4.5)
        if #remaining == 0 then break end
        for _, d in ipairs(remaining) do
            if stopFn and stopFn() then break end
            if not isDropGone(d.raw) then
                softMove(d.cx, d.cy, stopFn, delay, {d.raw})
            end
        end
    end

    if not (stopFn and stopFn()) then
        standAt(cx, cy, stopFn)
    end
end

-- ══════════════════════════════════════════════════════════════
--  UI HELPERS
-- ══════════════════════════════════════════════════════════════
local C3 = Color3.fromRGB
local COL = {
    bg    = C3(12,12,18),    panel  = C3(18,18,27),
    card  = C3(25,25,37),    card2  = C3(32,32,48),
    line  = C3(48,44,90),    acc    = C3(124,92,255),
    acc2  = C3(70,200,255),  wh     = C3(240,240,250),
    dm    = C3(140,140,168), ON     = C3(60,210,120),
    OFF   = C3(58,58,78),    RED    = C3(235,80,90),
    YEL   = C3(255,190,70),
}
local FONT = {b=Enum.Font.GothamBold, r=Enum.Font.Gotham, m=Enum.Font.GothamMedium}
local AL, AR = Enum.TextXAlignment.Left, Enum.TextXAlignment.Right
local conns = {}

local function new(cls, props, parent)
    local i = Instance.new(cls)
    pcall(function() i.BorderSizePixel = 0 end)
    for k, v in pairs(props) do pcall(function() i[k] = v end) end
    i.Parent = parent; return i
end
local function corner(r, p) pcall(function()
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,r); c.Parent = p
end) end
local function stroke(clr, th, p) pcall(function()
    local s = Instance.new("UIStroke"); s.Color = clr; s.Thickness = th or 1
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; s.Parent = p
end) end
local function gradient(clr1, clr2, rot, p) pcall(function()
    local g = Instance.new("UIGradient")
    g.Color = ColorSequence.new(clr1, clr2); g.Rotation = rot or 0; g.Parent = p
end) end
local function pad(p, t, l, r, b) new("UIPadding",{
    PaddingTop=UDim.new(0,t or 0), PaddingLeft=UDim.new(0,l or 0),
    PaddingRight=UDim.new(0,r or 0), PaddingBottom=UDim.new(0,b or 0)},p) end
local function tween(obj, dur, props, es, ed)
    local ok, tw = pcall(function()
        return TS:Create(obj, TweenInfo.new(dur,
            es or Enum.EasingStyle.Quad, ed or Enum.EasingDirection.Out), props)
    end)
    if ok and tw then tw:Play(); return tw end
end
local function hoverGlow(btn)
    local s = pcall(function()
        local st = Instance.new("UIStroke"); st.Color = COL.acc2
        st.Thickness = 1; st.Transparency = 1
        st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = btn
        btn.MouseEnter:Connect(function() tween(st, 0.15, {Transparency=0.25}) end)
        btn.MouseLeave:Connect(function() tween(st, 0.15, {Transparency=1}) end)
    end)
end

-- ══════════════════════════════════════════════════════════════
--  SCREEN GUI
-- ══════════════════════════════════════════════════════════════
local sg = new("ScreenGui", {
    Name="Dylano", ResetOnSpawn=false,
    DisplayOrder=999999, ZIndexBehavior=Enum.ZIndexBehavior.Sibling
}, nil)
local ok1 = pcall(function() sg.Parent = gethui() end)
if not ok1 or not sg.Parent then
    local ok2 = pcall(function() sg.Parent = game:GetService("CoreGui") end)
    if not ok2 or not sg.Parent then sg.Parent = lp:WaitForChild("PlayerGui") end
end
getgenv().DG = sg

-- viewport scale
local vp    = workspace.CurrentCamera.ViewportSize
local scale = math.clamp(math.min(vp.X/600, vp.Y/400), 0.6, 1)

-- main window
local win = new("Frame", {
    Size=UDim2.new(0,540,0,360), AnchorPoint=Vector2.new(0.5,0.5),
    Position=UDim2.new(0.5,0,0.5,0), BackgroundColor3=COL.bg, Active=true
}, sg)
corner(14, win); stroke(COL.line, 1.5, win)
local uiscale = new("UIScale", {Scale=scale}, win)

-- glassmorphism tint
win.BackgroundColor3 = Color3.fromRGB(255,255,255)
win.BackgroundTransparency = 0.2
gradient(C3(46,40,96), C3(12,12,24), 55, win)
local ws = win:FindFirstChildOfClass("UIStroke")
if ws then ws.Color = COL.wh; ws.Transparency = 0.72; ws.Thickness = 1.2 end

-- top bar
local tbar = new("Frame", {
    Size=UDim2.new(1,0,0,46), BackgroundColor3=COL.panel, Active=true
}, win)
corner(14, tbar)
new("Frame", {Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,1,-14),
    BackgroundColor3=COL.panel}, tbar)
-- gradient bar under title
local gbar = new("Frame", {Size=UDim2.new(1,0,0,2), Position=UDim2.new(0,0,0,46),
    BackgroundColor3=COL.wh}, win)
gradient(COL.acc, COL.acc2, 0, gbar)
-- logo D
local logo = new("TextLabel", {
    Size=UDim2.new(0,30,0,30), Position=UDim2.new(0,10,0.5,-15),
    BackgroundColor3=COL.wh, Text="D", TextColor3=COL.wh, TextSize=17, Font=FONT.b
}, tbar)
corner(9, logo); gradient(COL.acc, COL.acc2, 45, logo)
-- title
new("TextLabel", {Size=UDim2.new(0,160,0,18), Position=UDim2.new(0,48,0,7),
    BackgroundTransparency=1, Text=HUB_NAME, TextColor3=COL.wh,
    TextSize=15, Font=FONT.b, TextXAlignment=AL}, tbar)
new("TextLabel", {Size=UDim2.new(0,220,0,14), Position=UDim2.new(0,48,0,25),
    BackgroundTransparency=1, Text="Farm  •  Collect  •  Info",
    TextColor3=COL.dm, TextSize=10, Font=FONT.r, TextXAlignment=AL}, tbar)
-- version badge
local vbadge = new("TextLabel", {
    Size=UDim2.new(0,42,0,16), Position=UDim2.new(0,148,0,8),
    BackgroundColor3=COL.card2, Text="V"..HUB_VER,
    TextColor3=COL.acc2, TextSize=10, Font=FONT.b
}, tbar)
corner(8, vbadge)
-- minimize / close
local minBtn = new("TextButton", {
    Size=UDim2.new(0,28,0,26), Position=UDim2.new(1,-72,0.5,-13),
    AutoButtonColor=false, BackgroundColor3=COL.card, Text="–",
    TextColor3=COL.wh, TextSize=16, Font=FONT.b
}, tbar); corner(8, minBtn); hoverGlow(minBtn)
local closeBtn = new("TextButton", {
    Size=UDim2.new(0,28,0,26), Position=UDim2.new(1,-38,0.5,-13),
    AutoButtonColor=false, BackgroundColor3=COL.RED, Text="X",
    TextColor3=COL.wh, TextSize=13, Font=FONT.b
}, tbar); corner(8, closeBtn); hoverGlow(closeBtn)

-- drag
do
    local drag, ds, sp = false, nil, nil
    tbar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            drag, ds, sp = true, i.Position, win.Position
        end
    end)
    conns[#conns+1] = UIS.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then drag = false end
    end)
    conns[#conns+1] = UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            win.Position = UDim2.new(sp.X.Scale, sp.X.Offset+d.X, sp.Y.Scale, sp.Y.Offset+d.Y)
        end
    end)
end

-- sidebar
local sidebar = new("Frame", {
    Size=UDim2.new(0,136,1,-96), Position=UDim2.new(0,10,0,58),
    BackgroundColor3=COL.panel
}, win); corner(10, sidebar)

local navScroll = new("ScrollingFrame", {
    Size=UDim2.new(1,0,1,-54), BackgroundTransparency=1,
    ScrollBarThickness=2, ScrollBarImageColor3=COL.acc,
    CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y
}, sidebar)
new("UIListLayout", {Padding=UDim.new(0,3), SortOrder=Enum.SortOrder.LayoutOrder}, navScroll)
pad(navScroll, 6,6,6,6)

-- user card
local ucard = new("Frame", {
    Size=UDim2.new(1,-12,0,42), Position=UDim2.new(0,6,1,-48),
    BackgroundColor3=COL.card
}, sidebar); corner(8, ucard)
local uavatar = new("ImageLabel", {
    Size=UDim2.new(0,30,0,30), Position=UDim2.new(0,6,0.5,-15),
    BackgroundColor3=COL.bg, Image=""
}, ucard); corner(15, uavatar)
new("TextLabel", {
    Size=UDim2.new(1,-46,0,14), Position=UDim2.new(0,42,0,7),
    BackgroundTransparency=1, Text=lp.DisplayName, TextColor3=COL.wh,
    TextSize=11, Font=FONT.b, TextXAlignment=AL, TextTruncate=Enum.TextTruncate.AtEnd
}, ucard)
new("TextLabel", {
    Size=UDim2.new(1,-46,0,12), Position=UDim2.new(0,42,0,22),
    BackgroundTransparency=1, Text="@"..lp.Name, TextColor3=COL.dm,
    TextSize=9, Font=FONT.r, TextXAlignment=AL, TextTruncate=Enum.TextTruncate.AtEnd
}, ucard)
task.spawn(function()
    local ok, img = pcall(function()
        return Players:GetUserThumbnailAsync(lp.UserId,
            Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
    end)
    if ok and img then uavatar.Image = img end
end)

-- content area
local content = new("Frame", {
    Size=UDim2.new(1,-166,1,-96), Position=UDim2.new(0,156,0,58),
    BackgroundTransparency=1
}, win)
local pageTitle = new("TextLabel", {
    Size=UDim2.new(1,0,0,20), BackgroundTransparency=1,
    TextColor3=COL.wh, TextSize=17, Font=FONT.b, TextXAlignment=AL
}, content)
local pageSubt = new("TextLabel", {
    Size=UDim2.new(1,0,0,14), Position=UDim2.new(0,0,0,21),
    BackgroundTransparency=1, TextColor3=COL.dm, TextSize=11,
    Font=FONT.r, TextXAlignment=AL
}, content)
local pageHolder = new("Frame", {
    Size=UDim2.new(1,0,1,-42), Position=UDim2.new(0,0,0,42),
    BackgroundTransparency=1, ClipsDescendants=true
}, content)

-- status bar
local statBar = new("Frame", {
    Size=UDim2.new(1,-20,0,26), Position=UDim2.new(0,10,1,-32),
    BackgroundColor3=COL.panel
}, win); corner(8, statBar)
local statDot = new("Frame", {
    Size=UDim2.new(0,8,0,8), Position=UDim2.new(0,10,0.5,-4),
    BackgroundColor3=COL.ON
}, statBar); corner(4, statDot)
local statLbl = new("TextLabel", {
    Size=UDim2.new(1,-170,1,0), Position=UDim2.new(0,24,0,0),
    BackgroundTransparency=1, Text="Siap", TextColor3=COL.dm,
    TextSize=11, Font=FONT.m, TextXAlignment=AL, TextTruncate=Enum.TextTruncate.AtEnd
}, statBar)
new("TextLabel", {
    Size=UDim2.new(0,140,1,0), Position=UDim2.new(1,-150,0,0),
    BackgroundTransparency=1, Text="RightShift = sembunyikan",
    TextColor3=COL.OFF, TextSize=10, Font=FONT.r, TextXAlignment=AR
}, statBar)

local function setStatus(txt, clr)
    statLbl.Text = tostring(txt)
    statDot.BackgroundColor3 = clr or COL.ON
end

-- toast notifications
local toastFrame = new("Frame", {
    Size=UDim2.new(0,240,0,300), AnchorPoint=Vector2.new(1,1),
    Position=UDim2.new(1,-12,1,-12), BackgroundTransparency=1
}, sg)
new("UIListLayout", {
    Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder,
    VerticalAlignment=Enum.VerticalAlignment.Bottom
}, toastFrame)
local toastN = 0
local function toast(msg, clr)
    toastN = toastN + 1
    local wrap = new("Frame", {
        Size=UDim2.new(1,0,0,42), BackgroundTransparency=1, LayoutOrder=toastN
    }, toastFrame)
    local card = new("Frame", {
        Size=UDim2.new(1,0,1,0), Position=UDim2.new(1,30,0,0),
        BackgroundColor3=COL.panel
    }, wrap)
    corner(8, card); stroke(COL.line, 1, card)
    new("Frame", {
        Size=UDim2.new(0,3,1,-14), Position=UDim2.new(0,7,0,7),
        BackgroundColor3=clr or COL.acc
    }, card)
    new("TextLabel", {
        Size=UDim2.new(1,-26,1,0), Position=UDim2.new(0,18,0,0),
        BackgroundTransparency=1, Text=tostring(msg), TextColor3=COL.wh,
        TextSize=11, Font=FONT.m, TextWrapped=true, TextXAlignment=AL
    }, card)
    tween(card, 0.3, {Position=UDim2.new(0,0,0,0)}, Enum.EasingStyle.Back)
    task.delay(2.8, function()
        tween(card, 0.25, {Position=UDim2.new(1,30,0,0)})
        task.wait(0.3)
        pcall(function() wrap:Destroy() end)
    end)
end

-- ══════════════════════════════════════════════════════════════
--  TAB SYSTEM
-- ══════════════════════════════════════════════════════════════
local tabDef  = {}
local tabLO   = 0
local curPage = nil
local stopFns = {}

local function newLO() tabLO = tabLO + 1; return tabLO end

local function switchTo(name)
    if curPage == name then return end
    curPage = name
    for n, t in pairs(tabDef) do
        local active = n == name
        tween(t.btn, 0.18, {BackgroundTransparency=(active and 0.35) or 1})
        tween(t.ind, 0.18, {BackgroundTransparency=(active and 0) or 1})
        tween(t.lbl, 0.18, {TextColor3=(active and COL.wh) or COL.dm})
        t.page.Visible = active
        if active then
            pageTitle.Text = n
            pageSubt.Text  = t.desc or ""
            t.page.Position = UDim2.new(0,14,0,0)
            tween(t.page, 0.22, {Position=UDim2.new(0,0,0,0)})
        end
    end
end

local function addTab(name, icon, desc)
    local btn = new("TextButton", {
        Size=UDim2.new(1,0,0,26), BackgroundColor3=COL.card,
        BackgroundTransparency=1, Text="", AutoButtonColor=false,
        LayoutOrder=newLO()
    }, navScroll); corner(7, btn)
    local ind = new("Frame", {
        Size=UDim2.new(0,3,0,14), Position=UDim2.new(0,0,0.5,-7),
        BackgroundColor3=COL.acc, BackgroundTransparency=1
    }, btn); corner(2, ind)
    new("TextLabel", {
        Size=UDim2.new(0,22,1,0), Position=UDim2.new(0,8,0,0),
        BackgroundTransparency=1, Text=icon, TextSize=13, TextColor3=COL.wh, Font=FONT.b
    }, btn)
    local lbl = new("TextLabel", {
        Size=UDim2.new(1,-36,1,0), Position=UDim2.new(0,32,0,0),
        BackgroundTransparency=1, Text=name, TextColor3=COL.dm, TextSize=11, Font=FONT.b, TextXAlignment=AL
    }, btn)
    local page = new("ScrollingFrame", {
        Size=UDim2.new(1,0,1,0), BackgroundTransparency=1,
        ScrollBarThickness=3, ScrollBarImageColor3=COL.acc,
        CanvasSize=UDim2.new(0,0,0,0), AutomaticCanvasSize=Enum.AutomaticSize.Y,
        Visible=false
    }, pageHolder)
    new("UIListLayout", {Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder}, page)
    pad(page, 2,0,8,8)
    tabDef[name] = {btn=btn, ind=ind, lbl=lbl, page=page, desc=desc}
    btn.Activated:Connect(function() switchTo(name) end)
    return page
end

-- ── UI component helpers ──────────────────────────────────────
local function sectionHead(page, txt)
    new("TextLabel", {
        Size=UDim2.new(1,0,0,22), BackgroundTransparency=1,
        Text=string.upper(txt), TextColor3=COL.acc2, TextSize=10,
        Font=FONT.b, TextXAlignment=AL, TextYAlignment=Enum.TextYAlignment.Bottom,
        LayoutOrder=newLO()
    }, page)
end

local function makeToggle(page, label, initial, onChange)
    local row = new("Frame", {
        Size=UDim2.new(1,0,0,36), BackgroundColor3=COL.card, LayoutOrder=newLO()
    }, page); corner(8, row)
    new("TextLabel", {
        Size=UDim2.new(1,-66,1,0), Position=UDim2.new(0,12,0,0),
        BackgroundTransparency=1, Text=label, TextColor3=COL.wh,
        TextSize=12, Font=FONT.r, TextXAlignment=AL, TextTruncate=Enum.TextTruncate.AtEnd
    }, row)
    local track = new("Frame", {
        Size=UDim2.new(0,40,0,20), Position=UDim2.new(1,-52,0.5,-10),
        BackgroundColor3=(initial and COL.ON) or COL.OFF
    }, row); corner(10, track)
    local thumb = new("Frame", {
        Size=UDim2.new(0,16,0,16),
        Position=UDim2.new(0,(initial and 22) or 2, 0.5,-8),
        BackgroundColor3=COL.wh
    }, track); corner(8, thumb)
    local hitbox = new("TextButton", {
        Size=UDim2.new(1,0,1,0), BackgroundTransparency=1, Text=""
    }, row); corner(8, hitbox); hoverGlow(hitbox)
    local state = {v = initial == true}
    local function refresh(s, silent)
        state.v = s
        tween(track, 0.18, {BackgroundColor3=(s and COL.ON) or COL.OFF})
        tween(thumb, 0.18, {Position=UDim2.new(0,(s and 22) or 2, 0.5,-8)})
        if onChange and not silent then task.spawn(onChange, s) end
    end
    hitbox.Activated:Connect(function() refresh(not state.v) end)
    return {get=function() return state.v end, set=function(s,si) refresh(s,si) end}
end

local function makeInput(page, label, default, half)
    local row = new("Frame", {
        Size=half and UDim2.new(0.5,-3,1,0) or UDim2.new(1,0,1,0),
        BackgroundColor3=COL.card
    }, page); corner(8, row)
    new("TextLabel", {
        Size=UDim2.new(1,-16,0,14), Position=UDim2.new(0,8,0,5),
        BackgroundTransparency=1, Text=label, TextColor3=COL.dm,
        TextSize=10, Font=FONT.m, TextXAlignment=AL, TextTruncate=Enum.TextTruncate.AtEnd
    }, row)
    local box = new("TextBox", {
        Size=UDim2.new(1,-16,0,22), Position=UDim2.new(0,8,0,21),
        BackgroundColor3=COL.bg, Text=tostring(default), TextColor3=COL.wh,
        TextSize=12, Font=FONT.b, ClearTextOnFocus=false
    }, row); corner(6, box)
    local st = stroke(COL.line, 1, box)
    if st then
        box.Focused:Connect(function() tween(st, 0.15, {Color=COL.acc}) end)
        box.FocusLost:Connect(function() tween(st, 0.15, {Color=COL.line}) end)
    end
    return box
end

local function makeInputRow(page, l1, d1, l2, d2)
    local wrap = new("Frame", {
        Size=UDim2.new(1,0,0,50), BackgroundTransparency=1, LayoutOrder=newLO()
    }, page)
    new("UIListLayout", {
        FillDirection=Enum.FillDirection.Horizontal,
        Padding=UDim.new(0,6), SortOrder=Enum.SortOrder.LayoutOrder
    }, wrap)
    local b1 = makeInput(wrap, l1, d1, l2 ~= nil)
    local b2 = l2 and makeInput(wrap, l2, d2, true) or nil
    return b1, b2
end

local function makeButton(page, label, onClick, clr)
    local btn = new("TextButton", {
        Size=UDim2.new(1,0,0,34), BackgroundColor3=clr or COL.acc,
        Text=label, AutoButtonColor=false, TextColor3=COL.wh,
        TextSize=12, Font=FONT.b, LayoutOrder=newLO()
    }, page); corner(8, btn); hoverGlow(btn)
    btn.Activated:Connect(function()
        tween(btn, 0.08, {TextTransparency=0.4})
        task.delay(0.1, function() tween(btn, 0.12, {TextTransparency=0}) end)
        onClick()
    end)
    return btn
end

local function makeNote(page, txt)
    new("TextLabel", {
        Size=UDim2.new(1,0,0,0), AutomaticSize=Enum.AutomaticSize.Y,
        BackgroundTransparency=1, Text=txt, TextColor3=COL.dm, TextSize=10,
        Font=FONT.r, TextWrapped=true, TextXAlignment=AL,
        TextYAlignment=Enum.TextYAlignment.Top, LayoutOrder=newLO()
    }, page)
end

-- ══════════════════════════════════════════════════════════════
--  TAB: FARM
-- ══════════════════════════════════════════════════════════════
do
    local pg = addTab("Farm", "🌱", "Farm 5x5 (Fixed)  •  Op32 & Op3  •  Auto Refill")

    -- position indicator
    local posRow = new("Frame", {
        Size=UDim2.new(1,0,0,26), BackgroundColor3=COL.card, LayoutOrder=newLO()
    }, pg); corner(8, posRow)
    local posLbl = new("TextLabel", {
        Size=UDim2.new(1,-16,1,0), Position=UDim2.new(0,8,0,0),
        BackgroundTransparency=1, Text="Posisi: belum terbaca (gerakkan karakter)",
        TextColor3=COL.YEL, TextSize=11, Font=FONT.b, TextXAlignment=AL
    }, posRow)
    task.spawn(function()
        while sg.Parent do
            if PP.x and PP.y then
                local tx, ty = tileCoord(PP.x, PP.y)
                posLbl.Text = string.format("Posisi: x=%.2f y=%.2f | sel (%d, %d)", PP.x, PP.y, tx, ty)
                posLbl.TextColor3 = COL.ON
            else
                posLbl.Text = "Posisi: belum terbaca (gerakkan karakter)"
                posLbl.TextColor3 = COL.YEL
            end
            task.wait(0.25)
        end
    end)

    -- 5x5 tile selector
    sectionHead(pg, "Selector Area 5x5 (Klik untuk Pilih)")
    local selectorCard = new("Frame", {
        Size=UDim2.new(1,0,0,268), BackgroundColor3=COL.card, LayoutOrder=newLO()
    }, pg); corner(10, selectorCard)
    local selCountLbl = new("TextLabel", {
        Size=UDim2.new(1,-20,0,20), Position=UDim2.new(0,10,0,6),
        BackgroundTransparency=1, Text="Terpilih: 0 tile (ME = tengah)",
        TextColor3=COL.acc2, TextSize=11, Font=FONT.b,
        TextXAlignment=Enum.TextXAlignment.Center
    }, selectorCard)
    local grid = new("Frame", {
        Size=UDim2.new(0,200,0,200), Position=UDim2.new(0.5,-100,0,30),
        BackgroundTransparency=1
    }, selectorCard)

    -- selected tiles: list of slot indices, map of selected bools, cell defs
    local selList, selMap, cellDefs = {}, {}, {}

    local function refreshGrid()
        for idx, cell in ipairs(cellDefs) do
            if selMap[idx] then
                cell.btn.BackgroundColor3 = COL.acc; cell.btn.TextColor3 = COL.wh
            elseif idx == 13 then
                cell.btn.BackgroundColor3 = COL.card2; cell.btn.TextColor3 = COL.YEL
            else
                cell.btn.BackgroundColor3 = COL.bg; cell.btn.TextColor3 = COL.dm
            end
        end
        selCountLbl.Text = string.format("Terpilih: %d tile (ME = tengah)", #selList)
    end

    for row = 0, 4 do
        for col = 0, 4 do
            local idx = row * 5 + col + 1
            local dx, dy = col - 2, row - 2
            local isMe = idx == 13
            local btn = new("TextButton", {
                Size=UDim2.new(0,36,0,36),
                Position=UDim2.new(0, col*41, 0, row*41),
                BackgroundColor3=COL.bg,
                Text=isMe and "ME" or tostring(idx),
                TextColor3=isMe and COL.YEL or COL.dm,
                TextSize=11, Font=FONT.b, AutoButtonColor=false
            }, grid); corner(6, btn); stroke(COL.line, 1, btn)
            cellDefs[idx] = {btn=btn, dx=dx, dy=dy}
            local i2 = idx
            btn.Activated:Connect(function()
                if selMap[i2] then
                    selMap[i2] = nil
                    for j, v in ipairs(selList) do
                        if v == i2 then table.remove(selList, j); break end
                    end
                else
                    selMap[i2] = true; selList[#selList+1] = i2
                end
                refreshGrid()
            end)
        end
    end
    refreshGrid()

    -- quick select buttons
    local qs1 = new("TextButton", {Size=UDim2.new(0,96,0,24), Position=UDim2.new(0.5,-150,0,236),
        BackgroundColor3=COL.card2, Text="Atas 3 (2,3,4)", TextColor3=COL.wh,
        TextSize=10, Font=FONT.b, AutoButtonColor=false}, selectorCard)
    corner(6,qs1); hoverGlow(qs1)
    local qs2 = new("TextButton", {Size=UDim2.new(0,96,0,24), Position=UDim2.new(0.5,-48,0,236),
        BackgroundColor3=COL.card2, Text="Pilih Semua", TextColor3=COL.wh,
        TextSize=10, Font=FONT.b, AutoButtonColor=false}, selectorCard)
    corner(6,qs2); hoverGlow(qs2)
    local qs3 = new("TextButton", {Size=UDim2.new(0,96,0,24), Position=UDim2.new(0.5,54,0,236),
        BackgroundColor3=COL.card2, Text="Reset Pilihan", TextColor3=COL.wh,
        TextSize=10, Font=FONT.b, AutoButtonColor=false}, selectorCard)
    corner(6,qs3); hoverGlow(qs3)
    qs1.Activated:Connect(function()
        selList={2,3,4}; selMap={[2]=true,[3]=true,[4]=true}; refreshGrid()
    end)
    qs2.Activated:Connect(function()
        selList,selMap={},{}
        for i=1,25 do if i~=13 then selMap[i]=true; selList[#selList+1]=i end end
        refreshGrid()
    end)
    qs3.Activated:Connect(function() selList,selMap={},{}; refreshGrid() end)

    -- settings
    sectionHead(pg, "Pengaturan Block & Pukulan")
    local inpID, inpHits   = makeInputRow(pg, "ID Block Pasang", 2, "Hit Break (1-15)", 3)
    sectionHead(pg, "Auto Ambil Block (Saat Stok Habis)")
    local inpAX, inpAY     = makeInputRow(pg, "Ambil Block X", 50, "Ambil Block Y", 37)
    local inpMin, inpWait  = makeInputRow(pg, "Ambil jika Block <", 20, "Tunggu Ambil (dtk)", 3)
    sectionHead(pg, "Pengaturan Auto Collect")
    local inpDelay, inpVer = makeInputRow(pg, "Jeda Collect/Titik (dtk)", 0.16, "Maks Verifikasi Sisa", 3)
    local togCollect       = makeToggle(pg, "Auto Collect Setelah Break", false)

    makeButton(pg, "Diagnostik Posisi (paket ByteNet)", function()
        local s = diagStr().."\nP.x="..tostring(PP.x).."  P.y="..tostring(PP.y)
        print(s); setStatus(s, COL.YEL); toast("Diagnostik dicetak ke console (F9)", COL.YEL)
    end, COL.card2)

    -- farm loop
    sectionHead(pg, "Kontrol Farm")
    local farmRun, farmGen = false, 0
    local farmCycle = 0
    local togFarm

    togFarm = makeToggle(pg, "Auto Pasang & Break", false, function(on)
        farmRun = on; farmGen = farmGen + 1
        local gen = farmGen
        if not on then stopMove(); setStatus("Farm berhenti", COL.YEL); return end
        if #selList == 0 then
            setStatus("Pilih minimal 1 tile!", COL.RED)
            toast("Farm: pilih minimal 1 tile!", COL.RED)
            farmRun = false; togFarm.set(false, true); return
        end
        if not (PP.x and PP.y) then
            setStatus("Posisi belum terbaca. Gerakkan karakter!", COL.RED)
            toast("Farm: gerakkan karakter sedikit dulu!", COL.RED)
            print(diagStr())
            farmRun = false; togFarm.set(false, true); return
        end
        local bnRE = getRemotes()
        if not bnRE then
            setStatus("ByteNetReliable tidak ketemu", COL.RED)
            toast("Farm: ByteNetReliable tidak ketemu", COL.RED)
            farmRun = false; togFarm.set(false, true); return
        end
        findWorldFns(true)
        local mx, my = tileCoord(PP.x, PP.y)
        setStatus(string.format("Farm dimulai | ME=(%d, %d)", mx, my), COL.ON)
        toast(string.format("Farm dimulai | ME=(%d, %d)", mx, my), COL.ON)
        local function stop() return not farmRun or gen ~= farmGen or not sg.Parent end

        task.spawn(function()
            while farmRun and gen == farmGen and sg.Parent do
                local id    = tonumber(inpID.Text) or 2
                local hits  = math.clamp(math.floor(tonumber(inpHits.Text) or 3), 1, 15)
                local ax    = math.floor(tonumber(inpAX.Text) or 50)
                local ay    = math.floor(tonumber(inpAY.Text) or 37)
                local minSt = math.max(math.floor(tonumber(inpMin.Text) or 20), 1)
                local waitT = math.max(tonumber(inpWait.Text) or 3, 0.5)
                local delay = math.clamp(tonumber(inpDelay.Text) or 0.16, 0.08, 1)
                local maxV  = math.clamp(math.floor(tonumber(inpVer.Text) or 3), 1, 10)

                -- refill check
                local stok = countItem(id, true)
                if stok ~= nil and stok < minSt then
                    setStatus(string.format("Stok ID %d sisa %d < %d → ambil ke (%d,%d)...", id,stok,minSt,ax,ay), COL.YEL)
                    if navTo(ax, ay, stop, 45) then
                        local t0 = os.clock()
                        while not stop() and ((os.clock()-t0 < waitT) or ((countItem(id,true) or 0) < minSt)) do
                            if os.clock()-t0 > math.max(waitT+6,10) then break end
                            task.wait(0.25)
                        end
                    end
                    if stop() then break end
                    setStatus(string.format("Selesai ambil (stok:%s) → balik ke ME (%d,%d)...",
                        tostring(countItem(id,true) or "?"), mx, my), COL.ON)
                    navTo(mx, my, stop, 45)
                    standAt(mx, my, stop)
                end

                -- ensure at ME
                local cx, cy = tileCoord(PP.x or 0, PP.y or 0)
                if cx ~= mx or cy ~= my then standAt(mx, my, stop)
                else sendPos(mx+0.5, my+0.999); task.wait(0.06) end
                if stop() then break end

                -- place phase
                for _, slot in ipairs(selList) do
                    if stop() then break end
                    local cell = cellDefs[slot]
                    local tx, ty = mx+cell.dx, my+cell.dy
                    setStatus(string.format("Pasang Tile #%d di (%d,%d)", slot, tx, ty), COL.ON)
                    placeTile(bnRE, tx, ty, id, false)
                    task.wait(0.175)
                end
                task.wait(0.1)

                -- retry place
                for _, slot in ipairs(selList) do
                    if stop() then break end
                    local cell = cellDefs[slot]
                    local tx, ty = mx+cell.dx, my+cell.dy
                    local fg = getTileFG(tx, ty)
                    if fg ~= nil and fg ~= id then
                        setStatus(string.format("Retry Pasang #%d di (%d,%d)", slot, tx, ty), COL.ON)
                        placeTile(bnRE, tx, ty, id, true)
                        task.wait(0.16)
                    end
                end
                task.wait(0.24)

                -- break phase
                local broken = {}
                for _, slot in ipairs(selList) do
                    if stop() then break end
                    local cell = cellDefs[slot]
                    local tx, ty = mx+cell.dx, my+cell.dy
                    broken[#broken+1] = {x=tx, y=ty, num=slot}
                    setStatus(string.format("Break Tile #%d di (%d,%d) [%d hit]...", slot, tx, ty, hits), COL.ON)
                    breakTile(bnRE, tx, ty, hits, stop)
                    task.wait(0.08)
                end

                -- collect
                if togCollect.get() and not stop() then
                    collectAround(mx, my, delay, maxV, stop)
                end

                farmCycle = farmCycle + 1
                setStatus(string.format("Farm berjalan | Siklus #%d | Stok ID %d: %s",
                    farmCycle, id, tostring(countItem(id,true) or "?")), COL.ON)
                task.wait(0.15)
            end
            stopMove()
        end)
    end)

    makeNote(pg, "Gerakkan karakter, pastikan indikator Posisi berwarna hijau, lalu pilih tile & nyalakan toggle Auto Pasang & Break.")
    stopFns[#stopFns+1] = function()
        farmRun = false; farmGen = farmGen + 1; stopMove(); togFarm.set(false, true)
    end
end

-- ══════════════════════════════════════════════════════════════
--  TAB: COLLECT
-- ══════════════════════════════════════════════════════════════
do
    local pg = addTab("Collect", "🧲", "Kejar item drop terdekat  •  v2")
    sectionHead(pg, "Auto Collect")
    local statTxt = new("TextLabel", {
        Size=UDim2.new(1,0,0,56), BackgroundColor3=COL.card, LayoutOrder=newLO(),
        Text="Belum berjalan.", TextColor3=COL.dm, TextSize=11,
        Font=FONT.r, TextWrapped=true, TextXAlignment=AL, TextYAlignment=Enum.TextYAlignment.Top
    }, pg); corner(8, statTxt); pad(statTxt, 6,8,8,6)

    -- BFS pathfinding for collect
    local function colIsSolid(tx, ty)
        if not tileData then return false end
        local fg = getTileFG(tx, ty)
        if not fg or fg == 0 then return false end
        local defs = getItemDefs()
        if not defs then return false end
        local def = defs[fg]
        return def and (def.solid == true or def.hurts == true) or false
    end

    local function colAStar(sx, sy, ex, ey)
        local function key(x,y) return y*256+x end
        local open = {{sx,sy}}
        local head = 1
        local parent={[key(sx,sy)]=false}
        local dirs={{1,0},{-1,0},{0,1},{0,-1}}
        while head<=#open and head<6000 do
            local cur=open[head]; head=head+1
            if cur[1]==ex and cur[2]==ey then
                local path,node={},cur
                while node do table.insert(path,1,node); node=parent[key(node[1],node[2])] end
                return path
            end
            for _,d in ipairs(dirs) do
                local nx,ny=cur[1]+d[1],cur[2]+d[2]
                local k=key(nx,ny)
                if parent[k]==nil and not colIsSolid(nx,ny) then
                    parent[k]=cur; open[#open+1]={nx,ny}
                end
            end
        end
    end

    -- screen-based fallback
    local dropFrameParent = nil
    local lastFP = 0
    local function findDropFrames()
        if not (dropFrameParent and dropFrameParent.Parent) then
            dropFrameParent = nil
            if os.clock() - lastFP > 1 then
                lastFP = os.clock()
                for _, v in ipairs(lp.PlayerGui:GetDescendants()) do
                    if v.Name == "Drop" and v:IsA("GuiObject") then
                        dropFrameParent = v.Parent; break
                    end
                end
            end
        end
        local frames = {}
        if dropFrameParent then
            for _, v in ipairs(dropFrameParent:GetChildren()) do
                if v.Name == "Drop" and v:IsA("GuiObject") then frames[#frames+1] = v end
            end
        end
        return frames
    end

    local colRun, colGen = false, 0
    local skipList = {}
    local lastMx, lastMy, lastMvT, stuckCt = 0, 0, 0, 0
    local function colStuck(key)
        if not (PP.x and PP.y) then return end
        if math.abs(PP.x-lastMx)+math.abs(PP.y-lastMy) < 0.03 then
            if os.clock()-lastMvT > 0.8 then
                vkey(KSP,true); task.wait(0.12); vkey(KSP,false)
                stuckCt = stuckCt + 1; lastMvT = os.clock()
                if stuckCt >= 4 then
                    stopMove(); if key then skipList[key] = os.clock()+10 end
                    stuckCt = 0
                end
            end
        else
            lastMx,lastMy,lastMvT,stuckCt = PP.x,PP.y,os.clock(),0
        end
    end

    local togCol
    togCol = makeToggle(pg, "Auto Collect", false, function(on)
        colRun = on; colGen = colGen + 1
        local gen = colGen
        if not on then stopMove(); statTxt.Text="Berhenti."; setStatus("Collect berhenti", COL.YEL); return end
        skipList, stuckCt = {}, 0
        task.spawn(function()
            while colRun and gen == colGen and sg.Parent do
                local drops = getAllDrops()
                local best, bestD = nil, math.huge
                if drops then
                    for _, d in ipairs(drops) do
                        local k = math.floor(d.x)..","..math.floor(d.y)
                        if not (skipList[k] and skipList[k] > os.clock()) then
                            if PP.x and PP.y then
                                local dd = math.abs(d.x-PP.x)+math.abs(d.y-PP.y)
                                if dd < bestD then best, bestD = d, dd end
                            end
                        end
                    end
                end
                if best then
                    local k = math.floor(best.x)..","..math.floor(best.y)
                    local dx, dy = best.x-(PP.x or 0), best.y-(PP.y or 0)
                    if math.abs(dx) < 0.45 and math.abs(dy) < 1.3 then
                        stopMove(); skipList[k] = os.clock()+2
                        statTxt.Text = string.format("Sampai di drop (%.1f, %.1f)", best.x, best.y)
                        task.wait(0.25)
                    else
                        local cx,cy = tileCoord(PP.x or 0, PP.y or 0)
                        local tx,ty = math.floor(best.x), math.floor(best.y)
                        if colIsSolid(tx,ty) then ty=ty-1 end
                        local path = colAStar(cx,cy,tx,ty)
                        if path and #path >= 2 then
                            local nx,ny = path[2][1],path[2][2]
                            if ny == cy then holdKey(nx > cx and KD or KA)
                            elseif ny < cy then stopMove(); jump(); task.wait(0.3)
                            else stopMove() end
                        else
                            stopMove(); skipList[k] = os.clock()+10
                        end
                        colStuck(k)
                        statTxt.Text = string.format("Kejar drop (%.1f,%.1f) | bot (%.1f,%.1f)",
                            best.x,best.y,PP.x or 0,PP.y or 0)
                        setStatus("Collect: mengejar item", COL.ON)
                    end
                else
                    -- screen fallback
                    local frames = findDropFrames()
                    if #frames > 0 then
                        local vps = workspace.CurrentCamera.ViewportSize
                        local best2, bestDist2 = nil, math.huge
                        for _, f in ipairs(frames) do
                            local center = f.AbsolutePosition + f.AbsoluteSize/2
                            local d = (center - vps/2).Magnitude
                            if d < bestDist2 then best2, bestDist2 = center, d end
                        end
                        if best2 then
                            local offX = best2.X - vps.X/2
                            local k = offX > 12 and KD or offX < -12 and KA or nil
                            if k then holdKey(k) else stopMove() end
                            statTxt.Text = string.format("Mode layar | frame Drop: %d | jarak X: %.0f px", #frames, offX)
                            setStatus("Collect: mode layar", COL.ON)
                        end
                    else
                        stopMove()
                        statTxt.Text = "Tidak ada drop terdeteksi."
                        setStatus("Collect: tidak ada item", COL.dm)
                    end
                end
                task.wait(0.05)
            end
            stopMove()
        end)
    end)
    makeNote(pg, "Prioritas: koordinat dunia dari state game. Cadangan: frame Drop di layar.")
    stopFns[#stopFns+1] = function()
        colRun=false; colGen=colGen+1; stopMove(); togCol.set(false,true)
    end
end

-- ══════════════════════════════════════════════════════════════
--  TAB: INFO
-- ══════════════════════════════════════════════════════════════
do
    local pg = addTab("Info", "ℹ️", "Tentang hub & kontrol")
    sectionHead(pg, "Tentang")
    makeNote(pg, HUB_NAME.." (Farm 5x5 Fixed + Auto Collect).\n"
        .."• Geser jendela lewat bar atas\n"
        .."• Tombol – untuk minimize\n"
        .."• RightShift untuk sembunyikan/tampilkan\n"
        .."• X untuk menutup hub dan menghentikan semua fitur")
    sectionHead(pg, "Kontrol")
    makeButton(pg, "Hentikan Semua", function()
        for _, fn in ipairs(stopFns) do pcall(fn) end
        setStatus("Semua dihentikan", COL.YEL); toast("Semua fitur dihentikan", COL.YEL)
    end, COL.card2)
    makeButton(pg, "Tutup Hub", function()
        for _, fn in ipairs(stopFns) do pcall(fn) end
        stopMove()
        for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
        tween(uiscale, 0.18, {Scale=scale*0.8})
        task.delay(0.2, function() pcall(function() sg:Destroy() end) end)
    end, COL.RED)
end

-- ══════════════════════════════════════════════════════════════
--  MINIMIZE / SHOW / HIDE
-- ══════════════════════════════════════════════════════════════
-- floating D button (saat minimize)
local floatBtn = new("TextButton", {
    Size=UDim2.new(0,46,0,46), Position=UDim2.new(0,14,0.5,-23),
    AutoButtonColor=false, BackgroundColor3=COL.wh, Text="D",
    TextColor3=COL.wh, TextSize=19, Font=FONT.b, Visible=false
}, sg)
corner(23, floatBtn); gradient(COL.acc, COL.acc2, 45, floatBtn); stroke(COL.wh,1.5,floatBtn)

-- drag floatBtn
do
    local drag,ds,sp,moved=false,nil,nil,false
    floatBtn.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag,moved,ds,sp=true,false,i.Position,floatBtn.Position
            i.Changed:Connect(function()
                if i.UserInputState==Enum.UserInputState.End then
                    if drag and not moved then
                        win.Visible=true; floatBtn.Visible=false
                        tween(uiscale,0.28,{Scale=scale},Enum.EasingStyle.Back)
                    end
                    drag=false
                end
            end)
        end
    end)
    conns[#conns+1]=UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-ds
            if d.Magnitude>4 then moved=true end
            floatBtn.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
        end
    end)
end

local function showWin()
    win.Visible=true; floatBtn.Visible=false
    uiscale.Scale=scale*0.85; tween(uiscale,0.28,{Scale=scale},Enum.EasingStyle.Back)
end
local function hideWin()
    tween(uiscale,0.16,{Scale=scale*0.85})
    task.delay(0.16,function() win.Visible=false; floatBtn.Visible=true end)
end

-- drag main window
do
    local drag,ds,sp=false,nil,nil
    tbar.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            drag,ds,sp=true,i.Position,win.Position
        end
    end)
    conns[#conns+1]=UIS.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
    end)
    conns[#conns+1]=UIS.InputChanged:Connect(function(i)
        if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-ds
            win.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
        end
    end)
end

minBtn.Activated:Connect(hideWin)
closeBtn.Activated:Connect(function()
    for _, fn in ipairs(stopFns) do pcall(fn) end
    stopMove()
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    getgenv().HubStop = function() end
    tween(uiscale,0.18,{Scale=scale*0.8})
    task.delay(0.2,function() pcall(function() sg:Destroy() end) end)
end)
conns[#conns+1]=UIS.InputBegan:Connect(function(i, gp)
    if gp then return end
    if i.KeyCode==Enum.KeyCode.RightShift then
        if win.Visible then hideWin() else showWin() end
    end
end)

getgenv().HubStop = function()
    for _, fn in ipairs(stopFns) do pcall(fn) end
    stopMove()
end

-- open Farm tab by default
switchTo("Farm")

-- initial scale anim
uiscale.Scale = scale * 0.85
tween(uiscale, 0.3, {Scale=scale}, Enum.EasingStyle.Back)

print("[Dylano] "..HUB_NAME.." loaded")
