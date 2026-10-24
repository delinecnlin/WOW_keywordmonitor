WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor
local ROW_H = 28
local trim
local setStatus

local function extractLinkText(link)
    if type(link) ~= "string" or link == "" then return nil end

    local text = link:match("|h%[([^%]]+)%]|h")
        or link:match("|h(.-)|h")
        or link

    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    text = text:gsub("^%[", ""):gsub("%]$", "")
    text = trim(text)

    if text == "" then return nil end
    return text
end

local function asRuleTerm(text)
    if not text then return nil end
    if text:find("%s") then
        text = text:gsub('"', "")
        return '"' .. text .. '"'
    end
    return text
end

function WKM:InsertGameLinkIntoRule(link)
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    if not panel or not panel:IsShown() or not panel.exprEdit or not panel.exprEdit:HasFocus() then
        return false
    end

    local text = asRuleTerm(extractLinkText(link))
    if not text then return false end

    local current = panel.exprEdit:GetText() or ""
    if current == "" then
        panel.exprEdit:Insert(text)
    else
        panel.exprEdit:Insert(" " .. text .. " ")
    end

    setStatus(panel, "已插入游戏内文本：" .. text, "ff66ff99")
    return true
end

function WKM:InstallRuleLinkHook()
    if self.ruleLinkHookInstalled then return end
    self.ruleLinkHookInstalled = true

    local function onLink(link)
        WKM:InsertGameLinkIntoRule(link)
    end

    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", onLink)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", onLink)
    end
end

