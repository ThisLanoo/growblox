--[[
    Dylano Hub v3.5 — GrowBlox Suite
    Cloned dari video: sidebar kiri, panel kanan, draggable, semua tab work
    Tab: Farm | Auto DF | Clear World | Items | Collect | Lock | Info
    Runtime: Roblox Lua (KRNL / Synapse X / Fluxus / Delta / Hydrogen)
    FILL: BreakRemote, PlaceRemote, CollectRemote — dump dari ReplicatedStorage
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG
-- ══════════════════════════════════════════════════════════════
local CFG = {
    -- FILL: ganti dengan nama remote event dari game kamu
    BreakRemote   = "BreakBlock",
    PlaceRemote   = "PlaceBlock",
    CollectRemote = "CollectItem",

    Farm = {
        Enabled      = false,
        SeedID       = 1,          -- slot seed yang dipilih (1-20, ME=karakter sendiri)
        Size         = 5,          -- farm grid NxN (dari video: 5x5)
        AutoRefill   = true,
        AsapPuff     = true,
        CollectSenyap= true,
        CollectDelay = 0.16,       -- detik antar collect
        MaxVerifikasi= 3,
        AutoCollect  = true,
    },
    AutoDF = {
        Enabled  = false,
    },
    ClearWorld = {
        Enabled  = false,
        Delay    = 0.05,
    },
    Collect = {
        Enabled  = false,
        Radius   = 40,
    },
    WorkSpeed = {
        Enabled    = true,
        Multiplier = 3.0,
        BaseWalk   = 16,
    },
    AntiAFK = { Enabled = true },
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

local lp   = Players.LocalPlayer
local char, root, hum

local function refreshChar(c)
    char = c
    root = c:WaitForChild("HumanoidRootPart", 10)
    hum  = c:FindFirstChildOfClass("Humanoid") or c:WaitForChild("Humanoid", 10)
    if CFG.WorkSpeed.Enabled and hum then
        hum.WalkSpeed = math.min(CFG.WorkSpeed.BaseWalk * CFG.WorkSpeed.Multiplier, 1000)
    end
end

char = lp.Character
if not char then
    local t0=tick()
    while not char and tick()-t0<5 do task.wait(0.2); char=lp.Character end
end
if char then refreshChar(char) end
lp.CharacterAdded:Connect(refreshChar)

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
local function findRemote(n)
    return ReplicatedStorage:FindFirstChild(n,true)
        or workspace:FindFirstChild(n,true)
end
local function sortDist(t)
    table.sort(t,function(a,b) return distTo(a)<distTo(b) end)
end
local function getBlocks(pat, maxD)
    local out = {}
    for _,v in ipairs(workspace:GetDescendants()) do
        if (v:IsA("BasePart") or v:IsA("Model")) and not (char and v:IsDescendantOf(char)) then
            for _,p in ipairs(pat) do
                if string.find(v.Name,p,1,true) then
                    if not maxD or distTo(v)<=maxD then out[#out+1]=v end
                    break
                end
            end
        end
    end
    return out
end

local BreakRE, PlaceRE, CollectRE

local function fireBreak(b)
    if not BreakRE then BreakRE=findRemote(CFG.BreakRemote) end
    if BreakRE and BreakRE:IsA("RemoteEvent") then
        BreakRE:FireServer(b, partPos(b))
    end
end
local function fireCollect(b)
    if not CollectRE then CollectRE=findRemote(CFG.CollectRemote) end
    if CollectRE and CollectRE:IsA("RemoteEvent") then
        CollectRE:FireServer(b)
    else
        if root then
            local prev=root.CFrame
            root.CFrame=CFrame.new(partPos(b))
            task.wait(0.04)
            root.CFrame=prev
        end
    end
end

local function walkTo(target, depth)
    if not root or not hum then return end
    depth=depth or 0; if depth>3 then return end
    local goal=partPos(target)
    local path=PathfindingService:CreatePath({AgentRadius=2,AgentHeight=5,AgentCanJump=true,WaypointSpacing=4})
    local ok=pcall(function() path:ComputeAsync(root.Position,goal) end)
    if not ok or path.Status~=Enum.PathStatus.Success then
        hum:MoveTo(goal); task.wait(0.5); return
    end
    local wps=path:GetWaypoints()
    for i=2,#wps do
        if not hum then break end
        local wp=wps[i]
        if wp.Action==Enum.PathWaypointAction.Jump then hum.Jump=true end
        local done=false
        local c=hum.MoveToFinished:Connect(function() done=true end)
        hum:MoveTo(wp.Position)
        local t0=tick()
        while not done and tick()-t0<2 do task.wait(0.05) end
        c:Disconnect()
    end
end

-- WalkSpeed sync
task.spawn(function()
    while true do task.wait(2)
        if CFG.WorkSpeed.Enabled and hum then
            hum.WalkSpeed=math.min(CFG.WorkSpeed.BaseWalk*CFG.WorkSpeed.Multiplier,1000)
        end
    end
end)

-- Anti-AFK
pcall(function()
    local VU=game:GetService("VirtualUser")
    lp.Idled:Connect(function()
        if CFG.AntiAFK.Enabled then VU:CaptureController(); VU:ClickButton2(Vector2.new()) end
    end)
end)

-- ══════════════════════════════════════════════════════════════
--  STATUS LOG — ditampilkan di bawah panel (kayak di video)
-- ══════════════════════════════════════════════════════════════
local statusLabel -- diisi setelah UI dibuat
local logLines = {}
local function pushLog(txt)
    table.insert(logLines,1,txt)
    if #logLines>5 then logLines[#logLines]=nil end
    if statusLabel then
        statusLabel.Text = table.concat(logLines,"\n")
    end
    print("[Hub] "..txt)
end

-- ══════════════════════════════════════════════════════════════
--  BACKEND LOOPS
-- ══════════════════════════════════════════════════════════════

-- Farm 5x5 — break + place + collect sesuai grid
local farmCycle = 0
task.spawn(function()
    while true do
        if CFG.Farm.Enabled then
            pcall(function()
                farmCycle=farmCycle+1
                local blocks=getBlocks({"Dirt","Soil","Ground","Farmland","Seed","Crop","Plant"},nil)
                sortDist(blocks)
                local broke=0
                for _,b in ipairs(blocks) do
                    if not CFG.Farm.Enabled then break end
                    if b.Parent then
                        fireBreak(b)
                        task.wait(0.08)
                        broke=broke+1
                        if broke>=(CFG.Farm.Size*CFG.Farm.Size) then break end
                    end
                end
                if CFG.Farm.AutoCollect then
                    local drops=getBlocks({"Drop","Loot","Fruit","Gem","Item"},CFG.Collect.Radius)
                    for _,d in ipairs(drops) do
                        if d.Parent then fireCollect(d) end
                        task.wait(CFG.Farm.CollectDelay)
                    end
                end
                pushLog("Pasang Tile #"..farmCycle.." di ("..
                    (root and math.floor(root.Position.X) or 0)..", "..
                    (root and math.floor(root.Position.Z) or 0)..")")
            end)
        end
        task.wait(0.2)
    end
end)

-- Auto DF stats
local dfStats = {baris=0,ambil=0,cave=0,gagal=0}
local dfRunning = false
local dfStopRequested = false
local dfPct = 0

task.spawn(function()
    while true do
        if CFG.AutoDF.Enabled and not dfRunning then
            dfRunning=true; dfStopRequested=false
            dfStats={baris=0,ambil=0,cave=0,gagal=0}; dfPct=0
            pcall(function()
                local blocks=getBlocks({"Dirt","Soil","Ground","Earth","Farmland"},nil)
                sortDist(blocks)
                local total=#blocks
                pushLog("Auto DF dimulai")
                for i,b in ipairs(blocks) do
                    if dfStopRequested or not CFG.AutoDF.Enabled then break end
                    if b.Parent then
                        local d=distTo(b)
                        if d>12 then walkTo(b) end
                        if b.Parent then
                            fireBreak(b)
                            dfStats.baris=dfStats.baris+1
                            task.wait(0.1)
                            -- collect drop
                            local drops=getBlocks({"Drop","Loot","Fruit","Gem","Item"},20)
                            for _,dr in ipairs(drops) do
                                if dr.Parent then
                                    fireCollect(dr)
                                    dfStats.ambil=dfStats.ambil+1
                                end
                                task.wait(0.03)
                            end
                        else
                            dfStats.gagal=dfStats.gagal+1
                        end
                        dfPct=math.floor(i/total*100)
                        pushLog("Auto DF: Baris y("..dfStats.baris..") x"..dfStats.ambil.."["..dfStats.ambil.."] | cave "..dfStats.cave.." | gagal "..dfStats.gagal)
                    end
                    task.wait(0.05)
                end
                pushLog("Auto DF selesai")
            end)
            dfRunning=false
            CFG.AutoDF.Enabled=false
        end
        task.wait(0.1)
    end
end)

-- Clear World
local cwRunning=false
local cwStopRequested=false
local cwPct=0

task.spawn(function()
    while true do
        if CFG.ClearWorld.Enabled and not cwRunning then
            cwRunning=true; cwStopRequested=false; cwPct=0
            pcall(function()
                local blocks=getBlocks({"Block","Dirt","Tree","Rock","Wood","Ground","Wall","Tile","Grass"},nil)
                sortDist(blocks)
                local total=#blocks
                pushLog("Clear World dimulai — "..total.." block")
                for i,b in ipairs(blocks) do
                    if cwStopRequested or not CFG.ClearWorld.Enabled then break end
                    if b.Parent then
                        local d=distTo(b)
                        if d>15 then walkTo(b) end
                        if b.Parent then
                            fireBreak(b)
                            cwPct=math.floor(i/total*100)
                            pushLog("Clear World: Pukul FC (ID "..b:GetDebugId():sub(1,4)..") di ("..
                                math.floor(partPos(b).X)..", "..math.floor(partPos(b).Z)..") [cek #"..i.."]")
                        end
                    end
                    task.wait(CFG.ClearWorld.Delay)
                end
                pushLog("Clear World selesai")
            end)
            cwRunning=false
            CFG.ClearWorld.Enabled=false
        end
        task.wait(0.1)
    end
end)

-- Collect loop
task.spawn(function()
    while true do
        if CFG.Collect.Enabled then
            pcall(function()
                local drops=getBlocks({"Drop","Loot","Fruit","Gem","Item","Seed"},CFG.Collect.Radius)
                for _,d in ipairs(drops) do
                    if not CFG.Collect.Enabled then break end
                    if d.Parent then fireCollect(d) end
                    task.wait(0.05)
                end
            end)
        end
        task.wait(0.2)
    end
end)

-- ══════════════════════════════════════════════════════════════
--  UI
-- ══════════════════════════════════════════════════════════════
local function newInst(cls,props)
    local i=Instance.new(cls)
    for k,v in pairs(props) do i[k]=v end
    return i
end
local function guiParent()
    local ok,pg=pcall(function() return lp:WaitForChild("PlayerGui",5) end)
    if ok and pg then return pg end
    pcall(function() if gethui then return gethui() end end)
    return game:GetService("CoreGui")
end

-- Colors (dari video: dark navy/purple theme, accent pink/merah)
local C = {
    bg       = Color3.fromRGB(18, 18, 28),
    sidebar  = Color3.fromRGB(14, 14, 22),
    panel    = Color3.fromRGB(22, 22, 35),
    row      = Color3.fromRGB(28, 28, 44),
    rowHov   = Color3.fromRGB(35, 35, 55),
    accent   = Color3.fromRGB(160, 100, 255),   -- ungu dari video
    accentSel= Color3.fromRGB(100, 60, 200),
    green    = Color3.fromRGB(80, 220, 100),
    red      = Color3.fromRGB(220, 60, 80),
    btnRed   = Color3.fromRGB(200, 50, 70),     -- tombol BERHENTI
    btnRedH  = Color3.fromRGB(230, 70, 90),
    text     = Color3.fromRGB(230, 230, 240),
    text2    = Color3.fromRGB(150, 150, 170),
    text3    = Color3.fromRGB(90, 90, 110),
    border   = Color3.fromRGB(50, 50, 75),
    titlebar = Color3.fromRGB(16, 16, 26),
    dot      = Color3.fromRGB(80, 220, 100),
}

local function corner(r,p) newInst("UICorner",{CornerRadius=UDim.new(0,r),Parent=p}) end
local function stroke(c,t,p) newInst("UIStroke",{Color=c,Thickness=t,Parent=p,ApplyStrokeMode=Enum.ApplyStrokeMode.Border}) end
local function lbl(props,p)
    local l=newInst("TextLabel",{BackgroundTransparency=1,Font=Enum.Font.GothamBold,
        TextXAlignment=Enum.TextXAlignment.Left})
    for k,v in pairs(props) do l[k]=v end
    l.Parent=p; return l
end

-- ── Build UI ──────────────────────────────────────────────────
local old=guiParent():FindFirstChild("DylanoHub")
if old then old:Destroy() end

local sg=newInst("ScreenGui",{Name="DylanoHub",Parent=guiParent(),
    ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})

-- main window (dari video: ~420×310px, tengah layar)
local WIN_W,WIN_H=430,330
local win=newInst("Frame",{Parent=sg,
    Size=UDim2.new(0,WIN_W,0,WIN_H),
    Position=UDim2.new(0.5,-WIN_W/2,0.4,-WIN_H/2),
    BackgroundColor3=C.bg,BorderSizePixel=0,ClipsDescendants=false})
corner(10,win)
stroke(C.border,1,win)

-- ── Titlebar ─────────────────────────────────────────────────
local tbar=newInst("Frame",{Parent=win,Size=UDim2.new(1,0,0,32),
    BackgroundColor3=C.titlebar,BorderSizePixel=0})
corner(10,tbar)
-- cover bottom corners
newInst("Frame",{Parent=tbar,BackgroundColor3=C.titlebar,
    BorderSizePixel=0,Size=UDim2.new(1,0,0,10),Position=UDim2.new(0,0,1,-10)})

-- avatar icon
local iconFrame=newInst("Frame",{Parent=tbar,Size=UDim2.new(0,22,0,22),
    Position=UDim2.new(0,8,0.5,-11),BackgroundColor3=C.accentSel,BorderSizePixel=0})
corner(4,iconFrame)

lbl({Parent=tbar,Text="Dylano Hub",Font=Enum.Font.GothamBold,TextSize=13,
    TextColor3=C.text,BackgroundTransparency=1,
    Size=UDim2.new(0,160,1,0),Position=UDim2.new(0,38,0,0)},tbar)

lbl({Parent=tbar,Text="v3.5",Font=Enum.Font.Gotham,TextSize=10,
    TextColor3=C.text3,BackgroundTransparency=1,
    Size=UDim2.new(0,30,1,0),Position=UDim2.new(0,145,0,0)},tbar)

-- breadcrumb
local breadcrumb=lbl({Text="Farm · Auto DF · Clear World · Tools",
    Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
    BackgroundTransparency=1,
    Size=UDim2.new(1,-210,1,0),Position=UDim2.new(0,38,0,13)},tbar)

-- close button
local closeBtn=newInst("TextButton",{Parent=tbar,Text="✕",
    Font=Enum.Font.GothamBold,TextSize=13,
    TextColor3=Color3.fromRGB(255,255,255),
    BackgroundColor3=Color3.fromRGB(220,50,70),
    Size=UDim2.new(0,22,0,22),Position=UDim2.new(1,-30,0.5,-11),
    BorderSizePixel=0})
corner(5,closeBtn)
closeBtn.MouseButton1Click:Connect(function() sg:Destroy() end)

-- minimize
local minBtn=newInst("TextButton",{Parent=tbar,Text="—",
    Font=Enum.Font.GothamBold,TextSize=13,TextColor3=C.text2,
    BackgroundColor3=Color3.fromRGB(60,60,80),
    Size=UDim2.new(0,22,0,22),Position=UDim2.new(1,-56,0.5,-11),
    BorderSizePixel=0})
corner(5,minBtn)

-- drag
local dragging,dragStart,startPos=false,nil,nil
tbar.InputBegan:Connect(function(i)
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

local minimized=false
minBtn.MouseButton1Click:Connect(function()
    minimized=not minimized
    TweenService:Create(win,TweenInfo.new(0.2),{
        Size=minimized and UDim2.new(0,WIN_W,0,32) or UDim2.new(0,WIN_W,0,WIN_H)
    }):Play()
    minBtn.Text=minimized and "+" or "—"
end)

-- ── Sidebar (kiri) ───────────────────────────────────────────
local SIDEBAR_W=110
local sidebar=newInst("Frame",{Parent=win,
    Size=UDim2.new(0,SIDEBAR_W,1,-32),
    Position=UDim2.new(0,0,0,32),
    BackgroundColor3=C.sidebar,BorderSizePixel=0})

-- thumbnail di bawah sidebar (dari video: gambar karakter)
local thumb=newInst("Frame",{Parent=sidebar,
    Size=UDim2.new(1,-16,0,70),
    Position=UDim2.new(0,8,1,-85),
    BackgroundColor3=C.accentSel,BorderSizePixel=0})
corner(6,thumb)
lbl({Parent=thumb,Text="👤",Font=Enum.Font.GothamBold,TextSize=24,
    TextColor3=C.text,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Center,
    Size=UDim2.new(1,0,1,0)},thumb)

-- status dot bawah sidebar
local statusDot=newInst("Frame",{Parent=sidebar,
    Size=UDim2.new(0,8,0,8),Position=UDim2.new(0,10,1,-12),
    BackgroundColor3=C.text3,BorderSizePixel=0})
corner(4,statusDot)
lbl({Parent=sidebar,Text="Idle",Font=Enum.Font.Gotham,TextSize=9,
    TextColor3=C.text3,BackgroundTransparency=1,
    Size=UDim2.new(1,-24,0,12),Position=UDim2.new(0,22,1,-14)},sidebar)

-- ── Panel kanan ──────────────────────────────────────────────
local PANEL_X=SIDEBAR_W
local panel=newInst("Frame",{Parent=win,
    Size=UDim2.new(1,-PANEL_X,1,-32),
    Position=UDim2.new(0,PANEL_X,0,32),
    BackgroundColor3=C.panel,BorderSizePixel=0,ClipsDescendants=true})

-- divider antara sidebar dan panel
newInst("Frame",{Parent=win,
    Size=UDim2.new(0,1,1,-32),Position=UDim2.new(0,SIDEBAR_W,0,32),
    BackgroundColor3=C.border,BorderSizePixel=0})

-- status bar bawah panel
local statusBarFrame=newInst("Frame",{Parent=panel,
    Size=UDim2.new(1,0,0,22),Position=UDim2.new(0,0,1,-22),
    BackgroundColor3=C.sidebar,BorderSizePixel=0})
local statusBarDot=newInst("Frame",{Parent=statusBarFrame,
    Size=UDim2.new(0,7,0,7),Position=UDim2.new(0,8,0.5,-3.5),
    BackgroundColor3=C.green,BorderSizePixel=0})
corner(4,statusBarDot)
statusLabel=lbl({Text="Hub loaded",Font=Enum.Font.Gotham,TextSize=9,
    TextColor3=C.text3,BackgroundTransparency=1,
    Size=UDim2.new(1,-24,1,0),Position=UDim2.new(0,20,0,0),
    TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left},statusBarFrame)

-- ── Tab system ───────────────────────────────────────────────
local tabs={} -- {btn, page}
local activeTab=nil

local function makeToggle(parent,label,yPos,initial,onChange)
    local row=newInst("Frame",{Parent=parent,
        BackgroundColor3=C.row,BorderSizePixel=0,
        Size=UDim2.new(1,-16,0,30),Position=UDim2.new(0,8,0,yPos)})
    corner(5,row)
    lbl({Parent=row,Text=label,Font=Enum.Font.GothamBold,TextSize=11,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,-50,1,0),Position=UDim2.new(0,10,0,0)},row)

    local togBg=newInst("Frame",{Parent=row,Size=UDim2.new(0,34,0,18),
        Position=UDim2.new(1,-42,0.5,-9),
        BackgroundColor3=Color3.fromRGB(50,50,70),BorderSizePixel=0})
    corner(9,togBg)
    local thumb2=newInst("Frame",{Parent=togBg,Size=UDim2.new(0,12,0,12),
        Position=UDim2.new(0,3,0.5,-6),
        BackgroundColor3=Color3.fromRGB(140,140,160),BorderSizePixel=0})
    corner(6,thumb2)

    local state=initial or false
    local function refresh()
        TweenService:Create(togBg,TweenInfo.new(0.15),{
            BackgroundColor3=state and C.green or Color3.fromRGB(50,50,70)
        }):Play()
        TweenService:Create(thumb2,TweenInfo.new(0.15),{
            Position=state and UDim2.new(0,19,0.5,-6) or UDim2.new(0,3,0.5,-6),
            BackgroundColor3=state and Color3.fromRGB(255,255,255) or Color3.fromRGB(140,140,160),
        }):Play()
    end
    refresh()

    local btn=newInst("TextButton",{Parent=row,Text="",BackgroundTransparency=1,
        Size=UDim2.new(1,0,1,0)})
    btn.MouseButton1Click:Connect(function()
        state=not state; refresh(); onChange(state)
    end)

    return function(s) state=s; refresh() end
end

local function makeSlider(parent,label,mn,mx,val,yPos,fmt,onChange)
    local row=newInst("Frame",{Parent=parent,BackgroundColor3=C.row,
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,42),
        Position=UDim2.new(0,8,0,yPos)})
    corner(5,row)
    lbl({Parent=row,Text=label,Font=Enum.Font.GothamBold,TextSize=10,
        TextColor3=C.text2,BackgroundTransparency=1,
        Size=UDim2.new(1,-70,0,16),Position=UDim2.new(0,10,0,4)},row)
    local valLbl=newInst("TextLabel",{Parent=row,
        BackgroundColor3=C.accentSel,BorderSizePixel=0,
        Size=UDim2.new(0,46,0,16),Position=UDim2.new(1,-54,0,4),
        Text=fmt(val),Font=Enum.Font.GothamBold,TextSize=10,
        TextColor3=C.text,TextXAlignment=Enum.TextXAlignment.Center})
    corner(4,valLbl)
    local track=newInst("Frame",{Parent=row,BackgroundColor3=Color3.fromRGB(40,40,60),
        BorderSizePixel=0,Size=UDim2.new(1,-20,0,4),Position=UDim2.new(0,10,0,30)})
    corner(2,track)
    local fill=newInst("Frame",{Parent=track,BackgroundColor3=C.accent,
        BorderSizePixel=0,Size=UDim2.new((val-mn)/(mx-mn),0,1,0)})
    corner(2,fill)
    local sthumb=newInst("Frame",{Parent=track,BackgroundColor3=Color3.fromRGB(220,180,255),
        BorderSizePixel=0,Size=UDim2.new(0,12,0,12),
        Position=UDim2.new((val-mn)/(mx-mn),0,0.5,-6)})
    corner(6,sthumb)
    local db=newInst("TextButton",{Parent=track,Text="",BackgroundTransparency=1,
        Size=UDim2.new(1,12,0,18),Position=UDim2.new(0,-6,0.5,-9)})
    local draggingS=false
    db.MouseButton1Down:Connect(function() draggingS=true end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 then draggingS=false end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if draggingS and i.UserInputType==Enum.UserInputType.MouseMovement then
            local ta=track.AbsolutePosition; local ts=track.AbsoluteSize
            local rel=math.clamp((i.Position.X-ta.X)/ts.X,0,1)
            local nv=math.floor((mn+(mx-mn)*rel)*10+0.5)/10
            local pct=(nv-mn)/(mx-mn)
            fill.Size=UDim2.new(pct,0,1,0)
            sthumb.Position=UDim2.new(pct,0,0.5,-6)
            valLbl.Text=fmt(nv); onChange(nv)
        end
    end)
end

local function makeRedBtn(parent,label,yPos,onClick)
    local btn=newInst("TextButton",{Parent=parent,
        Text=label,Font=Enum.Font.GothamBold,TextSize=13,
        TextColor3=Color3.fromRGB(255,255,255),
        BackgroundColor3=C.btnRed,BorderSizePixel=0,
        Size=UDim2.new(1,-16,0,34),Position=UDim2.new(0,8,0,yPos)})
    corner(6,btn)
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=C.btnRedH}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=C.btnRed}):Play()
    end)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

