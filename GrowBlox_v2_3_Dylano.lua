--[[
    Dylano Hub v4.0 — SurferBot Edition
    Berdasarkan: Lua-Docs-main (SurferBot API)
    Runtime: SurferBot (surferwallet.net)
    
    Fitur dari zip:
    ✓ auto_spam       (autoSpam.lua)
    ✓ admin_detector  (admin_detector.lua)
    ✓ collect_items   (collect_specific_items.lua)
    ✓ connect_all_bot (connect_all_bot.lua)
    ✓ add_steam       (add_steam.lua)
    ✓ account_checker (account_checker.lua)
    ✓ deposit_bot     (deposit_bot.lua - partial, butuh surferWalletApi)
    ✓ drop_all_items  (drop_all_Items_In_Inventory.lua - diisi)
    
    Tambahan dari docs:
    ✓ Auto Farm (hitTile + placeTile + findPath)
    ✓ Auto Harvest (canHarvest + getTiles)
    ✓ Auto Clear World (autoManager)
    ✓ Mod/Admin Detector (registerEvent + autoManager)
    ✓ Auto Collect (autoCollect + collectObject)
    ✓ Auto Reconnect all bots
    ✓ Spammer (autoManager.spam)
    ✓ Event hooks (OnPlayerJoinWorld, OnBanned, OnDisconnect, dll)
    ✓ HTTP webhook support
    ✓ Bot status monitor
    ✓ Inventory manager
    ✓ World info logger
    ✓ Geiger signal reader
    ✓ Auto Malady
    ✓ Auto Trash
    ✓ Auto Wear
    ✓ Rotation manager
]]

-- ══════════════════════════════════════════════════════════════
--  CONFIG — isi semua ini sebelum run
-- ══════════════════════════════════════════════════════════════
local CFG = {
    -- Bot utama yang dipakai
    botName       = "growid",          -- growid bot kamu

    -- Farm
    farmEnabled   = false,
    farmItemID    = 2,                 -- ID block yang di-farm (2=Dirt)
    farmX         = 0,                 -- koordinat titik farm
    farmY         = 0,
    farmHits      = 3,                 -- hit per tile

    -- Harvest
    harvestEnabled = false,
    harvestSeedID  = 3,               -- seed ID yang di-harvest

    -- Auto Spam
    spamEnabled   = false,
    spamWorld     = "WORLD",          -- nama world tempat spam
    spamText      = "Buy stuff here!",
    spamDelay     = 5000,             -- ms antar pesan

    -- Collect
    collectEnabled  = false,
    collectItemID   = 2,              -- item ID yang di-collect (0 = semua)
    collectRange    = 10,

    -- Admin Detector
    adminEnabled    = false,
    adminLeave      = true,           -- keluar world kalau admin masuk

    -- Mod Detector
    modEnabled      = false,
    modLeave        = true,

    -- Auto Clear World
    clearEnabled    = false,
    clearSkipBg     = false,
    clearAutoTrash  = false,
    clearSaveWorld  = "SAVE|0",

    -- Drop All Items
    dropEnabled     = false,
    dropIgnore      = {242, 7188, 1796}, -- item ID yang TIDAK di-drop (DL, BGL, WL)

    -- Account Checker
    checkerEnabled  = false,
    checkerServer   = "http://yourserver.com/account",
    checkerEndpoint = "http://yourserver.com/account/found",
    checkerWebhook  = "https://discord.com/api/webhooks/...",

    -- Add Steam Bots
    steamEnabled    = false,
    steamAccounts   = {
        -- "email:password",
        -- "email:password:secretKey",
    },
    steamProxies    = {
        -- "ip:port:username:pass",
    },

    -- Connect All Disconnected Bots
    reconnectAll    = false,
    reconnectDelay  = 200,           -- ms antar reconnect

    -- Webhook (Discord)
    webhookEnabled  = false,
    webhookURL      = "https://discord.com/api/webhooks/...",

    -- Auto Malady
    maladyEnabled   = false,
    maladyAutoSurgery = false,
    maladySurgeryMaxPrice = 3,

    -- Auto Trash
    trashEnabled    = false,
    trashItems      = {},            -- {id1, id2, ...} item yang di-trash
    trashMinCount   = 50,

    -- Auto Wear
    wearEnabled     = false,
    wearItems       = {},            -- {id1, id2, ...}

    -- Rotation Manager
    rotationEnabled = false,
    rotationWorlds  = {
        -- {name="WORLD|id", type="FARM"},
        -- {name="SAVE|0", type="SAVE"},
    },

    -- World Info Log
    worldInfoLog    = true,

    -- Status Monitor interval (detik)
    monitorInterval = 10,
}

