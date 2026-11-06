WOWKeywordMonitorForever = WOWKeywordMonitorForever or {}
local WKM = WOWKeywordMonitorForever

-- Use a standalone, UIParent-owned banner instead of RaidWarningFrame.
-- The raid-notice API can be hidden or unavailable in Forever's UI.
local DISPLAY_SECONDS = 4.5

local function safeShorten(message, maxBytes)
    local text = WKM.Rules and WKM.Rules.Sanitize(message) or tostring(message or "")
    if #text <= maxBytes then return text end

    -- Avoid truncating Chinese UTF-8 characters in the middle of a byte sequence.
    local cut = maxBytes - 3
    while cut > 1 do
        local byte = text:byte(cut)
        if not byte or byte < 128 or byte >= 192 then break end
        cut = cut - 1
    end
    return text:sub(1, cut - 1) .. "..."
end

function WKM:EnsureScreenAlert()
    if self.screenAlertFrame then return self.screenAlertFrame end

    local frame = CreateFrame("Frame", "WKMF_ScreenAlert", UIParent)
    frame:SetSize(780, 132)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 160)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(false)

    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.02, 0.06, 0.10, 0.88)

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetTexture("Interface\\Buttons\\WHITE8x8")
    accent:SetVertexColor(1, 0.67, 0.12, 1)
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    accent:SetSize(780, 5)

    frame.titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.titleText:SetPoint("TOP", frame, "TOP", 0, -18)
    frame.titleText:SetWidth(735)
    frame.titleText:SetJustifyH("CENTER")
    frame.titleText:SetTextColor(1, 0.82, 0.20)

    frame.bodyText = frame:CreateFontString(nil, "OVERLAY",
        GameFontNormalHuge and "GameFontNormalHuge" or "GameFontNormalLarge")
    frame.bodyText:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -49)
    frame.bodyText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 14)
    frame.bodyText:SetJustifyH("CENTER")
    frame.bodyText:SetJustifyV("MIDDLE")
    frame.bodyText:SetWordWrap(true)
    frame.bodyText:SetTextColor(1, 1, 1)

    frame.remaining = 0
    frame:SetScript("OnUpdate", function(self, elapsed)
        self.remaining = self.remaining - elapsed
        if self.remaining <= 0 then self:Hide() end
    end)
    frame:Hide()
    self.screenAlertFrame = frame
    return frame
end

function WKM:ShowScreenAlert(entry)
    if not entry then return end
    local frame = self:EnsureScreenAlert()
    local names = table.concat(entry.ruleNames or {}, "、")
    if names == "" then names = "关键词命中" end
    local channel = tostring(entry.channel or "聊天")
    local sender = tostring(entry.sender or "未知玩家")

    frame.titleText:SetText("【关键词提醒 · " .. channel .. "】 " .. safeShorten(names, 100))
    frame.bodyText:SetText(sender .. "：" .. safeShorten(entry.message, 195))
    frame.remaining = DISPLAY_SECONDS
    frame:Show()
    self.screenAlertShownCount = (self.screenAlertShownCount or 0) + 1
end

function WKM:TestScreenAlert()
    self:ShowScreenAlert({
        channel = "测试",
        sender = "示例玩家",
        ruleNames = { "无限服屏幕大字测试" },
        message = "如果你看到这条居中提示，说明插件大字显示功能正常。",
    })
end

function WKM:Notify(entry)
    if not entry then return end
    self.notifyCount = (self.notifyCount or 0) + 1
    local settings = self.DB and self.DB.settings or {}

    if settings.sound and SOUNDKIT and SOUNDKIT.TELL_MESSAGE then
        PlaySound(SOUNDKIT.TELL_MESSAGE, "Master")
    end

    if settings.clientIconAlert and FlashClientIcon then
        local now = GetTime and GetTime() or 0
        if not self.lastClientIconFlash or now - self.lastClientIconFlash >= 2 then
            self.lastClientIconFlash = now
            pcall(FlashClientIcon, true)
        end
    end

    -- This is our own visible overlay, not a raid warning that the
    -- user or another addon can hide or relocate.
    if settings.screenAlert then
        self:ShowScreenAlert(entry)
    end

    if self.UpdateMinimapState then
        self:UpdateMinimapState()
    end
end
