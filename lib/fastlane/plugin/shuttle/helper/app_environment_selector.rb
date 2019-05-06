require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class AppEnvironmentSelector
      # class methods that you define here become available in your action
      # as `Helper::ShuttleHelper.your_method`
      #
      def self.get_app_environment(shuttle_instance, package_info, params) 
        helper = Helper::ShuttleHelper
        
        app_environment = self.get_app_env_from_params(shuttle_instance, package_info, params, helper)
        return app_environment unless app_environment.nil?

        all_environments = helper.get_environments(shuttle_instance)

        app_environment = nil
        environments = all_environments.select do |env|
          env.package_id == package_info.id
        end

        app_environments = helper.get_app_environments(shuttle_instance, environments).select do |app_env|
          app_env.shuttle_app.platform_id == package_info.platform_id
        end
        
        if app_environments.empty?
          app = self.get_app_interactive(shuttle_instance, package_info, helper)
          env = self.get_env_interactive(shuttle_instance, app, package_info, helper)
          app_environment = AppEnvironment.new(app, env)
        else
          if app_environments.count == 1 
            app_environment = app_environments[0]
          else
            app_environment = self.desambiguate_app_environment(app_environments, package_info, helper)
          end
        end

        return app_environment
      end

      def self.get_app_env_from_params(shuttle_instance, package_info, params, helper)
        env_id = params[:env_id]
        return nil if env_id.to_s.empty?
        environment = helper.get_environment(shuttle_instance, env_id)
        app = helper.get_app(shuttle_instance, environment.app_id)
          
        return AppEnvironment.new(app, environment) if environment.package_id == package_info.id && app.platform_id == package_info.platform_id
          
        UI.important("App #{app.name} doesn't match the given build platform #{package_info.platform_id}, please check that #{env_id} is the correct environment ID.") unless app.platform_id == package_info.platform_id
        UI.important("Environment #{environment.name} with ID #{env_id} doesn't match the build's package ID #{package_info.id}, please check that you set the correct environment ID") unless environment.package_id == package_info.id
        return nil
      end

      def self.desambiguate_app_environment(app_environments, package_info, helper)
        options = app_environments.map do |app_env|
          "#{app_env.shuttle_app.name} (#{app_env.shuttle_environment.name})"
        end
        choice_index = helper.prompt_choices(
            "Can't guess which app and environment to use, please choose the correct one:",
            options, 
            "Too many environments with package id #{package_info.id} for #{package_info.platform_id}"
        )
        app_environment = app_environments[choice_index]
      end

      def self.get_app_interactive(shuttle_instance, package_info, helper)
        apps = helper.get_apps(shuttle_instance).select do |app|
          app.platform_id == package_info.platform_id
        end
        options = apps.map do |app|
          "#{app.name}"
        end
        create_new_option = "Create a new one…"
        choice_index = helper.prompt_choices(
            "Can't guess which app to use, please choose the correct one:",
            options << create_new_option, 
            "No environments configured for package id #{package_info.id}"
        )
        return self.create_app_interactive(shuttle_instance, package_info, helper) if options[choice_index] == create_new_option
        return apps[choice_index]
      end

      def self.create_app_interactive(shuttle_instance, package_info, helper)
        app_name = UI.input("app name (default: #{package_info.name}): ")
        app_name = package_info.name if app_name.to_s.empty?
        helper.create_app(shuttle_instance, app_name, package_info.platform_id)
      end

      def self.get_env_interactive(shuttle_instance, app, package_info, helper)
        environments = helper.get_environments_for_app(shuttle_instance, app).select do |env|
          env.package_id == package_info.id
        end
        options = environments.map do |env|
          "#{env.name}"
        end
        create_new_option = "Create a new one…"
        choice_index = helper.prompt_choices(
            "Can't guess which #{app.name}'s environment to use, please choose the correct one:",
            options << create_new_option, 
            "No environments configured for package id #{package_info.id}"
        )
        return self.create_environment_interactive(shuttle_instance, app, package_info, helper) if options[choice_index] == create_new_option
        return environments[choice_index]
      end

      def self.create_environment_interactive(shuttle_instance, app, package_info, helper)
        env_name = UI.input("environment name: ")
        versioning_id_choices = ["version_only", "version_and_build"]
        choice_index = helper.prompt_choices("environment version scheme:", versioning_id_choices, "interactive mode needed")
        app_name = package_info.name if app_name.to_s.empty?
        helper.create_environment(shuttle_instance, env_name, versioning_id_choices[choice_index], app.id, package_info.id)
      end

    end
  end
end
