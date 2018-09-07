require 'fastlane_core/ui/ui'

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
        package_path = lane_context[SharedValues::IPA_OUTPUT_PATH] if package_path.to_s.empty?
        package_path = lane_context[SharedValues::GRADLE_APK_OUTPUT_PATH] if package_path.to_s.empty?
        UI.abort_with_message!("No Package file found") if package_path.to_s.empty?
        UI.abort_with_message!("Package at path #{package_path} does not exist") unless File.exist?(package_path)
        app_info = ::AppInfo.parse(package_path)
        PackageInfo.new(app_info.identifier, package_path, app_info.os.downcase, app_info.release_version, app_info.build_version)
      end

      def self.get_release_name(params, app_environment, package_info)
        return params[:release_name] unless params[:release_name].to_s.empty?
        release_name = "#{app_environment.shuttle_app.name} v#{package_info.release_version}"
        if app_environment.shuttle_environment.versioning_id == "version_and_build"
          return "#{release_name}-#{package_info.build_version}"
        end 
        return release_name
      end

      def self.get_release_info(params, app_environment, package_info) 
        release_name = self.get_release_name(params, app_environment, package_info)
        commit_id = Helper.backticks("git show --format='%H' --quiet").chomp
        ReleaseInfo.new(release_name, params[:release_notes], nil, app_environment.shuttle_environment, commit_id)
      end

      def self.connection(shuttle_instance, endpoint, is_multipart = false)
        return Faraday.new(url: "#{shuttle_instance.base_url}/api#{endpoint}") do |builder|
          # builder.response :logger, Logger.new(STDOUT), bodies: true
          builder.headers["Authorization"] = "Bearer #{shuttle_instance.access_token}"
          builder.headers["Accept"] = "application/vnd.api+json"
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

      def self.get_environments(shuttle_instance)
        self.get(shuttle_instance, '/environments').map do |env|
          attrb = env["attributes"]
          ShuttleEnvironment.new(
            env["id"],
            attrb["name"],
            attrb["package_id"],
            env["relationships"]["app"]["data"]["id"],
            attrb["versioning_id"]
          )
        end
      end

      def self.app_from_json(json_app)
        json_app_attrb = json_app["attributes"]
        ShuttleApp.new(
          json_app["id"],
          json_app_attrb["name"],
          json_app_attrb["platform_id"]
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
        json_app = self.post(shuttle_instance: shuttle_instance, endpoint: "/apps", body: body)
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
          UI.abort_with_message!("Error #{response.status.to_s} occured while calling endpoint #{endpoint} with body #{body}")
          nil
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

      def self.promptChoices(question, options, nonInteractiveErrorMessage) 
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

      def self.print_summary_table(shuttle_instance, app_environment, package_info, release)
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
            shuttle_instance.base_url, 
            app_environment.shuttle_app.name,
            app_environment.shuttle_environment.name, 
            package_info.path, 
            package_info.platform_id, 
            package_info.id,
            release.name,
            package_info.release_version,
            package_info.build_version,
            release.notes,
            release.commit_id
        ])
        table = Terminal::Table.new :rows => rows, :title => "Shuttle upload info summary".green
        puts
        puts table
        puts
      end
    end
  end
end
