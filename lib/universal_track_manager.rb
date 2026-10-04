# frozen_string_literal: true

module UniversalTrackManager
  require "railtie.rb" if defined?(Rails)

  class Settings
    attr_accessor :track_ips,
                  :track_utms,
                  :track_user_agent,
                  :track_http_referrer,
                  :campaign_columns,
                  :hashed_columns,
                  :track_gclid_present,
                  :touch_interval
  end

  def self.configure
    @_settings = Settings.new
    @campaign_column_names = nil
    @campaign_column_symbols = nil
    @campaign_column_hashed = nil

    yield @_settings if block_given?
  end

  def self.track_ips?
    @_settings.track_ips
  end

  def self.track_utms?
    @_settings.track_utms
  end

  def self.track_user_agent?
    @_settings.track_user_agent
  end

  def self.track_http_referrer?
    @_settings.track_http_referrer
  end

  def self.track_gclid_present?
    @_settings.track_gclid_present
  end

  # Segundos entre updates de last_pageload. nil usa 300. 0 escribe en cada request.
  def self.touch_interval
    value = @_settings.touch_interval
    value.nil? ? 300 : value.to_i
  end

  def self.campaign_column_names
    @campaign_column_names ||= campaign_column_symbols.map(&:to_s)
  end

  def self.campaign_column_symbols
    @campaign_column_symbols ||= split_columns(@_settings.campaign_columns)
  end

  def self.campaign_column_hashed
    @campaign_column_hashed ||= begin
      raw = @_settings.hashed_columns
      raw = @_settings.campaign_columns if raw.nil?
      split_columns(raw)
    end
  end

  def self.split_columns(raw)
    raw.to_s.split(",").filter_map do |name|
      stripped = name.strip
      stripped.empty? ? nil : stripped.to_sym
    end
  end
  private_class_method :split_columns
end
