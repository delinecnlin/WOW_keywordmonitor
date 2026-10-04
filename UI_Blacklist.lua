WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor
local ROWS, ROW_H = 10, 36

local function whisper(name)
    if name and name ~= "" then
        ChatFrame_OpenChat("/w " .. name .. " ")
    end
end

local function invite(name)
    if name and name ~= "" then
        local ok, err = pcall(InviteUnit, name)
        if not ok then WKM:Print("邀请失败：" .. tostring(err)) end
    end
end

local function classColor(classFile)
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local color = colors and classFile and colors[classFile]
    if color then
        return color.r or 1, color.g or 1, color.b or 1
    end
    return 1, 0.82, 0
end

local function blacklistCount()
    if WKM.GetNativeIgnoreCount then
        return WKM:GetNativeIgnoreCount()
    end
    return 0
end

local function pointerOver(row)
    if not row or not row:IsShown() then return false end
    if MouseIsOver then return MouseIsOver(row) end
    if row.IsMouseOver then return row:IsMouseOver() end

    local left, right, top, bottom = row:GetLeft(), row:GetRight(), row:GetTop(), row:GetBottom()
    if not left or not right or not top or not bottom then return false end
    local x, y = GetCursorPosition()
    local scale = row:GetEffectiveScale() or UIParent:GetEffectiveScale()
    x, y = x / scale, y / scale
    return x >= left and x <= right and y >= bottom and y <= top
end

function WKM:CreateBlacklistPanel(panel)
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
        row.time:SetPoint("LEFT", 4, 0)
        row.time:SetWidth(72)
        row.time:SetJustifyH("LEFT")

        row.sender = WKM:CreateButton(row, "", 112, 23)
        row.sender:SetPoint("LEFT", 78, 0)
        row.sender:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row.sender:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                WKM:ShowPlayerContextMenu(self.player, self.classFile, self.className)
            else
                whisper(self.player)
            end
        end)

        row.rule = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rule:SetPoint("LEFT", 195, 0)
        row.rule:SetWidth(135)
        row.rule:SetJustifyH("LEFT")
        row.rule:SetWordWrap(false)

        row.channel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.channel:SetPoint("LEFT", 334, 0)
        row.channel:SetWidth(85)
        row.channel:SetJustifyH("LEFT")
        row.channel:SetWordWrap(false)

        row.msg = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.msg:SetPoint("LEFT", 423, 0)
        row.msg:SetWidth(250)
        row.msg:SetJustifyH("LEFT")
        row.msg:SetWordWrap(false)

        row.remove = WKM:CreateButton(row, "移", 28, 22)
        row.remove:SetPoint("RIGHT", -100, 0)
        row.remove:SetScript("OnClick", function(self)
            if self.player then WKM:RemoveFromBlacklist(self.player) end
        end)

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
    panel.empty:SetPoint("CENTER", 0, 20)
    panel.empty:SetText("还没有黑名单匹配消息")

    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.count:SetPoint("BOTTOMLEFT", 8, 8)

    local clear = self:CreateButton(panel, "清空黑名单历史", 120, 24)
    clear:SetPoint("BOTTOMRIGHT", -8, 4)
    clear:SetScript("OnClick", function() WKM:ClearBlacklistHistory() end)

    panel:EnableMouseWheel(true)
    panel:SetScript("OnMouseWheel", function(_, delta)
        local max = math.max(0, #WKM.DB.blacklistHistory - ROWS)
        panel.offset = math.max(0, math.min(max, panel.offset + (delta < 0 and 1 or -1)))
        WKM:RefreshBlacklistUI()
    end)

    panel.tick = 0
    panel.hoverCheck = 0
    panel.hoveredRow = nil
    panel.hoveredEntry = nil
    panel:SetScript("OnUpdate", function(self, elapsed)
        if not self:IsShown() then
            if self.hoveredRow then
                self.hoveredRow = nil
                self.hoveredEntry = nil
                WKM:HideHistoryEntryTooltip()
            end
            return
        end

        self.hoverCheck = self.hoverCheck + elapsed
        if self.hoverCheck >= 0.05 then
            self.hoverCheck = 0
            local hovered = nil
            for _, row in ipairs(self.rows) do
                if row:IsShown() and row.entry and pointerOver(row) then
                    hovered = row
                    break
                end
            end

            local hoveredEntry = hovered and hovered.entry or nil
            if hovered ~= self.hoveredRow or hoveredEntry ~= self.hoveredEntry then
                self.hoveredRow = hovered
                self.hoveredEntry = hoveredEntry
                if hovered and hoveredEntry then
                    WKM:ShowHistoryEntryTooltip(hovered, hoveredEntry)
                else
                    WKM:HideHistoryEntryTooltip()
                end
            end
        end

        self.tick = self.tick + elapsed
        if self.tick >= 5 then
            self.tick = 0
            WKM:RefreshBlacklistUI()
        end
    end)
end

function WKM:RefreshBlacklistUI(reset)
    if not self.mainFrame then return end
    self:PruneExpiredHistory()

    local p, hist = self.mainFrame.blacklistPanel, self.DB.blacklistHistory
    if not p then return end
    if reset then p.offset = 0 end
    p.offset = math.min(p.offset or 0, math.max(0, #hist - ROWS))
    p.empty:SetShown(#hist == 0)
    p.count:SetText(string.format("黑名单 %d 人 · 已保存 %d / %d 条", blacklistCount(), #hist, self.DB.settings.maxHistory))

    for i, row in ipairs(p.rows) do
        local e = hist[#hist - p.offset - i + 1]
        if e then
            if not e.classFile and e.guid then
                e.classFile, e.className = self:GetPlayerClassByGUID(e.guid)
            end

            row:Show()
            row.entry = e
            row.time:SetText(self:GetRelativeTime(e.timestamp))

            row.sender:SetText(e.sender or "?")
            row.sender.player = e.sender
            row.sender.classFile = e.classFile
            row.sender.className = e.className

            local r, g, b = classColor(e.classFile)
            local fontString = row.sender:GetFontString()
            if fontString then fontString:SetTextColor(r, g, b) end

            row.rule:SetText(table.concat(e.ruleNames or {}, ","))
            row.channel:SetText(e.channel or "?")
            row.msg:SetText(self.Rules.Highlight(e.message, e.matchedTerms))

            row.remove.player = e.sender
            row.remove:SetEnabled(self:IsBlacklisted(e.sender, e.guid))
            row.pm.player = e.sender
            row.inv.player = e.sender
            row.copy.player = e.sender
        else
            row.entry = nil
            row.sender.player = nil
            row.remove.player = nil
            row.pm.player = nil
            row.inv.player = nil
            row.copy.player = nil
            row:Hide()
        end
    end
end
