# AuctionCollector · 0.1.0-alpha

独立 WoW 插件，**仅人工命令触发**。安装目录必须为 `Interface/AddOns/AuctionCollector`，与 KeywordMonitor 不共用配置。

在拍卖师处打开 AH 窗口，输入：

- `/ac probe`：查看 Legacy AH API、C_AuctionHouse、服务器、阵营和客户端 Interface Build。
- `/ac lotus`：**只查询黑莲花第一页**（要求客户端支持 `QueryAuctionItems`）。
- `/ac next`：人工查询下一页，不能自动连续扫描。
- `/ac page 2`：人工查询指定页，页码从 1 开始。
- `/ac status`：查看已缓存页数和等待状态。

记录至 `AuctionCollectorDB` SavedVariables，最多保留 80 次分页快照。**只有 /reload 或正常登出后文件才会更新**。路径大致为：

```text
WTF/Account/<ACCOUNT>/SavedVariables/AuctionCollector.lua
```

### 尚待验证

当前使用 Classic 的 Legacy `QueryAuctionItems`、`GetNumAuctionItems` 和 `GetAuctionItemInfo`。部分国服客户端可能使用不同 AH API，遇到不兼容时显示提示，**不发送查询、也不伪造数据**。卖家姓名可能无法解析；查询返回的 owner 为 nil 会记录缺失。第一页或某一页不是全市场扫描，模型必须检查 `coverage=single_page`。当前查询默认以物品中文名称精确匹配，尚未验证服务器是否返回预期结果。

一个扫描得到 0 行可能是正常无货、缓存未加载、查询失败或与其他 AH 插件冲突；测试时请记录聊天框提示及客户端 Build。若查询无结果，不应将其视为服务器没有黑莲花。

插件不读取游戏内存，不自动购买、交易、模拟输入、后台定时扫描或绕过查询冷却。原始快照可能包含游戏角色名，不应公开展示全量原始文件。
