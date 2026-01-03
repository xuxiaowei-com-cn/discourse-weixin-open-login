# frozen_string_literal: true

# name: discourse-weixin-open-login
# about: 允许用户使用微信（开放平台-网站应用）登录到您的 Discourse 论坛。
# version: 0.0.1
# authors: 徐晓伟<xuxiaowei@xuxiaowei.com.cn>
# url: http://github.com/xuxiaowei-com-cn/discourse-weixin-open-login

require_relative "lib/omniauth/strategies/weixin_open"

register_svg_icon "weixin_open" if respond_to?(:register_svg_icon)

enabled_site_setting :weixin_open_login_enabled

class WeixinOpenAuthenticator < ::Auth::ManagedAuthenticator
  def name
    "weixin_open"
  end

  def enabled?
    SiteSetting.weixin_open_login_enabled?
  end

  def provider_url
    "https://open.weixin.qq.com"
  end

  def register_middleware(omniauth)
    omniauth.provider :weixin_open,
                      setup: lambda { |env|
                        strategy = env["omniauth.strategy"]
                        strategy.options[:client_id] = SiteSetting.weixin_open_login_app_id
                        strategy.options[:client_secret] = SiteSetting.weixin_open_login_app_secret
                      }
  end

  def primary_email_verified?(auth_token)
    true
  end
end

auth_provider title_setting: "weixin_open_login_button_title", icon: "weixin_open", authenticator: WeixinOpenAuthenticator.new
