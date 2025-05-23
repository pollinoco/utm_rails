lib = File.expand_path("lib", __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "version.rb"

Gem::Specification.new do |s|
  s.name        = 'universal-track-manager'
  s.version     = UniversalTrackManager::VERSION
  s.license     = 'MIT'
  s.date        = Time.now.strftime("%Y-%m-%d")
  s.summary     = "A gem to track visitors and their UTMs to your website."
  s.description = "Simple, plug & play visitor tracking by user agent (browser), IP address, referer, and UTM parameters."
  s.authors     = ["Jason Fleetwood-Boldt"]
  s.email       = 'support@heliosdev.shop'

  all_files       = `git ls-files -z`.split("\x0")

  s.files         = all_files.reject{|x| !x.start_with?('lib')}

  s.require_paths = ["lib"]

  s.homepage    = 'https://heliosdev.shop/p/universal-track-manager'

  s.metadata    = { "source_code_uri" => "https://github.com/jasonfb/universal_track_manager",
                    "homepage_uri" => 'https://heliosdev.shop/p/universal-track-manager'}


  s.add_dependency('rails', '> 5.1')
  s.add_dependency('public_suffix')
  s.add_development_dependency('simplecov')
  s.add_development_dependency('simplecov-rcov')
  s.add_development_dependency('appraisal', '> 2.2')
end
