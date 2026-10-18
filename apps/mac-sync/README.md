# macOS SavedVariables 上传器

使用 Python 3.11+；仅解析 WoW 写出的文本，不执行 Lua。**先在游戏输入 `/reload` 或正常退出**，否则读到的是旧数据。

```bash
cd apps/mac-sync
python3 sync.py "/Applications/World of Warcraft/_classic_era_/WTF/Account/账号/SavedVariables/AuctionCollector.lua" --dry-run

export AUCTION_API_URL="https://market.example.com"
export AUCTION_API_TOKEN="<private-token>"
python3 sync.py "/Applications/World of Warcraft/_classic_era_/WTF/Account/账号/SavedVariables/AuctionCollector.lua"
```

上传确认记录在 `~/.auctioncollector/uploaded.json`，重复执行仅发送新增 scan_id。API 服务端再次去重。失败不会标记已上传，便于重试。仅支持 HTTPS，或本机 `http://127.0.0.1:` 开发环境。**不要将 Token 提交 Git。** 当前为手动运行的 MVP，LaunchAgent 需要等国服真实数据验证后再配。
