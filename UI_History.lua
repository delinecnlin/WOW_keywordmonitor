WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor
local ROWS, ROW_H = 10, 36

local function whisper(name)
    if name and name ~= "" then ChatFrame_OpenChat("/w " .. name .. " ") end
end

local function invite(name)
    if name and name ~= "" then
        local ok, err = pcall(InviteUnit, name)
        if not ok then WKM:Print("邀请失败：" .. tostring(err)) end
    end
end

function WKM:ShowCopyName(name)
    if not self.copyFrame then
        local tpl = BackdropTemplateMixin and "BackdropTemplate" or nil
        local f = CreateFrame("Frame", "WKM_CopyNameFrame", UIParent, tpl)
        f:SetSize(320, 95); f:SetPoint("CENTER"); f:SetFrameStrata("TOOLTIP")
        self:StylePanel(f)
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOP", 0, -18); t:SetText("Ctrl+C 复制玩家名字")
        f.edit = self:CreateEditBox(f, 245, 26); f.edit:SetPoint("CENTER", 0, -8)
        local x = CreateFrame("Button", nil, f, "UIPanelCloseButton"); x:SetPoint("TOPRIGHT", -4, -4)
        self.copyFrame = f
    end
    self.copyFrame.edit:SetText(name or "")
    self.copyFrame:Show()
    self.copyFrame.edit:SetFocus()
    self.copyFrame.edit:HighlightText()
end

function WKM:CreateHistoryPanel(panel)
    panel.offset, panel.rows = 0, {}

    local h = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    h:SetPoint("TOPLEFT", 8, -8)
    h:SetText("时间       玩家                 规则                    频道             消息")

    for i = 1, ROWS do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 4, -28 - (i - 1) * ROW_H)
        row:SetPoint("RIGHT", -4, 0)

        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.time:SetPoint("LEFT", 4, 0); row.time:SetWidth(72); row.time:SetJustifyH("LEFT")

        row.sender = WKM:CreateButton(row, "", 112, 23)
        row.sender:SetPoint("LEFT", 78, 0)
        row.sender:SetScript("OnClick", function(self) whisper(self.player) end)

        row.rule = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rule:SetPoint("LEFT", 195, 0); row.rule:SetWidth(135); row.rule:SetJustifyH("LEFT"); row.rule:SetWordWrap(false)

        row.channel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.channel:SetPoint("LEFT", 334, 0); row.channel:SetWidth(85); row.channel:SetJustifyH("LEFT"); row.channel:SetWordWrap(false)

        row.msg = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.msg:SetPoint("LEFT", 423, 0); row.msg:SetWidth(285); row.msg:SetJustifyH("LEFT"); row.msg:SetWordWrap(false)

        row.pm = WKM:CreateButton(row, "密", 28, 22)
        row.pm:SetPoint("RIGHT", -68, 0)
        row.pm:SetScript("OnClick", function(self) whisper(self.player) end)

        row.inv = WKM:CreateButton(row, "+", 28, 22)
        row.inv:SetPoint("RIGHT", -36, 0)
        row.inv:SetScript("OnClick", function(self) invite(self.player) end)

        row.copy = WKM:CreateButton(row, "复", 28, 22)
        row.copy:SetPoint("RIGHT", -4, 0)
        row.copy:SetScript("OnClick", function(self) WKM:ShowCopyName(self.player) end)

        panel.rows[i] = row
    end

    panel.empty = panel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("CENTER", 0, 20); panel.empty:SetText("还没有匹配消息")

    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.count:SetPoint("BOTTOMLEFT", 8, 8)

    local clear = self:CreateButton(panel, "清空历史", 90, 24)
    clear:SetPoint("BOTTOMRIGHT", -8, 4)
    clear:SetScript("OnClick", function() WKM:ClearHistory() end)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #WKM.DB.history - ROWS)
        panel.offset = math.max(0, math.min(max, panel.offset + (delta < 0 and 1 or -1)))
        WKM:RefreshHistoryUI()
    end)

    panel.tick = 0
    panel:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then return end
        self.tick = self.tick + elapsed
        if self.tick >= 5 then self.tick = 0; WKM:RefreshHistoryUI() end
    end)
end

function WKM:RefreshHistoryUI(reset)
    if not self.mainFrame then return end
    self:PruneExpiredHistory()
    local p, hist = self.mainFrame.historyPanel, self.DB.history
    if reset then p.offset = 0 end
    p.offset = math.min(p.offset or 0, math.max(0, #hist - ROWS))
    p.empty:SetShown(#hist == 0)
    p.count:SetText(string.format("已保存 %d / %d 条", #hist, self.DB.settings.maxHistory))

    for i, row in ipairs(p.rows) do
        local e = hist[#hist - p.offset - i + 1]
        if e then
            row:Show()
            row.time:SetText(self:GetRelativeTime(e.timestamp))
            row.sender:SetText(e.sender or "?"); row.sender.player = e.sender
            row.rule:SetText(table.concat(e.ruleNames or {}, ","))
            row.channel:SetText(e.channel or "?")
            row.msg:SetText(self.Rules.Highlight(e.message, e.matchedTerms))
            row.pm.player, row.inv.player, row.copy.player = e.sender, e.sender, e.sender
        else
            row:Hide()
        end
    end
end
