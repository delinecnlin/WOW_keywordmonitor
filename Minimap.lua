WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

local function place(button, angle)
    angle = angle or (WKM.DB and WKM.DB.minimapAngle) or 225
    local r = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(r) * 80, math.sin(r) * 80)
end

function WKM:UpdateMinimapState()
    if not self.minimapButton or not self.DB then return end
    local unread = self.DB.unread or 0
    self.minimapButton.badge:SetText(unread > 99 and "99+" or (unread > 0 and tostring(unread) or ""))
    if unread > 0 then
        self.minimapButton.icon:SetVertexColor(1, 0.35, 0.2)
        self.minimapButton:LockHighlight()
    else
        self.minimapButton.icon:SetVertexColor(1, 1, 1)
        self.minimapButton:UnlockHighlight()
    end
end

function WKM:CreateMinimapButton()
    if self.minimapButton then return end

    local b = CreateFrame("Button", "WOWKeywordMonitorMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:RegisterForClicks("LeftButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(19, 19)
    icon:SetTexture("Interface\\Icons\\Spell_Holy_MindVision")
    icon:SetPoint("CENTER")
    b.icon = icon

    local badge = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetPoint("TOP", b, "BOTTOM", 0, 3)
    badge:SetTextColor(1, 0.2, 0.2)
    b.badge = badge

    b:SetScript("OnClick", function() WKM:ToggleMainWindow() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("WOW Keyword Monitor")
        GameTooltip:AddLine("左键：打开匹配消息与规则", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("未读：" .. tostring(WKM.DB.unread or 0), 0.3, 0.9, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)

    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(btn)
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = (math.deg(atan2(cy - my, cx - mx)) + 360) % 360
            WKM.DB.minimapAngle = angle
            place(btn, angle)
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)

    self.minimapButton = b
    place(b)
    self:UpdateMinimapState()
end
