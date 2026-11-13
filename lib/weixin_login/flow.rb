# frozen_string_literal: true

module WeixinLogin
  # Chooses and describes the WeChat channel used for a login attempt.
  #
  # The channel is detected from the User-Agent on the authorization request
  # and is encoded into the OAuth2 `state` parameter, so the callback can pick
  # the matching AppID/AppSecret even if the session is not available.
  module Flow
    OPEN = :open
    MP = :mp
    SUPPORTED = [OPEN, MP].freeze

    AUTHORIZE_URLS = {
      OPEN => "https://open.weixin.qq.com/connect/qrconnect",
      MP => "https://open.weixin.qq.com/connect/oauth2/authorize",
    }.freeze

    SCOPES = {
      OPEN => "snsapi_login",
      MP => "snsapi_userinfo",
    }.freeze

    # WeChat documents `state` as an alphanumeric value, so the channel is
    # encoded as a prefix instead of using a separator such as ":".
    STATE_PREFIXES = { OPEN => "open", MP => "mp" }.freeze

    module_function

    def resolve(env)
      if callback_request?(env)
        flow = flow_from_params(callback_params(env))
        return flow if flow
      end

      detect(env)
    end

    # Inside WeChat the official account flow is the only one that works
    # properly; everywhere else prefer the QR code flow when it is configured.
    def detect(env)
      if wechat_browser?(env) && Config.mp_available?
        MP
      elsif Config.open_available?
        OPEN
      elsif Config.mp_available?
        MP
      end
    end

    def authorize_url(flow)
      AUTHORIZE_URLS.fetch(flow || OPEN)
    end

    def scope(flow)
      SCOPES.fetch(flow || OPEN)
    end

    def state(flow, random)
      "#{STATE_PREFIXES.fetch(flow || OPEN)}#{random}"
    end

    def flow_from_params(params)
      value = params["state"].to_s
      return MP if value.start_with?(STATE_PREFIXES[MP])
      return OPEN if value.start_with?(STATE_PREFIXES[OPEN])

      nil
    end

    def wechat_browser?(env)
      env["HTTP_USER_AGENT"].to_s.match?(/MicroMessenger/i)
    end

    def callback_request?(env)
      env["PATH_INFO"].to_s.end_with?("/callback")
    end

    def callback_params(env)
      Rack::Request.new(env).params
    rescue StandardError
      {}
    end
  end
end
