-- AuctionCollector dashboard and editable watchlist.
-- Each scan is started by an explicit user click; only pages for that item auto-continue.
local API = AuctionCollector
if type(API) ~= "table" then return end

local MIN_PANEL_HEIGHT = 680
local MAX_PANEL_HEIGHT = 910
local panelHeight = MAX_PANEL_HEIGHT
local panelTopInset = 20
if UIParent and type(UIParent.GetHeight) == "function" then
    local availableHeight = tonumber(UIParent:GetHeight())
    if availableHeight and availableHeight > 0 then
        panelHeight = math.min(MAX_PANEL_HEIGHT, math.max(MIN_PANEL_HEIGHT, availableHeight - 20))
        panelTopInset = math.min(20, math.max(0, (availableHeight - panelHeight) / 2))
    end
end
local watchlistHeight = math.max(28, panelHeight - 670)

local panel = CreateFrame("Frame", "AuctionCollectorStatusPanel", UIParent)
panel:SetSize(620, panelHeight)
panel:SetPoint("TOP", UIParent, "TOP", 0, -panelTopInset)
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

-- WoW closes the top matching special frame on Escape.
UISpecialFrames = UISpecialFrames or {}
local escapeRegistered = false
for _, frameName in ipairs(UISpecialFrames) do
    if frameName == "AuctionCollectorStatusPanel" then escapeRegistered = true end
end
if not escapeRegistered then
    UISpecialFrames[#UISpecialFrames + 1] = "AuctionCollectorStatusPanel"
end

local bg = panel:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(panel)
bg:SetColorTexture(0.065, 0.10, 0.16, 0.97)

local border = CreateFrame("Frame", nil, panel)
border:SetAllPoints(panel)
if border.SetBackdrop then
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 15,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    border:SetBackdropBorderColor(0.25, 0.54, 0.78, 0.9)
end

local function textLine(name, x, y, width, height, font)
    local value = panel:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    value:SetSize(width, height)
    value:SetJustifyH("LEFT")
    value:SetJustifyV("TOP")
    value:SetWordWrap(true)
    return value
end

local function divider(y)
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, y)
    line:SetSize(580, 1)
    line:SetColorTexture(0.23, 0.36, 0.52, 0.7)
end

local function button(parent, label, width, height)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, height)
    b:SetText(label)
    return b
end

local title = textLine("title", 20, -18, 540, 26, "GameFontNormalLarge")
title:SetText("|cff79c6ffAuctionCollector|r  |cff9eb7d2· 国服拍卖信息采集|r")
local subtitle = textLine("subtitle", 20, -49, 570, 20)
subtitle:SetText("点选一个物品开始采集；插件自动翻完该物品分页，不会自动切换其他物品")

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

local statusBg = panel:CreateTexture(nil, "ARTWORK")
statusBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -78)
statusBg:SetSize(580, 75)
statusBg:SetColorTexture(0.1, 0.16, 0.23, 0.98)

local dot = panel:CreateTexture(nil, "OVERLAY")
dot:SetSize(12, 12)
dot:SetPoint("TOPLEFT", panel, "TOPLEFT", 37, -95)
dot:SetColorTexture(0.6, 0.7, 0.8, 1)

local statusTitle = textLine("status", 58, -91, 515, 24, "GameFontNormal")
local statusDetail = textLine("detail", 37, -119, 545, 34)

local realm = textLine("realm", 22, -164, 350, 22, "GameFontHighlight")
local apis = textLine("api", 380, -164, 210, 22, "GameFontHighlight")
local counts = textLine("counts", 22, -190, 560, 22)
divider(-215)

local recentTitle = textLine("recent", 22, -228, 560, 22, "GameFontNormal")
local latest1 = textLine("latest1", 22, -253, 560, 22)
local latest2 = textLine("latest2", 22, -275, 560, 22)
local latest3 = textLine("latest3", 22, -297, 560, 22)
divider(-323)

local historyTitle = textLine("history", 22, -336, 560, 22, "GameFontNormal")
local history = {
    textLine("history1", 22, -361, 560, 21),
    textLine("history2", 22, -382, 560, 21),
    textLine("history3", 22, -403, 560, 21),
}
divider(-428)

local diskState = textLine("disk", 22, -437, 560, 22, "GameFontHighlight")
local diskHint = textLine("hint", 22, -458, 560, 23)

local watchlistTitle = textLine("watchlist", 22, -485, 565, 22, "GameFontNormal")
watchlistTitle:SetText("|cff82bffd采集物品清单|r  |cff9eb7c0点击采集；每项右侧 × 可移除|r")

