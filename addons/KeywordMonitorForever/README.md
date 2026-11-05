# WOW Keyword Monitor - 无限服（WoW Forever）

**0.1.0-alpha**：为 WoW Forever 1.60.1 / Interface **16001** 独立制作的首次兼容测试版，尚未经过真实游戏客户端验证。Classic Era 0.3.10-alpha 原版保持不变。

## 安装

完全关闭游戏，将安装包中的 **WOW_keywordmonitor_forever** 文件夹放入：
`World of Warcraft/_forever_/Interface/AddOns/WOW_keywordmonitor_forever/`

确认目录内直接有 `WOW_keywordmonitor_forever.toc`、`Core.lua` 等文件，然后重启客户端。请不要将此版和经典服版装进同一个客户端：两者都支持 `/wkm`，会有快捷命令冲突。

## 独立性

使用全局对象 `WOWKeywordMonitorForever`、保存文件 `WOWKeywordMonitorForeverDB` 和单独的 UI 框体名；**不会读取或修改经典服规则与记录**。

## 主要功能

保留公共频道与公会频道独立 ON/OFF 开关、AND/OR/NOT 规则、消息历史与高亮、声音/大字/Dock 提醒、WoW 原生 Ignore List、角色好友备注、私聊、组队邀请和临时关键词功能。

- `/wkm` 或 `/wkmf`：打开插件
- `/wkm 黑莲花`：直接临时监听公共频道关键词
- `/wkm tg 黑莲花`：临时监听公会频道
- `/wkm tl`、`/wkm tr 黑莲花`、`/wkm tc`：管理临时词
- `/wkm scopes`：查看已保存规则的频道开关
- `/wkm test 文本`、`/wkm testguild 文本`：测试规则

## 无限服 API 兼容

- 保留 `CHAT_MSG_CHANNEL` 与 `CHAT_MSG_GUILD` 监听；受保护的聊天正文或发送者在 `issecretvalue` 检测后安全跳过，不尝试解密或绕过游戏限制。部分受保护聊天**无法被关键词搜索**。
- 对受保护的频道名、lineID 或 GUID 清除附加元数据，不让它们参与字符串运算。
- 组队邀请优先使用 `C_PartyInfo.InviteUnit`，密语输入优先使用 `ChatFrameUtil.OpenChat`，好友备注继续使用 `C_FriendList`。

## 游戏内测试

1. `/dump select(4, GetBuildInfo())` 查看 Interface（目标：16001）。
2. `/console scriptErrors 1` 然后 `/reload`，观察是否有 Lua 报错。
3. `/wkmf` 打开窗口，检查规则和滑动开关。
4. `/wkm test 黑莲花` 或 `/wkm testguild 黑莲花` 测试规则。
5. 在已收到的公共/公会消息中观察匹配效果。
6. 公会 ON/OFF 切换后运行 `/wkm scopes`，再 `/reload` 并重复查询，验证保存。

如有报错，反馈客户端 Build、Lua 报错全文和操作步骤。**此版仅静态适配，尚不能声明已实测兼容。**
