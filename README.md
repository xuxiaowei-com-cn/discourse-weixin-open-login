# Discourse 微信登录插件

> 原项目名：`discourse-weixin-open-login`。现同时支持**微信开放平台（网站应用）扫码登录**与**微信公众号网页授权登录**。

这个插件允许用户使用微信登录 Discourse：

- **桌面 / 普通浏览器**：跳转微信开放平台「网站应用」扫码登录（`snsapi_login`）。
- **微信内置浏览器**：跳转微信公众号网页授权登录（`snsapi_userinfo`），微信内无需扫码。

两种渠道共用同一个登录按钮，插件根据 User-Agent 自动选择；两个渠道使用同一个 `provider`，并以 `unionid` 作为统一身份，因此同一个人通过扫码或公众号登录都会落到同一个 Discourse 账号。

## 目录

- [工作原理](#工作原理)
- [身份合并规则](#身份合并规则)
- [安装与升级](#安装与升级)
- [微信平台配置](#微信平台配置)
- [论坛设置](#论坛设置)
- [使用说明](#使用说明)
- [常见问题](#常见问题)
- [开发说明](#开发说明)

## 工作原理

```
用户点击「微信」
      │
      ▼
/auth/weixin  ── User-Agent 含 MicroMessenger？
      │                 │
      │ 否              │ 是
      ▼                 ▼
open.weixin.qq.com    open.weixin.qq.com
/connect/qrconnect    /connect/oauth2/authorize
(scope=snsapi_login)  (scope=snsapi_userinfo 或 snsapi_base)
      │                 │
      └───────┬─────────┘
              ▼
/auth/weixin/callback?code=...&state=open…|mp…
              │
              ▼
api.weixin.qq.com/sns/oauth2/access_token
              │
              ▼
api.weixin.qq.com/sns/userinfo   （access_token 以 query 参数传递）
              │
              ▼
UserAssociatedAccount（provider_name = weixin）
```

关键点：

- 渠道信息写入 OAuth2 `state` 前缀（`open` / `mp`），回调时据此选择对应的 AppID/AppSecret，避免两个应用凭据串用。
- 请求 `/sns/userinfo` 时 access_token 必须放在 URL query 中；`oauth2` 2.x 默认放在 `Authorization` header，微信不识别（会返回 `41001 access_token missing`），插件已显式改为 `mode: :query`。
- 微信接口出错时也返回 HTTP 200：token 接口的 `errcode` 会转成标准的登录失败；`/sns/userinfo` 失败时则保留身份继续登录（只记录日志、不阻断），避免资料接口抖动导致无法登录。

## 身份合并规则

关联关系保存在 Discourse 核心的 `user_associated_accounts` 表：

| 字段 | 内容 |
|---|---|
| `provider_name` | 固定为 `weixin` |
| `provider_uid` | `unionid`；公众号未绑定开放平台时为 `openid` |
| `info` | `nickname`、`image`、`location`、`sex`、`openid`、`unionid` |
| `credentials` | 微信 access_token、refresh_token、过期时间 |
| `extra` | `/sns/userinfo` 原始返回、授权 scope |

规则：

1. 接口返回 `unionid` 时，一律使用 `unionid` 作为 `provider_uid`。
2. 未返回 `unionid`（公众号未绑定开放平台）时，退回使用 `openid`。
3. **后期绑定后的数据同步**：公众号绑定到开放平台后，用户下次通过公众号登录时会同时拿到 `openid` 与 `unionid`，插件会自动把原来的 openid 记录升级为 unionid，用户账号保持不变。
4. 如果升级前用户既用扫码登录创建过 unionid 账号，又用公众号创建过 openid 账号，会出现两个账号。此时插件无法安全地自动合并，会在日志中输出 `[weixin-login] ... 冲突，需人工合并账号`，请管理员人工合并。
5. 只使用扫码登录的用户不会触发 openid→unionid 升级：扫码登录只能拿到网站应用的 openid，无法关联到公众号的 openid。需要该用户至少再通过公众号登录一次。

> 要获得统一的 `unionid`，网站应用与公众号必须绑定在**同一个微信开放平台账号**下。

## 安装与升级

### 全新安装

```shell
docker exec -it discourse-web-1 bash
cd /var/www/discourse/plugins
git clone https://github.com/xuxiaowei-com-cn/discourse-weixin-login.git
```

然后重启容器：

```shell
docker restart discourse-web-1
```

> 容器内 `git clone` 在重建容器后会丢失，生产环境建议把插件克隆写进 `app.yml` 的 `hooks: after_code`，或使用官方插件安装方式。

### 从 `discourse-weixin-open-login` 升级

1. **先备份数据库**。
2. 删除旧插件目录（不要与新插件同时启用，否则会出现两个微信登录入口，容易产生重复账号）：

   ```shell
   rm -rf /var/www/discourse/plugins/discourse-weixin-open-login
   ```

3. 按「全新安装」克隆新插件。
4. 执行数据迁移（把旧的 `weixin_open` 关联与设置项改名）：

   ```shell
   docker exec -it discourse-web-1 bash
   cd /var/www/discourse
   LOAD_PLUGINS=1 bundle exec rake 'plugin:migrate[discourse-weixin-login]'
   ```

   也可以执行 `LOAD_PLUGINS=1 bundle exec rake db:migrate`。

迁移内容：

- `user_associated_accounts.provider_name`：`weixin_open` → `weixin`
- `site_settings` 设置项改名：

  | 旧设置 | 新设置 |
  |---|---|
  | `weixin_open_login_enabled` | `weixin_login_enabled` |
  | `weixin_open_login_app_id` | `weixin_login_open_platform_app_id` |
  | `weixin_open_login_app_secret` | `weixin_login_open_platform_app_secret` |
  | `weixin_open_login_button_title` | `weixin_login_button_title` |

> 如果没有执行迁移，用户下次登录时插件会自动把该用户的 `weixin_open` 关联改为 `weixin`；但设置项不会自动改名，需要在后台重新填写。未登录过的老用户关联会一直保留旧 provider 名，直到其下次登录。
>
> 旧插件只有网站应用凭据；升级后如需在微信内登录，还要补配公众号的 AppID/AppSecret。

## 微信平台配置

### A. 微信开放平台网站应用（扫码登录）

1. 登录 [微信开放平台](https://open.weixin.qq.com/)，完成开发者资质认证。
2. 管理中心 → 网站应用 → 创建网站应用，等待审核通过。
3. 填写**授权回调域**：`forum.example.com`（只填域名，不带 `http://`、`https://` 或路径）。
4. 记录应用的 `AppID` 和 `AppSecret`。

### B. 微信公众号（微信内登录）

1. 网页授权**仅支持已认证的服务号**（已认证的政府/媒体类公众号也有权限），订阅号、未认证号不支持。
2. 公众号后台 → 设置与开发 → 开发接口管理 → 接口权限 → 网页服务 → 网页授权，填写**网页授权域名**：`forum.example.com`（不带协议和路径）。
3. 微信要求把 `MP_verify_<code>.txt` 放在**域名根目录**，且内容就是 `<code>`（无多余换行/空格）。Discourse 的 `public/` 就是站点根目录，nginx 会优先返回其中的静态文件（不需要登录）：
   - 直接上传到运行中的容器（临时，容器重建后丢失）：

     ```shell
     docker cp MP_verify_<code>.txt <discourse-container>:/var/www/discourse/public/
     docker exec <discourse-container> chmod 644 /var/www/discourse/public/MP_verify_<code>.txt
     ```

   - 需要重建后仍生效：把文件放到宿主机 `/var/discourse/shared/standalone/`，并在 `/var/discourse/containers/app.yml` 的 `hooks` 中加入：

     ```yaml
     hooks:
       after_code:
         - exec:
             cd: $home
             cmd:
               - cp /shared/MP_verify_<code>.txt public/
     ```

   - 验证（应返回 200 和 `<code>`）：

     ```shell
     curl -i https://forum.example.com/MP_verify_<code>.txt
     ```

4. 记录公众号的 `AppID` 和 `AppSecret`。
5. **重要**：在微信开放平台把该公众号绑定到与网站应用相同的开放平台账号，才会返回相同的 `unionid`。

## 论坛设置

后台 → 插件 → 微信登录 → 设置，或 后台 → 设置 → 登录与认证（分类「微信登录」）：

| 设置 | 说明 |
|---|---|
| `weixin_login_enabled` | 总开关。关闭后登录按钮消失 |
| `weixin_login_open_platform_enabled` | 启用开放平台扫码渠道 |
| `weixin_login_open_platform_app_id` | 网站应用 AppID |
| `weixin_login_open_platform_app_secret` | 网站应用 AppSecret |
| `weixin_login_mp_enabled` | 启用公众号网页授权渠道 |
| `weixin_login_mp_app_id` | 公众号 AppID |
| `weixin_login_mp_app_secret` | 公众号 AppSecret |
| `weixin_login_mp_scope` | 公众号网页授权的 scope，可选 `snsapi_userinfo`（默认）或 `snsapi_base` |
| `weixin_login_button_title` | 登录按钮文字，默认「微信」 |

- 总开关打开，并且至少一个渠道的 `AppID` + `AppSecret` 填写完整，登录按钮才会出现。
- 只配置一个渠道也能使用：未配置公众号时，微信内会回落到扫码页（体验较差，建议两个都配置）；未配置网站应用时，桌面端会提示需要在微信内打开。

### 公众号 scope 说明

微信网页授权只有两个 scope，可由管理员在 `weixin_login_mp_scope` 中选择：

| scope | 行为 | 能获取的信息 |
|---|---|---|
| `snsapi_userinfo`（默认） | 首次需要用户手动同意（已关注服务号时可能静默） | `openid`、`unionid`、昵称、头像、地区 |
| `snsapi_base` | 静默授权，不弹授权页 | 仅 `openid`（公众号绑定开放平台时包含 `unionid`），没有昵称/头像/地区 |

注意：

- 两个 scope 都要求公众号是**已认证的服务号**；如果账号没有网页授权权限，两个 scope 都会报 `Scope 参数错误或没有 Scope 权限`，这不是改 scope 能解决的。
- 网站应用扫码登录固定使用 `snsapi_login`，没有可选值。
- `snsapi_base` 登录后 `info` 里没有昵称/头像，Discourse 注册页不会预填昵称，头像也不会自动下载；身份仍然按 `unionid`/`openid` 合并。

## 使用说明

1. 桌面端：点击「微信」→ 微信扫码 → 手机确认 → 回跳论坛。
2. 微信内：点击「微信」→ 微信授权页（`snsapi_base` 时静默通过；`snsapi_userinfo` 时已关注服务号的用户通常静默，其他情况会弹出授权页）→ 回跳论坛。
3. 微信不返回邮箱。**首次登录**会进入注册页，需要填写邮箱并完成邮箱激活；已有账号可在「偏好设置 → 账户 → 关联账户」中绑定微信。
4. 使用 `snsapi_userinfo` 时会同步昵称、头像与地区（`country province city`），头像由后台任务异步下载；使用 `snsapi_base` 时只保留 `openid`/`unionid` 身份，没有昵称和头像。

## 常见问题

**登录按钮不显示？**
检查总开关是否打开，以及至少一个渠道的 AppID/AppSecret 是否都已填写。

**微信内点击后提示「请在微信外打开」？**
说明当前走的是扫码渠道：公众号未配置，或 User-Agent 检测未命中。请配置公众号，或在微信内打开论坛。

**回调报 `redirect_uri` 参数错误 / 授权回调域错误？**
开放平台「授权回调域」和公众号「网页授权域名」都必须与论坛实际域名完全一致（子目录部署时还要确认 `DISCOURSE_RELATIVE_URL_ROOT` 配置正确）。

**公众号保存时提示「验证文件无法访问」？**
- 确认文件在容器 `/var/www/discourse/public/` 下，文件名大小写完全一致；
- `curl -i https://你的域名/MP_verify_<code>.txt` 必须返回 200 和验证码，不能 301/302 到登录页；
- 文件内容是验证码本身，不能有 HTML、BOM 或多余换行（`docker cp` 会保持原样）；
- `docker cp` 在容器重建后会丢失，长期使用请按上文 `app.yml` 的 `after_code` hook 持久化；
- 如果套了 CDN/WAF，确认该路径没有被拦截或缓存 404。

**报 `Scope 参数错误或没有 Scope 权限`？**
说明当前公众号 AppID 没有 `snsapi_userinfo`/`snsapi_base` 权限。先确认 `weixin_login_mp_app_id` 是**公众号**的 AppID（不是网站应用或小程序），且该公众号是**已认证的服务号**、接口权限里有「网页服务 → 网页授权」。两个 scope 都需要该权限，改成 `snsapi_base` 并不能绕过。

**为什么没有返回 unionid？**
公众号未绑定开放平台，或绑定到了另一个开放平台账号。此时插件会使用 openid 登录；绑定后用户下次通过公众号登录会自动升级。

**出现了重复账号？**
见[身份合并规则](#身份合并规则)第 4 条。日志中搜索 `[weixin-login]` 可以看到冲突提示。

**登录失败如何排查？**
查看 `log/production.log`（或容器日志）中的 `[weixin-login]` 记录；也可以在微信开放平台/公众号后台查看接口调用情况。

## 开发说明

代码结构：

| 文件 | 作用 |
|---|---|
| `plugin.rb` | 插件入口：注册图标、设置开关、登录提供商 |
| `lib/weixin_login/authenticator.rb` | `Auth::ManagedAuthenticator` 子类，注册 OmniAuth 中间件 |
| `lib/omniauth/strategies/weixin.rb` | OmniAuth2 策略：渠道切换、token、用户信息、错误处理 |
| `lib/weixin_login/flow.rb` | 渠道检测、授权地址、scope、state 前缀 |
| `lib/weixin_login/config.rb` | 两个渠道的设置读取与可用性判断 |
| `lib/weixin_login/identity.rb` | unionid/openid 归一化与旧数据迁移 |
| `db/migrate/*` | 旧插件 provider/设置项改名 |

参考文档：

- [微信开放平台 - 网站应用微信登录](https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Wechat_Login.html)
- [微信开放平台 - 授权后接口调用（UnionID）](https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Authorized_Interface_Calling_UnionID.html)
- [微信公众平台 - 网页授权](https://developers.weixin.qq.com/doc/service/guide/h5/auth.html)
- [获取授权用户信息](https://developers.weixin.qq.com/doc/service/api/webdev/access/api_snsuserinfo.html)

## 联系我

![wechat-work.png](static/wechat-work.png)

## License

[Apache License 2.0](LICENSE)
