-- AuctionCollector in-game dashboard. Rendering only: no automatic AH queries.
-- Classic-compatible textures and FontStrings; does not require an external UI library.
local API = AuctionCollector
if type(API) ~= "table" then return end

local panel = CreateFrame("Frame", "AuctionCollectorStatusPanel", UIParent)
panel:SetSize(574, 594)
panel:SetPoint("CENTER", UIParent, "CENTER", 205, 0)
panel:SetFrameStrata("DIALOG")
panel:SetMovable(true)
panel:SetClampedToScreen(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
panel:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

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
    line:SetSize(532, 1)
    line:SetColorTexture(0.23, 0.36, 0.52, 0.7)
end

local title = textLine("title", 20, -18, 470, 26, "GameFontNormalLarge")
title:SetText("|cff79c6ffAuctionCollector|r  |cff9eb7d2· 数据采集状态|r")
local subtitle = textLine("subtitle", 20, -49, 515, 20)
subtitle:SetText("硬核服 / 联盟 · 黑莲花市场研究 · 手动采样")

local function button(label, x, width, callback)
    local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    b:SetSize(width, 28)
    b:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -523)
    b:SetText(label)
    b:SetScript("OnClick", callback)
    return b
end

local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -4)

local statusBg = panel:CreateTexture(nil, "ARTWORK")
statusBg:SetPoint("TOPLEFT", panel, "TOPLEFT", 20, -79)
statusBg:SetSize(532, 77)
statusBg:SetColorTexture(0.1, 0.16, 0.23, 0.98)

local dot = panel:CreateTexture(nil, "OVERLAY")
dot:SetSize(12, 12)
dot:SetPoint("TOPLEFT", panel, "TOPLEFT", 37, -96)
dot:SetColorTexture(0.6, 0.7, 0.8, 1)

local statusTitle = textLine("status", 58, -92, 465, 26, "GameFontNormal")
local statusDetail = textLine("detail", 37, -121, 492, 31)

local realm = textLine("realm", 22, -174, 324, 24, "GameFontHighlight")
local apis = textLine("api", 350, -174, 200, 24, "GameFontHighlight")
local counts = textLine("counts", 22, -202, 525, 22)
divider(-232)

local recentTitle = textLine("recent", 22, -245, 530, 22, "GameFontNormal")
local latest1 = textLine("latest1", 22, -272, 526, 22)
local latest2 = textLine("latest2", 22, -294, 526, 22)
local latest3 = textLine("latest3", 22, -316, 526, 22)
divider(-343)

local historyTitle = textLine("history", 22, -357, 523, 22, "GameFontNormal")
local history = {
    textLine("history1", 22, -385, 524, 22),
    textLine("history2", 22, -406, 524, 22),
    textLine("history3", 22, -427, 524, 22),
}

divider(-454)
local diskState = textLine("disk", 22, -467, 525, 23, "GameFontHighlight")
local diskHint = textLine("hint", 22, -490, 525, 25)

local scanButton = button("扫描黑莲花", 20, 125, function()
    if type(API.ScanLotus) == "function" then API.ScanLotus() end
end)
local nextButton = button("扫描下一页", 151, 121, function()
    if type(API.ScanNext) == "function" then API.ScanNext() end
end)
local probeButton = button("检测 API", 278, 106, function()
    if type(API.Probe) == "function" then API.Probe() end
end)
local saveButton = button("写盘并重载", 391, 161, function()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffffcc00[AuctionCollector]|r 战斗中不执行界面重载。")
        end
        return
    end
    if type(ReloadUI) == "function" then ReloadUI() end
end)
local footer = textLine("footer", 22, -559, 526, 25)
footer:SetText("|cff91a7c0注意：只采集 AH 可见分页数据；挂牌不代表成交。点击顶部可拖动窗口。|r")

local function clock(ts)
    if type(ts) ~= "number" or ts <= 0 then return "未知" end
    if date then return date("%m-%d %H:%M:%S", ts) end
    return tostring(ts)
end

local function scanStats(scan)
    local number = 0
    local quantity = 0
    local known = 0
    local totalRows = scan and scan.rows
    if type(totalRows) == "table" then
        for _, row in ipairs(totalRows) do
            number = number + 1
            quantity = quantity + (tonumber(row.quantity) or 0)
            if row.seller_character and row.seller_character ~= "" then known = known + 1 end
        end
    end
    return number, quantity, known
end

local COLOR = {
    error = {0.95, 0.27, 0.27},
    cooldown = {0.98, 0.68, 0.27},
    pending = {0.98, 0.73, 0.29},
    captured = {0.98, 0.73, 0.29},
    empty_result = {0.98, 0.68, 0.27},
    restored = {0.26, 0.83, 0.50},
    empty = {0.58, 0.68, 0.79},
}

local STATUS = {
    error = "查询失败 / 需要检查",
    cooldown = "查询冷却中",
    pending = "扫描请求已发送 · 等待返回",
    captured = "扫描成功 · 数据已在内存中",
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
    recentTitle:SetText("|cff82bffd最近一次扫描|r")
    if latest then
        local rows, quantity, known = scanStats(latest)
        latest1:SetText("采集时间：" .. clock(latest.observed_at)
            .. "   物品：" .. tostring(latest.query or "?")
            .. "   第 " .. tostring((tonumber(latest.page) or 0) + 1) .. " 页")
        latest2:SetText("本页挂单：|cffffffff" .. rows
            .. "|r 条    物品数量：|cffffffff" .. quantity
            .. "|r    AH 返回总条目：" .. tostring(latest.reported_total or "?"))
        latest3:SetText("有卖家名：|cffffffff" .. known .. "/" .. rows
            .. "|r    读取异常：" .. tostring(latest.invalid_rows or 0)
            .. "    耗时：" .. tostring(latest.duration_ms or "?") .. " ms")
    else
        latest1:SetText("尚未取得任何扫描结果。")
        latest2:SetText("打开拍卖行，点击下方「扫描黑莲花」。")
        latest3:SetText("一次仅扫描一页；可手动点击「扫描下一页」。")
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
        diskHint:SetText("点击「写盘并重载」或正常退出游戏，之后重新进入可验证是否读回。")
    elseif state.restoredCount > 0 then
        diskState:SetText("|cff70df9b存档读取成功：" .. state.restoredCount .. " 页|r")
        diskHint:SetText("这些记录已由游戏重新加载；本次尚无新增待写入扫描。")
    else
        diskState:SetText("|cffb5c4d6当前没有已读回的存档数据|r")
        diskHint:SetText("先人工扫描；插件无法直接检查 Mac 文件是否已经写入。")
    end
    if scanButton.Enable then
        if state.pending or not state.legacyAPIAvailable then scanButton:Disable() else scanButton:Enable() end
        if state.pending or not state.legacyAPIAvailable then nextButton:Disable() else nextButton:Enable() end
    end
end

function API.ShowPanel()
    panel:Show()
    API.RefreshPanel()
end

function API.TogglePanel()
    if panel:IsShown() then
        panel:Hide()
    else
        API.ShowPanel()
    end
end

panel:Hide()
