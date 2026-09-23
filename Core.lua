local ADDON_NAME = ...
WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

local eventFrame = CreateFrame("Frame")
local recentMessages = {}

local DEFAULT_RULE = {
    name = "示例：玛拉顿找T",
    expression = "(MLD OR 玛拉顿 OR 玛拉) AND (T OR MT OR 坦 OR 坦克) AND NOT (带 OR 老板 OR 工作室)",
    enabled = true,
}

local function copyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = {}
                copyDefaults(target[key], value)
            else
                target[key] = value
            end
        elseif type(value) == "table" and type(target[key]) == "table" then
            copyDefaults(target[key], value)
        end
    end
end

local function shortName(name)
    return tostring(name or ""):match("^([^-]+)") or tostring(name or "")
end

local function mergeUnique(target, values)
    local seen = {}
    for _, v in ipairs(target) do seen[tostring(v):lower()] = true end
    for _, v in ipairs(values or {}) do
        local key = tostring(v):lower()
        if not seen[key] then
            seen[key] = true
            target[#target + 1] = v
        end
    end
end

function WKM:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ccff[WKM]|r " .. tostring(message or ""))
end

function WKM:GetRelativeTime(timestamp)
    local delta = math.max(0, time() - (timestamp or time()))
    if delta < 10 then return "刚刚" end
    if delta < 60 then return tostring(delta) .. "秒前" end
    if delta < 3600 then return tostring(math.floor(delta / 60)) .. "分钟前" end
    if delta < 86400 then return tostring(math.floor(delta / 3600)) .. "小时前" end
    return tostring(math.floor(delta / 86400)) .. "天前"
end

function WKM:GetPlayerClassByGUID(guid)
    if not guid or guid == "" then return nil, nil end

    if GetPlayerInfoByGUID then
        local localizedClass, classFile = GetPlayerInfoByGUID(guid)
        if classFile and classFile ~= "" then
            return classFile, localizedClass
        end
    end

    if UnitClassFromGUID then
        local localizedClass, classFile = UnitClassFromGUID(guid)
        if classFile and classFile ~= "" then
            return classFile, localizedClass
        end
    end

    return nil, nil
end

function WKM:FindRule(id)
    for index, rule in ipairs(self.DB.rules) do
        if rule.id == id then return rule, index end
    end
end

function WKM:AddRule(name, expression)
    name = (name or ""):match("^%s*(.-)%s*$")
    expression = (expression or ""):match("^%s*(.-)%s*$")
    if name == "" then return false, "规则名称不能为空" end

    local valid, err = self.Rules.Validate(expression)
    if not valid then return false, err end

    local rule = {
        id = self.DB.nextRuleId,
        name = name,
        expression = expression,
        enabled = true,
    }
    self.DB.nextRuleId = self.DB.nextRuleId + 1
    table.insert(self.DB.rules, rule)
    self.Rules.ClearCache()
    if self.RefreshRulesUI then self:RefreshRulesUI() end
    return true, rule
end

function WKM:UpdateRule(id, name, expression, enabled)
    local rule = self:FindRule(id)
    if not rule then return false, "规则不存在" end

    if expression ~= nil then
        expression = (expression or ""):match("^%s*(.-)%s*$")
        local valid, err = self.Rules.Validate(expression)
        if not valid then return false, err end
        rule.expression = expression
    end

    if name ~= nil then
        name = (name or ""):match("^%s*(.-)%s*$")
        if name == "" then return false, "规则名称不能为空" end
        rule.name = name
    end

    if enabled ~= nil then rule.enabled = enabled and true or false end
    self.Rules.ClearCache()
    if self.RefreshRulesUI then self:RefreshRulesUI() end
    return true, rule
end

function WKM:DeleteRule(id)
    local _, index = self:FindRule(id)
    if not index then return false end
    table.remove(self.DB.rules, index)
    self.Rules.ClearCache()
    if self.RefreshRulesUI then self:RefreshRulesUI() end
    return true
end

function WKM:MatchText(message)
    local matchedRules, matchedTerms = {}, {}
    for _, rule in ipairs(self.DB.rules) do
        if rule.enabled then
            local matched, terms, err = self.Rules.Match(rule, message)
            if matched then
                matchedRules[#matchedRules + 1] = rule
                mergeUnique(matchedTerms, terms)
            elseif err and not rule._reportedError then
                rule._reportedError = true
                self:Print("规则「" .. rule.name .. "」有错误：" .. err)
            end
        end
    end
    return matchedRules, matchedTerms
end

function WKM:ProcessChat(message, sender, channelName, channelIndex, lineID, guid)
    if not self.DB.enabled or not message or message == "" then return end
    if shortName(sender) == UnitName("player") then return end

    self:PruneExpiredHistory()

    local matchedRules, terms = self:MatchText(message)
    if #matchedRules == 0 then return end

    local ruleNames, ruleIds = {}, {}
    for _, rule in ipairs(matchedRules) do
        ruleNames[#ruleNames + 1] = rule.name
        ruleIds[#ruleIds + 1] = tostring(rule.id)
    end

    local now = time()
    local key = tostring(sender) .. "|" .. tostring(message) .. "|" .. table.concat(ruleIds, ",")
    local last = recentMessages[key]
    if last and now - last < self.DB.settings.dedupeSeconds then return end
    recentMessages[key] = now

    for k, seenAt in pairs(recentMessages) do
        if now - seenAt > 60 then recentMessages[k] = nil end
    end

    local classFile, className = self:GetPlayerClassByGUID(guid)

    local entry = {
        id = self.DB.nextMessageId,
        timestamp = now,
        sender = sender or "?",
        guid = guid,
        classFile = classFile,
        className = className,
        message = message,
        channel = channelName or "?",
        channelIndex = channelIndex,
        lineID = lineID,
        ruleNames = ruleNames,
        matchedTerms = terms,
    }
    self.DB.nextMessageId = self.DB.nextMessageId + 1
    table.insert(self.DB.history, entry)

    while #self.DB.history > self.DB.settings.maxHistory do
        table.remove(self.DB.history, 1)
    end

    self.DB.unread = (self.DB.unread or 0) + 1
    self:Notify(entry)
    if self.RefreshHistoryUI then self:RefreshHistoryUI() end
end

function WKM:PruneExpiredHistory()
    if not self.DB or not self.DB.settings or not self.DB.settings.autoDeleteOldMessages then
        return 0
    end

    local minutes = tonumber(self.DB.settings.autoDeleteMinutes) or 10
    local cutoff = time() - math.max(1, minutes) * 60
    local history = self.DB.history
    local removed = 0

    for i = #history, 1, -1 do
        local entry = history[i]
        if (entry.timestamp or 0) < cutoff then
            table.remove(history, i)
            removed = removed + 1
        end
    end

    if removed > 0 then
        self.DB.unread = math.min(self.DB.unread or 0, #history)
        if self.UpdateMinimapState then self:UpdateMinimapState() end
    end

    return removed
end

function WKM:ClearHistory()
    self.DB.history = {}
    self.DB.unread = 0
    if self.RefreshHistoryUI then self:RefreshHistoryUI() end
    if self.UpdateMinimapState then self:UpdateMinimapState() end
end

function WKM:MarkRead()
    self.DB.unread = 0
    if self.UpdateMinimapState then self:UpdateMinimapState() end
end

function WKM:SetEnabled(enabled)
    self.DB.enabled = enabled and true or false
    if self.UpdateGlobalState then self:UpdateGlobalState() end
    if self.UpdateMinimapState then self:UpdateMinimapState() end
end

local function initializeDB()
    WOWKeywordMonitorDB = WOWKeywordMonitorDB or {}
    copyDefaults(WOWKeywordMonitorDB, {
        schema = 1,
        enabled = true,
        nextRuleId = 1,
        nextMessageId = 1,
        unread = 0,
        lastRuleUndo = false,
        minimapAngle = 225,
        rules = {},
        history = {},
        settings = {
            maxHistory = 200,
            dedupeSeconds = 8,
            screenAlert = true,
            sound = true,
            autoDeleteOldMessages = false,
            autoDeleteMinutes = 10,
        },
    })

    WKM.DB = WOWKeywordMonitorDB

    if #WKM.DB.rules == 0 then
        local rule = {
            id = WKM.DB.nextRuleId,
            name = DEFAULT_RULE.name,
            expression = DEFAULT_RULE.expression,
            enabled = DEFAULT_RULE.enabled,
        }
        WKM.DB.nextRuleId = WKM.DB.nextRuleId + 1
        table.insert(WKM.DB.rules, rule)
    end

    while #WKM.DB.history > WKM.DB.settings.maxHistory do
        table.remove(WKM.DB.history, 1)
    end

    WKM:PruneExpiredHistory()
end

local function handleSlash(input)
    local cmd, rest = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = (cmd or ""):lower()

    if cmd == "" then
        WKM:ToggleMainWindow()
    elseif cmd == "on" then
        WKM:SetEnabled(true)
        WKM:Print("监听已开启")
    elseif cmd == "off" then
        WKM:SetEnabled(false)
        WKM:Print("监听已关闭")
    elseif cmd == "clear" then
        WKM:ClearHistory()
        WKM:Print("匹配历史已清空")
    elseif cmd == "test" then
        if rest == "" then
            WKM:Print("用法：/wkm test 要测试的聊天文本")
            return
        end
        local rules = WKM:MatchText(rest)
        if #rules == 0 then
            WKM:Print("测试结果：没有规则匹配")
        else
            local names = {}
            for _, rule in ipairs(rules) do names[#names + 1] = rule.name end
            WKM:Print("测试结果：匹配 " .. table.concat(names, "、"))
        end
    else
        WKM:Print("/wkm - 打开窗口；/wkm test 文本；/wkm on；/wkm off；/wkm clear")
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then return end

        initializeDB()
        eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        if WKM.CreateMainWindow then WKM:CreateMainWindow() end
        if WKM.CreateMinimapButton then WKM:CreateMinimapButton() end

        SLASH_WOWKEYWORDMONITOR1 = "/wkm"
        SLASH_WOWKEYWORDMONITOR2 = "/kwm"
        SlashCmdList["WOWKEYWORDMONITOR"] = handleSlash
        WKM:Print("已加载。/wkm 打开设置与匹配历史")
        return
    end

    if event == "CHAT_MSG_CHANNEL" then
        local message, sender, _, channelName, _, _, _, channelIndex, channelBaseName, _, lineID, guid = ...
        local displayChannel = channelBaseName
        if not displayChannel or displayChannel == "" then displayChannel = channelName end
        WKM:ProcessChat(message, sender, displayChannel, channelIndex, lineID, guid)
    end
end)
