# WOW Keyword Monitor

面向 **World of Warcraft Classic Era / Hardcore** 的聊天关键词监控插件。

> 当前为早期测试版。目标是帮助玩家在世界/组队等公共聊天频道消息量很大时，通过布尔关键词规则自动捕获真正关心的消息，并保留历史记录、提醒和玩家快捷操作。

## 第一版目标

- 多条独立规则
- 规则表达式支持 `AND` / `OR` / `NOT` / 括号
- 监听 `CHAT_MSG_CHANNEL`
- 匹配消息历史与相对时间
- 未读计数
- 屏幕中央提醒
- 可选声音提醒
- 匹配关键词高亮
- 对发送者执行密语、邀请、复制名字
- 短时重复消息去重
- SavedVariables 持久化规则与历史记录

### 示例

```text
MLD AND T AND NOT 带
(MLD OR 玛拉顿 OR 玛拉) AND (T OR MT OR 坦 OR 坦克) AND NOT (带 OR 老板 OR 工作室)
```

## 版权说明

本项目是独立实现。KeywordAlert 仅用于需求与行为参考；本仓库不复制或重新发布其受版权保护的源码或素材。

## 状态

开发中。