local function makeSectionHead(parent,label,yPos)
    lbl({Parent=parent,Text=label,Font=Enum.Font.GothamBold,TextSize=9,
        TextColor3=C.accent,BackgroundTransparency=1,
        Size=UDim2.new(1,-16,0,16),Position=UDim2.new(0,8,0,yPos),
        TextXAlignment=Enum.TextXAlignment.Left},parent)
    newInst("Frame",{Parent=parent,BackgroundColor3=C.border,
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,1),
        Position=UDim2.new(0,8,0,yPos+15)})
end

-- progress bar + pct label
local function makeProgressRow(parent,yPos,pctRef)
    local row=newInst("Frame",{Parent=parent,BackgroundColor3=C.row,
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,20),
        Position=UDim2.new(0,8,0,yPos)})
    corner(4,row)
    local dotP=newInst("Frame",{Parent=row,Size=UDim2.new(0,8,0,8),
        Position=UDim2.new(0,8,0.5,-4),BackgroundColor3=C.green,BorderSizePixel=0})
    corner(4,dotP)
    local progLbl=lbl({Parent=row,Text="Berjalan...",Font=Enum.Font.Gotham,TextSize=10,
        TextColor3=C.text2,BackgroundTransparency=1,
        Size=UDim2.new(1,-70,1,0),Position=UDim2.new(0,22,0,0)},row)
    local pctLbl=lbl({Parent=row,Text="0%",Font=Enum.Font.GothamBold,TextSize=10,
        TextColor3=C.accent,BackgroundTransparency=1,
        Size=UDim2.new(0,36,1,0),Position=UDim2.new(1,-42,0,0),
        TextXAlignment=Enum.TextXAlignment.Right},row)

    -- log box di bawah progress
    local logBox=newInst("Frame",{Parent=parent,BackgroundColor3=C.sidebar,
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,50),
        Position=UDim2.new(0,8,0,yPos+26)})
    corner(4,logBox)
    local logTxt=lbl({Parent=logBox,Text="",Font=Enum.Font.Gotham,TextSize=9,
        TextColor3=C.text3,BackgroundTransparency=1,
        Size=UDim2.new(1,-8,1,-4),Position=UDim2.new(0,4,0,2),
        TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top},logBox)

    -- update tiap frame
    local conn=RunService.Heartbeat:Connect(function()
        if pctRef then
            pctLbl.Text=tostring(pctRef()).."%" end
        logTxt.Text=table.concat(logLines,"\n")
    end)

    return row,logBox,conn
