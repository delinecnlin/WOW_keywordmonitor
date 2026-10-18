local ADDON_NAME = ...
local AC = CreateFrame("Frame")
local pending = nil
local lastQuery = nil
local sequence = 0
local MAX_SCANS = 80
local LOTUS = "黑莲花"

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

local function beginPage(query, page)
    if not supported() then
        say("此客户端未检测到 Classic QueryAuctionItems API。请记录 /ac probe 结果；尚未支持 C_AuctionHouse。")
        return
    end
    if pending then
        say("上一次查询仍在等待 AUCTION_ITEM_LIST_UPDATE。")
        return
    end
    if type(query) ~= "string" or #query > 63 then
        say("查询名称必须是 63 字节以内的字符串。")
        return
    end
    page = tonumber(page) or 0
    if page < 0 or page ~= math.floor(page) then
        say("页号必须是非负整数。")
        return
    end
    if type(CanSendAuctionQuery) == "function" then
        local ok, can = pcall(CanSendAuctionQuery)
        if not ok or not can then
            say("客户端查询冷却中，未发送请求。")
            return
        end
    end

    sequence = sequence + 1
    local request = {
        query = query, page = page, start_ms = (GetTime and GetTime() or 0) * 1000,
        started_at = now(), sequence = sequence,
    }
    -- Query is always user-initiated. No timed retries, auto-clicks or auto-pagination.
    local ok, err = pcall(QueryAuctionItems, query, nil, nil, page, false, nil, false, true, nil)
    if not ok then
        say("客户端拒绝查询: " .. tostring(err))
        return
    end
    pending = request
    lastQuery = query
    say("已发送人工查询： " .. query .. " 第 " .. tostring(page + 1) .. " 页，等待 AH 响应。")
end

local function collect()
    if not pending then return end
    local request = pending
    pending = nil
    local ok, num, total = pcall(GetNumAuctionItems, "list")
    if not ok or type(num) ~= "number" then
        say("无法获取拍卖行列表；本次未保存。")
        return
    end
    local rows = {}
    local invalid = 0
    local missingOwner = 0
    local missingInfo = 0
    for index = 1, num do
        local success, name, _, count, _, _, _, _, minBid, minIncrement, buyout, currentBid,
            _, _, owner, ownerFullName, _, itemId, hasAllInfo =
            pcall(GetAuctionItemInfo, "list", index)
        if success and name then
            local seller = copyString(ownerFullName) or copyString(owner)
            if not seller then missingOwner = missingOwner + 1 end
            if hasAllInfo == false then missingInfo = missingInfo + 1 end
            local qty = tonumber(count) or 0
            local buyoutCopper = tonumber(buyout) or 0
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
            }
        else
            invalid = invalid + 1
        end
    end
    local end_ms = (GetTime and GetTime() or 0) * 1000
    local scan = {
        schema_version = 1,
        scan_id = tostring(now()) .. "-" .. tostring(request.sequence) .. "-" .. tostring(math.floor(end_ms)),
        observed_at = now(),
        started_at = request.started_at,
        realm = getRealm(), faction = faction(), client_build = clientBuild(),
        query = request.query, page = request.page,
        reported_page_count = num, reported_total = tonumber(total),
        coverage = "single_page",
        complete = invalid == 0 and missingInfo == 0 and #rows == num,
        invalid_rows = invalid, missing_owner_rows = missingOwner, missing_info_rows = missingInfo,
        duration_ms = math.max(0, math.floor(end_ms - request.start_ms)),
        rows = rows,
    }
    initialize()
    table.insert(AuctionCollectorDB.scans, scan)
    while #AuctionCollectorDB.scans > MAX_SCANS do
        table.remove(AuctionCollectorDB.scans, 1)
    end
    say("保存 " .. tostring(#rows) .. "/" .. tostring(num)
        .. " 行，总结果 " .. tostring(total or "?") .. "；卖家缺失 " .. tostring(missingOwner)
        .. "；仅本页，需 /reload 或正常登出落盘。")
end

SLASH_AUCTIONCOLLECTOR1 = "/ac"
SLASH_AUCTIONCOLLECTOR2 = "/auctioncollector"
SlashCmdList.AUCTIONCOLLECTOR = function(msg)
    local command, argument = tostring(msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = (command or ""):lower()
    if command == "probe" then
        say("Legacy API " .. tostring(supported())
            .. " / C_AuctionHouse " .. tostring(type(C_AuctionHouse) == "table")
            .. " / Realm " .. tostring(getRealm())
            .. " / Faction " .. tostring(faction()) .. " / Build " .. tostring(clientBuild()))
        return
    end
    if command == "status" then
        initialize()
        say("快照页数 " .. tostring(#AuctionCollectorDB.scans)
            .. " / " .. tostring(MAX_SCANS)
            .. "；正在等待 " .. tostring(pending ~= nil)
            .. "；历史保存需 /reload 或正常登出。")
        return
    end
    if command == "lotus" or command == "scan" then
        beginPage(LOTUS, 0)
        return
    end
    if command == "next" then
        if not lastQuery then say("请先 /ac lotus"); return end
        initialize()
        local last = AuctionCollectorDB.scans[#AuctionCollectorDB.scans]
        local nextPage = 0
        if last and last.query == lastQuery then nextPage = (last.page or 0) + 1 end
        beginPage(lastQuery, nextPage)
        return
    end
    if command == "page" then
        local page = tonumber(argument)
        if not page or page ~= math.floor(page) or page < 1 then
            say("用法：/ac page 1 （页码从 1 开始）")
        else
            beginPage(lastQuery or LOTUS, page - 1)
        end
        return
    end
    if command == "clear" then
        say("为避免误删研究数据，暂不提供游戏内清空功能，请先导出并自行清理 SavedVariables。")
        return
    end
    say("命令：/ac probe、/ac lotus、/ac next、/ac page N、/ac status")
end

AC:RegisterEvent("ADDON_LOADED")
AC:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
AC:RegisterEvent("AUCTION_HOUSE_CLOSED")
AC:SetScript("OnEvent", function(self, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON_NAME then
        initialize()
        say("已加载（测试版）；在拍卖师窗口手动输入 /ac probe 或 /ac lotus。")
    elseif event == "AUCTION_ITEM_LIST_UPDATE" then
        collect()
    elseif event == "AUCTION_HOUSE_CLOSED" then
        pending = nil
    end
end)
