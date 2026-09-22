# WOW Keyword Monitor

面向 **World of Warcraft Classic Era / Hardcore** 的聊天关键词监控插件。

当前版本：**0.1.0-alpha**。这是用于实际游戏测试规则写法和交互方式的第一版。

## 已实现

- 多条独立监听规则
- 布尔表达式：`AND` / `OR` / `NOT` / 括号
- 支持 `&&` / `||` / `!`
- 连续关键词用空格连接时默认视为 `AND`
- 双引号或单引号可表示包含空格的短语
- 监听 `CHAT_MSG_CHANNEL`
- 匹配消息历史，默认保存最近 200 条
- 打开窗口后显示“刚刚 / N 秒前 / N 分钟前”等相对时间
- 多条规则同时命中时只保存一条消息，并记录全部命中规则
- 8 秒短时重复消息去重
- 匹配关键词高亮
- 屏幕中央大字提醒
- 可关闭声音提醒 / 大字提醒
- 小地图按钮 + 未读计数
- 点击发送者直接打开密语
- “+”按钮邀请玩家
- “复”按钮弹出可 Ctrl+C 的玩家名
- SavedVariables 持久化规则、设置和历史记录

## 规则示例

### 玛拉顿找 T，排除带刷

```text
MLD AND T AND NOT 带
```

### 支持多个副本/职业写法

```text
(MLD OR 玛拉顿 OR 玛拉) AND (T OR MT OR 坦 OR 坦克) AND NOT (带 OR 老板 OR 工作室)
```

### 多个排除词

```text
黑下 AND (治疗 OR 奶 OR 牧师) AND NOT (带 OR G团 OR 工作室)
```

### 空格默认 AND

下面两条等价：

```text
MLD T NOT 带
MLD AND T AND NOT 带
```

如果关键词本身包含空格，请加引号：

```text
"Blackrock Depths" AND healer
```

运算优先级：

1. `NOT`
2. `AND`
3. `OR`

复杂规则建议明确使用括号，避免歧义。

## 安装

### Git clone

把仓库放到：

```text
World of Warcraft/_classic_era_/Interface/AddOns/WOW_keywordmonitor
```

目录内应直接看到：

```text
WOW_keywordmonitor.toc
Core.lua
Parser.lua
Rules.lua
...
```

### GitHub Download ZIP

GitHub 下载后的目录通常叫：

```text
WOW_keywordmonitor-main
```

请先改名为：

```text
WOW_keywordmonitor
```

再放入 `Interface/AddOns`。

当前 TOC Interface 为 `11509`，面向当前 Classic Era / Hardcore 客户端。若后续客户端补丁升级，可在游戏聊天框执行：

```text
/dump select(4, GetBuildInfo())
```

确认 Interface 版本。

## 使用

进入游戏后：

```text
/wkm
```

或：

```text
/kwm
```

打开插件窗口。

窗口包含：

- **匹配消息**：查看历史、相对时间、发件人、命中规则、频道和具体消息。
- **规则设置**：新增、修改、启用/停用、删除规则。
- **声音提醒**：全局开关。
- **屏幕大字**：全局开关。
- **监听：开启/关闭**：暂停或恢复聊天监听。

### 命令

```text
/wkm
/wkm on
/wkm off
/wkm clear
/wkm test <聊天文本>
```

例如：

```text
/wkm test MLD 4=1 来T
```

会在聊天框告诉你当前哪些规则能够匹配这句话，非常适合调试规则。

## 第一轮建议测试

默认已经放入一条示例规则：

```text
(MLD OR 玛拉顿 OR 玛拉) AND (T OR MT OR 坦 OR 坦克) AND NOT (带 OR 老板 OR 工作室)
```

建议分别测试：

```text
MLD 4=1 来T
玛拉顿缺坦克
MLD带刷 来老板
MLD 4=1 来FS
```

预期：

- 前两条匹配
- 第三条因为出现“带/老板”而排除
- 第四条因为没有 T/坦相关关键词而不匹配

## 当前限制

- 第一版只监听客户端实际收到的 `CHAT_MSG_CHANNEL`。
- 插件不能读取登录前的服务器历史聊天。
- 未加入的频道无法监听。
- “复制名字”受 WoW 插件安全模型限制，不能直接写入系统剪贴板，因此使用弹窗选中文本后 Ctrl+C。
- 邀请和密语都由玩家主动点击触发，不做自动邀请或自动发言。
- 当前没有“简单模式”；现阶段优先通过实际使用确定最合适的规则表达方式。
- 当前没有按规则指定频道、单独提示音、单独冷却时间等高级设置，这些留到测试后决定。

## 数据

SavedVariables：

```text
WOWKeywordMonitorDB
```

默认保存：

- 规则
- 开关设置
- 最近 200 条匹配历史
- 未读数量
- 小地图按钮位置

## 版权

本项目采用 MIT License。

本项目为独立实现。KeywordAlert 仅作为需求和行为参考；本仓库没有复制或重新发布 KeywordAlert 的源码、图标或其他受版权保护素材。
