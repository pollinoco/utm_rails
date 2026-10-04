UniversalTrackManager.configure do |config|
  config.track_ips = true
  config.track_utms = true
  config.track_user_agent = true
  config.campaign_columns = "<%= campaign_column_list %>"
  config.hashed_columns = "<%= campaign_column_list %>"

  config.track_gclid_present = true # agrega gclid a campaign_columns si lo usas
  config.track_http_referrer = false
  # Segundos entre escrituras de last_pageload. 0 actualiza en cada request.
  config.touch_interval = 300
end