local nameLabel = textLine("nameLabel", 22, -511, 250, 18)
nameLabel:SetText("物品名称（按国服 AH 显示名填写）")
local idLabel = textLine("idLabel", 290, -511, 100, 18)
idLabel:SetText("物品 ID")

local idInput
local nameInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
nameInput:SetSize(250, 26)
nameInput:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -529)
nameInput:SetAutoFocus(false)
nameInput:SetMaxLetters(63)
nameInput:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    panel:Hide()
end)
nameInput:SetScript("OnEnterPressed", function(self)
    if idInput and type(API.AddWatchlistItem) == "function" then
        if API.AddWatchlistItem(self:GetText(), idInput:GetText()) then
            self:SetText("")
            idInput:SetText("")
            self:ClearFocus()
        end
    end
end)

idInput = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
idInput:SetSize(100, 26)
idInput:SetPoint("TOPLEFT", panel, "TOPLEFT", 292, -529)
idInput:SetAutoFocus(false)
idInput:SetMaxLetters(12)
idInput:SetNumeric(true)
idInput:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    panel:Hide()
end)
idInput:SetScript("OnEnterPressed", function(self)
    if type(API.AddWatchlistItem) == "function" then
        if API.AddWatchlistItem(nameInput:GetText(), self:GetText()) then
            nameInput:SetText("")
            self:SetText("")
            nameInput:ClearFocus()
        end
    end
end)

local addButton = button(panel, "加入清单", 145, 27)
addButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 415, -528)
addButton:SetScript("OnClick", function()
    if type(API.AddWatchlistItem) == "function"
        and API.AddWatchlistItem(nameInput:GetText(), idInput:GetText()) then
        nameInput:SetText("")
        idInput:SetText("")
        nameInput:ClearFocus()
    end
end)

local watchlistHint = textLine("watchlistHint", 22, -557, 570, 20)
watchlistHint:SetText("|cffd9bd75自动翻页期间请勿在 AH 切换搜索；如需中止可点下方停止按钮。|r")

local watchScroll = CreateFrame("ScrollFrame", "AuctionCollectorWatchlistScroll", panel, "UIPanelScrollFrameTemplate")
watchScroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -580)
watchScroll:SetSize(580, watchlistHeight)
watchScroll:EnableMouseWheel(true)
local watchChild = CreateFrame("Frame", nil, watchScroll)
watchChild:SetSize(535, 1)
watchScroll:SetScrollChild(watchChild)
local watchRows = {}
local emptyWatchlist = watchChild:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyWatchlist:SetPoint("TOPLEFT", watchChild, "TOPLEFT", 4, -8)
emptyWatchlist:SetSize(500, 22)
emptyWatchlist:SetText("清单为空；填写物品名称与 ID 后加入。")

local function createWatchRow()
    local row = {
        scan = button(watchChild, "", 230, 25),
        remove = button(watchChild, "×", 28, 25),
    }
    row.scan:SetPoint("TOPLEFT", watchChild, "TOPLEFT", 0, 0)
    row.remove:SetPoint("TOPLEFT", watchChild, "TOPLEFT", 235, 0)
    return row
end