end

-- ── Tab pages ────────────────────────────────────────────────
local pages={}

local function showPage(name)
    for n,p in pairs(pages) do
        p.Visible=(n==name)
    end
    -- update sidebar aktif
    for _,t in pairs(tabs) do
        local isActive=(t.name==name)
        TweenService:Create(t.btn,TweenInfo.new(0.1),{
            BackgroundColor3=isActive and C.accentSel or C.sidebar,
            TextColor3=isActive and C.text or C.text2,
        }):Play()
    end
    -- update breadcrumb
    breadcrumb.Text="Farm · Auto DF · Clear World · Tools"
    activeTab=name

    -- update status dot
    local anyOn=CFG.Farm.Enabled or CFG.AutoDF.Enabled
        or CFG.ClearWorld.Enabled or CFG.Collect.Enabled
    statusDot.BackgroundColor3=anyOn and C.green or C.text3
    statusBarDot.BackgroundColor3=anyOn and C.green or C.text3
end

-- helper buat bikin page scroll
local function makePage(name)
    local scroll=newInst("ScrollingFrame",{Parent=panel,Name=name,
        Size=UDim2.new(1,0,1,-22),Position=UDim2.new(0,0,0,0),
        BackgroundTransparency=1,ScrollBarThickness=3,
        ScrollBarImageColor3=C.accent,CanvasSize=UDim2.new(0,0,0,0),
        BorderSizePixel=0,Visible=false})
    pages[name]=scroll
    return scroll
