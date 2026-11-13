# frozen_string_literal: true

# name: discourse-weixin-login
# about: 允许用户使用微信登录 Discourse：桌面端使用微信开放平台（网站应用）扫码登录，微信内使用微信公众号授权登录。
# version: 0.1.0
# authors: 徐晓伟<xuxiaowei@xuxiaowei.com.cn>
# url: https://github.com/xuxiaowei-com-cn/discourse-weixin-login

require_relative "lib/weixin_login/config"
require_relative "lib/weixin_login/flow"
require_relative "lib/weixin_login/identity"
require_relative "lib/omniauth/strategies/weixin"
require_relative "lib/weixin_login/authenticator"

register_svg_icon "weixin" if respond_to?(:register_svg_icon)

enabled_site_setting :weixin_login_enabled

auth_provider title_setting: "weixin_login_button_title",
              icon: "weixin",
              authenticator: WeixinLogin::Authenticator.new