trim = function(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

setStatus = function(panel, text, color)
    color = color or "ffffffff"
    panel.status:SetText("|c" .. color .. tostring(text or "") .. "|r")
end

local function editorChannels(panel)
    return {
        public = panel.publicCheck:GetChecked() and true or false,
        guild = panel.guildCheck:GetChecked() and true or false,
    }
end

local function channelsLabel(rule)
    local ch = rule.channels or { public = true, guild = false }
    if ch.public ~= false and ch.guild == true then return "公共/公会" end
    if ch.guild == true then return "公会" end
    return "公共"
end

local function markDirty(panel)
    if panel.loadingEditor then return end
    if panel.selectedId then
        setStatus(panel, "有未保存的修改", "ffffcc55")
    else
        setStatus(panel, "新规则尚未保存", "ffffcc55")
    end
end

function WKM:BeginNewRule()
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    if not panel then return end

    panel.loadingEditor = true
    panel.selectedId = nil
    panel.originalName = ""
    panel.originalExpression = ""
    panel.nameEdit:SetText("")
    panel.exprEdit:SetText("")
    panel.publicCheck:SetChecked(true)
    panel.guildCheck:SetChecked(false)
    panel.save:SetText("保存新规则")
    panel.mode:SetText("当前：新建规则")
    panel.loadingEditor = false
    setStatus(panel, "请输入名称和规则表达式", "ffbbbbbb")
    panel.nameEdit:SetFocus()
end

function WKM:LoadRuleIntoEditor(rule)
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    if not panel then return end
    if not rule then
        self:BeginNewRule()
        return
    end

    panel.loadingEditor = true
    panel.selectedId = rule.id
    panel.originalName = rule.name or ""
    panel.originalExpression = rule.expression or ""
    panel.nameEdit:SetText(panel.originalName)
    panel.exprEdit:SetText(panel.originalExpression)
    local channels = rule.channels or { public = true, guild = false }
    panel.publicCheck:SetChecked(channels.public ~= false)
    panel.guildCheck:SetChecked(channels.guild == true)
    panel.save:SetText("确认修改")
    panel.mode:SetText("当前：编辑「" .. (rule.name or "") .. "」")
    panel.loadingEditor = false
    setStatus(panel, "修改后点击“确认修改”，会再次弹窗确认", "ffbbbbbb")
end

function WKM:CancelRuleEdit()
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    if not panel then return end

    if panel.selectedId then
        local rule = self:FindRule(panel.selectedId)
        if rule then
            self:LoadRuleIntoEditor(rule)
            setStatus(panel, "已撤销未保存的修改", "ff66ff99")
            return
        end
    end

    self:BeginNewRule()
    setStatus(panel, "已清空未保存的新规则", "ff66ff99")
end

function WKM:CommitPendingRuleUpdate()
    local pending = self.pendingRuleUpdate
    self.pendingRuleUpdate = nil
    if not pending then return end

    local rule = self:FindRule(pending.id)
    if not rule then
        setStatus(self.mainFrame.rulesPanel, "规则不存在，无法修改", "ffff5555")
        return
    end

    local before = {
        id = rule.id,
        name = rule.name,
        expression = rule.expression,
        enabled = rule.enabled,
        channels = {
            public = not rule.channels or rule.channels.public ~= false,
            guild = rule.channels and rule.channels.guild == true or false,
        },
    }

    local ok, result = self:UpdateRule(pending.id, pending.name, pending.expression, nil, pending.channels)
    if not ok then
        setStatus(self.mainFrame.rulesPanel, tostring(result), "ffff5555")
        return
    end

    self.DB.lastRuleUndo = before
    local updated = self:FindRule(pending.id)
    self:LoadRuleIntoEditor(updated)
    setStatus(self.mainFrame.rulesPanel, "修改已保存；如有误可点“回退上次修改”", "ff66ff99")
end

function WKM:UndoLastRuleUpdate()
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    local backup = self.DB.lastRuleUndo
    if not backup then
        setStatus(panel, "当前没有可回退的规则修改", "ffffcc55")
        return
    end

    local rule = self:FindRule(backup.id)
    if not rule then
        setStatus(panel, "原规则已不存在，无法回退", "ffff5555")
        return
    end

    local ok, result = self:UpdateRule(backup.id, backup.name, backup.expression, backup.enabled, backup.channels)
    if not ok then
        setStatus(panel, tostring(result), "ffff5555")
        return
    end

    self.DB.lastRuleUndo = false
    self:LoadRuleIntoEditor(self:FindRule(backup.id))
    setStatus(panel, "已回退到修改前的规则", "ff66ff99")
end

function WKM:SaveRuleEditor()
    local panel = self.mainFrame.rulesPanel
    local name = trim(panel.nameEdit:GetText())
    local expression = trim(panel.exprEdit:GetText())
    local channels = editorChannels(panel)

    if not channels.public and not channels.guild then
        setStatus(panel, "至少选择一个监听频道", "ffff5555")
        return
    end

    if name == "" then
        setStatus(panel, "规则名称不能为空", "ffff5555")
        return
    end

    local valid, err = self.Rules.Validate(expression)
    if not valid then
        setStatus(panel, tostring(err), "ffff5555")
        return
    end

    if not panel.selectedId then
        local ok, result = self:AddRule(name, expression, channels)
        if not ok then
            setStatus(panel, tostring(result), "ffff5555")
            return
        end
        self:LoadRuleIntoEditor(result)
        panel.page = 1
        self:RefreshRulesUI(true)
        setStatus(panel, "新规则已创建，已排到第 1 页最上方", "ff66ff99")
        return
    end

    local current = self:FindRule(panel.selectedId)
    if not current then
        setStatus(panel, "规则不存在，请重新选择", "ffff5555")
        return
    end

    local currentChannels = current.channels or { public = true, guild = false }
    if current.name == name and current.expression == expression
        and (currentChannels.public ~= false) == channels.public
        and (currentChannels.guild == true) == channels.guild then
        setStatus(panel, "没有需要保存的修改", "ffffcc55")
        return
    end

    self.pendingRuleUpdate = {
        id = panel.selectedId,
        name = name,
        expression = expression,
        channels = channels,
    }

    StaticPopup_Show("WKM_CONFIRM_RULE_UPDATE", current.name)
end

function WKM:ConfirmDeleteRule(id)
    local rule = self:FindRule(id)
    if not rule then return end
    self.pendingDeleteRuleId = id
    StaticPopup_Show("WKM_CONFIRM_RULE_DELETE", rule.name)
end

StaticPopupDialogs["WKM_CONFIRM_RULE_UPDATE"] = {
    text = "确认修改规则「%s」？\n\n修改保存后仍可使用“回退上次修改”恢复一次。",
    button1 = "确认修改",
    button2 = "取消",
    OnAccept = function() WKM:CommitPendingRuleUpdate() end,
    OnCancel = function() WKM.pendingRuleUpdate = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["WKM_CONFIRM_RULE_DELETE"] = {
    text = "确认删除规则「%s」？\n\n删除后不会触发匹配。",
    button1 = "删除",
    button2 = "取消",
    OnAccept = function()
        local id = WKM.pendingDeleteRuleId
        WKM.pendingDeleteRuleId = nil
        if not id then return end
        WKM:DeleteRule(id)
        local panel = WKM.mainFrame and WKM.mainFrame.rulesPanel
        if panel and panel.selectedId == id then WKM:BeginNewRule() end
    end,
    OnCancel = function() WKM.pendingDeleteRuleId = nil end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local RULES_PER_PAGE = 9

function WKM:GetRulePageCount()
    local total = #(self.DB.rules or {})
    return math.max(1, math.ceil(total / RULES_PER_PAGE))
end

function WKM:SetRulePage(page)
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    if not panel then return end

    local pages = self:GetRulePageCount()
    panel.page = math.max(1, math.min(pages, tonumber(page) or 1))
    self:RefreshRulesUI()
end

function WKM:ChangeRulePage(delta)
    local panel = self.mainFrame and self.mainFrame.rulesPanel
    if not panel then return end
    self:SetRulePage((panel.page or 1) + delta)
end

local function bindRuleWheel(widget)
    widget:EnableMouseWheel(true)
    widget:SetScript("OnMouseWheel", function(_, delta)
        if delta < 0 then
            WKM:ChangeRulePage(1)
        elseif delta > 0 then
            WKM:ChangeRulePage(-1)
        end
    end)
end

function WKM:CreateRuleRow(panel, index)
    local row = CreateFrame("Frame", nil, panel)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 4, -154 - (index - 1) * ROW_H)
    row:SetPoint("RIGHT", -4, 0)
    bindRuleWheel(row)

    row.switch = self:CreateToggleSwitch(row, true, function(value, toggle)
        if toggle.ruleId then
            WKM:UpdateRule(toggle.ruleId, nil, nil, value)
            panel.page = 1
            WKM:RefreshRulesUI(true)
        end
    end)
    row.switch:SetPoint("LEFT", 2, 0)
    bindRuleWheel(row.switch)

    row.name = self:CreateButton(row, "", 170, 24)
    row.name:SetPoint("LEFT", 64, 0)
    bindRuleWheel(row.name)
    row.name:SetScript("OnClick", function(button)
        local rule = WKM:FindRule(button.ruleId)
        if rule then WKM:LoadRuleIntoEditor(rule) end
    end)

    row.expr = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.expr:SetPoint("LEFT", 240, 0)
    row.expr:SetWidth(395)
    row.expr:SetJustifyH("LEFT")
    row.expr:SetWordWrap(false)

    row.scope = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.scope:SetPoint("LEFT", 642, 0)
    row.scope:SetWidth(102)
    row.scope:SetJustifyH("LEFT")
    row.scope:SetWordWrap(false)

    row.del = self:CreateButton(row, "删除", 58, 22)
    row.del:SetPoint("RIGHT", -4, 0)
    bindRuleWheel(row.del)
    row.del:SetScript("OnClick", function(button)
        if button.ruleId then WKM:ConfirmDeleteRule(button.ruleId) end
    end)

    panel.rows[index] = row
    return row
end

function WKM:CreateRulesPanel(panel)
    panel.rows = {}
    panel.page = 1

    local nameLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameLabel:SetPoint("TOPLEFT", 8, -8)
    nameLabel:SetText("名称")

    panel.nameEdit = self:CreateEditBox(panel, 190, 26)
    panel.nameEdit:SetPoint("TOPLEFT", 8, -28)
    panel.nameEdit:SetScript("OnTextChanged", function() markDirty(panel) end)

    local expressionLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expressionLabel:SetPoint("TOPLEFT", 210, -8)
    expressionLabel:SetText("规则表达式")

    panel.exprEdit = self:CreateEditBox(panel, 600, 26)
    panel.exprEdit:SetPoint("TOPLEFT", 210, -28)
    panel.exprEdit:SetScript("OnTextChanged", function() markDirty(panel) end)
    panel.exprEdit:SetScript("OnEditFocusGained", function()
        setStatus(panel, "规则框已激活：可 Shift+点击任务、物品等游戏链接插入名称", "ffbbbbbb")
    end)

    panel.mode = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.mode:SetPoint("TOPLEFT", 8, -62)
    panel.mode:SetWidth(330)
    panel.mode:SetJustifyH("LEFT")

    panel.new = self:CreateButton(panel, "新建", 70, 24)
    panel.new:SetPoint("TOPLEFT", 350, -58)
    panel.new:SetScript("OnClick", function() WKM:BeginNewRule() end)

    panel.save = self:CreateButton(panel, "保存新规则", 100, 24)
    panel.save:SetPoint("LEFT", panel.new, "RIGHT", 6, 0)
    panel.save:SetScript("OnClick", function() WKM:SaveRuleEditor() end)

    panel.cancel = self:CreateButton(panel, "撤销编辑", 90, 24)
    panel.cancel:SetPoint("LEFT", panel.save, "RIGHT", 6, 0)
    panel.cancel:SetScript("OnClick", function() WKM:CancelRuleEdit() end)

    panel.undo = self:CreateButton(panel, "回退上次修改", 110, 24)
    panel.undo:SetPoint("LEFT", panel.cancel, "RIGHT", 6, 0)
    panel.undo:SetScript("OnClick", function() WKM:UndoLastRuleUpdate() end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 8, -92)
    panel.status:SetWidth(800)
    panel.status:SetJustifyH("LEFT")

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    help:SetPoint("TOPLEFT", 8, -110)
    help:SetWidth(418)
    help:SetJustifyH("LEFT")
    help:SetText("AND / OR / NOT；空格默认 AND；Shift+点击插入链接")

    local channelLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    channelLabel:SetPoint("TOPLEFT", 446, -112)
    channelLabel:SetText("监听：")

    panel.publicCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.publicCheck:SetSize(22, 22)
    panel.publicCheck:SetPoint("TOPLEFT", 494, -106)
    panel.publicCheck:SetScript("OnClick", function() markDirty(panel) end)
    local publicText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    publicText:SetPoint("LEFT", panel.publicCheck, "RIGHT", 0, 0)
    publicText:SetText("公共频道")

    panel.guildCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    panel.guildCheck:SetSize(22, 22)
    panel.guildCheck:SetPoint("TOPLEFT", 615, -106)
    panel.guildCheck:SetScript("OnClick", function() markDirty(panel) end)
    local guildText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    guildText:SetPoint("LEFT", panel.guildCheck, "RIGHT", 0, 0)
    guildText:SetText("公会频道")

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 8, -134)
    header:SetText("状态        名称                       表达式")

    local scopeHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scopeHeader:SetPoint("TOPLEFT", 646, -134)
    scopeHeader:SetText("监听频道")

    for i = 1, RULES_PER_PAGE do
        self:CreateRuleRow(panel, i)
    end

    panel.prevPage = self:CreateButton(panel, "上一页", 72, 24)
    panel.prevPage:SetPoint("BOTTOMLEFT", 8, 4)
    panel.prevPage:SetScript("OnClick", function() WKM:ChangeRulePage(-1) end)

    panel.pageText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.pageText:SetPoint("LEFT", panel.prevPage, "RIGHT", 12, 0)
    panel.pageText:SetWidth(180)
    panel.pageText:SetJustifyH("LEFT")

    panel.nextPage = self:CreateButton(panel, "下一页", 72, 24)
    panel.nextPage:SetPoint("LEFT", panel.pageText, "RIGHT", 8, 0)
    panel.nextPage:SetScript("OnClick", function() WKM:ChangeRulePage(1) end)

    bindRuleWheel(panel)
    self:InstallRuleLinkHook()
    self:BeginNewRule()
    self:RefreshRulesUI(true)
end

function WKM:RefreshRulesUI(reset)
    if not self.mainFrame then return end
    local panel = self.mainFrame.rulesPanel
    if not panel then return end

    if reset then panel.page = 1 end

    local rules = self.DB.rules or {}
    local pages = self:GetRulePageCount()
    panel.page = math.max(1, math.min(pages, panel.page or 1))

    local startIndex = (panel.page - 1) * RULES_PER_PAGE + 1

    for i = 1, RULES_PER_PAGE do
        local row = panel.rows[i]
        local rule = rules[startIndex + i - 1]
        if rule then
            row:Show()
            row.switch.ruleId = rule.id
            self:SetToggleState(row.switch, rule.enabled)
            row.name.ruleId = rule.id
            row.name:SetText(rule.name)
            row.expr:SetText(rule.expression)
            row.scope:SetText(channelsLabel(rule))
            row.del.ruleId = rule.id
        else
            row:Hide()
            row.switch.ruleId = nil
            row.name.ruleId = nil
            row.del.ruleId = nil
        end
    end

    if panel.pageText then
        panel.pageText:SetText(string.format("第 %d / %d 页 · 共 %d 条", panel.page, pages, #rules))
    end
    if panel.prevPage then panel.prevPage:SetEnabled(panel.page > 1) end
    if panel.nextPage then panel.nextPage:SetEnabled(panel.page < pages) end
end
