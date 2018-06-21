require 'fastlane/action'
require_relative '../helper/shuttle_helper'
require 'faraday'
require 'json'
require 'app-info'
require 'terminal-table'

module Fastlane
  module Actions
    class ShuttleAction < Action
      def self.app_info(package_path)
        app_info = ::AppInfo.parse(package_path)
        return app_info.os.downcase, app_info.identifier, app_info.release_version, app_info.build_version
      end

      def self.get_release_name(params, app, environment, release_version, build_version)
        return params[:release_name] unless params[:release_name].to_s.empty?
        release_name = "#{app["attributes"]["name"]} v#{release_version}"
        if environment["attributes"]["versioning_id"] == "version_and_build"
          return "#{release_name}-#{build_version}"
        end 
        return release_name
      end

      def self.connection(params, endpoint, is_multipart = false)
        shuttle_base_url = params[:base_url]
        shuttle_access_token = params[:access_token]
        return Faraday.new(url: "#{shuttle_base_url}/api#{endpoint}") do |builder|
          # builder.response :logger, Logger.new(STDOUT), bodies: true
          builder.headers["Authorization"] = "Bearer #{shuttle_access_token}"
          builder.headers["Accept"] = "application/vnd.api+json"
          if is_multipart
            builder.request :multipart
          else
            builder.headers["Content-Type"] = "application/vnd.api+json"
          end
          builder.adapter :net_http
        end
      end

      def self.get_environments(params)
        connection = self.connection(params, '/environments')
        res = connection.get()
        data = JSON.parse(res.body)
        # UI.message("Debug: #{JSON.pretty_generate(data["data"][0])}\n")
        return data["data"]
      end

      def self.get_app(params, app_id)
        connection = self.connection(params, "/apps/#{app_id}")
        res = connection.get()
        data = JSON.parse(res.body)
        # UI.message("Debug: #{JSON.pretty_generate(data["data"])}\n")
        return data["data"]
      end

      def self.zipAppsWithEnvironments(params, environments)
        apps = environments.map do |env| 
          self.get_app(params, env["relationships"]["app"]["data"]["id"])
        end

        apps.zip(environments)
      end

      def self.upload_build(params, package_path, app_id)
        connection = self.connection(params, '/builds', true)
        res = connection.post do |req|
          req.body = {
            "build[app_id]": app_id,
            "build[package]": Faraday::UploadIO.new(package_path, 'application/octet-stream')
          }
        end
        data = JSON.parse res.body
        # UI.message(JSON.pretty_generate(data))
        return data["data"]
      end

      def self.create_release(params, build_id, env_id, commit_id, release_name)
        connection = self.connection(params, "/releases")
        res = connection.post do |req|
          req.body = JSON.generate({
            data: {
              type: "releases",
              attributes: {
                title: release_name,
                notes: params[:release_notes],
                commit_id: commit_id
              },
              relationships: {
                build: {
                  data: {
                    id: build_id,
                    type: "builds"
                  }
                },
                environment: {
                  data: {
                    id: env_id,
                    type: "environments"
                  }
                }
              }
            }
          })
        end
        data = JSON.parse res.body
        # UI.message(JSON.pretty_generate(data))
      end

      def self.run(params)
        package_path = params[:package_path] unless params[:package_path].to_s.empty?
        package_path = lane_context[SharedValues::IPA_OUTPUT_PATH] if package_path.to_s.empty?
        package_path = lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH] if package_path.to_s.empty?
        UI.abort_with_message!("No Package file found") if package_path.to_s.empty?
        UI.abort_with_message!("Package at path #{package_path} does not exist") unless File.exist?(package_path)

        package_platform_id, package_id, release_version, build_version = self.app_info(package_path)
        commit_id = Helper.backticks("git show --format='%H' --quiet").chomp
        
        UI.message("Uploading #{package_platform_id} package #{package_path} with ID #{package_id}…")

        environments = self.get_environments(params)

        app = nil
        app_id = ""
        env_id = ""
        environment = nil
        environments.select do |env|
          env["attributes"]["package_id"] == package_id
        end
        
        UI.abort_with_message!("No environments configured for package id #{package_id}") if environments.empty?

        if environments.count == 1 
            env = environments[0]
            env_id = env["id"]
            app_id = env["relationships"]["app"]["data"]["id"]
            environment = env
            app = self.get_app(params, app_id)
        else
          UI.abort_with_message!("Too many environments with package id #{package_id}") unless UI.interactive?
          appsWithEnvironments = self.zipAppsWithEnvironments(params, environments)
          options = appsWithEnvironments.map do |appWithEnv|
            app = appWithEnv[0]
            env = appWithEnv[1]
            "#{app["attributes"]["name"]} (#{env["attributes"]["name"]})"
          end
          abort_options = "None match, abort"
          user_choice = UI.select "Can't guess which app and environment to use, please choose the correct one:", options << abort_options
          case user_choice
          when abort_options
            UI.user_error!("Aborting…")
          else
            choice_index = options.find_index(user_choice)
            appWithEnv = appsWithEnvironments[choice_index]
            app = appWithEnv[0]
            env = appWithEnv[1]
            env_id = env["id"]
            app_id = app["id"]
            environment = env
          end
        end

        
        
        release_name = self.get_release_name(params, app, environment, release_version, build_version)

        if app["attributes"]["platform_id"] != package_platform_id 
          UI.error("No apps configured for #{package_platform_id} with package id #{package_id}")
          return 
        end

        rows = [
          'Shuttle Base URL', 
          'Shuttle app name', 
          'Shuttle env name', 
          'Package path', 
          'Platform', 
          'Package Id',
          'Release name',
          'Release version',
          'Build version',
          'Release notes',
          'Commit hash'
        ].zip([
            params[:base_url], 
            app["attributes"]["name"], 
            environment["attributes"]["name"], 
            package_path, 
            package_platform_id, 
            package_id,
            release_name,
            release_version,
            build_version,
            params[:release_notes],
            commit_id
        ])
        table = Terminal::Table.new :rows => rows, :title => "Summary for Shuttle upload".green
        puts
        puts table
        puts

        build = self.upload_build(params, package_path, app_id)
        build_id = build["id"]

        self.create_release(params, build_id, env_id, commit_id, release_name)
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
