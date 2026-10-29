local ADDON_NAME = ...
WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

local eventFrame = CreateFrame("Frame")
local recentMessages = {}
-- Temporary keywords are intentionally runtime-only: /reload and logout clear them.
local temporaryKeywords = {}
local MAX_TEMP_KEYWORDS = 30
local MAX_TEMP_KEYWORD_BYTES = 120

local DEFAULT_RULE = {
    name = "示例：玛拉顿找T",
    expression = "(MLD OR 玛拉顿 OR 玛拉) AND (T OR MT OR 坦 OR 坦克) AND NOT (带 OR 老板 OR 工作室)",
    enabled = true,
    channels = { public = true, guild = false },
}

-- Older SavedVariables entries predate channel selection. They remain public-only.
local function normalizeChannels(channels)
    if type(channels) ~= "table" then
        return { public = true, guild = false }
    end
    return {
        public = channels.public ~= false,
        guild = channels.guild == true,
    }
end

local function hasChannel(channels)
    return channels.public or channels.guild
end

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

function WKM:IsBlacklisted(name, guid)
    if not C_FriendList then return false end

    if guid and guid ~= "" and C_FriendList.IsIgnoredByGuid then
        local ok, ignored = pcall(C_FriendList.IsIgnoredByGuid, guid)
        if ok and ignored then return true end
    end

    if name and name ~= "" and C_FriendList.IsIgnored then
        local ok, ignored = pcall(C_FriendList.IsIgnored, name)
        if ok and ignored then return true end

        local short = shortName(name)
        if short ~= name then
            ok, ignored = pcall(C_FriendList.IsIgnored, short)
            if ok and ignored then return true end
        end
    end

    return false
end

function WKM:GetNativeIgnoreCount()
    if not C_FriendList or not C_FriendList.GetNumIgnores then return 0 end
    local ok, count = pcall(C_FriendList.GetNumIgnores)
    if ok then return tonumber(count) or 0 end
    return 0
end

