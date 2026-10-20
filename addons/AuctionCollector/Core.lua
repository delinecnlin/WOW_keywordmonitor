local ADDON_NAME = ...
local AC = CreateFrame("Frame")
AuctionCollector = AuctionCollector or {}
local API = AuctionCollector

local pending = nil
local activeBatch = nil
local lastQuery = nil
local lastQueryItemId = nil
local sequence = 0
local MAX_SCANS = 200
local MAX_AUTO_PAGES = 200
local AUCTIONS_PER_PAGE = 50
local AUTO_PAGE_RETRY_SECONDS = 2
local MAX_COOLDOWN_RETRIES = 180
local SELLER_RESOLUTION_WAIT_SECONDS = 2

-- User-editable names must match the Simplified Chinese Classic Era AH names.
-- Previously listed herbs were removed; keep only the requested products/material.
local DEFAULT_WATCHLIST = {
    {name = "黑莲花", item_id = 13468},
    {name = "泰坦合剂", item_id = 13510},
    {name = "精炼智慧合剂", item_id = 13511},
    {name = "超级能量合剂", item_id = 13512},
    {name = "多重抗性合剂", item_id = 13513},
    {name = "化石合剂", item_id = 13506},
    {name = "石鳞鱼油", item_id = 13423},
}

-- Only a subsequent /reload/login can confirm WoW has reloaded SavedVariables.
local session = {
    restoredCount = 0, restoredLatest = nil, newPages = 0,
    status = "not_loaded", message = "插件尚未初始化", lastResult = nil,
    lastBatch = nil,
}

local function refreshPanel()
    if type(API.RefreshPanel) == "function" then API.RefreshPanel() end
end

local function setStatus(status, message)
    session.status = status
    session.message = message
    refreshPanel()
end

local function say(message)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff[AuctionCollector]|r " .. tostring(message))
    end
end

local function now()
    if GetServerTime then return GetServerTime() end
    return time()
end

