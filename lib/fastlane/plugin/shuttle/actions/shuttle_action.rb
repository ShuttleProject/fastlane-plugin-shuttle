require 'fastlane/action'
require_relative '../helper/shuttle_helper'
require_relative '../helper/app_environment_selector'
require 'faraday'
require 'json'
require 'app-info'
require 'terminal-table'

ShuttleInstance = Struct.new(:base_url, :access_token)
ShuttleApp = Struct.new(:id, :name, :platform_id)
ShuttleEnvironment = Struct.new(:id, :name, :package_id, :app_id, :versioning_id)
ShuttleBuild = Struct.new(:id)
AppEnvironment = Struct.new(:shuttle_app, :shuttle_environment)
PackageInfo = Struct.new(:id, :path, :platform_id, :release_version, :build_version)
ReleaseInfo = Struct.new(:name, :notes, :build, :environment, :commit_id)

module Fastlane
  module Actions
    class ShuttleAction < Action
      def self.run(params)
        helper = Helper::ShuttleHelper
        selector = Helper::AppEnvironmentSelector
        shuttle_instance = helper.get_shuttle_instance(params)
        package_info = helper.get_app_info(params)
        
        UI.message("Uploading #{package_info.platform_id} package #{package_info.path} with ID #{package_info.id}…")

        app_environment = selector.get_app_environment(shuttle_instance, package_info)
        
        release = helper.get_release_info(params, app_environment, package_info)

        helper.print_summary_table(shuttle_instance, app_environment, package_info, release)

        release.build = helper.upload_build(shuttle_instance, package_info, app_environment.shuttle_app.id)

        helper.create_release(shuttle_instance, release)
      end

      def self.description
        "Publish your builds on Shuttle.tools"
      end

      def self.authors
        ["Frédéric Ruaudel"]
      end

      def self.return_value
        # If your method provides a return value, you can describe here what it does
      end

      def self.details
        # Optional:
        "Fastlane plugin to help you distribute your builds on your Shuttle.tools instance"
      end

      def self.available_options
        [
          FastlaneCore::ConfigItem.new(key: :package_path,
                                  env_name: "SHUTTLE_PACKAGE_PATH",
                               description: "The path to the new app you want to upload to Shuttle (check in shared values GRADLE_APK_OUTPUT_PATH or IPA_OUTPUT_PATH if not present)",
                                  optional: true,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :base_url,
                                  env_name: "SHUTTLE_BASE_URL",
                               description: "The base url of your Shuttle instance",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :access_token,
                                  env_name: "SHUTTLE_ACCESS_TOKEN",
                               description: "The access token of your account on Shuttle",
                                  optional: false,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :release_name,
                                  env_name: "SHUTTLE_RELEASE_NAME",
                               description: "The name of the release (eg. MyApp v3)",
                                  optional: true,
                                      type: String),
          FastlaneCore::ConfigItem.new(key: :release_notes,
                                  env_name: "SHUTTLE_RELEASE_NOTES",
                               description: "The release notes of the release (eg. Bug fixes)",
                                  optional: true,
                             default_value: "Bug fixes and improvements",
                                      type: String)
        ]
      end

      def self.is_supported?(platform)
        # Adjust this if your plugin only works for a particular platform (iOS vs. Android, for example)
        # See: https://docs.fastlane.tools/advanced/#control-configuration-by-lane-and-by-platform
        #
        # [:ios, :mac, :android].include?(platform)
        true
      end
    end
  end
end
