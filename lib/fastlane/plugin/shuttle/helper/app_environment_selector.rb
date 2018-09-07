require 'fastlane_core/ui/ui'

module Fastlane
  UI = FastlaneCore::UI unless Fastlane.const_defined?("UI")

  module Helper
    class AppEnvironmentSelector
      # class methods that you define here become available in your action
      # as `Helper::ShuttleHelper.your_method`
      #
      def self.get_app_environment(shuttle_instance, package_info) 
        helper = Helper::ShuttleHelper
        
        environments = helper.get_environments(shuttle_instance)

        app_environment = nil
        environments.select do |env|
          env.package_id == package_info.id
        end
        
        if environments.empty?
          options = helper.get_apps(shuttle_instance).map do |app|
            "#{app.name}"
          end
          create_new_option = "Create a new one…"
          choice_index = helper.promptChoices(
              "Can't guess which app and environment to use, please choose the correct one:",
              options << create_new_option, 
              "No environments configured for package id #{package_info.id}"
          )
          if choice_index < options.length
            # we have our app
          else
            # we need to create one
          end
        end

        app_environments = helper.get_app_environments(shuttle_instance, environments).select do |app_env|
          app_env.shuttle_app.platform_id == package_info.platform_id
        end

        UI.abort_with_message!("No apps configured for #{package_info.platform_id} with package id #{package_info.id}") if app_environments.empty?

        if app_environments.count == 1 
          app_environment = app_environments[0]
        else
          app_environment = self.desambiguateAppEnvironment(app_environments, package_info)
        end

        return app_environment
      end

      def desambiguateAppEnvironment(app_environments, package_info)
        options = app_environments.map do |app_env|
          "#{app_env.shuttle_app.name} (#{app_env.shuttle_environment.name})"
        end
        choice_index = helper.promptChoices(
            "Can't guess which app and environment to use, please choose the correct one:",
            options, 
            "Too many environments with package id #{package_info.id} for #{package_info.platform_id}"
        )
        app_environment = app_environments[choice_index]
      end

    end
  end
end