local function renderWatchlist(state)
    local items = type(API.GetWatchlist) == "function" and API.GetWatchlist() or {}
    local busy = state.pending or state.autoScanning
    for i, item in ipairs(items) do
        local row = watchRows[i] or createWatchRow()
        watchRows[i] = row
        row.scan:ClearAllPoints()
        row.remove:ClearAllPoints()
        local column = (i - 1) % 2
        local line = math.floor((i - 1) / 2)
        local columnOffset = column * 270
        row.scan:SetPoint("TOPLEFT", watchChild, "TOPLEFT", columnOffset, -(line * 28))
        row.remove:SetPoint("TOPLEFT", watchChild, "TOPLEFT", columnOffset + 235, -(line * 28))
        row.scan:SetText(item.name .. "  ·  ID " .. tostring(item.item_id))
        local itemIndex = i
        row.scan:SetScript("OnClick", function()
            if type(API.ScanWatchlistItem) == "function" then API.ScanWatchlistItem(itemIndex) end
        end)
        row.remove:SetScript("OnClick", function()
            if type(API.RemoveWatchlistItem) == "function" then API.RemoveWatchlistItem(itemIndex) end
        end)
        if busy then row.scan:Disable() else row.scan:Enable() end
        if busy then row.remove:Disable() else row.remove:Enable() end
        row.scan:Show()
        row.remove:Show()
    end
    for i = #items + 1, #watchRows do
        watchRows[i].scan:Hide()
        watchRows[i].remove:Hide()
    end
    if #items == 0 then emptyWatchlist:Show()
    else emptyWatchlist:Hide() end
    watchChild:SetHeight(math.max(24, math.ceil(#items / 2) * 28))
    if watchScroll.UpdateScrollChildRect then watchScroll:UpdateScrollChildRect() end
    if #items == 0 and watchScroll.SetVerticalScroll then watchScroll:SetVerticalScroll(0) end
    if addButton.Enable then
        if busy then
            addButton:Disable()
            nameInput:Disable()
            idInput:Disable()
        else
            addButton:Enable()
            nameInput:Enable()
            idInput:Enable()
        end
    end
end

watchScroll:SetScript("OnMouseWheel", function(self, delta)
    local current = self:GetVerticalScroll() or 0
    local itemCount = #(API.GetWatchlist())
    local contentHeight = math.max(24, math.ceil(itemCount / 2) * 28)
    local maximum = math.max(0, contentHeight - watchlistHeight)
    self:SetVerticalScroll(math.max(0, math.min(maximum, current - delta * 28)))
end)

local stopButton = button(panel, "停止自动翻页", 175, 28)
stopButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -(580 + watchlistHeight + 14))
stopButton:SetScript("OnClick", function()
    if type(API.StopAutoScan) == "function" then API.StopAutoScan() end
end)
local probeButton = button(panel, "检测 API", 125, 28)
probeButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 205, -(580 + watchlistHeight + 14))
probeButton:SetScript("OnClick", function()
    if type(API.Probe) == "function" then API.Probe() end
end)
local saveButton = button(panel, "写盘并重载游戏界面", 215, 28)
saveButton:SetPoint("TOPLEFT", panel, "TOPLEFT", 340, -(580 + watchlistHeight + 14))
saveButton:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[AuctionCollector]|r 战斗中不执行界面重载。")
        end
        return
    end
    if type(ReloadUI) == "function" then ReloadUI() end
end)
local footer = textLine("footer", 22, -(580 + watchlistHeight + 50), 570, 22)
footer:SetText("|cff91a7c0Esc 关闭面板但不停止采集；完整结果需重载/登出后才写入 SavedVariables。|r")

local function clock(ts)
    if type(ts) ~= "number" or ts <= 0 then return "未知" end
    if date then return date("%m-%d %H:%M:%S", ts) end
    return tostring(ts)
end

local function scanStats(scan)
    local number = 0
    local quantity = 0
    local known = 0
    local timeLeftKnown = 0
    local totalRows = scan and scan.rows
    if type(totalRows) == "table" then
        for _, row in ipairs(totalRows) do
            number = number + 1
            quantity = quantity + (tonumber(row.quantity) or 0)
            if row.seller_character and row.seller_character ~= "" then known = known + 1 end
            if tonumber(row.time_left_bucket) then timeLeftKnown = timeLeftKnown + 1 end
        end
    end
    return number, quantity, known, timeLeftKnown
end

local COLOR = {
    error = {0.95, 0.27, 0.27},
    cooldown = {0.98, 0.68, 0.27},
    pending = {0.98, 0.73, 0.29},
    auto_wait = {0.98, 0.73, 0.29},
    stopping = {0.98, 0.68, 0.27},
    stopped = {0.98, 0.68, 0.27},
    resolving = {0.98, 0.73, 0.29},
    captured = {0.98, 0.73, 0.29},
    completed = {0.26, 0.83, 0.50},
    empty_result = {0.98, 0.68, 0.27},
    restored = {0.26, 0.83, 0.50},
    empty = {0.58, 0.68, 0.79},
}

local STATUS = {
    error = "查询失败 / 需要检查",
    cooldown = "查询冷却中",
    pending = "拍卖行查询已发送 · 等待返回",
    auto_wait = "自动翻页中 · 等待查询冷却",
    stopping = "正在停止自动翻页",
    stopped = "自动翻页已停止",
    resolving = "数据已返回 · 等待卖家名称解析",
    captured = "单页扫描成功 · 数据在内存中",
    completed = "该物品自动采集完成 · 数据在内存中",
    empty_result = "查询返回 0 条 · 请核实",
    restored = "已从 SavedVariables 存档读回数据",
    empty = "尚无扫描记录",
}