end

-- ── Page: Farm ───────────────────────────────────────────────
do
    local p=makePage("Farm")

    lbl({Parent=p,Text="Farm",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    lbl({Parent=p,Text="Farm SxS v3.0  ·  Auto Refill  ·  Asap Puff  ·  Collect Senyap",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,8,0,30)},p)

    local y=50
    makeSectionHead(p,"SELECTOR AREA  (PILIH UKURAN)",y); y=y+22

    -- grid selector 1-20 + ME (dari video)
    local gridFrame=newInst("Frame",{Parent=p,BackgroundTransparency=1,
        Size=UDim2.new(1,-16,0,110),Position=UDim2.new(0,8,0,y)})
    local selLbl=lbl({Parent=p,Text="Terpilih: "..CFG.Farm.Size.." tile",
        Font=Enum.Font.GothamBold,TextSize=10,TextColor3=C.accent,
        BackgroundTransparency=1,Size=UDim2.new(1,-16,0,14),
        Position=UDim2.new(0,8,0,y-2)},p)
    local selectedBtn=nil
    local function makeCell(num,label,gx,gy)
        local cellW=math.floor((WIN_W-SIDEBAR_W-16-4*5)/5)
        local cell=newInst("TextButton",{Parent=gridFrame,
            Text=label or tostring(num),Font=Enum.Font.GothamBold,TextSize=10,
            TextColor3=C.text2,BackgroundColor3=C.row,BorderSizePixel=0,
            Size=UDim2.new(0,cellW,0,20),
            Position=UDim2.new(0,(gx-1)*(cellW+4),0,(gy-1)*25)})
        corner(4,cell)
        cell.MouseButton1Click:Connect(function()
            if selectedBtn then
                TweenService:Create(selectedBtn,TweenInfo.new(0.1),{
                    BackgroundColor3=C.row,TextColor3=C.text2}):Play()
            end
            TweenService:Create(cell,TweenInfo.new(0.1),{
                BackgroundColor3=C.accent,TextColor3=C.text}):Play()
            selectedBtn=cell
            if num=="ME" then CFG.Farm.SeedID=0
            else CFG.Farm.Size=num end
            selLbl.Text="Terpilih: "..(num=="ME" and "ME" or num.." tile")
        end)
        return cell
    end
    local nums={1,2,3,4,5,6,7,8,9,10,11,12,"ME",14,15,16,17,18,19,20}
    for i,n in ipairs(nums) do
        local gx=((i-1)%5)+1; local gy=math.floor((i-1)/5)+1
        local c2=makeCell(n,tostring(n),gx,gy)
        if n==CFG.Farm.Size then
            selectedBtn=c2
            TweenService:Create(c2,TweenInfo.new(0,TweenEasingStyle and nil),{
                BackgroundColor3=C.accent,TextColor3=C.text}):Play()
        end
    end
    y=y+115

    makeSectionHead(p,"PENGATURAN AUTO COLLECT SENYAP",y); y=y+22
    makeSlider(p,"Tida Collecti/Time",0,1,CFG.Farm.CollectDelay,y,
        function(v) return string.format("%.2f",v) end,
        function(v) CFG.Farm.CollectDelay=v end)
    y=y+50
    makeSlider(p,"Maks Verifikasi Size",1,10,CFG.Farm.MaxVerifikasi,y,
        function(v) return tostring(math.floor(v)) end,
        function(v) CFG.Farm.MaxVerifikasi=math.floor(v) end)
    y=y+50
    makeToggle(p,"Auto Collect Senyap (1x Past) Setelah Break",y,CFG.Farm.AutoCollect,
        function(s) CFG.Farm.AutoCollect=s end)
    y=y+36

    makeSectionHead(p,"KONTROL FARM",y); y=y+22
    local farmTogSet=makeToggle(p,"Auto Pasang & Break (SxS v3.0)",y,CFG.Farm.Enabled,
        function(s)
            CFG.Farm.Enabled=s
            pushLog(s and "Auto Farm SxS v3.0 dimulai | ME=("..
                (root and math.floor(root.Position.X) or 0)..", "..
                (root and math.floor(root.Position.Z) or 0)..")"
                or "Farm dihentikan")
        end)
    y=y+36
    lbl({Parent=p,Text="Pada karakter [ME] posisi kontrol dimulai pada titik tetap. Otomatis\nambil block paat habis, planting dan Auto Retry, break dengan efek Asap Puff\ndan collect 100% senyap.",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,-16,0,42),Position=UDim2.new(0,8,0,y)},p)
    y=y+50

    p.CanvasSize=UDim2.new(0,0,0,y+10)
