# frozen_string_literal: true

require "omniauth-oauth2"
require "uri"

# A single OmniAuth strategy shared by the 微信开放平台网站应用 (QR code login)
# and the 微信公众号 (OAuth2 login inside WeChat). The channel is detected on
# the authorization request (see WeixinLogin::Flow) and encoded into the OAuth2
# state parameter so the callback uses the matching AppID/AppSecret.
class OmniAuth::Strategies::Weixin < ::OmniAuth::Strategies::OAuth2
  option :name, "weixin"

  # /sns/userinfo is only available for these scopes. snsapi_base is the
  # silent official-account scope and only returns openid (plus unionid when
  # the account is bound to the open platform), so it must skip userinfo.
  USERINFO_SCOPES = %w[snsapi_userinfo snsapi_login].freeze

  option :client_options, {
    site: "https://api.weixin.qq.com",
    token_url: "/sns/oauth2/access_token",
    token_method: :get,
  }

  # oauth2 2.x sends the access token in the Authorization header by default,
  # but WeChat only accepts it as a query parameter. See
  # https://developers.weixin.qq.com/doc/oplatform/Website_App/WeChat_Login/Authorized_Interface_Calling_UnionID.html
  option :auth_token_params, { mode: :query }

  def client
    ::OAuth2::Client.new(options.client_id, options.client_secret, connection_options)
  end

  def request_phase
    flow = current_flow
    return fail!(:weixin_not_configured) if flow.blank?

    options[:flow] = flow

    # Built by hand instead of client.auth_code.authorize_url because oauth2
    # 2.x injects its own `client_id` parameter, while WeChat expects `appid`.
    params = { redirect_uri: callback_url, response_type: "code" }.merge(authorize_params)
    query = URI.encode_www_form(params.to_hash)
    redirect "#{WeixinLogin::Flow.authorize_url(flow)}?#{query}#wechat_redirect"
  end

  def authorize_params
    super.tap do |params|
      flow = current_flow || WeixinLogin::Flow::OPEN

      params[:appid] = options.client_id
      params[:scope] = WeixinLogin::Flow.scope(flow)
      params[:state] = WeixinLogin::Flow.state(flow, params[:state])

      # omniauth-oauth2 stored the raw state in the session before returning.
      # Keep the CSRF comparison in sync with the state we actually send.
      session["omniauth.state"] = params[:state]
    end
  end

  def token_params
    super.tap do |params|
      params[:appid] = options.client_id
      params[:secret] = options.client_secret
    end
  end

  def build_access_token
    token = super
    params = token.params

    # WeChat reports errors with HTTP 200 and an errcode payload, so the
    # oauth2 gem would otherwise build an empty access token.
    if params["errcode"].present? || token.token.blank? || params["openid"].blank?
      message = params["errmsg"].presence || "WeChat authorization failed"
      raise CallbackError.new(:weixin_token_error, message)
    end

    token
  end

  uid do
    params = access_token.params
    params["unionid"].presence || raw_info["unionid"].presence || params["openid"]
  end

  info do
    raw = raw_info
    {
      nickname: raw["nickname"],
      name: raw["nickname"],
      image: raw["headimgurl"],
      location: location(raw),
      sex: raw["sex"],
      openid: access_token.params["openid"],
      unionid: access_token.params["unionid"].presence || raw["unionid"],
    }
  end

  extra do
    {
      "raw_info" => raw_info,
      "scope" => access_token.params["scope"],
    }
  end

  def raw_info
    return @raw_info if defined?(@raw_info)

    @raw_info =
      begin
        openid = access_token.params["openid"]
        if openid.blank? || !userinfo_scope?
          {}
        else
          data =
            access_token.get("/sns/userinfo", params: { openid: openid, lang: "zh_CN" }).parsed
          if data.is_a?(Hash) && data["errcode"].present?
            log_warn("userinfo failed: #{data["errcode"]} #{data["errmsg"]}")
            {}
          else
            data.is_a?(Hash) ? data : {}
          end
        end
      rescue StandardError => e
        log_warn("userinfo request failed: #{e.class}: #{e.message}")
        {}
      end
  end

  def callback_url
    # OmniAuth 2 already includes script_name in callback_path, and the query
    # string must not end up in the redirect_uri used for the token exchange.
    full_host + callback_path
  end

  private

  def current_flow
    options[:flow].presence || WeixinLogin::Flow.resolve(env)
  end

  def connection_options
    opts = options.client_options.to_hash
    opts[:authorize_url] = WeixinLogin::Flow.authorize_url(current_flow)
    opts[:connection_build] ||= proc do |builder|
      builder.request :url_encoded
      builder.response :json, content_type: /\bjson$/
      builder.response :json, content_type: /\btext\/plain/
      builder.adapter Faraday.default_adapter
    end
    deep_symbolize(opts)
  end

  def userinfo_scope?
    scope = access_token.params["scope"].to_s
    scope.blank? || USERINFO_SCOPES.include?(scope)
  end

  def location(raw)
    [raw["country"], raw["province"], raw["city"]].reject(&:blank?).join(" ").presence
  end

  def log_warn(message)
    Rails.logger.warn("[weixin-login] #{message}")
  rescue StandardError
    nil
  end
end
