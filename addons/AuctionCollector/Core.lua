local ADDON_NAME = ...
local AC = CreateFrame("Frame")
AuctionCollector = AuctionCollector or {}
local API = AuctionCollector
local pending = nil
local lastQuery = nil
local lastQueryItemId = nil
local sequence = 0
local MAX_SCANS = 80
local SELLER_RESOLUTION_WAIT_SECONDS = 2
-- Names are the Simplified Chinese Classic Era client names. Keep item IDs
-- alongside them so a stale/shared Legacy result list cannot be mislabeled.
local WATCHLIST = {
    {name = "黑莲花", item_id = 13468},
    {name = "泰坦合剂", item_id = 13510},
    {name = "精炼智慧合剂", item_id = 13511},
    {name = "超级能量合剂", item_id = 13512},
    {name = "多重抗性合剂", item_id = 13513},
    {name = "化石合剂", item_id = 13506},
    {name = "格罗姆之血", item_id = 8846},
    {name = "石鳞鱼油", item_id = 13423},
    {name = "梦叶草", item_id = 13463},
    {name = "冰盖草", item_id = 13467},
    {name = "山鼠草", item_id = 13465},
}
-- Only a subsequent /reload/login can confirm WoW has reloaded SavedVariables.
local session = {
    restoredCount = 0, restoredLatest = nil, newPages = 0,
    status = "not_loaded", message = "插件尚未初始化", lastResult = nil,
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

local function initialize()
    if type(AuctionCollectorDB) ~= "table" then AuctionCollectorDB = {} end
    if type(AuctionCollectorDB.scans) ~= "table" then AuctionCollectorDB.scans = {} end
    AuctionCollectorDB.schema_version = 1
end

local function beginPage(query, page, expectedItemId)
    if not supported() then
        setStatus("error", "客户端不支持 Legacy AH 查询接口")
        say("此客户端未检测到 Classic QueryAuctionItems API。请记录 /ac probe 结果；尚未支持 C_AuctionHouse。")
        return
    end
    if pending then
        setStatus("pending", "上一次查询尚未返回，请勿连续触发")
        say("上一次查询仍在等待 AUCTION_ITEM_LIST_UPDATE。")
        return
    end
    if type(query) ~= "string" or #query > 63 then
        setStatus("error", "无效的查询名称")
        say("查询名称必须是 63 字节以内的字符串。")
        return
    end
    page = tonumber(page) or 0
    if page < 0 or page ~= math.floor(page) then
        setStatus("error", "页号必须是非负整数")
        say("页号必须是非负整数。")
        return
    end
    if type(CanSendAuctionQuery) == "function" then
        local ok, can = pcall(CanSendAuctionQuery)
        if not ok or not can then
            setStatus("cooldown", "查询冷却中，本次未发送请求")
            say("客户端查询冷却中，未发送请求。")
            return
        end
    end

    sequence = sequence + 1
    local request = {
        query = query, page = page, start_ms = (GetTime and GetTime() or 0) * 1000,
        started_at = now(), sequence = sequence,
        item_id = tonumber(expectedItemId),
    }
    -- Only this explicit user action submits a query. No unattended scanning.
    pending = request
    setStatus("pending", "正在等待：" .. query .. " 第 " .. tostring(page + 1) .. " 页")
    local ok, err = pcall(QueryAuctionItems, query, nil, nil, page, false, nil, false, true, nil)
    if not ok then
        if pending == request then pending = nil end
        setStatus("error", "查询失败：" .. tostring(err))
        say("客户端拒绝查询: " .. tostring(err))
        return
    end
    lastQuery = query
    lastQueryItemId = request.item_id
    say("已发送人工查询： " .. query .. " 第 " .. tostring(page + 1) .. " 页，等待 AH 响应。")
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(30, function()
            if pending == request then
                pending = nil
                setStatus("error", "查询 30 秒未返回，未生成扫描数据")
                say("查询超时；请检查 AH 窗口、API 或其他拍卖插件。")
            end
        end)
    end
end

local function collect(forcePartialOwnerCapture)
    if not pending then return end
    local request = pending
    local ok, num, total = pcall(GetNumAuctionItems, "list")
    if not ok or type(num) ~= "number" then
        pending = nil
        setStatus("error", "读取拍卖行列表失败；本次未保存")
        say("无法获取拍卖行列表；本次未保存。")
        return
    end
    if num == 0 then
        pending = nil
        -- With no rows, the shared Legacy list cannot identify which query
        -- produced the update, so show the result but do not persist it.
        setStatus("empty_result", "AH 返回 0 条；无法核对查询归属，本次未保存")
        say("AH 当前列表为 0 条；因无法核对查询归属，本次未保存空页。")
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
        setStatus("error", "AH 当前列表与请求物品不一致；本次未保存")
        say("AH 结果列表中的物品与本次查询不一致，本次未保存；请关闭其他搜索后重试。")
        return
    end
    if #rows == 0 then
        pending = nil
        setStatus("error", "未能读取有效挂单；本次未保存")
        say("列表有挂单但插件未能读取有效数据；本次未保存。")
        return
    end
    if missingOwner > 0 and not forcePartialOwnerCapture then
        if C_Timer and type(C_Timer.After) == "function" then
            if not request.ownerResolutionFallbackScheduled then
                request.ownerResolutionFallbackScheduled = true
                setStatus("resolving", "等待客户端解析卖家名称；不重发 AH 查询")
                say("部分卖家名称尚未解析，等待最多 " .. SELLER_RESOLUTION_WAIT_SECONDS
                    .. " 秒；不会再次查询 AH。")
                C_Timer.After(SELLER_RESOLUTION_WAIT_SECONDS, function()
                    if pending == request then collect(true) end
                end)
            end
            return
        end
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
        complete = invalid == 0 and missingOwner == 0 and missingInfo == 0 and #rows == num,
        invalid_rows = invalid, missing_owner_rows = missingOwner, missing_info_rows = missingInfo,
        time_left_api_available = timeLeftAPIAvailable,
        missing_time_left_rows = missingTimeLeft,
        time_left_complete = missingTimeLeft == 0,
        seller_resolution_timed_out = forcePartialOwnerCapture == true and missingOwner > 0,
        duration_ms = math.max(0, math.floor(end_ms - request.start_ms)),
        rows = rows,
    }
    initialize()
    table.insert(AuctionCollectorDB.scans, scan)
    while #AuctionCollectorDB.scans > MAX_SCANS do
        table.remove(AuctionCollectorDB.scans, 1)
    end
    session.newPages = session.newPages + 1
    session.lastResult = scan
    local partialSellerNote = missingOwner > 0
        and ("；卖家名仍缺 " .. tostring(missingOwner) .. " 条，已标记为部分数据") or ""
    setStatus("captured", "已采集 " .. tostring(#rows) .. " 条挂单（内存，待写盘）" .. partialSellerNote)
    say("保存 " .. tostring(#rows) .. "/" .. tostring(num)
        .. " 行，总结果 " .. tostring(total or "?") .. "；卖家缺失 " .. tostring(missingOwner)
        .. (scan.seller_resolution_timed_out and "（等待后仍未解析）" or "")
        .. "；仅本页，需 /reload 或正常登出落盘。")
end

-- Read-only public API for the optional in-game status window.
function API.GetState()
    initialize()
    return {
        status = session.status,
        message = session.message,
        pending = pending ~= nil,
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
    }
end

function API.GetWatchlist()
    local copy = {}
    for i, item in ipairs(WATCHLIST) do
        copy[i] = {name = item.name, item_id = item.item_id}
    end
    return copy
end

function API.ScanWatchlistItem(index)
    index = tonumber(index)
    if not index or index ~= math.floor(index) or not WATCHLIST[index] then
        setStatus("error", "物品清单序号无效")
        say("物品清单序号无效；输入 /ac items 查看清单。")
        return
    end
    local item = WATCHLIST[index]
    beginPage(item.name, 0, item.item_id)
end

API.ScanLotus = function() API.ScanWatchlistItem(1) end
API.ScanNext = function()
    if not lastQuery then
        setStatus("error", "请先扫描第一页，再手动选择下一页")
        say("请先 /ac lotus")
        return
    end
    initialize()
    local last = AuctionCollectorDB.scans[#AuctionCollectorDB.scans]
    local nextPage = 0
    if last and last.query == lastQuery then nextPage = (last.page or 0) + 1 end
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
        for i, item in ipairs(WATCHLIST) do
            say(tostring(i) .. ". " .. item.name)
        end
        return
    end
    if command == "lotus" then
        API.ScanLotus()
        return
    end
    if command == "scan" then
        if argument == "" then
            API.ScanLotus()
        else
            API.ScanWatchlistItem(argument)
        end
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
        else
            beginPage(lastQuery or WATCHLIST[1].name, page - 1,
                lastQueryItemId or WATCHLIST[1].item_id)
        end
        return
    end
    if command == "clear" then
        say("为避免误删研究数据，暂不提供游戏内清空功能，请先导出并自行清理 SavedVariables。")
        return
    end
    say("命令：/ac 打开面板、/ac items、/ac scan 序号、/ac lotus、/ac next、/ac page N、/ac status")
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
        say("已加载。输入 /ac 打开状态面板。")
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        collect()
    elseif event == "AUCTION_HOUSE_SHOW" then
        if type(API.ShowPanel) == "function" then API.ShowPanel() end
    elseif event == "AUCTION_HOUSE_CLOSED" then
        if pending then
            pending = nil
            setStatus("error", "拍卖行已关闭，本次查询未保存")
        end
    end
end)
