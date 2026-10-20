# WoW Addons & Market Research

这是一个支持多个独立魔兽世界插件及配套市场研究服务的 Monorepo。原 `WOW Keyword Monitor`（0.3.2-alpha）已**逐文件按原 Blob 迁移**至 `addons/KeywordMonitor/`，无需修改原插件内部代码、SavedVariables 或聊天命令。

| 子项目 | 路径 | 状态 |
| --- | --- | --- |
| WOW Keyword Monitor | `addons/KeywordMonitor/` | 现有关键词插件，`/wkm` |
| AuctionCollector | `addons/AuctionCollector/` | AH 多物品人工采集器，不含插件内分析，`/ac` |
| Mac Sync | `apps/mac-sync/` | SavedVariables 导入 |
| Market API & Research | `services/` | 数据存储、市场研究、回归基线 |
| Azure Global | `deploy/azure/` | 国际版 Azure 部署方案 |

## macOS 安装

**不再直接把整个仓库放入游戏 AddOns 目录。** 关闭游戏后运行：

```bash
bash scripts/install-macos.sh "/Applications/World of Warcraft/_classic_era_/Interface/AddOns"
```

请将路径替换为实际客户端安装路径。脚本会先检查并暂存两套独立插件，再替换 `WOW_keywordmonitor` 与 `AuctionCollector`；旧目录会保留为 `*.backup-时间戳-PID`。若源插件缺失或暂存失败，脚本会在替换现有目录前停止。不会修改 WTF/SavedVariables。也可手动把 `addons/KeywordMonitor` 复制到 `AddOns/WOW_keywordmonitor`，把 `addons/AuctionCollector` 复制到 `AddOns/AuctionCollector`。

安装后启动游戏，在角色选择界面的「插件」列表确认两个插件都已加载；若提示过期插件，勾选「加载过期插件」。进入硬核服联盟角色，打开拍卖行并运行 `/ac probe`。记录服务器、阵营、客户端 build 和 Legacy API 状态。Legacy API 不可用时，插件会停止扫描；API 显示可用也不等于已经验证，需在实际国服客户端完成人工扫描和 `/reload` 读回流程，详见 [AuctionCollector 安装与验证](docs/auction-market/INSTALL-macos.md)。

回滚：关闭游戏后，将当前 `WOW_keywordmonitor`、`AuctionCollector` 目录改名保留，再将对应的 `*.backup-时间戳-PID` 目录恢复为原目录名；不要删除 WTF。原插件名称及 `WOWKeywordMonitorDB` 保持不变。

## AuctionMarket 第一阶段

**研究**国服硬核服（显示名“硬核服”）联盟黑莲花等商品的 AH 可见库存、角色级挂单集中度、补货、理论产能区间、工作室/组织化供应代理指标，并研究 7881 参考金价（人民币 / 1000 金）的时间关系。该阶段不执行交易，不声称 AH 挂单为实际成交，不从角色名推断真实玩家或工作室。

- 插件操作见 `addons/AuctionCollector/README.md`
- 分析范围/局限见 `docs/auction-market/PRD.md`
- 任务见 Issues #1–#5

## 重要限制

国服实际 AH API 尚未在用户 Mac 客户端验证；若接口不兼容，插件应安全报错而非假装扫描成功。第三方挂牌金价不代表已成交价格。位面数与金价的历史对应关系目前是待核实的用户观察，不能直接作为因果推断。
