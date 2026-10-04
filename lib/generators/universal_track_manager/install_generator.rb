# frozen_string_literal: true

require "rails/generators"

module UniversalTrackManager
  class InstallGenerator < Rails::Generators::Base
    include Rails::Generators::Migration

    desc "Crea el initializer y la migración de Universal Track Manager."

    source_root File.expand_path("../templates", __dir__)

    class_option :orm, type: :boolean
    class_option :param_list, type: :string, default: nil
    class_option :add, type: :string, default: nil
    class_option :only, type: :string, default: nil

    def self.next_migration_number(path)
      Time.now.utc.strftime("%Y%m%d%H%M%S")
    end

    def create_universal_track_manager_migration
      prepare_campaign_columns!
      migration_template "create_universal_track_manager_tables.rb",
                         "db/migrate/create_universal_track_manager_tables.rb"
    end

    def create_universal_track_manager_initializer
      prepare_campaign_columns!
      template "universal_track_manager.rb", "config/initializers/universal_track_manager.rb"
    end

    private

    def campaign_column_list
      prepare_campaign_columns!.join(",")
    end

    def prepare_campaign_columns!
      return @default_params if defined?(@default_params) && @default_params

      if options[:param_list]
        raise Thor::Error, "param_list ya no existe; usa add para sumar columnas u only para reemplazarlas"
      end
      if options[:add] && options[:only]
        raise Thor::Error, "usa add u only, no los dos a la vez"
      end

      @default_params = %w[utm_id utm_source utm_medium utm_campaign utm_content utm_term]
      extras = if options[:only]
        options[:only].split(",")
      elsif options[:add]
        options[:add].split(",")
      else
        []
      end

      if options[:only]
        @default_params = []
      end

      extras.each do |name|
        column = name.strip
        unless column.match?(/\A[a-z][a-z0-9_]*\z/)
          raise Thor::Error, "columna inválida: #{column}"
        end
        @default_params << column unless @default_params.include?(column)
      end

      @default_params
    end

    def migration_version
      "[#{ActiveRecord::Migration.current_version}]" if ActiveRecord::Migration.respond_to?(:current_version)
    end
  end
end
