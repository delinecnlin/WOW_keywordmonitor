# WOW Keyword Monitor — 无限服独立版 (0.1.0-alpha)

基于 Classic Era / Hardcore 的 0.3.10-alpha 功能创建的独立无限服版本。

- 适用：魔兽世界「无限」/ WoW Forever，Interface 16001，1.60.1
- 安装路径：`World of Warcraft/_forever_/Interface/AddOns/WOW_keywordmonitor_forever/`；以实际客户端目录为准
- 打开窗口：`/wkmf` 或 `/kwmf`，与经典旧世版的 `/wkm` 分离
- 配置数据：`WOWKeywordMonitorForeverDB`，不读取也不修改经典旧世版配置
- 功能：公共/公会聊天、布尔匹配规则、每规则 ON/OFF 滑动开关、历史和提醒、角色好友备注、原生黑名单
- 临时监控：`/wkmf 黑莲花`（公共），`/wkmf tg 黑莲花`（公会），`/wkmf tl` 查看
- 诊断：`/wkmf scopes` 查看已保存规则频道，`/wkmf secrets` 查看受保护消息跳过计数

## 无限服客户端限制

现代版客户端的聊天事件（尤其在通信限制激活时）可能返回受保护 Secret Value，插件无法合法读取其内容或用作关键词搜索。本版读取前先使用 `issecretvalue` 检查，跳过受保护消息，避免报错；这意味着可能出现受限聊天漏检。不会规避游戏安全限制。

**0.1.0-alpha 为游戏实测前的适配测试包**：已分离命名空间、SavedVariables、插件目录、快捷命令和关键聊天事件保护。某些 UI、好友 API、兼容性仍需无限服客户端实测。

经典旧世/硬核服源代码：`addons/KeywordMonitor/`；无限服源代码：`addons/KeywordMonitorForever/`。两个版本分别打包，不混装。