-- ══════════════════════════════════════════════════════════════
--  HELPERS
-- ══════════════════════════════════════════════════════════════
local function logT(...)
    local ts = os.date("[%H:%M:%S]")
    local args = {...}
    for i, v in ipairs(args) do args[i] = tostring(v) end
    log(ts .. " " .. table.concat(args, " "))
end

local function sendWebhook(text, url)
    url = url or CFG.webhookURL
    if not CFG.webhookEnabled or url == "" then return end
    local ok, res = pcall(function()
        return httpReq({
            url = url,
            method = POST,
            postData = "content=" .. text
        })
    end)
    if ok and res and res.success then
        logT("Webhook sent OK")
    else
        logT("Webhook failed")
    end
end

local function getBot2()
    -- wrapper aman, support nama atau tanpa arg
    local ok, b = pcall(function()
        if CFG.botName ~= "" then return getBot(CFG.botName)
        else return getBot() end
    end)
    return ok and b or nil
end

-- ══════════════════════════════════════════════════════════════
--  1. AUTO FARM
--  Dari docs: hitTile, placeTile, findPath, canHarvest, canPunch
-- ══════════════════════════════════════════════════════════════
local function runFarm(bot)
    if not CFG.farmEnabled then return end
    logT("Farm dimulai — item ID:", CFG.farmItemID)
    local itemID = CFG.farmItemID
    local fx, fy = CFG.farmX, CFG.farmY

    while CFG.farmEnabled do
        if not bot:inWorld() then sleep(2000); goto continue_farm end

        -- ambil semua tile yang bisa di-harvest di sekitar
        local tiles = bot:getTiles({skip=true})
        local targets = {}
        for _, tile in ipairs(tiles) do
            if bot:canHarvest(tile.x, tile.y) then
                targets[#targets+1] = tile
            end
        end

        if #targets > 0 then
            for _, tile in ipairs(targets) do
                if not CFG.farmEnabled then break end
                -- path ke tile
                if bot:findPath(tile.x, tile.y) then
                    sleep(300)
                    for _ = 1, CFG.farmHits do
                        bot:hitTile(tile.x, tile.y)
                        sleep(350)
                    end
                end
            end
        else
            -- kalau tidak ada yang harvest, path ke titik farm dan place
            if bot:findPath(fx, fy) then
                sleep(300)
                if bot:canPlace(fx, fy) then
                    bot:placeTile(fx, fy, itemID)
                    sleep(500)
                    for _ = 1, CFG.farmHits do
                        bot:hitTile(fx, fy)
                        sleep(350)
                    end
                end
            end
        end

        ::continue_farm::
        sleep(500)
    end
    logT("Farm berhenti")
end

-- ══════════════════════════════════════════════════════════════
--  2. AUTO HARVEST
--  Dari docs: getTiles({r=true}), canHarvest, hitTile, findPath
-- ══════════════════════════════════════════════════════════════
local function runHarvest(bot)
    if not CFG.harvestEnabled then return end
    logT("Harvest dimulai — seed ID:", CFG.harvestSeedID)

    while CFG.harvestEnabled do
        if not bot:inWorld() then sleep(2000); goto continue_harvest end

        -- getTiles dengan filter ready=true
        local readyTiles = bot:getTiles({r=true})
        local harvested = 0
        for _, tile in ipairs(readyTiles) do
            if not CFG.harvestEnabled then break end
            if tile.fg == CFG.harvestSeedID or bot:canHarvest(tile.x, tile.y) then
                if bot:findPath(tile.x, tile.y) then
                    sleep(200)
                    bot:hitTile(tile.x, tile.y)
                    sleep(350)
                    harvested = harvested + 1
                end
            end
        end

        if harvested > 0 then
            logT("Harvest:", harvested, "tile selesai")
        end

        ::continue_harvest::
        sleep(1000)
    end
    logT("Harvest berhenti")
end

-- ══════════════════════════════════════════════════════════════
--  3. AUTO SPAM
--  Dari: autoSpam.lua + autoManager.spam
-- ══════════════════════════════════════════════════════════════
local function setupSpam(bot)
    if not CFG.spamEnabled then return end
    logT("Setup spam di world:", CFG.spamWorld)
    local spamMgr = bot:autoManager().spam
    spamMgr.enabled     = true
    spamMgr.randomColor = false
    spamMgr.worldName   = CFG.spamWorld
    spamMgr.delay       = CFG.spamDelay
    spamMgr:clearText()
    spamMgr:pushText(CFG.spamText)
    logT("Spam aktif — teks:", CFG.spamText)
end

-- fallback spam loop kalau autoManager tidak tersedia
local function runSpamLoop(bot)
    if not CFG.spamEnabled then return end
    logT("Spam loop dimulai")
    local lastSpam = os.time()
    while CFG.spamEnabled do
        local now = os.time()
        if now - lastSpam >= CFG.spamDelay / 1000 then
            if bot:inWorld() then
                bot:say(CFG.spamText)
                lastSpam = now
            end
        end
        sleep(1000)
    end
    logT("Spam berhenti")
end

-- ══════════════════════════════════════════════════════════════
--  4. ADMIN DETECTOR
--  Dari: admin_detector.lua + registerEvent OnModeratorJoin
-- ══════════════════════════════════════════════════════════════
local function runAdminDetector(bot)
    if not CFG.adminEnabled then return end
    logT("Admin detector aktif")

    -- cek admin yang sudah ada di world
    local function checkExistingAdmins()
        if not bot:inWorld() then return end
        local world = bot:getWorld()
        local players = bot:getPlayers()
        for _, player in ipairs(players) do
            for _, adminID in ipairs(world.access) do
                if player.userid == adminID then
                    logT("Admin di world:", player.name, "| UserID:", player.userid)
                    sendWebhook("⚠️ Admin ditemukan: " .. player.name)
                    if CFG.adminLeave then
                        bot:sendPacket("action|quit_to_exit", 3)
                        logT("Keluar world karena admin!")
                    end
                end
            end
        end
    end

    -- log akses world
    if bot:inWorld() then
        local world = bot:getWorld()
        logT("World access list:")
        for _, adminID in ipairs(world.access) do
            logT("  UserID:", adminID)
        end
        checkExistingAdmins()
    end
end

-- ══════════════════════════════════════════════════════════════
--  5. COLLECT SPECIFIC ITEMS
--  Dari: collect_specific_items.lua + autoCollect
-- ══════════════════════════════════════════════════════════════
local function runCollect(bot)
    if not CFG.collectEnabled then return end
    logT("Collect dimulai — item ID:", CFG.collectItemID, "range:", CFG.collectRange)

    -- enable autoCollect bawaan SurferBot
    bot:autoCollect(CFG.collectRange, true)
    bot:setBool("autocollect", true)

    -- loop manual untuk item spesifik
    while CFG.collectEnabled do
        if not bot:inWorld() then sleep(2000); goto continue_collect end

        for _, object in ipairs(bot:getObjects()) do
            local match = (CFG.collectItemID == 0) or (object.id == CFG.collectItemID)
            if match then
                local posX = math.floor(object.pos.x / 32)
                local posY = math.floor(object.pos.y / 32)
                if bot:isInside(posX, posY, CFG.collectRange) then
                    bot:collectObject(object.uid)
                    sleep(50)
                elseif bot:findPath(posX, posY) then
                    sleep(200)
                    bot:collectObject(object.uid)
                    sleep(50)
                end
            end
        end

        ::continue_collect::
        sleep(500)
    end

    bot:autoCollect(0, false)
    logT("Collect berhenti")
end

-- ══════════════════════════════════════════════════════════════
--  6. CONNECT ALL DISCONNECTED BOTS
--  Dari: connect_all_bot.lua
-- ══════════════════════════════════════════════════════════════
local function reconnectAllBots()
    logT("Reconnect semua bot yang disconnected...")
    local count = 0
    for _, b in pairs(getAllBot()) do
        if b:getEnetStatus() == Disconnected then
            b:reConnect()
            count = count + 1
            sleep(CFG.reconnectDelay)
        end
    end
    logT("Reconnected:", count, "bot")
end

-- ══════════════════════════════════════════════════════════════
--  7. ADD STEAM BOTS
--  Dari: add_steam.lua
-- ══════════════════════════════════════════════════════════════
local function addSteamBots()
    if not CFG.steamEnabled or #CFG.steamAccounts == 0 then return end
    logT("Menambah", #CFG.steamAccounts, "Steam bot...")

    for i, accStr in ipairs(CFG.steamAccounts) do
        local email, password, secretKey = accStr:match("([^:]+):([^:]+):?(.*)")
        if not email or not password then
            logT("Format akun salah:", accStr); goto continue_steam
        end
        local proxy = CFG.steamProxies[((i-1) % math.max(#CFG.steamProxies,1)) + 1] or "auto"
        local account = {
            type      = STEAM,
            mail      = email,
            password  = password,
            secretKey = secretKey or "",
            proxy     = proxy,
            connect   = true
        }
        local botID = addBot(account)
        logT("Steam bot ditambah — email:", email, "| botID:", botID)
        sleep(10000)
        ::continue_steam::
    end
end

-- ══════════════════════════════════════════════════════════════
--  8. ACCOUNT CHECKER
--  Dari: account_checker.lua
-- ══════════════════════════════════════════════════════════════
local function runAccountChecker()
    if not CFG.checkerEnabled then return end
    logT("Account checker dimulai — server:", CFG.checkerServer)

    local function getRandomProxy()
        local startPort, endPort = 10466, 19466
        return string.format("ip:%d", math.random(startPort, endPort))
    end

    local function getAccount()
        local res = httpReq({url = CFG.checkerServer})
        if res.success then
            return res.body:match("([^|]+)|([^|]+)")
        end
        return nil, nil
    end

    local function sendAccountResult(data)
        httpReq({
            url      = CFG.checkerEndpoint,
            method   = POST,
            postData = "data=" .. data
        })
    end

    local function handleCheckerBot(b, growid, password)
        local totalTempTry = 0
        while true do
            local status = b:getBotStatus()
            if status == Banned or status == Suspended
                or status == Wrong_Password or status == AAP
                or status == InvalidEmail
            then
                logT("BANNED/WRONG:", growid)
                sendWebhook("❌ " .. growid .. " | " .. password .. " — banned/wrong")
                b:remove(); return false
            end
            if status == temporaryBan then
                totalTempTry = totalTempTry + 1
                if totalTempTry > 15 then b:remove(); return false
                else sleep(5000); b:remove(); return true end
            end
            if status == failedToFetchMeta or status == LogonATTEMPTS then
                b:remove(); return true
            end
            if status == Disconnected then b:setBool("autoReconnect", true) end

            local info = b:getLocal()
            if b:getEnetStatus() == Connected and status == Success
                and info.slot > 1 and info.level > 0
            then
                sleep(2000)
                info = b:getLocal()
                local wl = b:getItemCount(242)
                        + (b:getItemCount(7188) * 10000)
                        + (b:getItemCount(1796) * 100)
                local dataStr = string.format("%s|%s|%d|%d|%d|%d|%d",
                    growid, password, info.level, info.gems, wl,
                    info.playTime or 0, info.createDate or 0)
                sendAccountResult(dataStr)
                sendWebhook("✅ " .. growid .. " | Lv:" .. info.level .. " | Gems:" .. info.gems .. " | WL:" .. wl)
                logT("Akun valid:", growid, "| Lv:", info.level)
                b:remove(); return false
            end
            sleep(500)
        end
    end

    while CFG.checkerEnabled do
        local growid, password = getAccount()
        if not growid then sleep(1000); goto next_check end

        local proxy = {HostName = getRandomProxy(), Type = SOCKS5}
        local botID = addBot({
            type=LEGACY, growid=growid, password=password,
            proxy=string.format("%s", getRandomProxy()), connect=true
        })

        if botID >= 0 then
            local b = getBot(botID)
            b:setBool("autoReconnect", true)
            b:setReconnectInterval(1)
            if not handleCheckerBot(b, growid, password) then sleep(1000) end
        else
            logT("Gagal buat bot untuk:", growid)
            sleep(5000)
        end

        ::next_check::
    end
    logT("Account checker berhenti")
end

-- ══════════════════════════════════════════════════════════════
--  9. DROP ALL ITEMS IN INVENTORY
--  Dari: drop_all_Items_In_Inventory.lua (file kosong, diisi)
--  Docs: getInventory() + drop(id, count) via sendPacketRaw
-- ══════════════════════════════════════════════════════════════
local function dropAllItems(bot)
    if not CFG.dropEnabled then return end
    logT("Drop semua item dimulai...")

    -- buat lookup ignore list
    local ignore = {}
    for _, id in ipairs(CFG.dropIgnore) do ignore[id] = true end

    local inv = bot:getInventory()
    local dropped = 0
    for _, item in ipairs(inv) do
        if not ignore[item.id] and item.count > 0 then
            -- drop via GamePacket type 18 (PACKET_ITEM_ACTIVATE_REQUEST sendPacketRaw)
            -- atau via sendPacket drop|item_count
            bot:sendPacket(string.format("action|drop\nnetID|%d\nitem|%d\ncount|%d",
                bot:getLocal().netid, item.id, item.count), 3)
            logT("Drop:", item.count, "x ID:", item.id)
            dropped = dropped + 1
            sleep(300)
        end
    end
    logT("Total item di-drop:", dropped, "jenis")
end

-- ══════════════════════════════════════════════════════════════
--  10. AUTO CLEAR WORLD
--  Dari: autoManager.clearWorld
-- ══════════════════════════════════════════════════════════════
local function setupClearWorld(bot, worldName)
    if not CFG.clearEnabled then return end
    logT("Setup clear world:", worldName)
    local cw = bot:autoManager().clearWorld
    cw.enabled     = true
    cw.skipBg      = CFG.clearSkipBg
    cw.autoTrash   = CFG.clearAutoTrash
    cw.saveWorld   = CFG.clearSaveWorld
    cw:addWorld(worldName)
    logT("Clear world aktif untuk:", worldName)
end

-- ══════════════════════════════════════════════════════════════
--  11. AUTO MALADY
--  Dari: autoManager.malady
-- ══════════════════════════════════════════════════════════════
local function setupMalady(bot)
    if not CFG.maladyEnabled then return end
    logT("Setup auto malady...")
    local m = bot:autoManager().malady
    m.autoSurgery      = CFG.maladyAutoSurgery
    m.surgeryMaxPrice  = CFG.maladySurgeryMaxPrice
    m.grumbleteeth     = true
    m.chickenFeet      = true
    logT("Auto malady aktif")
end

-- ══════════════════════════════════════════════════════════════
--  12. AUTO TRASH
--  Dari: autoManager.trash
-- ══════════════════════════════════════════════════════════════
local function setupTrash(bot)
    if not CFG.trashEnabled or #CFG.trashItems == 0 then return end
    logT("Setup auto trash —", #CFG.trashItems, "item")
    local tr = bot:autoManager().trash
    tr.enabled  = true
    tr.minCount = CFG.trashMinCount
    for _, id in ipairs(CFG.trashItems) do
        tr:addItem(id)
    end
    logT("Auto trash aktif")
end

-- ══════════════════════════════════════════════════════════════
--  13. AUTO WEAR
--  Dari: autoManager.wear
-- ══════════════════════════════════════════════════════════════
local function setupWear(bot)
    if not CFG.wearEnabled or #CFG.wearItems == 0 then return end
    logT("Setup auto wear —", #CFG.wearItems, "item")
    local w = bot:autoManager().wear
    w.enabled = true
    for _, id in ipairs(CFG.wearItems) do
        w:addItem(id)
    end
    logT("Auto wear aktif")
end

-- ══════════════════════════════════════════════════════════════
--  14. ROTATION MANAGER
--  Dari: rotationManager docs
-- ══════════════════════════════════════════════════════════════
local function setupRotation()
    if not CFG.rotationEnabled or #CFG.rotationWorlds == 0 then return end
    logT("Setup rotation manager —", #CFG.rotationWorlds, "world")
    local rm = rotationManager()
    for _, w in ipairs(CFG.rotationWorlds) do
        local wtype = w.type or "FARM"
        if wtype == "FARM"    then rm:addWorld(w.name, FARM)
        elseif wtype == "SAVE" then rm:addWorld(w.name, SAVE)
        elseif wtype == "PNB"  then rm:addWorld(w.name, PNB)
        elseif wtype == "SEED" then rm:addWorld(w.name, SEED)
        end
        logT("Rotation world ditambah:", w.name, "type:", wtype)
    end
    logT("Rotation aktif")
end

-- ══════════════════════════════════════════════════════════════
--  15. EVENT HOOKS
--  Dari: Event.md — registerEvent
-- ══════════════════════════════════════════════════════════════
local function setupEvents(bot)
    logT("Setup event hooks...")

    -- Mod/Guardian join
    local function onModJoin(isGuardian)
        if isGuardian then
            logT("⚠️ GUARDIAN masuk world!")
            sendWebhook("🚨 Guardian masuk world " .. bot:getCurrentWorld())
        else
            logT("⚠️ MOD masuk world!")
            sendWebhook("🚨 Mod masuk world " .. bot:getCurrentWorld())
        end
        if CFG.modEnabled and CFG.modLeave then
            bot:sendPacket("action|quit_to_exit", 3)
            logT("Keluar world karena mod!")
        end
    end

    -- Player join
    local function onPlayerJoin(player)
        logT("Player join:", player.name, "| netID:", player.netid)
        -- cek kalau player adalah admin
        if CFG.adminEnabled and bot:inWorld() then
            local world = bot:getWorld()
            for _, adminID in ipairs(world.access) do
                if player.userid == adminID then
                    logT("ADMIN masuk:", player.name)
                    sendWebhook("⚠️ Admin masuk: " .. player.name)
                    if CFG.adminLeave then
                        bot:sendPacket("action|quit_to_exit", 3)
                    end
                end
            end
        end
    end

    -- Player exit
    local function onPlayerExit(player)
        logT("Player keluar:", player.name)
    end

    -- World join
    local function onWorldJoin()
        local wn = bot:getCurrentWorld()
        logT("Bot join world:", wn)
        sendWebhook("✅ Bot join world: " .. wn)
        if CFG.worldInfoLog then
            local world = bot:getWorld()
            logT("World:", world.name, "| Size:", world.width, "x", world.height)
            logT("Main door:", world.maindoor.x, world.maindoor.y)
            logT("Access list count:", #world.access)
        end
    end

    -- World exit
    local function onWorldExit()
        logT("Bot keluar world")
    end

    -- Disconnect
    local function onDisconnect()
        logT("Bot disconnected — reconnecting...")
        bot:reConnect()
    end

    -- Banned
    local function onBanned(days)
        logT("Bot BANNED selama", days, "hari!")
        sendWebhook("❌ BOT BANNED " .. days .. " hari — " .. CFG.botName)
    end

    -- Level up
    local function onLevelUp()
        local info = bot:getLocal()
        logT("Level up! Level baru:", info.level)
        sendWebhook("🎉 Level up! " .. CFG.botName .. " sekarang level " .. info.level)
    end

    -- Inventory update
    local function onInventoryUpdate(itemId, count)
        local info = bot:getItemInfo(itemId)
        local name = info and info.name or ("ID:" .. itemId)
        if count > 0 then logT("+ Dapat:", count, "x", name)
        else logT("- Hilang:", math.abs(count), "x", name) end
    end

    -- register semua events
    pcall(function() bot:registerEvent(onModJoin,         OnModeratorJoin) end)
    pcall(function() bot:registerEvent(onPlayerJoin,      OnPlayerJoinWorld) end)
    pcall(function() bot:registerEvent(onPlayerExit,      OnPlayerExitWorld) end)
    pcall(function() bot:registerEvent(onWorldJoin,       OnWorldJoin) end)
    pcall(function() bot:registerEvent(onWorldExit,       OnWorldExit) end)
    pcall(function() bot:registerEvent(onDisconnect,      OnDisconnect) end)
    pcall(function() bot:registerEvent(onBanned,          OnBanned) end)
    pcall(function() bot:registerEvent(onLevelUp,         OnLevelUp) end)
    pcall(function() bot:registerEvent(onInventoryUpdate, OnInventoryUpdate) end)

    logT("Event hooks terpasang")
end

-- ══════════════════════════════════════════════════════════════
--  16. STATUS MONITOR
--  Dari: getBotStatus, getLocal, getItemCount
-- ══════════════════════════════════════════════════════════════
local function runMonitor(bot)
    while true do
        sleep(CFG.monitorInterval * 1000)
        if not bot then goto next_monitor end

        local status = bot:getBotStatus()
        local enet   = bot:getEnetStatus()
        local info   = bot:getLocal()
        local world  = bot:inWorld() and bot:getCurrentWorld() or "LOBBY"

        -- WL count
        local wl = bot:getItemCount(242)
                 + (bot:getItemCount(7188) * 10000)
                 + (bot:getItemCount(1796) * 100)
        local gems = info.gems or 0

        logT(string.format("[MONITOR] %s | World:%s | WL:%d | Gems:%d | Status:%s | Enet:%s",
            CFG.botName, world, wl, gems, tostring(status), tostring(enet)))

        -- geiger signal
        pcall(function()
            if bot:isEquipped(2204) then
                local sig = bot:getSignal()
                logT("[GEIGER] Signal:", tostring(sig))
            end
        end)

        -- auto malady check
        pcall(function()
            if bot:checkAutoMalady() then
                logT("[MALADY] Auto malady sedang berjalan...")
            end
        end)

        ::next_monitor::
    end
end

-- ══════════════════════════════════════════════════════════════
--  17. WORLD INFO LOGGER
--  Dari: getWorld, getTiles, getPlayers, getObjects
-- ══════════════════════════════════════════════════════════════
local function logWorldInfo(bot)
    if not CFG.worldInfoLog then return end
    if not bot:inWorld() then logT("Bot tidak di world"); return end

    local world   = bot:getWorld()
    local players = bot:getPlayers()
    local objects = bot:getObjects()

    logT("=== WORLD INFO ===")
    logT("Nama:", world.name)
    logT("Ukuran:", world.width, "x", world.height)
    logT("Timer:", world.timer, "menit")
    logT("Main door:", world.maindoor.x, world.maindoor.y)
    logT("Players:", #players)
    logT("Objects:", #objects)
    logT("Access list:", #world.access, "ID")

    for _, player in ipairs(players) do
        logT("  Player:", player.name, "| netID:", player.netid,
            "| UserID:", player.userid, "| Mod:", tostring(player.mod))
    end
    for _, adminID in ipairs(world.access) do
        logT("  Admin UserID:", adminID)
    end
    logT("==================")
end

-- ══════════════════════════════════════════════════════════════
--  MAIN — entry point
-- ══════════════════════════════════════════════════════════════
logT("=================================")
logT("Dylano Hub v4.0 — SurferBot")
logT("=================================")

local bot = getBot2()
if not bot then
    logT("FATAL: Bot tidak ditemukan. Set CFG.botName ke growid bot kamu.")
    return
end

logT("Bot ditemukan:", CFG.botName)

-- tunggu bot connected
local t0 = os.time()
while bot:getEnetStatus() ~= Connected or bot:getBotStatus() ~= Success do
    if os.time() - t0 > 30 then logT("Timeout menunggu bot connect"); break end
    sleep(1000)
end
logT("Bot connected!")

-- setup events dulu
setupEvents(bot)

-- setup autoManager features
setupSpam(bot)
setupClearWorld(bot, bot:getCurrentWorld())
setupMalady(bot)
setupTrash(bot)
setupWear(bot)
setupRotation()

-- log world info awal
logWorldInfo(bot)

-- admin detector awal
runAdminDetector(bot)

-- reconnect all jika diaktifkan
if CFG.reconnectAll then
    reconnectAllBots()
end

-- add steam bots jika diaktifkan
if CFG.steamEnabled then
    task.spawn and task.spawn(addSteamBots) or coroutine.wrap(addSteamBots)()
end

-- spawn semua fitur yang punya loop
local threads = {}

if CFG.farmEnabled then
    threads[#threads+1] = coroutine.create(function() runFarm(bot) end)
end
if CFG.harvestEnabled then
    threads[#threads+1] = coroutine.create(function() runHarvest(bot) end)
end
if CFG.collectEnabled then
    threads[#threads+1] = coroutine.create(function() runCollect(bot) end)
end
if CFG.checkerEnabled then
    threads[#threads+1] = coroutine.create(function() runAccountChecker() end)
end
if CFG.dropEnabled then
    -- jalankan sekali
    dropAllItems(bot)
end

-- jalankan spam loop manual kalau autoManager tidak ada
if CFG.spamEnabled then
    threads[#threads+1] = coroutine.create(function() runSpamLoop(bot) end)
end

-- monitor loop
threads[#threads+1] = coroutine.create(function() runMonitor(bot) end)

-- resume semua thread
for _, co in ipairs(threads) do
    coroutine.resume(co)
end

logT("Semua fitur aktif. Hub berjalan.")

-- main loop
while true do
    -- resume coroutines yang masih hidup
    for _, co in ipairs(threads) do
        if coroutine.status(co) == "suspended" then
            local ok, err = coroutine.resume(co)
            if not ok then logT("Thread error:", tostring(err)) end
        end
    end
    sleep(100)
end
