require 'fastlane_core/ui/ui'
require 'fastlane/action'
require 'uri'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class ShuttleHelper
      # class methods that you define here become available in your action
      # as `Helper::ShuttleHelper.your_method`
      #
      def self.get_shuttle_instance(params) 
        shuttle_base_url = params[:base_url]
        shuttle_access_token = params[:access_token]
        ShuttleInstance.new(shuttle_base_url, shuttle_access_token)
      end

      def self.get_app_info(params)
        package_path = params[:package_path] unless params[:package_path].to_s.empty?
        package_path = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::IPA_OUTPUT_PATH] if package_path.to_s.empty?
        package_path = Fastlane::Actions.lane_context[Fastlane::Actions::SharedValues::GRADLE_APK_OUTPUT_PATH] if package_path.to_s.empty?
        UI.abort_with_message!("No Package file found") if package_path.to_s.empty?
        UI.abort_with_message!("Package at path #{package_path} does not exist") unless File.exist?(package_path)
        app_info = ::AppInfo.parse(package_path)
        PackageInfo.new(app_info.identifier, app_info.name, package_path, app_info.os.downcase, app_info.release_version, app_info.build_version)
      end

      def self.get_release_info(params, app_environment, package_info) 
        name = params[:release_name]
        notes = params[:release_notes]
        commit_id = Helper.backticks("git show --format='%H' --quiet").chomp
        ReleaseInfo.new(name, notes, nil, app_environment.shuttle_environment, commit_id)
      end

      def self.connection(shuttle_instance, endpoint, is_multipart = false)
        return Faraday.new(url: "#{shuttle_instance.base_url}/api#{endpoint}") do |builder|
          # builder.response :logger, Logger.new(STDOUT), bodies: true
          builder.headers["Authorization"] = "Bearer #{shuttle_instance.access_token}"
          builder.headers["Accept"] = "application/vnd.api+json"
          builder.options.timeout = 120
          if is_multipart
            builder.request :multipart
          else
            builder.headers["Content-Type"] = "application/vnd.api+json"
          end
          builder.adapter :net_http
        end
      end

      def self.get(shuttle_instance, endpoint, debug=false) 
        connection = self.connection(shuttle_instance, endpoint)
        response = connection.get()
        case response.status
        when 200...300
          data = JSON.parse(response.body)
          UI.message("Debug: #{JSON.pretty_generate(data["data"])}\n") if debug == true
          data["data"]
        else 
          UI.abort_with_message!("Error #{response.status.to_s} occured while calling endpoint #{endpoint}")
          nil
        end
      end

      def self.environment_from_json(json_env)
        attrb = json_env["attributes"]
        ShuttleEnvironment.new(
          json_env["id"],
          attrb["name"],
          attrb["package_id"],
          json_env["relationships"]["app"]["data"]["id"],
          attrb["versioning_id"],
          attrb["path"]
        )
      end

      def self.get_environments(shuttle_instance)
        self.get(shuttle_instance, '/environments').map do |json_env|
          self.environment_from_json(json_env)
        end
      end

      def self.get_environment(shuttle_instance, env_id)
        json_env = self.get(shuttle_instance, "/environments/#{env_id}")
        self.environment_from_json(json_env)
      end

      def self.get_environments_for_app(shuttle_instance, app)
        self.get(shuttle_instance, "/apps/#{app.id}/environments").map do |json_env|
          self.environment_from_json(json_env)
        end
      end

      def self.create_environment(shuttle_instance, name, versioning_id, app_id, package_id)
        body = JSON.generate({
          data: {
            type: "environments",
            attributes: {
              name: name,
              path: name.downcase,
              package_id: package_id,
              versioning_id: versioning_id
            },
            relationships: {
              app: {
                data: {
                  id: app_id,
                  type: "apps"
                }
              }
            }
          }
        })
        json_env = self.post(shuttle_instance, "/environments", body)
        self.environment_from_json(json_env)
      end

      def self.app_from_json(json_app)
        json_app_attrb = json_app["attributes"]
        ShuttleApp.new(
          json_app["id"],
          json_app_attrb["name"],
          json_app_attrb["platform_id"],
          json_app_attrb["path"]
        )
      end

      def self.get_apps(shuttle_instance)
        self.get(shuttle_instance, "/apps/").map do |json_app|
          self.app_from_json(json_app)
        end
      end

      def self.get_app(shuttle_instance, app_id)
        json_app = self.get(shuttle_instance, "/apps/#{app_id}")
        self.app_from_json(json_app)
      end

      def self.create_app(shuttle_instance, app_name, app_platform)
        app_path = "#{app_name.downcase}-#{app_platform}"
        body = JSON.generate({
          data: {
            type: "apps",
            attributes: {
              name: app_name,
              path: app_path,
              platform_id: app_platform
            }
          }
        })
        json_app = self.post(shuttle_instance, "/apps", body)
        self.app_from_json(json_app)
      end

      def self.get_app_environments(shuttle_instance, environments)
        apps = environments.map do |env| 
          self.get_app(shuttle_instance, env.app_id)
        end

        apps.zip(environments).map do |app_env| 
          AppEnvironment.new(
            app_env[0],
            app_env[1]
          )
        end
      end

      def self.post(shuttle_instance, endpoint, body, is_multipart: false, debug: false)
        connection = self.connection(shuttle_instance, endpoint, is_multipart)
        response = connection.post do |req|
          req.body = body
        end
        case response.status
        when 200...300
          data = JSON.parse response.body
          UI.message(JSON.pretty_generate(data)) if debug == true
          data["data"]
        else
          self.abort(endpoint, body, response)
          nil
        end
      end

      def self.abort(endpoint, body, response)
        reqBody = JSON.parse body
        errorBody = JSON.parse response.body
        case endpoint
        when "/releases"
          UI.abort_with_message!("💥 Can't create release for #{reqBody["data"]["attributes"]["title"]}: #{errorBody["errors"][0]["detail"]}")
        else
          UI.abort_with_message!("Error #{response.status.to_s} occured while calling endpoint #{endpoint} with body #{body} => #{errorBody["errors"][0]["detail"]}")
        end
      end 

      def self.upload_build(shuttle_instance, package_info, app_id)
        body = {
          "build[app_id]": app_id,
          "build[package]": Faraday::UploadIO.new(package_info.path, 'application/octet-stream')
        }
        json_build = self.post(shuttle_instance, '/builds', body, is_multipart: true)
        ShuttleBuild.new(json_build["id"])
      end

      def self.create_release(shuttle_instance, release)
        body = JSON.generate({
          data: {
            type: "releases",
            attributes: {
              title: release.name,
              notes: release.notes,
              commit_id: release.commit_id
            },
            relationships: {
              build: {
                data: {
                  id: release.build.id,
                  type: "builds"
                }
              },
              environment: {
                data: {
                  id: release.environment.id,
                  type: "environments"
                }
              }
            }
          }
        })
        json_release = self.post(shuttle_instance, "/releases", body)
      end

      def self.prompt_choices(question, options, nonInteractiveErrorMessage) 
        UI.abort_with_message!(nonInteractiveErrorMessage) unless UI.interactive?
          abort_option = "None match, abort"
          user_choice = UI.select question, options << abort_option
          case user_choice
          when abort_option
            UI.user_error!("Aborting…")
          else
            choice_index = options.find_index(user_choice)
          end
      end

      def self.download_url(shuttle_instance, app_environment, package_info)
        app = app_environment.shuttle_app
        env = app_environment.shuttle_environment
        url_path = File.join(
                      app.path, 
                      env.path,
                      package_info.release_version)
        url_path = File.join(url_path, package_info.build_version) if env.versioning_id == "version_and_build"
        return URI.join(
          shuttle_instance.base_url, url_path).to_s
      end

      def self.print_summary_table(shuttle_instance, app_environment, package_info, release)
        rows = [
          'Shuttle Base URL', 
          'Shuttle app name', 
          'Shuttle env name', 
          'Shuttle env ID', 
          'Package path', 
          'Platform', 
          'Package Id',
          'Release name',
          'Release version',
          'Build version',
          'Release notes',
          'Commit hash',
          'Shuttle release URL'
        ].zip([
            shuttle_instance.base_url, 
            app_environment.shuttle_app.name,
            app_environment.shuttle_environment.name, 
            app_environment.shuttle_environment.id, 
            package_info.path, 
            package_info.platform_id, 
            package_info.id,
            release.name,
            package_info.release_version,
            package_info.build_version,
            release.notes,
            release.commit_id,
            self.download_url(shuttle_instance, app_environment, package_info)
        ])
        table = Terminal::Table.new :rows => rows, :title => "Shuttle upload info summary".green
        puts
        puts table
        puts
      end
    end
  end
end