function API.RefreshPanel()
    if not panel:IsShown() then return end
    if type(API.GetState) ~= "function" then return end
    local state = API.GetState()
    local color = COLOR[state.status] or COLOR.empty
    dot:SetColorTexture(color[1], color[2], color[3], 1)
    statusTitle:SetText(STATUS[state.status] or "正在初始化")
    statusDetail:SetText(state.message or "等待操作")

    local f = state.faction == "Alliance" and "联盟" or tostring(state.faction or "?")
    realm:SetText("服务器：|cffffffff" .. tostring(state.realm or "?") .. "|r  ·  阵营：" .. f)
    apis:SetText(state.legacyAPIAvailable and "|cff6bdf99查询 API 可用|r"
            or "|cffff7777Legacy API 不可用|r")
    counts:SetText("已读回存档：|cffffffff" .. state.restoredCount
        .. "|r 页     本次新采集：|cffffffaa" .. state.newPages
        .. "|r 页     当前缓存：|cffffffff" .. state.totalPages .. "/" .. state.maxPages .. "|r 页")

    local latest = state.latest
    recentTitle:SetText("|cff82bffd最近一次采集|r")
    if latest then
        local rows, quantity, known, timeLeftKnown = scanStats(latest)
        local pageDetail = "第 " .. tostring((tonumber(latest.page) or 0) + 1) .. " 页"
        if latest.collection_id then
            pageDetail = pageDetail .. " · 自动采集组 " .. tostring(latest.collection_status or "进行中")
        end
        latest1:SetText("采集时间：" .. clock(latest.observed_at)
            .. "   物品：" .. tostring(latest.query or "?") .. "   " .. pageDetail)
        latest2:SetText("本页挂单：|cffffffff" .. rows
            .. "|r 条    物品数量：|cffffffff" .. quantity
            .. "|r    AH 返回总条目：" .. tostring(latest.reported_total or "?"))
        latest3:SetText("卖家名：|cffffffff" .. known .. "/" .. rows
            .. "|r    时限档：|cffffffff" .. timeLeftKnown .. "/" .. rows
            .. "|r    异常：" .. tostring(latest.invalid_rows or 0)
            .. "    查询耗时：" .. tostring(latest.duration_ms or "?") .. " ms")
    else
        latest1:SetText("尚未取得任何扫描结果。")
        latest2:SetText("点击下方一个物品开始；自动翻页只查询该物品。")
        latest3:SetText("扫描完成后仍需写入 SavedVariables，才可从 Mac 导入。")
    end

    historyTitle:SetText("|cff82bffd最近 3 条扫描记录|r")
    local scans = AuctionCollectorDB and AuctionCollectorDB.scans or {}
    for i = 1, 3 do
        local scan = scans[#scans - i + 1]
        if scan then
            local rows, quantity = scanStats(scan)
            history[i]:SetText(clock(scan.observed_at) .. "   " .. tostring(scan.query or "?")
                .. " · 第 " .. tostring((tonumber(scan.page) or 0) + 1) .. " 页"
                .. "   " .. rows .. " 条 / " .. quantity .. " 件")
        else
            history[i]:SetText("|cff8398ae暂无记录|r")
        end
    end

    if state.newPages > 0 then
        diskState:SetText("|cffffc56d待写入磁盘：" .. state.newPages .. " 页新数据|r")
        diskHint:SetText("点「写盘并重载」或正常退出游戏；SavedVariables 读回不是 Azure 已上传。")
    elseif state.restoredCount > 0 then
        diskState:SetText("|cff70df9b存档读取成功：" .. state.restoredCount .. " 页|r")
        diskHint:SetText("插件已从上次游戏存档读回；本次还没有新增待写入记录。")
    else
        diskState:SetText("|cffb5c4d6当前没有已读回的存档数据|r")
        diskHint:SetText("插件无法直接检查 Mac 文件是否已写入。")
    end

    renderWatchlist(state)
    if stopButton.Enable then
        local stopping = state.status == "stopping"
        if state.autoScanning and not stopping then
            stopButton:SetText("停止自动翻页")
            stopButton:Enable()
        elseif stopping then
            stopButton:SetText("正在停止…")
            stopButton:Disable()
        else
            stopButton:SetText("停止自动翻页")
            stopButton:Disable()
        end
        if state.pending or state.autoScanning then saveButton:Disable()
        else saveButton:Enable() end
        if state.pending or not state.legacyAPIAvailable then probeButton:Disable()
        else probeButton:Enable() end
    end
end

function API.ShowPanel()
    panel:Show()
    API.RefreshPanel()
end

function API.TogglePanel()
    if panel:IsShown() then panel:Hide()
    else API.ShowPanel() end
end

panel:Hide()