local function copyString(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

local function getRealm()
    if GetRealmName then return GetRealmName() end
    return "UNKNOWN"
end

local function clientBuild()
    if GetBuildInfo then return select(4, GetBuildInfo()) end
    return nil
end

local function faction()
    if UnitFactionGroup then return UnitFactionGroup("player") end
    return "UNKNOWN"
end

local function supported()
    return type(QueryAuctionItems) == "function"
       and type(GetNumAuctionItems) == "function"
       and type(GetAuctionItemInfo) == "function"
       and type(CanSendAuctionQuery) == "function"
end

local function copyDefaults()
    local copy = {}
    for i, item in ipairs(DEFAULT_WATCHLIST) do
        copy[i] = {name = item.name, item_id = item.item_id}
    end
    return copy
end

local function trim(value)
    if type(value) ~= "string" then return "" end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isValidWatchItem(name, itemId)
    return type(name) == "string"
       and #name > 0 and #name <= 63
       and not name:find("[%c]")
       and type(itemId) == "number"
       and itemId >= 1 and itemId <= 2147483647
       and itemId == math.floor(itemId)
end

local function initialize()
    if type(AuctionCollectorDB) ~= "table" then AuctionCollectorDB = {} end
    if type(AuctionCollectorDB.scans) ~= "table" then AuctionCollectorDB.scans = {} end
    if type(AuctionCollectorDB.watchlist) ~= "table" then
        AuctionCollectorDB.watchlist = copyDefaults()
    else
        local cleaned = {}
        local seenNames, seenIds = {}, {}
        for _, item in ipairs(AuctionCollectorDB.watchlist) do
            local name = type(item) == "table" and trim(item.name) or ""
            local itemId = type(item) == "table" and tonumber(item.item_id) or nil
            if isValidWatchItem(name, itemId)
                and not seenNames[name] and not seenIds[itemId] then
                cleaned[#cleaned + 1] = {name = name, item_id = itemId}
                seenNames[name] = true
                seenIds[itemId] = true
            end
        end
        AuctionCollectorDB.watchlist = cleaned
    end
    AuctionCollectorDB.schema_version = 2
end

local function setBatchScanMetadata(batch, status, complete)
    for _, scan in ipairs(batch.scans) do
        scan.collection_status = status
        scan.collection_complete = complete == true
        scan.collection_page_count = #batch.scans
        scan.collection_row_count = batch.rowCount
    end
end

local function stopBatch(batch, status, message)
    if not batch or activeBatch ~= batch then return end
    setBatchScanMetadata(batch, status == "error" and "failed" or "stopped", false)
    session.lastBatch = {
        id = batch.id, query = batch.query, pages = #batch.scans,
        rows = batch.rowCount, complete = false,
    }
    activeBatch = nil
    setStatus(status, message)
    say(message)
end

local function completeBatch(batch)
    if not batch or activeBatch ~= batch then return end
    setBatchScanMetadata(batch, "complete", true)
    session.lastBatch = {
        id = batch.id, query = batch.query, pages = #batch.scans,
        rows = batch.rowCount, complete = true,
    }
    activeBatch = nil
    local message = batch.query .. " 自动采集完成：" .. tostring(#batch.scans)
        .. " 页、" .. tostring(batch.rowCount) .. " 条挂单；数据在内存中，待写盘。"
    setStatus("completed", message)
    say(message)
end

local beginPage
local function scheduleAutoRetry(batch)
    if activeBatch ~= batch or batch.stop_requested then return end
    if not C_Timer or type(C_Timer.After) ~= "function" then
        stopBatch(batch, "error", "客户端定时器不可用，自动翻页已停止。")
        return
    end
    batch.cooldownRetries = (batch.cooldownRetries or 0) + 1
    if batch.cooldownRetries > MAX_COOLDOWN_RETRIES then
        stopBatch(batch, "error", "等待拍卖行查询冷却超过 6 分钟，自动翻页已停止。")
        return
    end
    C_Timer.After(AUTO_PAGE_RETRY_SECONDS, function()
        if activeBatch ~= batch then return end
        if batch.stop_requested then
            stopBatch(batch, "stopped", batch.query .. " 自动翻页已停止；已保留已采集页面。")
            return
        end
        if pending then return end
        beginPage(batch.query, batch.nextPage, batch.item_id, batch)
    end)
end

beginPage = function(query, page, expectedItemId, batch)
    if not supported() then
        if batch then
            stopBatch(batch, "error", "客户端不支持 Legacy AH 查询接口；自动翻页停止。")
        else
            setStatus("error", "客户端不支持 Legacy AH 查询接口")
            say("此客户端未检测到 Classic QueryAuctionItems API。请记录 /ac probe 结果；尚未支持 C_AuctionHouse。")
        end
        return false
    end
    if pending then
        if batch then
            setStatus("auto_wait", "上一页仍在等待 AH 返回，自动翻页暂候。")
        else
            setStatus("pending", "上一次查询尚未返回，请勿连续触发")
            say("上一次查询仍在等待 AUCTION_ITEM_LIST_UPDATE。")
        end
        return false
    end
    if activeBatch and activeBatch ~= batch then
        setStatus("auto_wait", "当前物品正在自动翻页；请等待完成或先停止。")
        return false
    end
    if type(query) ~= "string" or #query > 63 or query == "" then
        if batch then stopBatch(batch, "error", "无效的查询名称；自动翻页停止。")
        else setStatus("error", "无效的查询名称") end
        return false
    end
    page = tonumber(page) or 0
    if page < 0 or page ~= math.floor(page) then
        if batch then stopBatch(batch, "error", "页号无效；自动翻页停止。")
        else setStatus("error", "页号必须是非负整数") end
        return false
    end

    local ok, can = pcall(CanSendAuctionQuery)
    if not ok then
        if batch then
            stopBatch(batch, "error", "读取 AH 查询冷却状态失败；自动翻页停止。")
        else
            setStatus("error", "读取 AH 查询冷却状态失败")
            say("无法读取客户端查询冷却状态；本次未发送请求。")
        end
        return false
    end
    if not can then
        if batch then
            batch.nextPage = page
            setStatus("auto_wait", "自动翻页等待 AH 查询冷却，即将查询第 " .. tostring(page + 1) .. " 页。")
            scheduleAutoRetry(batch)
        else
            setStatus("cooldown", "查询冷却中，本次未发送请求")
            say("客户端查询冷却中，未发送请求。")
        end
        return false
    end

    if batch then batch.cooldownRetries = 0 end
    sequence = sequence + 1
    local request = {
        query = query, page = page, start_ms = (GetTime and GetTime() or 0) * 1000,
        started_at = now(), sequence = sequence,
        item_id = tonumber(expectedItemId), batch = batch,
    }
    pending = request
    if batch then
        batch.nextPage = page
        setStatus("pending", "自动采集 " .. query .. "：正在查询第 " .. tostring(page + 1) .. " 页。")
    else
        setStatus("pending", "正在等待：" .. query .. " 第 " .. tostring(page + 1) .. " 页")
    end
    local queryOk, err = pcall(QueryAuctionItems, query, nil, nil, page, false, nil, false, true, nil)
    if not queryOk then
        if pending == request then pending = nil end
        if batch then
            stopBatch(batch, "error", "客户端拒绝查询：" .. tostring(err) .. "；自动翻页停止。")
        else
            setStatus("error", "查询失败：" .. tostring(err))
            say("客户端拒绝查询: " .. tostring(err))
        end
        return false
    end
    lastQuery = query
    lastQueryItemId = request.item_id
    say((batch and "已启动自动采集：" or "已发送查询：") .. query
        .. " 第 " .. tostring(page + 1) .. " 页，等待 AH 响应。")
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(30, function()
            if pending == request then
                pending = nil
                if batch then
                    stopBatch(batch, "error", "查询第 " .. tostring(page + 1)
                        .. " 页 30 秒未返回，自动翻页停止；已保留之前采集页。")
                else
                    setStatus("error", "查询 30 秒未返回，未生成扫描数据")
                    say("查询超时；请检查 AH 窗口、API 或其他拍卖插件。")
                end
            end
        end)
    end
    return true
end

local function resultHasMore(request, num, total)
    total = tonumber(total)
    if total and total >= 0 then
        local pageOffset = request.page * AUCTIONS_PER_PAGE
        if total < pageOffset then
            return nil, "AH 返回的总条目数已小于第 " .. tostring(request.page + 1) .. " 页起始位置"
        end
        local expectedRows = math.min(AUCTIONS_PER_PAGE, total - pageOffset)
        if num ~= expectedRows then
            return nil, "AH 第 " .. tostring(request.page + 1) .. " 页返回 " .. tostring(num)
                .. " 条，但总数对应应有 " .. tostring(expectedRows) .. " 条；可能在扫描期间发生变化"
        end
        return pageOffset + num < total
    end
    return num >= AUCTIONS_PER_PAGE
end

local function collect(forcePartialOwnerCapture)
    if not pending then return end
    local request = pending
    local ok, num, total = pcall(GetNumAuctionItems, "list")
    if not ok or type(num) ~= "number" then
        pending = nil
        if request.batch then
            stopBatch(request.batch, "error", "读取拍卖行列表失败；自动翻页停止，未保存本页。")
        else
            setStatus("error", "读取拍卖行列表失败；本次未保存")
            say("无法获取拍卖行列表；本次未保存。")
        end
        return
    end
    if num == 0 then
        pending = nil
        if request.batch then
            stopBatch(request.batch, "empty_result", "第 " .. tostring(request.page + 1)
                .. " 页返回 0 条，无法核对结果归属；自动翻页停止，之前页面已保留。")
        else
            -- With no rows, the shared Legacy list cannot identify which query
            -- produced the update, so show the result but do not persist it.
            setStatus("empty_result", "AH 返回 0 条；无法核对查询归属，本次未保存")
            say("AH 当前列表为 0 条；因无法核对查询归属，本次未保存空页。")
        end
        return
    end
    local rows = {}
    local invalid = 0
    local missingOwner = 0
    local missingTimeLeft = 0
    local missingInfo = 0
    local getTimeLeft = GetAuctionItemTimeLeft
    local timeLeftAPIAvailable = type(getTimeLeft) == "function"
    local mismatchedItem = false
    for index = 1, num do
        local success, name, _, count, _, _, _, _, minBid, minIncrement, buyout, currentBid,
            _, _, owner, ownerFullName, _, itemId, hasAllInfo =
            pcall(GetAuctionItemInfo, "list", index)
        if success and name then
            -- The legacy list-update event has no request ID. Fail closed if
            -- another AH search replaced our requested item's result list.
            if name ~= request.query
                or (request.item_id and tonumber(itemId) ~= request.item_id) then
                mismatchedItem = true
                invalid = invalid + 1
            else
                local seller = copyString(ownerFullName) or copyString(owner)
                if not seller then missingOwner = missingOwner + 1 end
                if hasAllInfo == false then missingInfo = missingInfo + 1 end
                local qty = tonumber(count) or 0
                local buyoutCopper = tonumber(buyout) or 0
                local timeLeftBucket
                if timeLeftAPIAvailable then
                    local timeLeftOk, value = pcall(getTimeLeft, "list", index)
                    value = timeLeftOk and tonumber(value) or nil
                    if value and value >= 1 and value <= 4 and value == math.floor(value) then
                        timeLeftBucket = value
                    else
                        missingTimeLeft = missingTimeLeft + 1
                    end
                else
                    missingTimeLeft = missingTimeLeft + 1
                end
                rows[#rows + 1] = {
                    index = index,
                    item_id = tonumber(itemId),
                    item_name = name,
                    quantity = qty,
                    buyout_copper = buyoutCopper,
                    unit_buyout_copper = (qty > 0 and buyoutCopper > 0) and math.floor(buyoutCopper / qty) or nil,
                    min_bid_copper = tonumber(minBid),
                    min_increment_copper = tonumber(minIncrement),
                    current_bid_copper = tonumber(currentBid),
                    seller_character = seller,
                    seller_missing = seller == nil,
                    has_all_info = hasAllInfo == true,
                    time_left_bucket = timeLeftBucket,
                }
            end
        else
            invalid = invalid + 1
        end
    end
    if mismatchedItem then
        pending = nil
        if request.batch then
            stopBatch(request.batch, "error", "AH 结果与请求物品不一致；自动翻页已停止，本页未保存。")
        else
            setStatus("error", "AH 当前列表与请求物品不一致；本次未保存")
            say("AH 结果列表中的物品与本次查询不一致，本次未保存；请关闭其他搜索后重试。")
        end
        return
    end
    if #rows == 0 then
        pending = nil
        if request.batch then
            stopBatch(request.batch, "error", "未能读取有效挂单；自动翻页停止，本页未保存。")
        else
            setStatus("error", "未能读取有效挂单；本次未保存")
            say("列表有挂单但插件未能读取有效数据；本次未保存。")
        end
        return
    end
    if missingOwner > 0 and not forcePartialOwnerCapture then
        if C_Timer and type(C_Timer.After) == "function" then
            if not request.ownerResolutionFallbackScheduled then
                request.ownerResolutionFallbackScheduled = true
                setStatus("resolving", "等待客户端解析卖家名称；不重发当前 AH 查询")
                say("部分卖家名称尚未解析，等待最多 " .. SELLER_RESOLUTION_WAIT_SECONDS
                    .. " 秒；不会再次查询 AH。")
                C_Timer.After(SELLER_RESOLUTION_WAIT_SECONDS, function()
                    if pending == request then collect(true) end
                end)
            end
            return
        end
    end

    local hasMore, paginationError
    if request.batch then
        hasMore, paginationError = resultHasMore(request, num, total)
    end
    pending = nil

    local end_ms = (GetTime and GetTime() or 0) * 1000
    local scan = {
        schema_version = 1,
        scan_id = tostring(now()) .. "-" .. tostring(request.sequence) .. "-" .. tostring(math.floor(end_ms)),
        observed_at = now(),
        started_at = request.started_at,
        realm = getRealm(), faction = faction(), client_build = clientBuild(),
        query = request.query, requested_item_id = request.item_id, page = request.page,
        reported_page_count = num, reported_total = tonumber(total),
        coverage = "single_page",
        complete = invalid == 0 and missingOwner == 0 and missingInfo == 0
            and #rows == num and not paginationError,
        pagination_error = paginationError,
        invalid_rows = invalid, missing_owner_rows = missingOwner, missing_info_rows = missingInfo,
        time_left_api_available = timeLeftAPIAvailable,
        missing_time_left_rows = missingTimeLeft,
        time_left_complete = missingTimeLeft == 0,
        seller_resolution_timed_out = forcePartialOwnerCapture == true and missingOwner > 0,
        duration_ms = math.max(0, math.floor(end_ms - request.start_ms)),
        rows = rows,
    }
    if request.batch then
        scan.collection_id = request.batch.id
        scan.collection_status = "in_progress"
        scan.collection_complete = false
        request.batch.reportedTotal = tonumber(total)
        request.batch.scans[#request.batch.scans + 1] = scan
        request.batch.rowCount = request.batch.rowCount + #rows
    end
    initialize()
    table.insert(AuctionCollectorDB.scans, scan)
    while #AuctionCollectorDB.scans > MAX_SCANS do
        table.remove(AuctionCollectorDB.scans, 1)
    end
    session.newPages = session.newPages + 1
    session.lastResult = scan
    local partialSellerNote = missingOwner > 0
        and ("；卖家名仍缺 " .. tostring(missingOwner) .. " 条，已标记为部分数据") or ""

    if request.batch then
        local batch = request.batch
        if paginationError then
            stopBatch(batch, "error", paginationError .. "；当前页已保存为不完整数据，自动翻页停止。")
            return
        end
        if not hasMore then
            completeBatch(batch)
            return
        end
        if batch.stop_requested then
            stopBatch(batch, "stopped", batch.query .. " 自动翻页已停止；已保留当前页和之前采集页。")
            return
        end
        if request.page + 1 >= MAX_AUTO_PAGES then
            stopBatch(batch, "stopped", batch.query .. " 已达到单次 " .. MAX_AUTO_PAGES
                .. " 页保护上限；已保留采集页，请检查 AH 返回总数。")
            return
        end
        batch.nextPage = request.page + 1
        setStatus("auto_wait", "自动翻页中：" .. batch.query .. " 已采集 "
            .. tostring(#batch.scans) .. " 页 / " .. tostring(batch.rowCount)
            .. " 条，等待查询第 " .. tostring(batch.nextPage + 1) .. " 页" .. partialSellerNote)
        scheduleAutoRetry(batch)
        return
    end

    setStatus("captured", "已采集 " .. tostring(#rows) .. " 条挂单（内存，待写盘）" .. partialSellerNote)
    say("保存 " .. tostring(#rows) .. "/" .. tostring(num)
        .. " 行，总结果 " .. tostring(total or "?") .. "；仅本页；需 /reload 或正常登出落盘。")
end

-- Read-only public API for the optional in-game status window.
function API.GetState()
    initialize()
    local expectedPages
    if activeBatch and activeBatch.reportedTotal and activeBatch.reportedTotal > 0 then
        expectedPages = math.ceil(activeBatch.reportedTotal / AUCTIONS_PER_PAGE)
    end
    return {
        status = session.status,
        message = session.message,
        pending = pending ~= nil,
        autoScanning = activeBatch ~= nil,
        autoQuery = activeBatch and activeBatch.query or nil,
        autoPage = activeBatch and (activeBatch.nextPage + 1) or nil,
        autoPagesDone = activeBatch and #activeBatch.scans or 0,
        autoRows = activeBatch and activeBatch.rowCount or 0,
        autoPagesExpected = expectedPages,
        lastBatch = session.lastBatch,
        restoredCount = session.restoredCount,
        restoredLatest = session.restoredLatest,
        newPages = session.newPages,
        totalPages = #AuctionCollectorDB.scans,
        maxPages = MAX_SCANS,
        latest = AuctionCollectorDB.scans[#AuctionCollectorDB.scans],
        lastResult = session.lastResult,
        realm = getRealm(),
        faction = faction(),
        clientBuild = clientBuild(),
        legacyAPIAvailable = supported(),
        modernAPIAvailable = type(C_AuctionHouse) == "table",
        timeLeftAPIAvailable = type(GetAuctionItemTimeLeft) == "function",
        watchlistCount = #AuctionCollectorDB.watchlist,
    }
end

function API.GetWatchlist()
    initialize()
    local copy = {}
    for i, item in ipairs(AuctionCollectorDB.watchlist) do
        copy[i] = {name = item.name, item_id = item.item_id}
    end
    return copy
end

function API.AddWatchlistItem(name, itemId)
    initialize()
    if activeBatch or pending then
        say("采集进行中，请结束或停止后再修改清单。")
        return false
    end
    name = trim(name)
    itemId = tonumber(itemId)
    if not isValidWatchItem(name, itemId) then
        say("新增失败：请填写物品名称和正整数物品 ID（名称不超过 63 字节）。")
        return false
    end
    for _, item in ipairs(AuctionCollectorDB.watchlist) do
        if item.name == name or item.item_id == itemId then
            say("新增失败：清单中已有相同名称或物品 ID。")
            return false
        end
    end
    AuctionCollectorDB.watchlist[#AuctionCollectorDB.watchlist + 1] = {
        name = name, item_id = itemId,
    }
    say("已加入采集清单：" .. name .. "（ID " .. tostring(itemId) .. "）。")
    refreshPanel()
    return true
end

function API.RemoveWatchlistItem(index)
    initialize()
    index = tonumber(index)
    if activeBatch or pending then
        say("采集进行中，请结束或停止后再修改清单。")
        return false
    end
    if not index or index ~= math.floor(index) or not AuctionCollectorDB.watchlist[index] then
        say("移除失败：清单项目序号无效。")
        return false
    end
    local removed = table.remove(AuctionCollectorDB.watchlist, index)
    say("已从清单移除：" .. removed.name .. "。历史采集记录保留。")
    refreshPanel()
    return true
end

function API.ScanWatchlistItem(index)
    initialize()
    index = tonumber(index)
    if not index or index ~= math.floor(index) or not AuctionCollectorDB.watchlist[index] then
        setStatus("error", "物品清单序号无效")
        say("物品清单序号无效；输入 /ac items 查看清单。")
        return
    end
    if pending or activeBatch then
        setStatus(activeBatch and "auto_wait" or "pending",
            "当前查询尚未完成；请等待自动翻页结束或先停止。")
        return
    end
    local item = AuctionCollectorDB.watchlist[index]
    local batch = {
        id = tostring(now()) .. "-collection-" .. tostring(sequence + 1),
        query = item.name, item_id = item.item_id,
        nextPage = 0, rowCount = 0, scans = {}, cooldownRetries = 0,
    }
    activeBatch = batch
    session.lastBatch = nil
    beginPage(item.name, 0, item.item_id, batch)
end

API.ScanLotus = function()
    initialize()
    for index, item in ipairs(AuctionCollectorDB.watchlist) do
        if item.item_id == 13468 or item.name == "黑莲花" then
            API.ScanWatchlistItem(index)
            return
        end
    end
    setStatus("error", "黑莲花已从清单移除；请先重新加入清单")
    say("黑莲花已从清单移除；请在面板填入名称和物品 ID 后重新加入。")
end

API.StopAutoScan = function()
    local batch = activeBatch
    if not batch then
        say("当前没有正在进行的自动翻页。")
        return false
    end
    batch.stop_requested = true
    if pending and pending.batch == batch then
        setStatus("stopping", "已请求停止；当前页若返回会先保存，然后停止自动翻页。")
        say("收到停止请求；不会再发送下一页查询。")
    else
        stopBatch(batch, "stopped", batch.query .. " 自动翻页已停止；已保留已采集页面。")
    end
    return true
end

API.ScanNext = function()
    if activeBatch then
        setStatus("pending", "正在自动翻页；无需手动点下一页。")
        return
    end
    if not lastQuery then
        setStatus("error", "请先从物品清单开始采集")
        say("请先点击清单中的物品。")
        return
    end
    initialize()
    local last = AuctionCollectorDB.scans[#AuctionCollectorDB.scans]
    local nextPage = 0
    if last and last.query == lastQuery and last.requested_item_id == lastQueryItemId then
        nextPage = (last.page or 0) + 1
    end
    beginPage(lastQuery, nextPage, lastQueryItemId)
end

API.Probe = function()
    say("Legacy API " .. tostring(supported())
        .. " / Auction item time-left API " .. tostring(type(GetAuctionItemTimeLeft) == "function")
        .. " / C_AuctionHouse " .. tostring(type(C_AuctionHouse) == "table")
        .. " / Realm " .. tostring(getRealm())
        .. " / Faction " .. tostring(faction()) .. " / Build " .. tostring(clientBuild()))
    refreshPanel()
end

SLASH_AUCTIONCOLLECTOR1 = "/ac"
SLASH_AUCTIONCOLLECTOR2 = "/auctioncollector"
SlashCmdList.AUCTIONCOLLECTOR = function(msg)
    local command, argument = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    if command == "" or command == "ui" or command == "show" then
        if type(API.TogglePanel) == "function" then API.TogglePanel() end
        return
    end
    if command == "probe" then
        API.Probe()
        return
    end
    if command == "status" then
        local state = API.GetState()
        say(state.message .. "；已从存档读回 " .. state.restoredCount
            .. " 页、本次新增 " .. state.newPages
            .. " 页、当前缓存 " .. state.totalPages .. "/" .. state.maxPages .. " 页。")
        if type(API.ShowPanel) == "function" then API.ShowPanel() end
        return
    end
    if command == "items" then
        for i, item in ipairs(API.GetWatchlist()) do
            say(tostring(i) .. ". " .. item.name .. "（ID " .. tostring(item.item_id) .. "）")
        end
        return
    end
    if command == "lotus" then
        API.ScanLotus()
        return
    end
    if command == "scan" then
        if argument == "" then API.ScanLotus()
        else API.ScanWatchlistItem(argument) end
        return
    end
    if command == "stop" then
        API.StopAutoScan()
        return
    end
    if command == "next" then
        API.ScanNext()
        return
    end
    if command == "page" then
        local page = tonumber(argument)
        if not page or page ~= math.floor(page) or page < 1 then
            say("用法：/ac page 1 （页码从 1 开始）")
        elseif activeBatch or pending then
            say("当前查询尚未结束，不能切换分页。")
        else
            beginPage(lastQuery or DEFAULT_WATCHLIST[1].name, page - 1,
                lastQueryItemId or DEFAULT_WATCHLIST[1].item_id)
        end
        return
    end
    if command == "clear" then
        say("为避免误删研究数据，暂不提供游戏内清空功能，请先导出并自行清理 SavedVariables。")
        return
    end
    say("命令：/ac 打开面板、/ac items、/ac scan 序号、/ac lotus、/ac stop、/ac status")
end

AC:RegisterEvent("ADDON_LOADED")
AC:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
AC:RegisterEvent("AUCTION_HOUSE_CLOSED")
AC:RegisterEvent("AUCTION_HOUSE_SHOW")
AC:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON_NAME then
        initialize()
        session.restoredCount = #AuctionCollectorDB.scans
        session.restoredLatest = AuctionCollectorDB.scans[#AuctionCollectorDB.scans]
        session.newPages = 0
        if session.restoredCount > 0 then
            setStatus("restored", "已从存档读回 " .. session.restoredCount .. " 页扫描数据")
        else
            setStatus("empty", "尚无存档数据；请打开拍卖行开始采集")
        end
        say("已加载。点击物品开始采集；自动翻页完成后按 Esc 可关闭面板。")
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        collect()
    elseif event == "AUCTION_HOUSE_SHOW" then
        if type(API.ShowPanel) == "function" then API.ShowPanel() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        local hadPending = pending ~= nil
        pending = nil
        if activeBatch then
            stopBatch(activeBatch, "stopped", "拍卖行已关闭，自动翻页停止；已采集页面保留。")
        elseif hadPending then
            setStatus("error", "拍卖行已关闭，本次查询未保存")
        end
    end
end)
