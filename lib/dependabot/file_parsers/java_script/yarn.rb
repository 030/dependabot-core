# frozen_string_literal: true
require "dependabot/dependency"
require "dependabot/file_parsers/base"
require "dependabot/file_fetchers/java_script/yarn"
require "dependabot/shared_helpers"

module Dependabot
  module FileParsers
    module JavaScript
      class Yarn < Dependabot::FileParsers::Base
        def parse
          dependency_versions.map do |dep|
            Dependency.new(
              name: dep["name"],
              version: dep["version"],
              package_manager: "yarn"
            )
          end
        end

        private

        def dependency_versions
          SharedHelpers.in_a_temporary_directory do
            File.write("package.json", package_json.content)
            File.write("yarn.lock", yarn_lock.content)

            SharedHelpers.run_helper_subprocess(
              command: "node #{js_helper_path}",
              function: "parse",
              args: [Dir.pwd]
            )
          end
        end

        def js_helper_path
          project_root = File.join(File.dirname(__FILE__), "../../../..")
          File.join(project_root, "helpers/javascript/bin/run.js")
        end

        def required_files
          Dependabot::FileFetchers::JavaScript::Yarn.required_files
        end

        def package_json
          @package_json ||= get_original_file("package.json")
        end

        def yarn_lock
          @yarn_lock ||= get_original_file("yarn.lock")
        end
      end
    end
  end
end
