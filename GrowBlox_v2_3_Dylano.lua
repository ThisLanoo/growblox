--[[
    GrowBlox Suite v2.3
    Base  : GrowBlox_v2_2_fixed.lua (Sam's fixes merged)
    Tambah: Auto Dirtfarm — ported dari Growtopia script by PowerKuy/Deexzy
    Runtime: Roblox Lua (KRNL / Synapse X / Fluxus / Delta / Hydrogen)

    Port notes — Growtopia → GrowBlox:
      GetTiles()      → workspace scan by tag/pattern "Dirt","Soil","Ground"
      FindPath(x,y)   → PathfindingService:CreatePath
      BreakBlock(x,y) → fireBreak(instance)
      tile.fg/bg      → instance Name / CollectionService tag
      Sleep(ms)       → task.wait(ms/1000)
      odd-row check   → tetap: skip baris genap (tile.y%2==1) = y lantai
      FILL: DirtTag / DirtPatterns sesuai nama block dirt di GrowBlox-mu
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════════
local CFG = {
    WorkSpeed = {
        Enabled    = true,
        Multiplier = 3.0,
        Base = {
            WalkSpeed       = 16,
            HoldDuration    = 0.35,
            CooldownAfter   = 0.10,
            CollectInterval = 0.15,
            PunchInterval   = 0.30,
            ScanInterval    = 3.00,
            SweepDelay      = 0.08,
            DirtInterval    = 0.10,  -- interval antar break di dirtfarm
        },
    },
    Scan    = { Enabled=true, Radius=200, Interval=3.0,
                ItemPatterns={"Fruit","Crop","Drop","Loot","Item","Gem","Seed"},
                ItemTag="DroppedItem", PrintToOutput=true },
    Break   = { Enabled=false, HoldDuration=0.35, CooldownAfter=0.10,
                Radius=15, BlockTag="Block",
                BlockPatterns={"Block","Tree","Rock","Dirt","Wood","Seed"},
                BreakRemote="BreakBlock", NearestFirst=true },
    Clear   = { Enabled=false, WorldSweep=true, SweepDelay=0.08 },
    Collect = { Enabled=false, Radius=40, Interval=0.15 },
    Punch   = { Enabled=false, Range=60, Interval=0.30,
                Target="NPCs", Remote="PunchEvent" },
    Path    = { Enabled=true, WaypointSkip=3, RetryDelay=1.2,
                StuckThreshold=2.5, UseRPS=true },
    AntiAFK = { Enabled=true },

    -- ── Auto Dirtfarm ────────────────────────────────────────
    -- Ported dari: findingdirt() + BreakBlock() + while loop
    Dirtfarm = {
        Enabled      = false,
        -- FILL: nama / tag block dirt di GrowBlox
        -- cek dengan snippet dump remote di console (F9)
        DirtTag      = "Dirt",
        DirtPatterns = {"Dirt","Soil","Ground","Earth","Farmland"},
        -- radius scan dari posisi karakter
        ScanRadius   = 60,
        -- skip baris genap (port dari tile.y%2==1 Growtopia)
        -- true = hanya ambil baris ganjil (farming lane), false = semua
        OddRowOnly   = false,
        -- border skip: skip block di tepi world (port dari x==0,1,98,99)
        -- set sesuai ukuran world GrowBlox-mu, atau set 0 kalau ga perlu
        BorderSkip   = 2,
        -- setelah break, collect otomatis
        AutoCollect  = true,
        -- delay antar tiap block (detik)
        BreakDelay   = 0.10,
        -- remote break sama kayak CFG.Break.BreakRemote
        -- (otomatis pakai BreakRemote yang sama)
    },
}

-- ══════════════════════════════════════════════════════════════
--  SERVICES
-- ══════════════════════════════════════════════════════════════
local Players            = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local CollectionService  = game:GetService("CollectionService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")
local RunService         = game:GetService("RunService")

local lp = Players.LocalPlayer
print("[Dylano] v2.3 starting...")
pcall(function()
    game:GetService("StarterGui"):SetCore("SendNotification",{
        Title="Dylano", Text="GrowBlox Suite v2.3", Duration=4,
    })
end)

local char = lp.Character
do
    local t0 = tick()
    while not char and tick()-t0 < 5 do task.wait(0.2); char=lp.Character end
end
local root = char and char:WaitForChild("HumanoidRootPart", 5)
local hum  = char and (char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid",5))
if not root then warn("[Dylano] HumanoidRootPart tidak ditemukan") end
if not hum  then warn("[Dylano] Humanoid tidak ditemukan") end

lp.CharacterAdded:Connect(function(c)
    char=c; root=c:WaitForChild("HumanoidRootPart",10)
    hum=c:FindFirstChildOfClass("Humanoid") or c:WaitForChild("Humanoid",10)
end)

-- ══════════════════════════════════════════════════════════════
--  WORKSPEED
-- ══════════════════════════════════════════════════════════════
local WS = {}
WS.E = {
    WalkSpeed=16, HoldDuration=0.35, CooldownAfter=0.10,
    CollectInterval=0.15, PunchInterval=0.30,
    ScanInterval=3.00, SweepDelay=0.08, DirtInterval=0.10,
}
function WS.apply()
    local m = math.max(0.1, CFG.WorkSpeed.Multiplier)
    local B, E = CFG.WorkSpeed.Base, WS.E
    local fast = function(b) return math.max(0.01, b/m) end
    E.WalkSpeed       = math.min(B.WalkSpeed * m, 1000)
    E.HoldDuration    = fast(B.HoldDuration)
    E.CooldownAfter   = fast(B.CooldownAfter)
    E.CollectInterval = fast(B.CollectInterval)
    E.PunchInterval   = fast(B.PunchInterval)
    E.ScanInterval    = fast(B.ScanInterval)
    E.SweepDelay      = fast(B.SweepDelay)
    E.DirtInterval    = fast(B.DirtInterval)
    if hum and CFG.WorkSpeed.Enabled then hum.WalkSpeed = E.WalkSpeed end
end
WS.apply()

-- ══════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════
local function partPos(i)
    if i:IsA("Model") then return i:GetPivot().Position end
    return i.Position
end
local function distTo(i)
    if not root then return math.huge end
    return (partPos(i)-root.Position).Magnitude
end
local function matchPat(n,p)
    for _,v in ipairs(p) do if string.find(n,v,1,true) then return true end end
    return false
end
local function getByTag(tag,pat,maxD)
    local out,tagged={},CollectionService:GetTagged(tag)
    local pool=(#tagged>0) and tagged or workspace:GetDescendants()
    for _,v in ipairs(pool) do
        if v:IsA("BasePart") or v:IsA("Model") then
            if not (char and v:IsDescendantOf(char)) then
                if #tagged>0 or matchPat(v.Name,pat) then
                    if not maxD or distTo(v)<=maxD then out[#out+1]=v end
                end
            end
        end
    end
    return out
end
local function sortDist(t)
    table.sort(t,function(a,b) return distTo(a)<distTo(b) end)
end
local function findRemote(n)
    return ReplicatedStorage:FindFirstChild(n,true)
        or workspace:FindFirstChild(n,true)
end
local BreakRE = findRemote(CFG.Break.BreakRemote)
local PunchRE = findRemote(CFG.Punch.Remote)

local function fireBreak(block)
    if not BreakRE then BreakRE=findRemote(CFG.Break.BreakRemote) end
    if BreakRE and BreakRE:IsA("RemoteEvent") then
        BreakRE:FireServer(block, partPos(block))
    end
end

-- moveToWait — MoveToFinished dengan timeout, ga hang
local function moveToWait(pos, timeout)
    if not hum then return false end
    local done=false
    local c=hum.MoveToFinished:Connect(function() done=true end)
    hum:MoveTo(pos)
    local t0=tick()
    while not done and tick()-t0<timeout do task.wait(0.05) end
    c:Disconnect()
    return done
end

-- ══════════════════════════════════════════════════════════════
--  PATHFINDING
-- ══════════════════════════════════════════════════════════════
local PathMod={}; PathMod._active=false
function PathMod:walkTo(target, depth)
    if not root or not hum then return end
    depth=depth or 0
    if depth>3 then self._active=false; return end
    local goal=partPos(target)
    self._active=true
    local path=PathfindingService:CreatePath({
        AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4
    })
    local ok=pcall(function() path:ComputeAsync(root.Position,goal) end)
    if not ok or path.Status~=Enum.PathStatus.Success then
        moveToWait(goal,5); self._active=false; return
    end
    local wps=path:GetWaypoints()
    local lastPos=root.Position; local lastChg=tick()
    local i=2
    while i<=#wps and self._active do
        local wp=wps[i]
        if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end
        local reached=false
        local c=hum.MoveToFinished:Connect(function() reached=true end)
        hum:MoveTo(wp.Position)
        local t0=tick()
        while not reached and tick()-t0<2 and self._active do
            task.wait(0.1)
            if (root.Position-lastPos).Magnitude>=CFG.Path.StuckThreshold then
                lastPos=root.Position; lastChg=tick()
            end
            if tick()-lastChg>CFG.Path.RetryDelay then
                c:Disconnect(); task.wait(0.1)
                return self:walkTo(target,depth+1)
            end
        end
        c:Disconnect()
        i=i+CFG.Path.WaypointSkip
    end
    self._active=false
end
function PathMod:stop() self._active=false; if hum then hum:MoveTo(root.Position) end end

-- ══════════════════════════════════════════════════════════════
--  AUTO DIRTFARM
--  Port dari Growtopia: findingdirt() + BreakBlock()
--  Logic asli:
--    for each tile: skip baris genap & border
--    cek tile.fg == blockID (dirt=2) atau bg==14 & fg==0 (bg only)
--    FindPath ke tile → BreakBlock
--  GrowBlox port:
--    getByTag(DirtTag, DirtPatterns, ScanRadius)
--    skip instance yang posisi-nya di border world (X<BorderSkip atau >worldMax)
--    path ke instance → fireBreak → collect kalau AutoCollect true
-- ══════════════════════════════════════════════════════════════
local function getDirtBlocks()
    local DF = CFG.Dirtfarm
    local pool = getByTag(DF.DirtTag, DF.DirtPatterns, DF.ScanRadius)
    local out = {}

    -- estimasi batas world dari bounding box workspace
    local worldMinX, worldMaxX = math.huge, -math.huge
    for _,v in ipairs(pool) do
        local px = partPos(v).X
        if px < worldMinX then worldMinX=px end
        if px > worldMaxX then worldMaxX=px end
    end
    local borderStuds = DF.BorderSkip * 4 -- 1 tile ≈ 4 studs

    for _,v in ipairs(pool) do
        local pos = partPos(v)
        -- border skip (port dari x==0,1,98,99)
        if pos.X > worldMinX + borderStuds and pos.X < worldMaxX - borderStuds then
            -- odd row check (port dari tile.y%2==1)
            -- GrowBlox: pakai Z atau Y tergantung orientasi world
            -- default: skip kalau Z ganjil/genap — set OddRowOnly=false kalau ga perlu
            local rowOk = true
            if DF.OddRowOnly then
                local gridZ = math.floor(pos.Z / 4)
                rowOk = (gridZ % 2 == 1)
            end
            if rowOk then
                out[#out+1] = v
            end
        end
    end
    return out
end

-- dirtfarm loop — sama struktur while loop-nya kayak script asli
task.spawn(function()
    while true do
        if CFG.Dirtfarm.Enabled then
            local ok,err = pcall(function()
                -- findingdirt() equivalent
                local dirtyBlocks = getDirtBlocks()
                sortDist(dirtyBlocks)

                for _,block in ipairs(dirtyBlocks) do
                    if not CFG.Dirtfarm.Enabled then break end
                    if not block.Parent then continue end

                    local d = distTo(block)

                    -- FindPath equivalent: kalau terlalu jauh, path dulu
                    if d > 10 then
                        PathMod:walkTo(block)
                    end

                    -- BreakBlock equivalent
                    if block.Parent then
                        local hd = WS.E.HoldDuration
                        if hd <= 0.01 then
                            fireBreak(block)
                        else
                            local he = tick()+hd
                            while tick()<he do
                                if not block.Parent then break end
                                fireBreak(block); task.wait(0.05)
                            end
                        end
                    end

                    -- Sleep(110) equivalent
                    task.wait(WS.E.DirtInterval)

                    -- auto collect setelah break (bonus dari versi original)
                    if CFG.Dirtfarm.AutoCollect then
                        local drops = getByTag(
                            CFG.Scan.ItemTag,
                            CFG.Scan.ItemPatterns,
                            CFG.Collect.Radius
                        )
                        for _,drop in ipairs(drops) do
                            if drop.Parent then
                                local re=drop:FindFirstChildWhichIsA("RemoteEvent")
                                if re then re:FireServer()
                                else
                                    local prev=root.CFrame
                                    root.CFrame=CFrame.new(partPos(drop))
                                    task.wait(0.03)
                                    root.CFrame=prev
                                end
                            end
                        end
                    end
                end
            end)
            if not ok then warn("[Dylano] dirtfarm: "..tostring(err)) end
        end
        task.wait(0.1)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  BACKEND LOOPS (collect, break, punch, scan, afk, wsync)
-- ══════════════════════════════════════════════════════════════
task.spawn(function()
    while true do
        if CFG.Collect.Enabled then
            pcall(function()
                local items=getByTag(CFG.Scan.ItemTag,CFG.Scan.ItemPatterns,nil)
                local inR={}
                for _,it in ipairs(items) do
                    if distTo(it)<=CFG.Collect.Radius then inR[#inR+1]=it end
                end
                if #inR>0 then
                    sortDist(inR)
                    for _,it in ipairs(inR) do
                        if not CFG.Collect.Enabled then break end
                        if it.Parent then
                            local re=it:FindFirstChildWhichIsA("RemoteEvent")
                            if re then re:FireServer()
                            else
                                local prev=root.CFrame
                                root.CFrame=CFrame.new(partPos(it))
                                task.wait(0.05); root.CFrame=prev
                            end
                        end
                        task.wait(0.03)
                    end
                else
                    local best,bd=nil,math.huge
                    for _,it in ipairs(items) do
                        local d=distTo(it); if d<bd then best,bd=it,d end
                    end
                    if best and bd>CFG.Collect.Radius then PathMod:walkTo(best) end
                end
            end)
        end
        task.wait(WS.E.CollectInterval)
    end
end)

task.spawn(function()
    while true do
        if CFG.Break.Enabled then
            pcall(function()
                local blocks=getByTag(CFG.Break.BlockTag,CFG.Break.BlockPatterns,CFG.Break.Radius)
                if #blocks>0 then
                    if CFG.Break.NearestFirst then sortDist(blocks) end
                    for _,block in ipairs(blocks) do
                        if not CFG.Break.Enabled then break end
                        if block.Parent then
                            local hd=WS.E.HoldDuration
                            if hd<=0.01 then fireBreak(block)
                            else
                                local he=tick()+hd
                                while tick()<he do
                                    if not block.Parent then break end
                                    fireBreak(block); task.wait(0.05)
                                end
                            end
                            task.wait(WS.E.CooldownAfter)
                        end
                    end
                end
            end)
        end
        task.wait(0.1)
    end
end)

local pLast=0
task.spawn(function()
    while true do
        if CFG.Punch.Enabled then
            local now=tick()
            if now-pLast>=WS.E.PunchInterval then
                pLast=now
                pcall(function()
                    local best,bd=nil,math.huge
                    for _,p in ipairs(Players:GetPlayers()) do
                        if p~=lp and p.Character then
                            local hrp=p.Character:FindFirstChild("HumanoidRootPart")
                            if hrp then local d=(hrp.Position-root.Position).Magnitude
                                if d<bd then best,bd=hrp,d end end
                        end
                    end
                    for _,v in ipairs(workspace:GetDescendants()) do
                        if v:IsA("Humanoid") and v.Health>0 then
                            local nc=v.Parent
                            if nc~=char and not Players:GetPlayerFromCharacter(nc) then
                                local hrp=nc:FindFirstChild("HumanoidRootPart")
                                if hrp then local d=(hrp.Position-root.Position).Magnitude
                                    if d<bd then best,bd=hrp,d end end
                            end
                        end
                    end
                    if best and bd<=CFG.Punch.Range then
                        if not PunchRE then PunchRE=findRemote(CFG.Punch.Remote) end
                        if PunchRE and PunchRE:IsA("RemoteEvent") then
                            PunchRE:FireServer(best.Parent,best.Position)
                        end
                    end
                end)
            end
        end
        task.wait(0.05)
    end
end)

task.spawn(function()
    while true do
        if CFG.Scan.Enabled and CFG.Scan.PrintToOutput then
            pcall(function()
                local items={}
                local pool=getByTag(CFG.Scan.ItemTag,CFG.Scan.ItemPatterns,CFG.Scan.Radius)
                for _,obj in ipairs(pool) do
                    local id=obj.Name
                    local av=obj:FindFirstChild("Amount") or obj:FindFirstChild("Count")
                    local amt=(av and av:IsA("IntValue")) and av.Value or 1
                    items[id]=(items[id] or 0)+amt
                end
                print("── GrowScan ──")
                for id,c in pairs(items) do print(string.format("  %-20s x%d",id,c)) end
            end)
        end
        task.wait(math.max(1,WS.E.ScanInterval))
    end
end)

pcall(function()
    local VU=game:GetService("VirtualUser")
    lp.Idled:Connect(function()
        if CFG.AntiAFK.Enabled then
            VU:CaptureController(); VU:ClickButton2(Vector2.new())
        end
    end)
end)

task.spawn(function()
    while true do task.wait(2)
        if CFG.WorkSpeed.Enabled and hum then hum.WalkSpeed=WS.E.WalkSpeed end
    end
end)

-- ══════════════════════════════════════════════════════════════
--  IN-GAME UI — semua fix dari Sam + tombol Dirtfarm
-- ══════════════════════════════════════════════════════════════
local function newInst(cls,props)
    local i=Instance.new(cls)
    for k,v in pairs(props) do i[k]=v end
    return i
end
local function guiParent()
    local ok,pg=pcall(function() return lp:WaitForChild("PlayerGui",5) end)
    if ok and pg then return pg end
    local ok2,h=pcall(function() return gethui and gethui() end)
    if ok2 and h then return h end
    return game:GetService("CoreGui")
end

local UI={}

local function makeToggleRow(parent,label,desc,yPos,key,initial,onToggle)
    local row=newInst("Frame",{
        Name=key.."Row",Parent=parent,
        BackgroundColor3=Color3.fromRGB(28,28,34),
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,42),
        Position=UDim2.new(0,8,0,yPos),
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,6),Parent=row})
    newInst("TextLabel",{
        Parent=row,Text=label,Font=Enum.Font.GothamBold,TextSize=12,
        TextColor3=Color3.fromRGB(232,232,236),BackgroundTransparency=1,
        Size=UDim2.new(1,-60,0,22),Position=UDim2.new(0,10,0,4),
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    newInst("TextLabel",{
        Parent=row,Text=desc,Font=Enum.Font.Gotham,TextSize=10,
        TextColor3=Color3.fromRGB(90,90,106),BackgroundTransparency=1,
        Size=UDim2.new(1,-60,0,16),Position=UDim2.new(0,10,0,24),
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    local togBg=newInst("Frame",{
        Parent=row,Size=UDim2.new(0,38,0,20),
        Position=UDim2.new(1,-48,0.5,-10),
        BackgroundColor3=Color3.fromRGB(50,50,60),BorderSizePixel=0,
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,10),Parent=togBg})
    local thumb=newInst("Frame",{
        Parent=togBg,Size=UDim2.new(0,14,0,14),
        Position=UDim2.new(0,3,0.5,-7),
        BackgroundColor3=Color3.fromRGB(150,150,160),BorderSizePixel=0,
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,7),Parent=thumb})

    local state=initial or false
    local function refresh()
        TweenService:Create(togBg,TweenInfo.new(0.15),{
            BackgroundColor3=state and Color3.fromRGB(77,204,60) or Color3.fromRGB(50,50,60)
        }):Play()
        TweenService:Create(thumb,TweenInfo.new(0.15),{
            Position=state and UDim2.new(0,21,0.5,-7) or UDim2.new(0,3,0.5,-7),
            BackgroundColor3=state and Color3.fromRGB(255,255,255) or Color3.fromRGB(150,150,160),
        }):Play()
        TweenService:Create(row,TweenInfo.new(0.15),{
            BackgroundColor3=state and Color3.fromRGB(26,51,23) or Color3.fromRGB(28,28,34)
        }):Play()
    end
    refresh()

    local btn=newInst("TextButton",{
        Parent=row,Text="",BackgroundTransparency=1,
        Size=UDim2.new(1,0,1,0),
    })
    btn.MouseButton1Click:Connect(function()
        state=not state; refresh(); onToggle(state)
    end)
    UI[key.."SetState"]=function(s) state=s; refresh() end
    return row
end

local function makeSlider(parent,label,mn,mx,val,yPos,fmt,onChange)
    local row=newInst("Frame",{
        Parent=parent,BackgroundColor3=Color3.fromRGB(28,28,34),
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,52),
        Position=UDim2.new(0,8,0,yPos),
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,6),Parent=row})
    local valLbl=newInst("TextLabel",{
        Parent=row,BackgroundColor3=Color3.fromRGB(26,51,23),
        BorderSizePixel=0,Size=UDim2.new(0,52,0,20),
        Position=UDim2.new(1,-60,0,6),Text=fmt(val),
        Font=Enum.Font.GothamBold,TextSize=11,
        TextColor3=Color3.fromRGB(127,255,107),
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,4),Parent=valLbl})
    newInst("TextLabel",{
        Parent=row,Text=label,Font=Enum.Font.GothamBold,TextSize=11,
        TextColor3=Color3.fromRGB(152,152,168),BackgroundTransparency=1,
        Size=UDim2.new(1,-70,0,18),Position=UDim2.new(0,10,0,6),
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    local track=newInst("Frame",{
        Parent=row,BackgroundColor3=Color3.fromRGB(50,50,62),
        BorderSizePixel=0,Size=UDim2.new(1,-20,0,4),
        Position=UDim2.new(0,10,0,36),
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,2),Parent=track})
    local fill=newInst("Frame",{
        Parent=track,BackgroundColor3=Color3.fromRGB(77,204,60),
        BorderSizePixel=0,Size=UDim2.new((val-mn)/(mx-mn),0,1,0),
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,2),Parent=fill})
    local sthumb=newInst("Frame",{
        Parent=track,BackgroundColor3=Color3.fromRGB(127,255,107),
        BorderSizePixel=0,Size=UDim2.new(0,14,0,14),
        Position=UDim2.new((val-mn)/(mx-mn),0,0.5,-7),
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,7),Parent=sthumb})
    local dragging=false
    local db=newInst("TextButton",{
        Parent=track,Text="",BackgroundTransparency=1,
        Size=UDim2.new(1,14,0,20),Position=UDim2.new(0,-7,0.5,-10),
    })
    db.MouseButton1Down:Connect(function() dragging=true end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
            local ta=track.AbsolutePosition; local ts=track.AbsoluteSize
            local rel=math.clamp((i.Position.X-ta.X)/ts.X,0,1)
            local nv=math.floor((mn+(mx-mn)*rel)*10+0.5)/10
            local pct=(nv-mn)/(mx-mn)
            fill.Size=UDim2.new(pct,0,1,0)
            sthumb.Position=UDim2.new(pct,0,0.5,-7)
            valLbl.Text=fmt(nv); onChange(nv)
        end
    end)
end

local function buildUI()
    local old=guiParent():FindFirstChild("DylanoMenu")
    if old then old:Destroy() end
    local sg=newInst("ScreenGui",{
        Name="DylanoMenu",Parent=guiParent(),
        ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
    })
    local win=newInst("Frame",{
        Parent=sg,Size=UDim2.new(0,280,0,460),
        Position=UDim2.new(0,20,0.5,-230),
        BackgroundColor3=Color3.fromRGB(13,13,15),
        BorderSizePixel=0,ClipsDescendants=true,
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,10),Parent=win})
    newInst("UIStroke",{
        Parent=win,Color=Color3.fromRGB(58,58,70),
        Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
    })

    -- titlebar
    local title=newInst("Frame",{
        Parent=win,Size=UDim2.new(1,0,0,36),
        BackgroundColor3=Color3.fromRGB(20,20,24),BorderSizePixel=0,
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,10),Parent=title})
    newInst("Frame",{
        Parent=title,BackgroundColor3=Color3.fromRGB(20,20,24),
        BorderSizePixel=0,Size=UDim2.new(1,0,0,10),
        Position=UDim2.new(0,0,1,-10),
    })
    newInst("Frame",{
        Parent=title,BackgroundColor3=Color3.fromRGB(77,204,60),
        BorderSizePixel=0,Size=UDim2.new(0,3,0,20),
        Position=UDim2.new(0,10,0.5,-10),
    })
    newInst("TextLabel",{
        Parent=title,Text="Dylano  GrowBlox",
        Font=Enum.Font.GothamBold,TextSize=13,
        TextColor3=Color3.fromRGB(127,255,107),
        BackgroundTransparency=1,
        Size=UDim2.new(1,-80,1,0),Position=UDim2.new(0,20,0,0),
        TextXAlignment=Enum.TextXAlignment.Left,
    })
    newInst("TextLabel",{
        Parent=title,Text="v2.3",Font=Enum.Font.Gotham,TextSize=10,
        TextColor3=Color3.fromRGB(90,90,106),BackgroundTransparency=1,
        Size=UDim2.new(0,30,1,0),Position=UDim2.new(1,-70,0,0),
        TextXAlignment=Enum.TextXAlignment.Right,
    })
    local minBtn=newInst("TextButton",{
        Parent=title,Text="—",Font=Enum.Font.GothamBold,TextSize=14,
        TextColor3=Color3.fromRGB(90,90,106),BackgroundTransparency=1,
        Size=UDim2.new(0,28,0,28),Position=UDim2.new(1,-32,0.5,-14),
    })

    -- drag
    local dragging,dragStart,startPos=false,nil,nil
    title.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then
            dragging=true; dragStart=i.Position; startPos=win.Position
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
            local d=i.Position-dragStart
            win.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,
                startPos.Y.Scale,startPos.Y.Offset+d.Y)
        end
    end)

    local scroll=newInst("ScrollingFrame",{
        Parent=win,Position=UDim2.new(0,0,0,36),Size=UDim2.new(1,0,1,-36),
        BackgroundTransparency=1,ScrollBarThickness=3,
        ScrollBarImageColor3=Color3.fromRGB(77,204,60),
        CanvasSize=UDim2.new(0,0,0,0),BorderSizePixel=0,
    })

    local y=8
    local function section(txt)
        local lbl=newInst("TextLabel",{
            Parent=scroll,Text=txt,Font=Enum.Font.GothamBold,TextSize=9,
            TextColor3=Color3.fromRGB(90,90,106),BackgroundTransparency=1,
            Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0,8,0,y),
            TextXAlignment=Enum.TextXAlignment.Left,
        })
        newInst("Frame",{
            Parent=lbl,BackgroundColor3=Color3.fromRGB(42,42,52),
            BorderSizePixel=0,Size=UDim2.new(1,0,0,1),
            Position=UDim2.new(0,0,1,-1),
        })
        y=y+22
    end
    local function addToggle(label,desc,key,initial,onChange)
        makeToggleRow(scroll,label,desc,y,key,initial,onChange)
        y=y+48
    end
    local function addSlider(label,mn,mx,val,fmt,onChange)
        makeSlider(scroll,label,mn,mx,val,y,fmt,onChange)
        y=y+58
    end

    section("AUTO FARM")
    addToggle("Auto Collect","item sweep + pathfinding","collect",CFG.Collect.Enabled,
        function(s) CFG.Collect.Enabled=s end)
    addToggle("Auto Break","hold-to-break blocks in radius","break",CFG.Break.Enabled,
        function(s) CFG.Break.Enabled=s end)
    addToggle("Auto Clear World","breaks semua block","clear",CFG.Clear.Enabled,
        function(s) CFG.Clear.Enabled=s end)

    -- DIRTFARM ROW — tambahan baru
    section("DIRTFARM")
    addToggle("Auto Dirtfarm","port Growtopia — break dirt + collect","dirt",
        CFG.Dirtfarm.Enabled,
        function(s) CFG.Dirtfarm.Enabled=s end)
    addToggle("Auto Collect Dirt","collect drop setelah break","dirtcol",
        CFG.Dirtfarm.AutoCollect,
        function(s) CFG.Dirtfarm.AutoCollect=s end)
    addSlider("Scan radius dirt",10,150,CFG.Dirtfarm.ScanRadius,
        function(v) return math.floor(v).."st" end,
        function(v) CFG.Dirtfarm.ScanRadius=math.floor(v) end)

    section("COMBAT")
    addToggle("Long Punch","extended reach remote fire","punch",CFG.Punch.Enabled,
        function(s) CFG.Punch.Enabled=s end)

    section("UTILITY")
    addToggle("GrowScan","floating item scanner","scan",CFG.Scan.Enabled,
        function(s) CFG.Scan.Enabled=s end)
    addToggle("Anti-AFK","VirtualUser idle handler","afk",CFG.AntiAFK.Enabled,
        function(s) CFG.AntiAFK.Enabled=s end)

    section("WORKSPEED")
    addToggle("WorkSpeed aktif","multiply semua speed","wspeed",CFG.WorkSpeed.Enabled,
        function(s)
            CFG.WorkSpeed.Enabled=s
            if not s and hum then hum.WalkSpeed=CFG.WorkSpeed.Base.WalkSpeed end
            WS.apply()
        end)
    addSlider("Multiplier",0.5,10,CFG.WorkSpeed.Multiplier,
        function(v) return string.format("%.1f×",v) end,
        function(v) CFG.WorkSpeed.Multiplier=v; WS.apply() end)
    addSlider("Break hold (s)",0,1.5,CFG.Break.HoldDuration,
        function(v) return string.format("%.2fs",v) end,
        function(v) CFG.Break.HoldDuration=v end)
    addSlider("Break radius",5,80,CFG.Break.Radius,
        function(v) return math.floor(v).."st" end,
        function(v) CFG.Break.Radius=math.floor(v) end)
    addSlider("Punch range",10,120,CFG.Punch.Range,
        function(v) return math.floor(v).."st" end,
        function(v) CFG.Punch.Range=math.floor(v) end)
    addSlider("Collect radius",10,120,CFG.Collect.Radius,
        function(v) return math.floor(v).."st" end,
        function(v) CFG.Collect.Radius=math.floor(v) end)

    y=y+8
    scroll.CanvasSize=UDim2.new(0,0,0,y)

    -- minimize
    local minimized=false
    minBtn.MouseButton1Click:Connect(function()
        minimized=not minimized
        TweenService:Create(win,TweenInfo.new(0.2),{
            Size=minimized and UDim2.new(0,280,0,36) or UDim2.new(0,280,0,460)
        }):Play()
        minBtn.Text=minimized and "+" or "—"
    end)

    -- status dot
    local dot=newInst("Frame",{
        Parent=title,Size=UDim2.new(0,7,0,7),
        Position=UDim2.new(1,-52,0.5,-3.5),
        BackgroundColor3=Color3.fromRGB(90,90,106),BorderSizePixel=0,
    })
    newInst("UICorner",{CornerRadius=UDim.new(0,4),Parent=dot})
    RunService.Heartbeat:Connect(function()
        local any=CFG.Collect.Enabled or CFG.Break.Enabled or CFG.Punch.Enabled
            or CFG.Scan.Enabled or CFG.Dirtfarm.Enabled
        dot.BackgroundColor3=any
            and Color3.fromRGB(77,204,60) or Color3.fromRGB(90,90,106)
    end)
end

buildUI()
print("[Dylano] GrowBlox Suite v2.3 loaded — UI injected")
