# 云笺集多实例中心服务

该 Worker 只负责华为账号身份、邮箱实例目录、实例绑定关系和作用域角色。邮箱、邮件、密码与实例令牌仍归各 Cloud Mail 实例管理。

## 安全边界

- 邮箱密码由客户端直接发送到目标实例的 `/api/login`，不会发送到本服务。
- 本服务仅短暂使用实例返回的令牌调用该实例 `/api/my/loginUserInfo` 完成身份与管理员权限校验，令牌不会写入 D1。
- D1 仅保存华为身份标识、实例地址、绑定邮箱、已校验角色和审计记录。
- 只有 `SUPER_ADMIN` 能登记实例地址，且仅允许标准 HTTPS 公网域名，避免把服务变成任意请求代理。

## 首次部署

1. 复制 `wrangler.jsonc`，把 `database_id` 替换为新建 D1 的 ID。
2. 安装依赖：`npm install`。
3. 执行远程迁移：`npm run db:migrate:remote`。
4. 分别执行 `npx wrangler secret put HUAWEI_CLIENT_ID`、`npx wrangler secret put HUAWEI_CLIENT_SECRET`、`npx wrangler secret put PLATFORM_JWT_SECRET` 写入三项 Secret；Secret 不写入 `wrangler.jsonc`。
5. 把首位超级管理员在主实例 `/api/huawei/me` 返回的 `huaweiUserId` 写入 `SUPER_ADMIN_HUAWEI_IDS`；多个 ID 使用英文逗号分隔。若旧实例暂未返回该字段，可临时使用 `anchor:主邮箱地址`。
6. 执行 `npm run deploy`。

现有版本可通过 `ANCHOR_INSTANCE_API_BASE_URL` 指向已经完成华为账号绑定的主实例，客户端用主实例令牌换取平台令牌，避免重复消费同一份华为授权码。迁移完成后可改用平台自身的 `/api/platform/auth/huawei`。

`wrangler.jsonc` 是绑定、变量和部署配置的唯一来源；敏感值不得写入该文件或提交到 Git。
