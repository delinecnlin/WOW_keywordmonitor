# macOS 插件安装、验证与回滚

请先完全退出 WoW，再安装插件。安装器会预先检查两套插件，并在 AddOns 目录内暂存副本；替换已有版本时，会为两个旧目录各保留一份带时间和进程号的备份。它不会更改 `WTF/SavedVariables`。

```bash
bash scripts/install-macos.sh "/Applications/World of Warcraft/_classic_era_/Interface/AddOns"
```

将路径换成实际客户端的 `Interface/AddOns` 目录。安装输出会列出已安装插件和备份位置。安装失败时先看报错；缺少插件源或暂存副本不完整时，现有插件目录不会被替换。

## 游戏内验证

1. 从启动器启动对应客户端，在角色选择界面打开「插件」，确认 `WOW_keywordmonitor` 和 `AuctionCollector` 都在列表中。若提示过期插件，启用「加载过期插件」。
2. 进入硬核服联盟角色，在聊天框输入 `/ac probe`。检查输出中的服务器、阵营、客户端 build 和 `Legacy API` 状态。
3. 只有当 `Legacy API` 为 `true` 时，才继续测试 `/ac` 面板上的人工扫描按钮。Legacy API 不可用时，当前版本不会转用现代 `C_AuctionHouse` API，也不会提交扫描请求。
4. 人工扫描后，面板应先显示「正在等待」，收到拍卖行更新后显示本页条数及「数据在内存中」。点「写盘并重载」后，面板再次打开应显示「已从 SavedVariables 存档读回」。这验证了当前客户端中的一次采集和重载流程。
5. `/ac probe` 或 Lua 模拟测试都不能代替真实客户端兼容验证。记录完整输出、客户端 build、面板结果和 `/reload` 后状态，才能判断这台国服客户端的实际表现。采集只覆盖用户手动查询到的分页。

关键词插件和 AuctionCollector 使用不同的 TOC、插件目录和 SavedVariables 名称。升级或回滚 AuctionCollector 不会清除 `WOWKeywordMonitorDB` 或 `AuctionCollectorDB`；请保留 `WTF` 目录。

## 回滚

关闭 WoW 后，在 AddOns 目录中找到本次安装输出列出的备份目录。先把当前插件目录改名保留，再恢复对应备份：

```bash
ADDONS="/Applications/World of Warcraft/_classic_era_/Interface/AddOns"
mv "$ADDONS/WOW_keywordmonitor" "$ADDONS/WOW_keywordmonitor.failed"
mv "$ADDONS/WOW_keywordmonitor.backup-时间戳-PID" "$ADDONS/WOW_keywordmonitor"
mv "$ADDONS/AuctionCollector" "$ADDONS/AuctionCollector.failed"
mv "$ADDONS/AuctionCollector.backup-时间戳-PID" "$ADDONS/AuctionCollector"
```

把两处 `时间戳-PID` 替换成安装器实际输出的后缀。若该插件此前不存在、没有备份目录，只需在关闭游戏后移走对应的新插件目录。回滚不需要删除或改动 SavedVariables。
