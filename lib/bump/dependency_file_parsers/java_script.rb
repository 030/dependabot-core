# frozen_string_literal: true
require "json"
require "bump/dependency"

module Bump
  module DependencyFileParsers
    class JavaScript
      def initialize(dependency_files:)
        @package_json = dependency_files.find { |f| f.name == "package.json" }
        raise "No package.json!" unless @package_json
      end

      def parse
        parsed_content = parser

        dependencies_hash = parsed_content["dependencies"] || {}
        dependencies_hash.merge!(parsed_content["devDependencies"] || {})

        # TODO: Taking the version from the package.json file here is naive -
        #       the version info found there is more likely in node-semver
        #       format than the exact current version. In future we should
        #       parse the yarn.lock file.

        dependencies_hash.map do |name, version|
          Dependency.new(
            name: name,
            version: version.match(/[\d\.]+/).to_s,
            language: "javascript"
          )
        end
      end

      private

      def parser
        JSON.parse(@package_json.content)
      end
    end
  end
end
