-- WoW API mock: verifies list management and pagination state, not live-client behavior.
local made = {}
local chat = {}
local callbacks = {}
local queryCount = 0
local queryArguments = nil
local scannedRows = 2
local reportedTotal = 2
local resultItemName = "黑莲花"
local resultItemId = 13468
local sellerNamesResolved = false
local canSend = true
local queryThrows = false

local methods = {}
function methods:SetScript(event, fn) self.scripts[event] = fn end
function methods:RegisterEvent(event) self.events[event] = true end
function methods:SetPoint(...) self.point={...} end
function methods:SetSize(width, height) self.width=width self.height=height end
function methods:SetHeight(height) self.height=height end
function methods:GetHeight() return self.height end
function methods:ClearAllPoints() self.point=nil end
function methods:SetText(value) self.text = value end
function methods:GetText() return self.text end
function methods:IsShown() return self.shown end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value end
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
function methods:EnableMouseWheel() end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:SetColorTexture(r,g,b,a) self.color = {r,g,b,a} end
function methods:ClearFocus() self.focused = false end
setmetatable(methods, {__index=function(_,key) return function() end end})

local function frame(name, frameType, parent, template)
    local out = setmetatable({name=name,frameType=frameType,parent=parent,template=template,
        scripts={},events={},shown=true}, {__index=methods})
    made[#made + 1] = out
    return out
end

function CreateFrame(frameType,name,parent,template)
    return frame(name,frameType,parent,template)
end
UIParent=frame("UIParent","Frame")
UIParent:SetSize(1280,823)
UISpecialFrames={}
DEFAULT_CHAT_FRAME={AddMessage=function(_,message) chat[#chat + 1] = message end}
SlashCmdList={}
function GetRealmName() return "硬核服" end
function UnitFactionGroup() return "Alliance" end
function GetServerTime() return 1791000000 end
function GetTime() return 31.25 end
function GetBuildInfo() return "1.15.9", "release", "date", 11509 end
function CanSendAuctionQuery() return canSend end
function QueryAuctionItems(...)
    if queryThrows then error("simulated client rejection") end
    queryArguments = {n=select("#", ...), ...}
    assert(type(queryArguments[1])=="string" and #queryArguments[1]>0)
    assert(type(queryArguments[4])=="number" and queryArguments[4]>=0)
    queryCount = queryCount + 1
end
function GetNumAuctionItems() return scannedRows, reportedTotal end
function GetAuctionItemInfo(_,index)
    return resultItemName, "icon", index == 1 and 2 or 3, 4, true, 60,
        "Level", 10000, 1000, 200000, 0, false, nil,
        sellerNamesResolved and (index == 1 and "采集一" or "采集二") or nil,
        nil, 0, resultItemId, true
end
function GetAuctionItemTimeLeft(_,index) return index end
function ReloadUI() _G.reloadInvoked=true end
C_Timer={After=function(delay,callback)
    callbacks[#callbacks + 1] = {delay=delay,callback=callback}
end}

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
local function runNewestTimer(delay)
    for i=#callbacks,1,-1 do
        if callbacks[i].delay == delay then
            local entry=table.remove(callbacks,i)
            entry.callback()
            return true
        end
    end
    return false
end
local function clickButton(label)
    for _,v in ipairs(made) do
        if v.template=="UIPanelButtonTemplate" and v.text==label and v.scripts.OnClick then
            v.scripts.OnClick(v)
            return v
        end
    end
    error("button not found: "..label)
end
local function loadPlugin()
    assert(loadfile("addons/AuctionCollector/Core.lua"))("AuctionCollector")
    assert(loadfile("addons/AuctionCollector/UI.lua"))("AuctionCollector")
    fire("ADDON_LOADED","AuctionCollector")
end

loadPlugin()
local state=AuctionCollector.GetState()
assert(state.status=="empty" and state.restoredCount==0 and state.newPages==0)
local initial=AuctionCollector.GetWatchlist()
assert(#initial==7,"defaults should contain the lotus, elixirs and fish oil")
local names={}
for _,item in ipairs(initial) do names[item.name]=true end
for _,removed in ipairs({"格罗姆之血","梦叶草","冰盖草","山鼠草"}) do
    assert(not names[removed], removed.." should no longer be in the default watchlist")
end
assert(names["黑莲花"] and names["石鳞鱼油"] and names["泰坦合剂"])

-- Opening AH only opens the panel; it does not start an item scan.
local before=queryCount
fire("AUCTION_HOUSE_SHOW")
assert(queryCount==before,"Opening AH must not start a scan")
local escapeRegistered=false
for _,name in ipairs(UISpecialFrames) do
    if name=="AuctionCollectorStatusPanel" then escapeRegistered=true end
end
assert(escapeRegistered,"Esc should close the panel")

-- Add and remove a custom entry through the actual dashboard controls.
local editBoxes={}
for _,v in ipairs(made) do if v.frameType=="EditBox" then editBoxes[#editBoxes+1]=v end end
assert(#editBoxes==2,"dashboard should provide name and item-ID fields")
local panel
for _,v in ipairs(made) do
    if v.name=="AuctionCollectorStatusPanel" then panel=v end
end
local watchScroll
for _,v in ipairs(made) do
    if v.name=="AuctionCollectorWatchlistScroll" then watchScroll=v end
end
assert(panel and panel.height==803,"panel should fit and use the available screen height")
assert(panel.point[1]=="TOP" and panel.point[5]==-10,"panel should be raised and top-anchored")
assert(watchScroll and watchScroll.height==133,"watchlist should expand to the available panel height")
assert(editBoxes[1].scripts.OnEscapePressed,"focused fields should handle Escape")
editBoxes[1].scripts.OnEscapePressed(editBoxes[1])
assert(panel and not panel:IsShown(),"Escape should close the panel while an input is focused")
AuctionCollector.ShowPanel()
editBoxes[1]:SetText("测试合剂")
editBoxes[2]:SetText("990001")
clickButton("加入清单")
assert(#AuctionCollector.GetWatchlist()==8,"custom item should be added")
local customScan
for _,v in ipairs(made) do
    if v.template=="UIPanelButtonTemplate" and type(v.text)=="string"
        and string.find(v.text,"测试合剂",1,true) then customScan=v end
end
assert(customScan,"custom item should appear in the dashboard")
assert(customScan.point[5]==-84 and customScan.point[4]==270,
    "watchlist entries should use two columns so eight entries fit without scrolling")
local removed=false
for _,v in ipairs(made) do
    if v.parent==customScan.parent and v.text=="×" and v.scripts.OnClick
        and v.point and customScan.point and v.point[4]==customScan.point[4]+235
        and v.point[5]==customScan.point[5] then
        v.scripts.OnClick(v)
        removed=true
        break
    end
end
assert(removed and #AuctionCollector.GetWatchlist()==7,"x should remove the chosen item")
assert(AuctionCollector.AddWatchlistItem("测试合剂","990001"),"custom entry should be re-addable")
assert(AuctionCollectorDB.watchlist and #AuctionCollectorDB.watchlist==8,"watchlist should persist in SavedVariables")
assert(not AuctionCollector.AddWatchlistItem("重复物品","13468"),"duplicate item ID should be rejected")

-- A click starts page 1; sellers may resolve asynchronously before it is saved.
sellerNamesResolved=false
before=queryCount
SlashCmdList.AUCTIONCOLLECTOR("lotus")
state=AuctionCollector.GetState()
assert(state.status=="pending" and state.pending and state.autoScanning)
assert(state.autoPage==1 and queryCount==before+1)
assert(queryArguments[1]=="黑莲花" and queryArguments[4]==0)
assert(queryArguments[5]==false and queryArguments[7]==false and queryArguments[8]==true)
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="resolving" and state.pending and state.newPages==0)
local queryCountBeforeFallback=queryCount
sellerNamesResolved=true
assert(runNewestTimer(2),"seller resolution fallback should be scheduled")
state=AuctionCollector.GetState()
assert(state.status=="completed" and not state.autoScanning and state.newPages==1)
assert(state.totalPages==1 and state.restoredCount==0)
assert(state.latest.rows[1].seller_character=="采集一")
assert(state.latest.rows[2].seller_character=="采集二")
assert(state.latest.rows[1].item_id==13468 and state.latest.rows[1].buyout_copper==200000)
assert(state.latest.rows[1].unit_buyout_copper==100000)
assert(state.latest.rows[1].time_left_bucket==1 and state.latest.rows[2].time_left_bucket==2)
assert(state.latest.complete==true and state.latest.collection_complete==true)
assert(state.latest.collection_status=="complete" and state.latest.collection_page_count==1)
assert(state.latest.missing_owner_rows==0 and state.latest.time_left_complete==true)
assert(queryCount==queryCountBeforeFallback,"seller resolution must not send another query")
assert(anyText("待写入磁盘"),"UI should warn data is still in memory")
assert(anyText("卖家名："),"UI should show seller coverage")

-- A reload reads the saved page and the customized watchlist; it does not scan.
local saved=AuctionCollectorDB
made={}
SlashCmdList={}
AuctionCollector=nil
AuctionCollectorDB=saved
loadPlugin()
state=AuctionCollector.GetState()
assert(state.status=="restored" and state.restoredCount==1 and state.newPages==0)
assert(#AuctionCollector.GetWatchlist()==8)
assert(AuctionCollector.GetWatchlist()[8].name=="测试合剂")
AuctionCollector.ShowPanel()
assert(anyText("存档读取成功"))
assert(queryCount==queryCountBeforeFallback,"Plugin load should not scan")

-- An empty first page is not saved or presented as a confirmed successful batch.
scannedRows=0
reportedTotal=0
local beforePages=state.totalPages
SlashCmdList.AUCTIONCOLLECTOR("lotus")
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="empty_result" and not state.autoScanning and state.newPages==0)
assert(state.totalPages==beforePages)

-- If sellers remain unavailable, usable price rows are saved as partial, then paging ends.
scannedRows=2
reportedTotal=2
sellerNamesResolved=false
SlashCmdList.AUCTIONCOLLECTOR("lotus")
fire("AUCTION_ITEM_LIST_UPDATE")
assert(AuctionCollector.GetState().status=="resolving")
assert(runNewestTimer(2))
state=AuctionCollector.GetState()
assert(state.status=="completed" and state.newPages==1)
assert(state.latest.complete==false and state.latest.seller_resolution_timed_out==true)
assert(state.latest.missing_owner_rows==2 and #state.latest.rows==2)
assert(state.latest.collection_complete==true)

-- The expiry bucket is optional; its absence does not block capture.
local getTimeLeftAPI=GetAuctionItemTimeLeft
GetAuctionItemTimeLeft=nil
sellerNamesResolved=true
SlashCmdList.AUCTIONCOLLECTOR("lotus")
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="completed" and state.latest.complete==true)
assert(state.latest.time_left_api_available==false and state.latest.time_left_complete==false)
assert(state.latest.missing_time_left_rows==2 and state.latest.rows[1].time_left_bucket==nil)
GetAuctionItemTimeLeft=getTimeLeftAPI

-- Every required Legacy capability is checked before an auto query is queued.
local legacy={QueryAuctionItems=QueryAuctionItems,GetNumAuctionItems=GetNumAuctionItems,
    GetAuctionItemInfo=GetAuctionItemInfo,CanSendAuctionQuery=CanSendAuctionQuery}
for _,name in ipairs({"QueryAuctionItems","GetNumAuctionItems","GetAuctionItemInfo","CanSendAuctionQuery"}) do
    local pages=AuctionCollector.GetState().totalPages
    local queries=queryCount
    _G[name]=nil
    AuctionCollector.ScanLotus()
    state=AuctionCollector.GetState()
    assert(state.status=="error" and not state.pending and not state.autoScanning)
    assert(state.totalPages==pages and queryCount==queries)
    _G[name]=legacy[name]
end
C_AuctionHouse={}
for name in pairs(legacy) do _G[name]=nil end
state=AuctionCollector.GetState()
assert(not state.legacyAPIAvailable and state.modernAPIAvailable)
local modernOnlyPages=state.totalPages
AuctionCollector.ScanLotus()
state=AuctionCollector.GetState()
assert(state.status=="error" and state.totalPages==modernOnlyPages and not state.autoScanning)
for name,fn in pairs(legacy) do _G[name]=fn end
C_AuctionHouse=nil

-- A throwing cooldown API is an immediate error, not a six-minute retry loop.
local pagesBeforeCooldownError=AuctionCollector.GetState().totalPages
local queriesBeforeCooldownError=queryCount
CanSendAuctionQuery=function() error("simulated cooldown API failure") end
AuctionCollector.ScanLotus()
state=AuctionCollector.GetState()
assert(state.status=="error" and not state.autoScanning and not state.pending)
assert(queryCount==queriesBeforeCooldownError and state.totalPages==pagesBeforeCooldownError)
CanSendAuctionQuery=legacy.CanSendAuctionQuery

-- Auto-pagination waits for the API cooldown instead of sending early.
local pagesBeforeCooldown=AuctionCollector.GetState().totalPages
local queriesBeforeCooldown=queryCount
canSend=false
AuctionCollector.ScanLotus()
state=AuctionCollector.GetState()
assert(state.status=="auto_wait" and state.autoScanning and not state.pending)
assert(queryCount==queriesBeforeCooldown)
canSend=true
assert(runNewestTimer(2),"cooldown retry should be scheduled")
assert(queryCount==queriesBeforeCooldown+1 and queryArguments[4]==0)
fire("AUCTION_ITEM_LIST_UPDATE")
assert(AuctionCollector.GetState().status=="completed")
assert(AuctionCollector.GetState().totalPages==pagesBeforeCooldown+1)

-- Query errors and timeouts stop safely; a late event cannot resurrect a batch.
queryThrows=true
local pagesBeforeFailure=AuctionCollector.GetState().totalPages
queriesBeforeCooldown=queryCount
AuctionCollector.ScanLotus()
state=AuctionCollector.GetState()
assert(state.status=="error" and not state.autoScanning and not state.pending)
assert(queryCount==queriesBeforeCooldown and state.totalPages==pagesBeforeFailure)
queryThrows=false
AuctionCollector.ScanLotus()
local pagesBeforeTimeout=AuctionCollector.GetState().totalPages
assert(runNewestTimer(30),"query timeout should be scheduled")
state=AuctionCollector.GetState()
assert(state.status=="error" and not state.pending and not state.autoScanning)
fire("AUCTION_ITEM_LIST_UPDATE")
assert(AuctionCollector.GetState().totalPages==pagesBeforeTimeout)

-- A different item's result fails closed and stops the entire auto batch.
resultItemName="血色十字军"
resultItemId=12345
AuctionCollector.ScanLotus()
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="error" and not state.autoScanning)
assert(string.find(state.message,"不一致",1,true))
resultItemName="黑莲花"
resultItemId=13468

-- Three result pages are queried in sequence, with one user click and cooldown waits.
sellerNamesResolved=true
scannedRows=50
reportedTotal=120
local pageRunStart=#AuctionCollectorDB.scans
local queryRunStart=queryCount
local newPageRunStart=AuctionCollector.GetState().newPages
AuctionCollector.ScanLotus()
assert(queryArguments[4]==0)
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.autoScanning and state.autoPagesDone==1 and state.autoPage==2)
assert(state.status=="auto_wait" and queryCount==queryRunStart+1)
assert(runNewestTimer(2) and queryArguments[4]==1)
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.autoScanning and state.autoPagesDone==2 and state.autoPage==3)
assert(runNewestTimer(2) and queryArguments[4]==2)
scannedRows=20
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="completed" and not state.autoScanning)
assert(state.newPages-newPageRunStart==3 and state.lastBatch.complete and state.lastBatch.pages==3)
assert(state.lastBatch.rows==120 and queryCount==queryRunStart+3)
assert(#AuctionCollectorDB.scans==pageRunStart+3)
local batchId=AuctionCollectorDB.scans[pageRunStart+1].collection_id
for i=pageRunStart+1,pageRunStart+3 do
    local scan=AuctionCollectorDB.scans[i]
    assert(scan.page==i-pageRunStart-1)
    assert(scan.collection_id==batchId and scan.collection_status=="complete")
    assert(scan.collection_complete and scan.collection_page_count==3)
    assert(scan.collection_row_count==120)
end

-- Exact page boundaries do not trigger an unnecessary empty-page request.
scannedRows=50
reportedTotal=50
local exactQueryStart=queryCount
AuctionCollector.ScanLotus()
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="completed" and state.lastBatch.pages==1)
assert(queryCount==exactQueryStart+1)
reportedTotal=100
AuctionCollector.ScanLotus()
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.autoScanning and state.autoPagesDone==1)
assert(runNewestTimer(2) and queryArguments[4]==1)
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="completed" and state.lastBatch.pages==2)
assert(queryCount==exactQueryStart+3)

-- Inconsistent page size is retained as partial raw data, but never reported as complete.
scannedRows=49
reportedTotal=120
local pagesBeforeInconsistent=AuctionCollector.GetState().totalPages
AuctionCollector.ScanLotus()
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="error" and not state.autoScanning)
assert(state.totalPages==pagesBeforeInconsistent+1)
assert(state.latest.complete==false and state.latest.pagination_error~=nil)
assert(state.latest.collection_status=="failed" and not state.latest.collection_complete)

-- Stop while waiting prevents the scheduled next-page timer from sending a query.
scannedRows=50
reportedTotal=100
AuctionCollector.ScanLotus()
fire("AUCTION_ITEM_LIST_UPDATE")
local queriesBeforeStop=queryCount
assert(AuctionCollector.GetState().autoScanning)
assert(AuctionCollector.StopAutoScan())
state=AuctionCollector.GetState()
assert(state.status=="stopped" and not state.autoScanning)
assert(runNewestTimer(2))
assert(queryCount==queriesBeforeStop)

-- Stop during an in-flight page keeps that page, then halts before the next.
AuctionCollector.ScanLotus()
assert(AuctionCollector.GetState().pending)
assert(AuctionCollector.StopAutoScan())
assert(AuctionCollector.GetState().status=="stopping")
local pageCountBeforeStopResponse=AuctionCollector.GetState().totalPages
fire("AUCTION_ITEM_LIST_UPDATE")
state=AuctionCollector.GetState()
assert(state.status=="stopped" and not state.autoScanning and not state.pending)
assert(state.totalPages==pageCountBeforeStopResponse+1)

-- Closing AH stops the batch and leaves prior captured data intact.
AuctionCollector.ScanLotus()
fire("AUCTION_HOUSE_CLOSED")
state=AuctionCollector.GetState()
assert(state.status=="stopped" and not state.pending and not state.autoScanning)

print("AuctionCollector editable watchlist and auto-pagination mock: PASS")
