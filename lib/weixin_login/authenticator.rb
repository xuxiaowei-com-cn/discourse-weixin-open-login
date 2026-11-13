# frozen_string_literal: true

module WeixinLogin
  class Authenticator < ::Auth::ManagedAuthenticator
    def name
      WeixinLogin::Identity::PROVIDER
    end

    def display_name
      I18n.t("weixin_login.name", default: "微信")
    end

    def provider_url
      "https://open.weixin.qq.com"
    end

    def enabled?
      SiteSetting.weixin_login_enabled? && WeixinLogin::Config.any_available?
    end

    def register_middleware(omniauth)
      omniauth.provider :weixin,
                        setup: lambda { |env|
                          strategy = env["omniauth.strategy"]
                          flow = WeixinLogin::Flow.resolve(env)

                          strategy.options[:flow] = flow
                          strategy.options[:client_id] = WeixinLogin::Config.app_id(flow)
                          strategy.options[:client_secret] = WeixinLogin::Config.app_secret(flow)
                        }
    end

    # Normalize unionid/openid and migrate rows created before the official
    # account was bound to the open platform.
    def after_authenticate(auth_token, existing_account: nil)
      WeixinLogin::Identity.sync!(auth_token)
      super
    end
  end
end