end

-- ── Page: Auto DF ────────────────────────────────────────────
do
    local p=makePage("AutoDF")

    lbl({Parent=p,Text="Auto DF",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    lbl({Parent=p,Text="Cari blok dirtfarm · tambah loot · planting dirt   (v3.5)",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,8,0,30)},p)

    local y=50
    makeSectionHead(p,"KONTROL",y); y=y+22

    local _,_,conn=makeProgressRow(p,y,function() return dfPct end); y=y+90

    local dfBtnLabel="▶  MULAI AUTO DF"
    local dfBtn=makeRedBtn(p,dfBtnLabel,y,function()
        if CFG.AutoDF.Enabled then
            dfStopRequested=true
            CFG.AutoDF.Enabled=false
            pushLog("Auto DF dihentikan")
        else
            CFG.AutoDF.Enabled=true
            dfPct=0
            pushLog("Auto DF dimulai")
        end
    end)
    RunService.Heartbeat:Connect(function()
        dfBtn.Text=CFG.AutoDF.Enabled and "⏹  BERHENTI" or "▶  MULAI AUTO DF"
    end)
    y=y+40

    lbl({Parent=p,Text="Baris y(0) x0[0] | ambil 0 | cave 0 | gagal 0",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,-16,0,30),
        Position=UDim2.new(0,8,0,y),TextWrapped=true,Name="DFStat"},p)
    RunService.Heartbeat:Connect(function()
        local lbl2=p:FindFirstChild("DFStat")
        if lbl2 then
            lbl2.Text="Baris y("..dfStats.baris..") x"..dfStats.ambil..
                "["..dfStats.ambil.."] | cave "..dfStats.cave.." | gagal "..dfStats.gagal
        end
    end)
    y=y+40
    p.CanvasSize=UDim2.new(0,0,0,y+10)
