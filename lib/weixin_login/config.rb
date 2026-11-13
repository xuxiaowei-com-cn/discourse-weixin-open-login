# frozen_string_literal: true

module WeixinLogin
  # Resolves the credentials of the two WeChat channels.
  #
  # :open is the 微信开放平台网站应用 (QR code login) and :mp is the
  # 微信公众号 (OAuth2 login inside WeChat). Both flows share the same
  # OAuth2 endpoints but use a different AppID/AppSecret pair.
  module Config
    OPEN = :open
    MP = :mp

    module_function

    def app_id(flow)
      flow == MP ? SiteSetting.weixin_login_mp_app_id : SiteSetting.weixin_login_open_platform_app_id
    end

    def app_secret(flow)
      if flow == MP
        SiteSetting.weixin_login_mp_app_secret
      else
        SiteSetting.weixin_login_open_platform_app_secret
      end
    end

    def open_available?
      SiteSetting.weixin_login_open_platform_enabled? &&
        app_id(OPEN).present? &&
        app_secret(OPEN).present?
    end

    def mp_available?
      SiteSetting.weixin_login_mp_enabled? && app_id(MP).present? && app_secret(MP).present?
    end

    def any_available?
      open_available? || mp_available?
    end
  end
end
