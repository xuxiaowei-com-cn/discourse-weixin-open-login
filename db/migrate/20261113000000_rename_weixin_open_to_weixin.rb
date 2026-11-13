# frozen_string_literal: true

# Renames data created by the former discourse-weixin-open-login plugin so
# existing users keep their WeChat association and their admin configuration
# after upgrading.
class RenameWeixinOpenToWeixin < ActiveRecord::Migration[7.0]
  SETTINGS = {
    "weixin_open_login_enabled" => "weixin_login_enabled",
    "weixin_open_login_app_id" => "weixin_login_open_platform_app_id",
    "weixin_open_login_app_secret" => "weixin_login_open_platform_app_secret",
    "weixin_open_login_button_title" => "weixin_login_button_title",
  }.freeze

  def up
    # Skip rows that would violate either unique index on
    # user_associated_accounts: (provider_name, user_id) and
    # (provider_name, provider_uid).
    execute <<~SQL
      UPDATE user_associated_accounts AS legacy
      SET provider_name = 'weixin'
      WHERE legacy.provider_name = 'weixin_open'
        AND NOT EXISTS (
          SELECT 1
          FROM user_associated_accounts AS current
          WHERE current.provider_name = 'weixin'
            AND (
              current.user_id IS NOT DISTINCT FROM legacy.user_id
              OR current.provider_uid = legacy.provider_uid
            )
        )
    SQL

    SETTINGS.each do |old_name, new_name|
      execute <<~SQL
        UPDATE site_settings
        SET name = #{connection.quote(new_name)}
        WHERE name = #{connection.quote(old_name)}
          AND NOT EXISTS (
            SELECT 1 FROM site_settings WHERE name = #{connection.quote(new_name)}
          )
      SQL
    end
  end

  def down
    SETTINGS.each do |old_name, new_name|
      execute <<~SQL
        UPDATE site_settings
        SET name = #{connection.quote(old_name)}
        WHERE name = #{connection.quote(new_name)}
          AND NOT EXISTS (
            SELECT 1 FROM site_settings WHERE name = #{connection.quote(old_name)}
          )
      SQL
    end

    execute <<~SQL
      UPDATE user_associated_accounts AS current
      SET provider_name = 'weixin_open'
      WHERE current.provider_name = 'weixin'
        AND NOT EXISTS (
          SELECT 1
          FROM user_associated_accounts AS old
          WHERE old.provider_name = 'weixin_open'
            AND (
              old.user_id IS NOT DISTINCT FROM current.user_id
              OR old.provider_uid = current.provider_uid
            )
        )
    SQL
  end
end
