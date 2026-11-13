# frozen_string_literal: true

module WeixinLogin
  # Keeps the WeChat identity stored in `user_associated_accounts` stable
  # across the two channels.
  #
  # unionid is the preferred identifier because the website app and the
  # official account share it when both are bound to the same 开放平台 account.
  # Official accounts that are not (yet) bound to the open platform only return
  # an openid, which is used as a fallback. Once such an account gets bound,
  # the next official account login returns both identifiers and the row is
  # upgraded from openid to unionid, so the user keeps their forum account.
  module Identity
    PROVIDER = "weixin"
    LEGACY_PROVIDER = "weixin_open"

    module_function

    def uid_for(unionid:, openid:)
      unionid.presence || openid.presence
    end

    def extract(auth_token)
      info = auth_token[:info] || {}
      raw = raw_info(auth_token)

      unionid = pick(info, raw, :unionid)
      openid = pick(info, raw, :openid)

      [unionid, openid]
    end

    # Rewrites auth_token[:uid] and migrates legacy rows before
    # Auth::ManagedAuthenticator looks the association up.
    def sync!(auth_token)
      unionid, openid = extract(auth_token)
      uid = uid_for(unionid: unionid, openid: openid)
      return if uid.blank?

      auth_token[:uid] = uid

      # Rows created by discourse-weixin-open-login (or by an earlier version
      # of this plugin) are stored under the weixin_open provider name.
      # Migration is best-effort: it must never prevent a login.
      begin
        adopt_legacy_provider!(uid)
        migrate_openid_to_unionid!(unionid: unionid, openid: openid)
      rescue StandardError => e
        log_warn("身份迁移失败（不影响本次登录）：#{e.class}: #{e.message}")
      end
    end

    def adopt_legacy_provider!(uid)
      return if uid.blank? || LEGACY_PROVIDER == PROVIDER

      legacy = UserAssociatedAccount.find_by(provider_name: LEGACY_PROVIDER, provider_uid: uid)
      return if legacy.nil?

      current = UserAssociatedAccount.find_by(provider_name: PROVIDER, provider_uid: uid)

      if current.nil?
        legacy.update!(provider_name: PROVIDER)
      elsif current.user_id.nil?
        current.destroy!
        legacy.update!(provider_name: PROVIDER)
      elsif legacy.user_id.nil? || legacy.user_id == current.user_id
        legacy.destroy!
      else
        log_conflict("weixin_open → weixin", legacy, current)
      end
    rescue ActiveRecord::RecordNotUnique
      log_warn("provider 迁移冲突（uid=#{uid}），已跳过")
    end

    def migrate_openid_to_unionid!(unionid:, openid:)
      return if unionid.blank? || openid.blank? || unionid == openid

      rows =
        UserAssociatedAccount.where(
          provider_name: [PROVIDER, LEGACY_PROVIDER],
          provider_uid: openid,
        ).to_a
      return if rows.empty?

      canonical = UserAssociatedAccount.find_by(provider_name: PROVIDER, provider_uid: unionid)

      rows.each do |row|
        next if canonical && canonical.id == row.id

        if canonical.nil?
          canonical = move_to_unionid!(row, unionid)
        elsif canonical.user_id.nil?
          canonical.destroy!
          canonical = move_to_unionid!(row, unionid)
        elsif row.user_id.nil? || row.user_id == canonical.user_id
          row.destroy!
        else
          log_conflict("openid → unionid", row, canonical)
        end
      end
    end

    def move_to_unionid!(row, unionid)
      row.update!(provider_name: PROVIDER, provider_uid: unionid)
      log_info("已把关联记录 #{row.id} 从 openid 升级为 unionid")
      row
    rescue ActiveRecord::RecordNotUnique
      log_warn("unionid 迁移冲突（关联记录 #{row.id}），已跳过")
      UserAssociatedAccount.find_by(provider_name: PROVIDER, provider_uid: unionid)
    end

    def raw_info(auth_token)
      extra = auth_token[:extra]
      return {} unless extra.respond_to?(:[])

      raw = extra["raw_info"] || extra[:raw_info]
      raw.is_a?(Hash) ? raw : {}
    end

    def pick(info, raw, key)
      [info[key], info[key.to_s], raw[key], raw[key.to_s]].compact.find(&:present?)
    end

    def log_conflict(kind, row, canonical)
      log_warn(
        "#{kind} 冲突，需人工合并账号：user_id=#{row.user_id.inspect} " \
          "(#{row.provider_name}/#{row.provider_uid}) 与 user_id=#{canonical.user_id.inspect} " \
          "(#{canonical.provider_name}/#{canonical.provider_uid})",
      )
    end

    def log_info(message)
      Rails.logger.info("[weixin-login] #{message}")
    rescue StandardError
      nil
    end

    def log_warn(message)
      Rails.logger.warn("[weixin-login] #{message}")
    rescue StandardError
      nil
    end
  end
end