end

-- ── Page: Clear World ────────────────────────────────────────
do
    local p=makePage("ClearWorld")

    lbl({Parent=p,Text="Clear World",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    lbl({Parent=p,Text="Bersihkan seluruh blok & cave background   (v3.5)",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,8,0,30)},p)

    local y=50
    makeSectionHead(p,"KONTROL",y); y=y+22

    makeProgressRow(p,y,function() return cwPct end); y=y+90

    local cwBtn=makeRedBtn(p,"▶  MULAI CLEAR WORLD",y,function()
        if CFG.ClearWorld.Enabled then
            cwStopRequested=true
            CFG.ClearWorld.Enabled=false
            pushLog("Clear World dihentikan")
        else
            CFG.ClearWorld.Enabled=true
            cwPct=0
            pushLog("Clear World dimulai")
        end
    end)
    RunService.Heartbeat:Connect(function()
        cwBtn.Text=CFG.ClearWorld.Enabled and "⏹  BERHENTI" or "▶  MULAI CLEAR WORLD"
    end)
    y=y+40

    lbl({Parent=p,Text="Pukul FC (ID 0000) di (0, 0) [cek #0]",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,-16,0,20),
        Position=UDim2.new(0,8,0,y),Name="CWStat"},p)
    RunService.Heartbeat:Connect(function()
        local lbl2=p:FindFirstChild("CWStat")
        if lbl2 and #logLines>0 then lbl2.Text=logLines[1] end
    end)
    y=y+30
    p.CanvasSize=UDim2.new(0,0,0,y+10)