function WKM:AddToBlacklist(name)
    if not name or name == "" then return false end
    if not C_FriendList or not C_FriendList.AddIgnore then
        self:Print("当前客户端不支持原生黑名单 API")
        return false
    end

    local alreadyIgnored = self:IsBlacklisted(name)
    local ok, added = pcall(C_FriendList.AddIgnore, name)
    if not ok then
        self:Print("加入 WoW 原生黑名单失败：" .. tostring(added))
        return false
    end

    if added == false and not alreadyIgnored and not self:IsBlacklisted(name) then
        self:Print("未能加入 WoW 原生黑名单，可能已达到系统上限")
        return false
    end

    local target = tostring(name):lower()
    local targetShort = shortName(name):lower()
    local moved = 0
    for i = #self.DB.history, 1, -1 do
        local entry = self.DB.history[i]
        local sender = tostring(entry.sender or "")
        if sender:lower() == target or shortName(sender):lower() == targetShort then
            table.remove(self.DB.history, i)
            table.insert(self.DB.blacklistHistory, entry)
            moved = moved + 1
        end
    end

    while #self.DB.blacklistHistory > self.DB.settings.maxHistory do
        table.remove(self.DB.blacklistHistory, 1)
    end

    self.DB.unread = math.min(self.DB.unread or 0, #self.DB.history)
    self:PruneExpiredHistory()
    if self.RefreshHistoryUI then self:RefreshHistoryUI() end
    if self.RefreshBlacklistUI then self:RefreshBlacklistUI(true) end
    if self.UpdateMinimapState then self:UpdateMinimapState() end

    if alreadyIgnored then
        self:Print("该玩家已在 WoW 原生黑名单：" .. tostring(name))
    else
        self:Print("已加入 WoW 原生黑名单：" .. tostring(name))
    end
    return true, moved
end

function WKM:RemoveFromBlacklist(name)
    if not name or name == "" then return false end
    if not C_FriendList or not C_FriendList.DelIgnore then
        self:Print("当前客户端不支持原生黑名单 API")
        return false
    end

    local ok, removed = pcall(C_FriendList.DelIgnore, name)
    if not ok then
        self:Print("移出 WoW 原生黑名单失败：" .. tostring(removed))
        return false
    end

    if not removed and self:IsBlacklisted(name) then
        local short = shortName(name)
        if short ~= name then
            ok, removed = pcall(C_FriendList.DelIgnore, short)
        end
    end

    if self.RefreshBlacklistUI then self:RefreshBlacklistUI() end

    if removed or not self:IsBlacklisted(name) then
        self:Print("已移出 WoW 原生黑名单：" .. tostring(name))
        return true
    end

    self:Print("未能移出 WoW 原生黑名单：" .. tostring(name))
    return false
end

function WKM:ClearBlacklistHistory()
    self.DB.blacklistHistory = {}
    if self.RefreshBlacklistUI then self:RefreshBlacklistUI(true) end
end

function WKM:FindRule(id)
    for index, rule in ipairs(self.DB.rules) do
        if rule.id == id then return rule, index end
    end
end

function WKM:SortRulesByEnabled()
    if not self.DB or not self.DB.rules then return end

    local enabledRules, disabledRules = {}, {}
    for _, rule in ipairs(self.DB.rules) do
        if rule.enabled then
            enabledRules[#enabledRules + 1] = rule
        else
            disabledRules[#disabledRules + 1] = rule
        end
    end

    local sorted = {}
    for _, rule in ipairs(enabledRules) do sorted[#sorted + 1] = rule end
    for _, rule in ipairs(disabledRules) do sorted[#sorted + 1] = rule end
    self.DB.rules = sorted
end

function WKM:AddRule(name, expression, channels)
    name = (name or ""):match("^%s*(.-)%s*$")
    expression = (expression or ""):match("^%s*(.-)%s*$")
    if name == "" then return false, "规则名称不能为空" end

    local valid, err = self.Rules.Validate(expression)
    if not valid then return false, err end

    local selectedChannels = normalizeChannels(channels)
    if not hasChannel(selectedChannels) then
        return false, "至少选择一个监听频道"
    end

    local rule = {
        id = self.DB.nextRuleId,
        name = name,
        expression = expression,
        enabled = true,
        channels = selectedChannels,
    }
    self.DB.nextRuleId = self.DB.nextRuleId + 1
    table.insert(self.DB.rules, 1, rule)
    self.Rules.ClearCache()
    if self.RefreshRulesUI then self:RefreshRulesUI() end
    return true, rule
end

function WKM:UpdateRule(id, name, expression, enabled, channels)
    local rule = self:FindRule(id)
    if not rule then return false, "规则不存在" end

    local selectedChannels
    if channels ~= nil then
        selectedChannels = normalizeChannels(channels)
        if not hasChannel(selectedChannels) then
            return false, "至少选择一个监听频道"
        end
    end

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

    if selectedChannels then rule.channels = selectedChannels end
    if enabled ~= nil then
        rule.enabled = enabled and true or false
        self:SortRulesByEnabled()
    end
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

local function trimTemporaryKeyword(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

function WKM:AddTemporaryKeyword(text, channelType)
    text = trimTemporaryKeyword(text)
    channelType = channelType == "guild" and "guild" or "public"

    if text == "" then return false, "关键词不能为空" end
    if #text > MAX_TEMP_KEYWORD_BYTES then
        return false, "临时关键词最长 " .. MAX_TEMP_KEYWORD_BYTES .. " 字节"
    end
    if text:find("[\r\n]") then
        return false, "关键词不能包含换行"
    end

    local needle = text:lower()
    for _, entry in ipairs(temporaryKeywords) do
        if entry.channelType == channelType and entry.needle == needle then
            return false, "该频道已在临时监测：" .. entry.text
        end
    end
    if #temporaryKeywords >= MAX_TEMP_KEYWORDS then
        return false, "临时监测已达 " .. MAX_TEMP_KEYWORDS .. " 条，请先删除不需要的关键词"
    end

    temporaryKeywords[#temporaryKeywords + 1] = {
        text = text,
        needle = needle,
        channelType = channelType,
        rule = {
            id = "temp:" .. channelType .. ":" .. needle,
            name = "临时：" .. text,
            temporary = true,
        },
    }
    return true
end

function WKM:RemoveTemporaryKeyword(text)
    text = trimTemporaryKeyword(text)
    if text == "" then return 0 end
    local needle, removed = text:lower(), 0
    for i = #temporaryKeywords, 1, -1 do
        if temporaryKeywords[i].needle == needle then
            table.remove(temporaryKeywords, i)
            removed = removed + 1
        end
    end
    return removed
end

function WKM:ClearTemporaryKeywords()
    local removed = #temporaryKeywords
    for i = #temporaryKeywords, 1, -1 do
        temporaryKeywords[i] = nil
    end
    return removed
end

function WKM:ListTemporaryKeywords()
    if #temporaryKeywords == 0 then
        self:Print("暂无临时监测关键词")
        return
    end
    self:Print("当前临时监测：" .. #temporaryKeywords .. " 条（/reload 后清空）")
    for i, entry in ipairs(temporaryKeywords) do
        local channelLabel = entry.channelType == "guild" and "公会" or "公共"
        self:Print(i .. ". [" .. channelLabel .. "] " .. entry.text)
    end
end

function WKM:MatchText(message, channelType)
    channelType = channelType or "public"
    local matchedRules, matchedTerms = {}, {}
    for _, rule in ipairs(self.DB.rules) do
        local channels = normalizeChannels(rule.channels)
        if rule.enabled and channels[channelType] == true then
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

    -- Temporary terms are literal substrings, never parsed as boolean expressions.
    -- Use the visible text for matching so a user may monitor names in item links.
    local visibleText = self.Rules.Sanitize(message):lower()
    for _, entry in ipairs(temporaryKeywords) do
        if entry.channelType == channelType and visibleText:find(entry.needle, 1, true) then
            matchedRules[#matchedRules + 1] = entry.rule
            mergeUnique(matchedTerms, { entry.text })
        end
    end

    return matchedRules, matchedTerms
end

function WKM:ProcessChat(message, sender, channelName, channelIndex, lineID, guid, channelType)
    if not self.DB.enabled or not message or message == "" then return end
    if shortName(sender) == UnitName("player") then return end

    self:PruneExpiredHistory()

    channelType = channelType or "public"
    local matchedRules, terms = self:MatchText(message, channelType)
    if #matchedRules == 0 then return end

    local ruleNames, ruleIds = {}, {}
    for _, rule in ipairs(matchedRules) do
        ruleNames[#ruleNames + 1] = rule.name
        ruleIds[#ruleIds + 1] = tostring(rule.id)
    end

    local now = time()
    local key = channelType .. "|" .. tostring(sender) .. "|" .. tostring(message) .. "|" .. table.concat(ruleIds, ",")
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
        channelType = channelType,
        channelIndex = channelIndex,
        lineID = lineID,
        ruleNames = ruleNames,
        matchedTerms = terms,
    }
    self.DB.nextMessageId = self.DB.nextMessageId + 1

    if self:IsBlacklisted(sender, guid) then
        table.insert(self.DB.blacklistHistory, entry)
        while #self.DB.blacklistHistory > self.DB.settings.maxHistory do
            table.remove(self.DB.blacklistHistory, 1)
        end
        if self.RefreshBlacklistUI then self:RefreshBlacklistUI() end
        return
    end

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
    local removed = 0

    local function pruneList(list)
        local count = 0
        for i = #list, 1, -1 do
            local entry = list[i]
            if (entry.timestamp or 0) < cutoff then
                table.remove(list, i)
                count = count + 1
            end
        end
        return count
    end

    removed = removed + pruneList(self.DB.history)
    removed = removed + pruneList(self.DB.blacklistHistory)

    if removed > 0 then
        self.DB.unread = math.min(self.DB.unread or 0, #self.DB.history)
        if self.UpdateMinimapState then self:UpdateMinimapState() end
        if self.RefreshBlacklistUI then self:RefreshBlacklistUI() end
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
        blacklistHistory = {},
        settings = {
            maxHistory = 200,
            dedupeSeconds = 8,
            screenAlert = true,
            sound = true,
            clientIconAlert = true,
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
            channels = normalizeChannels(DEFAULT_RULE.channels),
        }
        WKM.DB.nextRuleId = WKM.DB.nextRuleId + 1
        table.insert(WKM.DB.rules, rule)
    end

    -- Migrate existing rules without changing their prior public-channel behavior.
    for _, rule in ipairs(WKM.DB.rules) do
        rule.channels = normalizeChannels(rule.channels)
    end
    WKM:SortRulesByEnabled()

    while #WKM.DB.history > WKM.DB.settings.maxHistory do
        table.remove(WKM.DB.history, 1)
    end
    while #WKM.DB.blacklistHistory > WKM.DB.settings.maxHistory do
        table.remove(WKM.DB.blacklistHistory, 1)
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
    elseif cmd == "t" or cmd == "temp" or cmd == "tg" then
        if rest == "" then
            WKM:Print(cmd == "tg" and "用法：/wkm tg 公会临时关键词" or "用法：/wkm t 公共频道临时关键词")
            return
        end
        local channelType = cmd == "tg" and "guild" or "public"
        local ok, err = WKM:AddTemporaryKeyword(rest, channelType)
        if ok then
            WKM:Print("已临时监测 [" .. (channelType == "guild" and "公会" or "公共") .. "]：" .. rest .. "（本次会话有效）")
        else
            WKM:Print(err)
        end
    elseif cmd == "tl" then
        WKM:ListTemporaryKeywords()
    elseif cmd == "tr" then
        if rest == "" then
            WKM:Print("用法：/wkm tr 要删除的临时关键词")
            return
        end
        local removed = WKM:RemoveTemporaryKeyword(rest)
        WKM:Print(removed > 0 and ("已移除临时关键词：" .. rest .. "（" .. removed .. " 条）") or ("没有找到临时关键词：" .. rest))
    elseif cmd == "tc" then
        local removed = WKM:ClearTemporaryKeywords()
        WKM:Print("已清空 " .. removed .. " 条临时监测关键词（不会清除已记录的消息）")
    elseif cmd == "test" or cmd == "testguild" then
        local isGuild = cmd == "testguild"
        if rest == "" then
            WKM:Print(isGuild and "用法：/wkm testguild 要测试的公会消息" or "用法：/wkm test 要测试的公共频道消息")
            return
        end
        local channelType = isGuild and "guild" or "public"
        local rules = WKM:MatchText(rest, channelType)
        local channelLabel = isGuild and "公会" or "公共"
        if #rules == 0 then
            WKM:Print(channelLabel .. "频道测试：没有规则匹配")
        else
            local names = {}
            for _, rule in ipairs(rules) do names[#names + 1] = rule.name end
            WKM:Print(channelLabel .. "频道测试：匹配 " .. table.concat(names, "、"))
        end
    else
        WKM:Print("/wkm t 关键词（公共）；/wkm tg 关键词（公会）；/wkm tl（查看）；/wkm tr 关键词（删除）；/wkm tc（清空）")
        WKM:Print("/wkm（窗口）；/wkm test 文本；/wkm testguild 文本；/wkm on；/wkm off；/wkm clear")
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loaded = ...
        if loaded ~= ADDON_NAME then return end

        initializeDB()
        eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
        eventFrame:RegisterEvent("CHAT_MSG_GUILD")
        eventFrame:RegisterEvent("IGNORELIST_UPDATE")
        if WKM.CreateMainWindow then WKM:CreateMainWindow() end
        if WKM.CreateMinimapButton then WKM:CreateMinimapButton() end

        SLASH_WOWKEYWORDMONITOR1 = "/wkm"
        SLASH_WOWKEYWORDMONITOR2 = "/kwm"
        SlashCmdList["WOWKEYWORDMONITOR"] = handleSlash
        WKM:Print("已加载。/wkm 打开设置与匹配历史")
        return
    end

    if event == "IGNORELIST_UPDATE" then
        if WKM.RefreshBlacklistUI then WKM:RefreshBlacklistUI() end
        return
    end

    if event == "CHAT_MSG_CHANNEL" then
        local message, sender, _, channelName, _, _, _, channelIndex, channelBaseName, _, lineID, guid = ...
        local displayChannel = channelBaseName
        if not displayChannel or displayChannel == "" then displayChannel = channelName end
        WKM:ProcessChat(message, sender, displayChannel, channelIndex, lineID, guid, "public")
        return
    end

    if event == "CHAT_MSG_GUILD" then
        local message, sender, _, _, _, _, _, _, _, _, lineID, guid = ...
        WKM:ProcessChat(message, sender, "公会", nil, lineID, guid, "guild")
    end
end)
