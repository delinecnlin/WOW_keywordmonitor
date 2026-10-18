# WoW Addons & Market Research

这是一个支持多个独立魔兽世界插件及配套市场研究服务的 Monorepo。原 `WOW Keyword Monitor`（0.3.2-alpha）已**逐文件按原 Blob 迁移**至 `addons/KeywordMonitor/`，无需修改原插件内部代码、SavedVariables 或聊天命令。

| 子项目 | 路径 | 状态 |
| --- | --- | --- |
| WOW Keyword Monitor | `addons/KeywordMonitor/` | 现有关键词插件，`/wkm` |
| AuctionCollector | `addons/AuctionCollector/` | 新增 AH 人工采集试验插件，`/ac` |
| Mac Sync | `apps/mac-sync/` | SavedVariables 导入 |
| Market API & Research | `services/` | 数据存储、市场研究、回归基线 |
| Azure Global | `deploy/azure/` | 国际版 Azure 部署方案 |

## macOS 安装

**不再直接把整个仓库放入游戏 AddOns 目录。** 关闭游戏后运行：

```bash
bash scripts/install-macos.sh "/Applications/World of Warcraft/_classic_era_/Interface/AddOns"
```

请将路径替换为实际客户端安装路径。脚本只复制两套独立插件：`WOW_keywordmonitor` 与 `AuctionCollector`，并把旧目录备份为 `*.backup-时间戳`。不会修改 WTF/SavedVariables。也可手动把 `addons/KeywordMonitor` 复制到 `AddOns/WOW_keywordmonitor`，把 `addons/AuctionCollector` 复制到 `AddOns/AuctionCollector`。

回滚：关闭游戏，将备份的 `WOW_keywordmonitor.backup-...` 还原为 `WOW_keywordmonitor`；不要删除 WTF。原插件名称及 `WOWKeywordMonitorDB` 保持不变。

## AuctionMarket 第一阶段

**研究**国服硬核服（显示名“硬核服”）联盟黑莲花等商品的 AH 可见库存、角色级挂单集中度、补货、理论产能区间、工作室/组织化供应代理指标，并研究 7881 参考金价（人民币 / 1000 金）的时间关系。该阶段不执行交易，不声称 AH 挂单为实际成交，不从角色名推断真实玩家或工作室。

- 插件操作见 `addons/AuctionCollector/README.md`
- 分析范围/局限见 `docs/auction-market/PRD.md`
- 任务见 Issues #1–#5

## 重要限制

国服实际 AH API 尚未在用户 Mac 客户端验证；若接口不兼容，插件应安全报错而非假装扫描成功。第三方挂牌金价不代表已成交价格。位面数与金价的历史对应关系目前是待核实的用户观察，不能直接作为因果推断。