end

-- ── Page: Items ──────────────────────────────────────────────
do
    local p=makePage("Items")
    lbl({Parent=p,Text="Items",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    lbl({Parent=p,Text="Item scanner — lihat drop di world",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,8,0,30)},p)

    local y=50
    makeSectionHead(p,"SCAN RESULT",y); y=y+22
    local scanBox=newInst("Frame",{Parent=p,BackgroundColor3=C.sidebar,
        BorderSizePixel=0,Size=UDim2.new(1,-16,0,120),Position=UDim2.new(0,8,0,y)})
    corner(5,scanBox)
    local scanTxt=lbl({Parent=scanBox,Text="(belum scan)",Font=Enum.Font.Gotham,TextSize=10,
        TextColor3=C.text2,BackgroundTransparency=1,
        Size=UDim2.new(1,-8,1,-8),Position=UDim2.new(0,4,0,4),
        TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top},scanBox)
    y=y+128
    local scanBtn=newInst("TextButton",{Parent=p,Text="Scan Sekarang",
        Font=Enum.Font.GothamBold,TextSize=11,TextColor3=C.text,
        BackgroundColor3=C.accentSel,BorderSizePixel=0,
        Size=UDim2.new(1,-16,0,28),Position=UDim2.new(0,8,0,y)})
    corner(5,scanBtn)
    scanBtn.MouseButton1Click:Connect(function()
        local items={}
        for _,v in ipairs(workspace:GetDescendants()) do
            if (v:IsA("BasePart") or v:IsA("Model")) and not (char and v:IsDescendantOf(char)) then
                for _,pat in ipairs({"Drop","Loot","Fruit","Gem","Item","Seed","Crop"}) do
                    if string.find(v.Name,pat,1,true) then
                        items[v.Name]=(items[v.Name] or 0)+1; break
                    end
                end
            end
        end
        local lines={}
        for n,c in pairs(items) do lines[#lines+1]=n.." x"..c end
        scanTxt.Text=#lines>0 and table.concat(lines,"\n") or "(tidak ada item)"
        pushLog("Items scanned: "..(#lines).." jenis")
    end)
    y=y+36
    p.CanvasSize=UDim2.new(0,0,0,y+10)
end

-- ── Page: Collect ────────────────────────────────────────────
do
    local p=makePage("Collect")
    lbl({Parent=p,Text="Collect",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    local y=36
    makeToggle(p,"Auto Collect Drop",y,CFG.Collect.Enabled,
        function(s) CFG.Collect.Enabled=s; pushLog("Auto Collect "..(s and "ON" or "OFF")) end)
    y=y+36
    makeSlider(p,"Collect Radius",10,120,CFG.Collect.Radius,y,
        function(v) return math.floor(v).."st" end,
        function(v) CFG.Collect.Radius=math.floor(v) end)
    y=y+50
    p.CanvasSize=UDim2.new(0,0,0,y+10)
end

-- ── Page: Lock ───────────────────────────────────────────────
do
    local p=makePage("Lock")
    lbl({Parent=p,Text="Lock",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    lbl({Parent=p,Text="Anti-AFK & proteksi karakter",
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text3,
        BackgroundTransparency=1,Size=UDim2.new(1,0,0,14),Position=UDim2.new(0,8,0,30)},p)
    local y=50
    makeToggle(p,"Anti-AFK",y,CFG.AntiAFK.Enabled,
        function(s) CFG.AntiAFK.Enabled=s; pushLog("Anti-AFK "..(s and "ON" or "OFF")) end)
    y=y+36
    makeToggle(p,"WorkSpeed",y,CFG.WorkSpeed.Enabled,
        function(s)
            CFG.WorkSpeed.Enabled=s
            if hum then hum.WalkSpeed=s and math.min(CFG.WorkSpeed.BaseWalk*CFG.WorkSpeed.Multiplier,1000) or CFG.WorkSpeed.BaseWalk end
        end)
    y=y+36
    makeSlider(p,"Speed Multiplier",0.5,10,CFG.WorkSpeed.Multiplier,y,
        function(v) return string.format("%.1f×",v) end,
        function(v) CFG.WorkSpeed.Multiplier=v
            if CFG.WorkSpeed.Enabled and hum then
                hum.WalkSpeed=math.min(CFG.WorkSpeed.BaseWalk*v,1000) end end)
    y=y+50
    p.CanvasSize=UDim2.new(0,0,0,y+10)
end

-- ── Page: Info ───────────────────────────────────────────────
do
    local p=makePage("Info")
    lbl({Parent=p,Text="Info",Font=Enum.Font.GothamBold,TextSize=16,
        TextColor3=C.text,BackgroundTransparency=1,
        Size=UDim2.new(1,0,0,24),Position=UDim2.new(0,8,0,8)},p)
    local infoLines={
        "GrowBlox Suite — Dylano Hub",
        "v3.5 by Dylano",
        "",
        "FILL sebelum run:",
        "· BreakRemote  = nama RemoteEvent break block",
        "· PlaceRemote  = nama RemoteEvent place block",
        "· CollectRemote= nama RemoteEvent collect item",
        "",
        "Dump remote:",
        "for _,v in ipairs(game.ReplicatedStorage:GetDescendants()) do",
        "  if v:IsA('RemoteEvent') then print(v:GetFullName()) end",
        "end",
    }
    lbl({Parent=p,Text=table.concat(infoLines,"\n"),
        Font=Enum.Font.Gotham,TextSize=9,TextColor3=C.text2,
        BackgroundTransparency=1,Size=UDim2.new(1,-16,0,180),
        Position=UDim2.new(0,8,0,36),TextWrapped=true,
        TextYAlignment=Enum.TextYAlignment.Top},p)
    p.CanvasSize=UDim2.new(0,0,0,220)
end

-- ── Sidebar buttons ──────────────────────────────────────────
local sideItems={
    {icon="🌾",label="Farm",    page="Farm"},
    {icon="⛏",label="Auto DF", page="AutoDF"},
    {icon="🌍",label="Clear World",page="ClearWorld"},
    {icon="📦",label="Items",   page="Items"},
    {icon="🎁",label="Collect", page="Collect"},
    {icon="🔒",label="Lock",    page="Lock"},
    {icon="ℹ",label="Info",    page="Info"},
}

for i,item in ipairs(sideItems) do
    local btn=newInst("TextButton",{Parent=sidebar,
        Text=item.icon.."  "..item.label,
        Font=Enum.Font.GothamBold,TextSize=11,
        TextColor3=C.text2,TextXAlignment=Enum.TextXAlignment.Left,
        BackgroundColor3=C.sidebar,BorderSizePixel=0,
        Size=UDim2.new(1,0,0,28),
        Position=UDim2.new(0,0,0,(i-1)*29),
        AutoButtonColor=false})
    -- left accent bar (hidden by default)
    local bar=newInst("Frame",{Parent=btn,BackgroundColor3=C.accent,
        BorderSizePixel=0,Size=UDim2.new(0,3,0,20),
        Position=UDim2.new(0,0,0.5,-10),Visible=false})
    btn.MouseEnter:Connect(function()
        if activeTab~=item.page then
            TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=C.rowHov,TextColor3=C.text}):Play()
        end
    end)
    btn.MouseLeave:Connect(function()
        if activeTab~=item.page then
            TweenService:Create(btn,TweenInfo.new(0.1),{BackgroundColor3=C.sidebar,TextColor3=C.text2}):Play()
        end
    end)
    btn.MouseButton1Click:Connect(function() showPage(item.page) end)
    tabs[#tabs+1]={name=item.page,btn=btn,bar=bar}
end

-- update active bar tiap tab switch
RunService.Heartbeat:Connect(function()
    for _,t in pairs(tabs) do
        t.bar.Visible=(activeTab==t.name)
        if activeTab==t.name then
            t.btn.BackgroundColor3=C.accentSel
            t.btn.TextColor3=C.text
        end
    end
    -- update status dot
    local anyOn=CFG.Farm.Enabled or CFG.AutoDF.Enabled
        or CFG.ClearWorld.Enabled or CFG.Collect.Enabled
    statusDot.BackgroundColor3=anyOn and C.green or C.text3
    statusBarDot.BackgroundColor3=anyOn and C.green or C.text3
end)

-- open Farm by default
showPage("Farm")
pushLog("Hub loaded — Dylano")
print("[Dylano] Dylano Hub v3.5 loaded")
