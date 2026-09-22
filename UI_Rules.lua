WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor
local ROWS = 9

function WKM:LoadRuleIntoEditor(rule)
    local p = self.mainFrame.rulesPanel
    p.selectedId = rule and rule.id or nil
    p.nameEdit:SetText(rule and rule.name or "")
    p.exprEdit:SetText(rule and rule.expression or "")
    p.save:SetText(rule and "保存修改" or "新增规则")
    p.status:SetText("")
end

function WKM:CreateRulesPanel(panel)
    panel.offset, panel.rows = 0, {}

    local n = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    n:SetPoint("TOPLEFT", 8, -8); n:SetText("名称")
    panel.nameEdit = self:CreateEditBox(panel, 190, 26)
    panel.nameEdit:SetPoint("TOPLEFT", 8, -28)

    local e = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    e:SetPoint("TOPLEFT", 210, -8); e:SetText("规则表达式")
    panel.exprEdit = self:CreateEditBox(panel, 560, 26)
    panel.exprEdit:SetPoint("TOPLEFT", 210, -28)

    panel.save = self:CreateButton(panel, "新增规则", 90, 24)
    panel.save:SetPoint("TOPRIGHT", -8, -28)
    panel.save:SetScript("OnClick", function()
        local name, expr = panel.nameEdit:GetText(), panel.exprEdit:GetText()
        local ok, result
        if panel.selectedId then
            ok, result = WKM:UpdateRule(panel.selectedId, name, expr, nil)
        else
            ok, result = WKM:AddRule(name, expr)
        end
        if ok then
            panel.status:SetText("|cff33ff66规则已保存|r")
            if not panel.selectedId and type(result) == "table" then panel.selectedId = result.id end
            panel.save:SetText("保存修改")
        else
            panel.status:SetText("|cffff5555" .. tostring(result) .. "|r")
        end
    end)

    panel.new = self:CreateButton(panel, "新建", 62, 24)
    panel.new:SetPoint("RIGHT", panel.save, "LEFT", -5, 0)
    panel.new:SetScript("OnClick", function() WKM:LoadRuleIntoEditor(nil) end)

    panel.status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.status:SetPoint("TOPLEFT", 8, -62)
    panel.status:SetWidth(800); panel.status:SetJustifyH("LEFT")
    panel.status:SetText("支持 AND / OR / NOT / 括号；空格连接默认视为 AND。短语可用引号。")

    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 8, -88)
    h:SetText("启用   名称                         表达式")

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(38)
        row:SetPoint("TOPLEFT", 4, -108 - (i - 1) * 38)
        row:SetPoint("RIGHT", -4, 0)

        row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        row.check:SetPoint("LEFT", 2, 0)
        row.check:SetScript("OnClick", function(self)
            if self.ruleId then WKM:UpdateRule(self.ruleId, nil, nil, self:GetChecked()) end
        end)

        row.name = WKM:CreateButton(row, "", 180, 24)
        row.name:SetPoint("LEFT", 42, 0)
        row.name:SetScript("OnClick", function(self)
            local rule = WKM:FindRule(self.ruleId)
            if rule then WKM:LoadRuleIntoEditor(rule) end
        end)

        row.expr = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.expr:SetPoint("LEFT", 228, 0)
        row.expr:SetWidth(505); row.expr:SetJustifyH("LEFT"); row.expr:SetWordWrap(false)

        row.del = WKM:CreateButton(row, "删除", 58, 22)
        row.del:SetPoint("RIGHT", -4, 0)
        row.del:SetScript("OnClick", function(self)
            if not self.ruleId then return end
            WKM:DeleteRule(self.ruleId)
            if panel.selectedId == self.ruleId then WKM:LoadRuleIntoEditor(nil) end
        end)

        panel.rows[i] = row
    end

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #WKM.DB.rules - ROWS)
        panel.offset = math.max(0, math.min(max, panel.offset + (delta < 0 and 1 or -1)))
        WKM:RefreshRulesUI()
    end)
end

function WKM:RefreshRulesUI(reset)
    if not self.mainFrame then return end
    local p = self.mainFrame.rulesPanel
    if reset then p.offset = 0 end
    p.offset = math.min(p.offset or 0, math.max(0, #self.DB.rules - ROWS))

    for i, row in ipairs(p.rows) do
        local rule = self.DB.rules[p.offset + i]
        if rule then
            row:Show()
            row.check.ruleId = rule.id; row.check:SetChecked(rule.enabled)
            row.name.ruleId = rule.id; row.name:SetText(rule.name)
            row.expr:SetText(rule.expression)
            row.del.ruleId = rule.id
        else
            row:Hide()
        end
    end
end
