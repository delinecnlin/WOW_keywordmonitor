WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor
local ROW_H = 38
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
        self:RefreshRulesUI(true)
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

function WKM:ScrollRulesByWheel(panel, delta)
    if not panel or not panel.ruleScroll then return end
    local scrollFrame = panel.ruleScroll
    local maxScroll = scrollFrame:GetVerticalScrollRange() or 0
    local current = scrollFrame:GetVerticalScroll() or 0
    local step = ROW_H * 2
    local target = current - (delta * step)
    target = math.max(0, math.min(maxScroll, target))

    scrollFrame:SetVerticalScroll(target)
    if panel.ruleScrollBar then
        panel.ruleScrollBar:SetValue(target)
    end
end

local function bindRuleWheel(widget, panel)
    widget:EnableMouseWheel(true)
    widget:SetScript("OnMouseWheel", function(_, delta)
        WKM:ScrollRulesByWheel(panel, delta)
    end)
end

function WKM:CreateRuleRow(panel, index)
    local parent = panel.ruleScrollChild
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", 0, -((index - 1) * ROW_H))
    row:SetPoint("RIGHT", -4, 0)
    bindRuleWheel(row, panel)

    row.switch = self:CreateToggleSwitch(row, true, function(value, toggle)
        if toggle.ruleId then
            WKM:UpdateRule(toggle.ruleId, nil, nil, value)
        end
    end)
    row.switch:SetPoint("LEFT", 2, 0)
    bindRuleWheel(row.switch, panel)

    row.name = self:CreateButton(row, "", 170, 24)
    row.name:SetPoint("LEFT", 64, 0)
    bindRuleWheel(row.name, panel)
    row.name:SetScript("OnClick", function(button)
        local rule = WKM:FindRule(button.ruleId)
        if rule then WKM:LoadRuleIntoEditor(rule) end
    end)

    row.expr = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.expr:SetPoint("LEFT", 240, 0)
    row.expr:SetWidth(475)
    row.expr:SetJustifyH("LEFT")
    row.expr:SetWordWrap(false)

    row.del = self:CreateButton(row, "删除", 58, 22)
    row.del:SetPoint("RIGHT", -4, 0)
    bindRuleWheel(row.del, panel)
    row.del:SetScript("OnClick", function(button)
        if button.ruleId then WKM:ConfirmDeleteRule(button.ruleId) end
    end)

    panel.rows[index] = row
    return row
end

function WKM:CreateRulesPanel(panel)
    panel.rows = {}

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

    panel.ruleScroll = CreateFrame("ScrollFrame", nil, panel)
    panel.ruleScroll:SetPoint("TOPLEFT", 4, -154)
    panel.ruleScroll:SetPoint("BOTTOMRIGHT", -30, 34)
    panel.ruleScroll:EnableMouse(true)
    bindRuleWheel(panel.ruleScroll, panel)

    panel.ruleScrollChild = CreateFrame("Frame", nil, panel.ruleScroll)
    panel.ruleScrollChild:SetSize(760, 1)
    panel.ruleScroll:SetScrollChild(panel.ruleScrollChild)

    panel.ruleScrollBar = CreateFrame("Slider", nil, panel)
    panel.ruleScrollBar:SetOrientation("VERTICAL")
    panel.ruleScrollBar:EnableMouse(true)
    bindRuleWheel(panel.ruleScrollBar, panel)
    panel.ruleScrollBar:SetPoint("TOPRIGHT", -7, -154)
    panel.ruleScrollBar:SetPoint("BOTTOMRIGHT", -7, 34)
    panel.ruleScrollBar:SetWidth(16)
    panel.ruleScrollBar:SetMinMaxValues(0, 0)
    panel.ruleScrollBar:SetValue(0)
    panel.ruleScrollBar:SetValueStep(ROW_H)
    if panel.ruleScrollBar.SetObeyStepOnDrag then
        panel.ruleScrollBar:SetObeyStepOnDrag(false)
    end

    local track = panel.ruleScrollBar:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetTexture("Interface\\Buttons\\WHITE8x8")
    track:SetVertexColor(0.12, 0.12, 0.12, 0.75)

    panel.ruleScrollBar:SetThumbTexture("Interface\\Buttons\\WHITE8x8")
    local thumb = panel.ruleScrollBar:GetThumbTexture()
    if thumb then
        thumb:SetSize(12, 36)
        thumb:SetVertexColor(0.55, 0.55, 0.55, 0.95)
    end

    panel.ruleScrollBar:SetScript("OnValueChanged", function(_, value)
        panel.ruleScroll:SetVerticalScroll(value or 0)
    end)

    panel.ruleScroll:SetScript("OnVerticalScroll", function(_, offset)
        if panel.ruleScrollBar and panel.ruleScrollBar:GetValue() ~= offset then
            panel.ruleScrollBar:SetValue(offset)
        end
    end)

    self:InstallRuleLinkHook()
    self:BeginNewRule()
    self:RefreshRulesUI(true)
end

function WKM:RefreshRulesUI(reset)
    if not self.mainFrame then return end
    local panel = self.mainFrame.rulesPanel
    if not panel or not panel.ruleScroll or not panel.ruleScrollChild then return end

    local rules = self.DB.rules or {}

    for i, rule in ipairs(rules) do
        local row = panel.rows[i] or self:CreateRuleRow(panel, i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
        row:SetPoint("RIGHT", -4, 0)
        row:Show()

        row.switch.ruleId = rule.id
        self:SetToggleState(row.switch, rule.enabled)

        row.name.ruleId = rule.id
        row.name:SetText(rule.name)

        row.expr:SetText(rule.expression)
        row.del.ruleId = rule.id
    end

    for i = #rules + 1, #panel.rows do
        panel.rows[i]:Hide()
    end

    local viewportHeight = math.max(1, panel.ruleScroll:GetHeight() or 1)
    local viewportWidth = math.max(1, panel.ruleScroll:GetWidth() or 1)
    local contentHeight = math.max(viewportHeight, #rules * ROW_H)

    panel.ruleScrollChild:SetWidth(viewportWidth)
    panel.ruleScrollChild:SetHeight(contentHeight)
    panel.ruleScroll:UpdateScrollChildRect()

    local maxScroll = math.max(0, contentHeight - viewportHeight)
    panel.ruleScrollBar:SetMinMaxValues(0, maxScroll)
    panel.ruleScrollBar:SetShown(maxScroll > 0)

    local current = reset and 0 or (panel.ruleScroll:GetVerticalScroll() or 0)
    current = math.max(0, math.min(maxScroll, current))
    panel.ruleScroll:SetVerticalScroll(current)
    panel.ruleScrollBar:SetValue(current)
end
