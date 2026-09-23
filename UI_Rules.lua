WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor
local ROWS = 8
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
    }

    local ok, result = self:UpdateRule(pending.id, pending.name, pending.expression, nil)
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

    local ok, result = self:UpdateRule(backup.id, backup.name, backup.expression, backup.enabled)
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
        local ok, result = self:AddRule(name, expression)
        if not ok then
            setStatus(panel, tostring(result), "ffff5555")
            return
        end
        self:LoadRuleIntoEditor(result)
        setStatus(panel, "新规则已创建", "ff66ff99")
        return
    end

    local current = self:FindRule(panel.selectedId)
    if not current then
        setStatus(panel, "规则不存在，请重新选择", "ffff5555")
        return
    end

    if current.name == name and current.expression == expression then
        setStatus(panel, "没有需要保存的修改", "ffffcc55")
        return
    end

    self.pendingRuleUpdate = {
        id = panel.selectedId,
        name = name,
        expression = expression,
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

function WKM:CreateRulesPanel(panel)
    panel.offset, panel.rows = 0, {}

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
    help:SetWidth(800)
    help:SetJustifyH("LEFT")
    help:SetText("支持 AND / OR / NOT / 括号；空格默认 AND。规则框获得焦点后可 Shift+点击任务/物品链接插入名称。")

    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", 8, -134)
    header:SetText("状态        名称                       表达式")

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(38)
        row:SetPoint("TOPLEFT", 4, -154 - (i - 1) * 38)
        row:SetPoint("RIGHT", -4, 0)

        row.switch = WKM:CreateToggleSwitch(row, true, function(value, self)
            if self.ruleId then WKM:UpdateRule(self.ruleId, nil, nil, value) end
        end)
        row.switch:SetPoint("LEFT", 2, 0)

        row.name = WKM:CreateButton(row, "", 170, 24)
        row.name:SetPoint("LEFT", 64, 0)
        row.name:SetScript("OnClick", function(self)
            local rule = WKM:FindRule(self.ruleId)
            if rule then WKM:LoadRuleIntoEditor(rule) end
        end)

        row.expr = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.expr:SetPoint("LEFT", 240, 0)
        row.expr:SetWidth(493)
        row.expr:SetJustifyH("LEFT")
        row.expr:SetWordWrap(false)

        row.del = WKM:CreateButton(row, "删除", 58, 22)
        row.del:SetPoint("RIGHT", -4, 0)
        row.del:SetScript("OnClick", function(self)
            if self.ruleId then WKM:ConfirmDeleteRule(self.ruleId) end
        end)

        panel.rows[i] = row
    end

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        local maxOffset = math.max(0, #WKM.DB.rules - ROWS)
        panel.offset = math.max(0, math.min(maxOffset, panel.offset + (delta < 0 and 1 or -1)))
        WKM:RefreshRulesUI()
    end)

    self:InstallRuleLinkHook()
    self:BeginNewRule()
end

function WKM:RefreshRulesUI(reset)
    if not self.mainFrame then return end
    local panel = self.mainFrame.rulesPanel
    if reset then panel.offset = 0 end
    panel.offset = math.min(panel.offset or 0, math.max(0, #self.DB.rules - ROWS))

    for i, row in ipairs(panel.rows) do
        local rule = self.DB.rules[panel.offset + i]
        if rule then
            row:Show()
            row.switch.ruleId = rule.id
            WKM:SetToggleState(row.switch, rule.enabled)
            row.name.ruleId = rule.id
            row.name:SetText(rule.name)
            row.expr:SetText(rule.expression)
            row.del.ruleId = rule.id
        else
            row:Hide()
        end
    end
end
