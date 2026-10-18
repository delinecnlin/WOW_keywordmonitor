WOWKeywordMonitor = WOWKeywordMonitor or {}
local WKM = WOWKeywordMonitor

local function shorten(text, maxLen)
    text = WKM.Rules and WKM.Rules.Sanitize(text) or tostring(text or "")
    if #text <= maxLen then return text end
    return text:sub(1, maxLen - 3) .. "..."
end

function WKM:Notify(entry)
    if not entry then return end
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

    if settings.screenAlert and RaidNotice_AddMessage and RaidWarningFrame then
        local rules = table.concat(entry.ruleNames or {}, ", ")
        local line = string.format("[%s] %s: %s", rules, entry.sender or "?", shorten(entry.message, 150))
        RaidNotice_AddMessage(RaidWarningFrame, line, ChatTypeInfo["RAID_WARNING"])
    end

    if self.UpdateMinimapState then
        self:UpdateMinimapState()
    end
end
