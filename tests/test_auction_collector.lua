-- Minimal WoW API mock: verifies scan-state UI without claiming live-client compatibility.
local made = {}
local chat = {}
local callbacks = {}
local queryCount = 0
local queryArguments = nil
local scannedRows = 2
local resultItemName = "黑莲花"

local methods = {}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:IsShown() return self.shown end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:CreateTexture()
    local child = setmetatable({scripts={},events={},shown=true}, {__index=methods})
    made[#made + 1] = child
    return child
end
function methods:CreateFontString()
    return self:CreateTexture()
end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:SetColorTexture(r,g,b,a) self.color = {r,g,b,a} end
setmetatable(methods, {__index=function(_,key) return function() end end})
local function frame(name)
    local out = setmetatable({name=name,scripts={},events={},shown=true}, {__index=methods})
    made[#made + 1] = out
    return out
end

function CreateFrame(_,name) return frame(name) end
UIParent=frame("UIParent")
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) chat[#chat + 1] = message end}
SlashCmdList={}
function GetRealmName() return "硬核服" end
function UnitFactionGroup() return "Alliance" end
function GetServerTime() return 1791000000 end
function GetTime() return 31.25 end
function GetBuildInfo() return "1.15.9", "release", "date", 11509 end
function CanSendAuctionQuery() return true end
function QueryAuctionItems(...)
    queryArguments = {n=select("#", ...), ...}
    local query, _, _, page = ...
    assert(query=="黑莲花")
    assert(page>=0)
    queryCount = queryCount + 1
end
function GetNumAuctionItems() return scannedRows, scannedRows end
function GetAuctionItemInfo(_,index)
    return resultItemName, "icon", index == 1 and 2 or 3, 4, true, 60,
        "Level", 10000, 1000, 200000, 0, false, nil,
        index == 1 and "采集一" or nil, nil, 0, 13468, true
end
function ReloadUI() _G.reloadInvoked=true end
C_Timer={After=function(_,callback) callbacks[#callbacks + 1] = callback end}

local function getCore()
    for _,v in ipairs(made) do
        if v.events and v.events.ADDON_LOADED then return v end
    end
    error("Core event frame missing")
end
local function fire(name,arg)
    local core = getCore()
    assert(core.events[name], "Core did not register "..name)
    core.scripts.OnEvent(core,name,arg)
end
local function anyText(needle)
    for _,v in ipairs(made) do
        if type(v.text)=="string" and string.find(v.text, needle, 1, true) then return true end
    end
    return false
end
local function loadPlugin()
    assert(loadfile("addons/AuctionCollector/Core.lua"))("AuctionCollector")
    assert(loadfile("addons/AuctionCollector/UI.lua"))("AuctionCollector")
    fire("ADDON_LOADED","AuctionCollector")
end

loadPlugin()
assert(AuctionCollector.GetState().status=="empty")
assert(AuctionCollector.GetState().restoredCount==0)
assert(AuctionCollector.GetState().newPages==0)
local count=queryCount
fire("AUCTION_HOUSE_SHOW")
assert(queryCount==count, "Opening AH should not scan automatically")
SlashCmdList.AUCTIONCOLLECTOR("lotus")
assert(AuctionCollector.GetState().status=="pending")
assert(queryCount==count+1)
assert(queryArguments[1]=="黑莲花" and queryArguments[4]==0)
assert(queryArguments[5]==false and queryArguments[7]==false and queryArguments[8]==true)
fire("AUCTION_ITEM_LIST_UPDATE")
local state=AuctionCollector.GetState()
assert(state.status=="captured" and state.newPages==1)
assert(state.totalPages==1 and state.restoredCount==0)
assert(state.latest.rows[1].seller_character=="采集一")
assert(state.latest.rows[1].item_id==13468)
assert(state.latest.rows[1].buyout_copper==200000)
assert(state.latest.rows[1].unit_buyout_copper==100000)
assert(state.latest.complete==true)
assert(state.latest.missing_owner_rows==1)
assert(anyText("待写入磁盘"),"UI should warn data is still in memory")
for _,callback in ipairs(callbacks) do callback() end
assert(AuctionCollector.GetState().status=="captured", "Late timeout must not overwrite result")

-- Direct user action reloads UI; SavedVariables has not been persisted by the mock.
-- Simulate the next WoW load using the snapshot it would have written to disk.
local saved=AuctionCollectorDB
made={}
SlashCmdList={}
AuctionCollector=nil
AuctionCollectorDB=saved
loadPlugin()
state=AuctionCollector.GetState()
assert(state.status=="restored" and state.restoredCount==1)
assert(state.newPages==0)
AuctionCollector.ShowPanel()
assert(anyText("存档读取成功"),"UI must show previous SavedVariables restored")
assert(queryCount==count+1,"Plugin load should not scan")
scannedRows=0
SlashCmdList.AUCTIONCOLLECTOR("lotus")
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="empty_result" and state.newPages==1)
assert(#state.latest.rows==0)
assert(anyText("待写入磁盘"))

-- Every required Legacy capability is checked before a query can be queued.
local legacy = {
    QueryAuctionItems=QueryAuctionItems,
    GetNumAuctionItems=GetNumAuctionItems,
    GetAuctionItemInfo=GetAuctionItemInfo,
    CanSendAuctionQuery=CanSendAuctionQuery,
}
for _,name in ipairs({"QueryAuctionItems", "GetNumAuctionItems", "GetAuctionItemInfo", "CanSendAuctionQuery"}) do
    local beforePages = AuctionCollector.GetState().totalPages
    local beforeQueries = queryCount
    _G[name] = nil
    AuctionCollector.ScanLotus()
    state = AuctionCollector.GetState()
    assert(state.status=="error", "Missing "..name.." must fail closed")
    assert(state.pending==false and state.totalPages==beforePages)
    assert(queryCount==beforeQueries, "Missing "..name.." must not submit a query")
    _G[name] = legacy[name]
end

-- A modern-only client is detected but never queried as if Legacy were supported.
C_AuctionHouse = {}
for name in pairs(legacy) do _G[name] = nil end
state = AuctionCollector.GetState()
assert(state.legacyAPIAvailable==false and state.modernAPIAvailable==true)
local beforePages = state.totalPages
AuctionCollector.ScanLotus()
state = AuctionCollector.GetState()
assert(state.status=="error" and state.totalPages==beforePages and not state.pending)
for name,fn in pairs(legacy) do _G[name] = fn end
C_AuctionHouse = nil

-- Cooldown and thrown query errors leave the scan count unchanged.
local beforePages = AuctionCollector.GetState().totalPages
local beforeQueries = queryCount
CanSendAuctionQuery=function() return false end
AuctionCollector.ScanLotus()
state = AuctionCollector.GetState()
assert(state.status=="cooldown" and not state.pending)
assert(queryCount==beforeQueries and state.totalPages==beforePages)
CanSendAuctionQuery=legacy.CanSendAuctionQuery

QueryAuctionItems=function() error("simulated client rejection") end
AuctionCollector.ScanLotus()
state = AuctionCollector.GetState()
assert(state.status=="error" and not state.pending)
assert(queryCount==beforeQueries and state.totalPages==beforePages)
QueryAuctionItems=legacy.QueryAuctionItems

-- A stale update after timeout cannot turn the timed-out request into a scan.
AuctionCollector.ScanLotus()
local lateCallback = callbacks[#callbacks]
lateCallback()
state = AuctionCollector.GetState()
assert(state.status=="error" and not state.pending)
fire("AUCTION_ITEM_LIST_UPDATE")
assert(AuctionCollector.GetState().totalPages==beforePages)

-- The shared Legacy result list may be replaced by another AH search.
scannedRows = 2
resultItemName = "血色十字军"
AuctionCollector.ScanLotus()
fire("AUCTION_ITEM_LIST_UPDATE")
state = AuctionCollector.GetState()
assert(state.status=="error" and state.totalPages==beforePages)
assert(string.find(state.message, "与请求物品不一致", 1, true))
print("AuctionCollector UI state transition mock: PASS")
