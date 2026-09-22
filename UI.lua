WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

function WKM:StylePanel(frame)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
end

function WKM:CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 90, height or 24)
    button:SetText(text or "")
    return button
end

function WKM:CreateEditBox(parent, width, height)
    local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    edit:SetSize(width or 160, height or 24)
    edit:SetAutoFocus(false)
    edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return edit
end

local function addCheckLabel(check, text)
    local label = check:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", check, "RIGHT", 2, 0)
    label:SetText(text)
    return label
end

function WKM:UpdateGlobalState()
    if not self.mainFrame then return end
    self.mainFrame.listenButton:SetText(self.DB.enabled and "监听：开启" or "监听：关闭")
    self.mainFrame.soundCheck:SetChecked(self.DB.settings.sound)
    self.mainFrame.screenCheck:SetChecked(self.DB.settings.screenAlert)
    self.mainFrame.autoDeleteCheck:SetChecked(self.DB.settings.autoDeleteOldMessages)
end

function WKM:ShowTab(tabName)
    if not self.mainFrame then return end
    local showHistory = tabName ~= "rules"
    self.mainFrame.historyPanel:SetShown(showHistory)
    self.mainFrame.rulesPanel:SetShown(not showHistory)
    self.mainFrame.historyTab:SetEnabled(not showHistory)
    self.mainFrame.rulesTab:SetEnabled(showHistory)

    if showHistory then
        self:MarkRead()
        if self.RefreshHistoryUI then self:RefreshHistoryUI(true) end
    elseif self.RefreshRulesUI then
        self:RefreshRulesUI(true)
    end
end

function WKM:ToggleMainWindow()
    if not self.mainFrame then return end
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
        self:ShowTab("history")
    end
end

function WKM:CreateMainWindow()
    if self.mainFrame then return end

    local template = BackdropTemplateMixin and "BackdropTemplate" or nil
    local frame = CreateFrame("Frame", "WOWKeywordMonitorMainFrame", UIParent, template)
    frame:SetSize(860, 570)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    self:StylePanel(frame)
    self.mainFrame = frame

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 22, -18)
    title:SetText("WOW Keyword Monitor")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("LEFT", title, "RIGHT", 12, 0)
    subtitle:SetText("Classic Era / Hardcore")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -5, -5)

    frame.listenButton = self:CreateButton(frame, "", 100, 24)
    frame.listenButton:SetPoint("TOPRIGHT", -48, -42)
    frame.listenButton:SetScript("OnClick", function()
        WKM:SetEnabled(not WKM.DB.enabled)
    end)

    frame.soundCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.soundCheck:SetPoint("TOPLEFT", 22, -48)
    addCheckLabel(frame.soundCheck, "声音提醒")
    frame.soundCheck:SetScript("OnClick", function(self)
        WKM.DB.settings.sound = self:GetChecked() and true or false
    end)

    frame.screenCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.screenCheck:SetPoint("LEFT", frame.soundCheck, "RIGHT", 100, 0)
    addCheckLabel(frame.screenCheck, "屏幕大字")
    frame.screenCheck:SetScript("OnClick", function(self)
        WKM.DB.settings.screenAlert = self:GetChecked() and true or false
    end)

    frame.autoDeleteCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    frame.autoDeleteCheck:SetPoint("LEFT", frame.screenCheck, "RIGHT", 115, 0)
    addCheckLabel(frame.autoDeleteCheck, "自动删除 >10分钟")
    frame.autoDeleteCheck:SetScript("OnClick", function(self)
        WKM.DB.settings.autoDeleteOldMessages = self:GetChecked() and true or false
        if WKM.DB.settings.autoDeleteOldMessages then
            WKM:PruneExpiredHistory()
            if WKM.RefreshHistoryUI then WKM:RefreshHistoryUI(true) end
        end
    end)

    frame.historyTab = self:CreateButton(frame, "匹配消息", 110, 26)
    frame.historyTab:SetPoint("TOPLEFT", 22, -82)
    frame.historyTab:SetScript("OnClick", function() WKM:ShowTab("history") end)

    frame.rulesTab = self:CreateButton(frame, "规则设置", 110, 26)
    frame.rulesTab:SetPoint("LEFT", frame.historyTab, "RIGHT", 6, 0)
    frame.rulesTab:SetScript("OnClick", function() WKM:ShowTab("rules") end)

    frame.historyPanel = CreateFrame("Frame", nil, frame)
    frame.historyPanel:SetPoint("TOPLEFT", 18, -115)
    frame.historyPanel:SetPoint("BOTTOMRIGHT", -18, 18)

    frame.rulesPanel = CreateFrame("Frame", nil, frame)
    frame.rulesPanel:SetPoint("TOPLEFT", 18, -115)
    frame.rulesPanel:SetPoint("BOTTOMRIGHT", -18, 18)

    if self.CreateHistoryPanel then self:CreateHistoryPanel(frame.historyPanel) end
    if self.CreateRulesPanel then self:CreateRulesPanel(frame.rulesPanel) end

    frame:SetScript("OnShow", function()
        WKM:UpdateGlobalState()
        WKM:ShowTab("history")
    end)

    self:UpdateGlobalState()
    self:ShowTab("history")
end
