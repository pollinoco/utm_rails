UniversalTrackManager.configure do |config|
  config.track_ips = true
  config.track_utms = true
  config.track_user_agent = true
  # GENERATOR INSERTS CAMPAIGN COLUMN CONFIG HERE

  config.track_gclid_present = true # be sure to add gclid to campaign_columns
  config.track_http_referrer = false # be sure to add referer to visits

end
