# frozen_string_literal: true

# El nombre con guion es el que Bundler carga. Los generators viven en
# lib/generators y Rails los encuentra solos: no hace falta requerirlos en cada boot.

$LOAD_PATH.unshift __dir__

require "universal_track_manager/identity"
require "universal_track_manager/column_limits"
require "universal_track_manager/controllers/concerns/universal_track_manager_concern"
require "universal_track_manager/models/browser"
require "universal_track_manager/models/campaign"
require "universal_track_manager/models/visit"
require "universal_track_manager"
