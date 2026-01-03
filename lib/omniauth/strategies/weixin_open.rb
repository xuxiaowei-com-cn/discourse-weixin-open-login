# frozen_string_literal: true

require "omniauth-oauth2"

module OmniAuth
  module Strategies
    class WeixinOpen < OmniAuth::Strategies::OAuth2
      option :name, "weixin_open"

      option :client_options, {
        site: "https://api.weixin.qq.com",
        authorize_url: "https://open.weixin.qq.com/connect/qrconnect",
        token_url: "/sns/oauth2/access_token",
        token_method: :get,
        auth_scheme: :request_body
      }

      def client
        options.client_options[:connection_build] ||= proc do |builder|
          builder.request :url_encoded
          builder.response :json, content_type: /\bjson$/
          builder.response :json, content_type: /\btext\/plain/
          builder.adapter ::Faraday.default_adapter
        end
        super
      end

      option :authorize_params, {
        scope: "snsapi_login"
      }

      def authorize_params
        super.tap do |params|
          params[:appid] = options.client_id
          params.delete(:client_id)
        end
      end

      def token_params
        super.tap do |params|
          params[:appid] = options.client_id
          params[:secret] = options.client_secret
          params.delete(:client_id)
          params.delete(:client_secret)
        end
      end

      uid do
        access_token.params["unionid"] || raw_info["unionid"]
      end

      info do
        {
          nickname: raw_info["nickname"],
          image: raw_info["headimgurl"],
          location: "#{raw_info['country']} #{raw_info['province']} #{raw_info['city']}",
          sex: raw_info["sex"]
        }
      end

      extra do
        {
          "raw_info" => raw_info
        }
      end

      def raw_info
        @raw_info ||= begin
          openid = access_token.params["openid"]
          response = access_token.get("/sns/userinfo", params: { openid: openid, lang: "zh_CN" })
          response.parsed
        end
      end

      def callback_url
        full_host + script_name + callback_path
      end
    end
  end
end
