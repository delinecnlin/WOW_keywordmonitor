# Azure Global Linux VM 部署（研究版）

1. Ubuntu 24.04 LTS VM，起步 2 vCPU / 4 GiB RAM。建议 Azure 香港或实测网络稳定的其他区域；没有实测前不保证低延迟。
2. 创建 DNS A 记录 `MARKET_DOMAIN` 指向 Azure Public IP。此版本使用 Caddy 自动申请 TLS 证书，必须开放 80/443；SSH 22 仅允许运维固定来源地址，禁止将 8000、DuckDB、Docker daemon 暴露公网。
3. 安装受信任版本的 Docker Engine + Compose plugin，克隆 GitHub 仓库。运行：

```bash
cd deploy/azure
cp .env.example .env
# 编辑 .env，将 MARKET_DOMAIN/ACME_EMAIL 设置为实际值，并生成 >=32 字节随机高强度 API Token
chmod 600 .env
docker compose --env-file .env up --build -d
docker compose ps
```

4. 浏览器打开 `https://MARKET_DOMAIN`，在页面输入 API Token 后获取最新 AH 数据；Mac sync 使用同一 Token。这是**内部研究版共享 Token**，生产对外使用前需要补充独立 Web 用户身份认证、多角色权限、速率限制及访问审计。
5. 定期备份 `market-data` Docker 卷及 Caddy TLS 卷，并在备份时暂停写入/执行一致性快照。DuckDB 单实例单写入进程，Compose 不要配置多副本 API worker。
6. 云端只存原始 AH 快照及手工金价报价，数据库包含可能可识别的游戏角色名；访问权限应限制，不应公开原始数据。

当前尚未部署真实 VM，`market.example.com` 是占位域名；请勿将其当作已上线网站。服务器端 `/api/health` 不需要认证，其余 API 请求需 Bearer Token。

研究建议：先积累数周不同时间段 AH 样本，并验证客户端是否能提供卖家字段。当前只有逐页人工扫描，覆盖率不足以做全服推断。
