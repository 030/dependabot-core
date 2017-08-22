# frozen_string_literal: true
require "bundler_definition_version_patch"
require "bundler_metadata_dependencies_patch"
require "bundler_git_source_patch"
require "excon"
require "gems"
require "gemnasium/parser"
require "dependabot/file_updaters/ruby/bundler"
require "dependabot/update_checkers/base"
require "dependabot/update_checkers/ruby/bundler/requirements_updater"
require "dependabot/shared_helpers"
require "dependabot/errors"

module Dependabot
  module UpdateCheckers
    module Ruby
      class Bundler < Dependabot::UpdateCheckers::Base
        class UnfixableRequirement < StandardError; end

        def latest_version
          @latest_version ||= fetch_latest_version
        end

        def latest_resolvable_version
          @latest_resolvable_version ||= fetch_latest_resolvable_version
        end

        def updated_requirements
          RequirementsUpdater.new(
            requirements: dependency.requirements,
            existing_version: dependency.version,
            latest_version: latest_version&.to_s,
            latest_resolvable_version: latest_resolvable_version&.to_s
          ).updated_requirements
        end

        private

        def fetch_latest_version
          case dependency_source
          when NilClass then latest_rubygems_version
          when ::Bundler::Source::Rubygems
            latest_private_version(dependency_source)
          end
        end

        def fetch_latest_resolvable_version
          return latest_version unless gemfile

          # We don't want to bump gems with a path/git source, so exit early
          return nil if dependency_source.is_a?(::Bundler::Source::Path)

          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
              ::Bundler.settings["github.com"] =
                "x-access-token:#{github_access_token}"

              definition = ::Bundler::Definition.build(
                "Gemfile",
                lockfile&.name,
                gems: [dependency.name]
              )

              definition.resolve_remotely!
              definition.resolve.find { |d| d.name == dependency.name }.version
            end
          end
        rescue SharedHelpers::ChildProcessFailed => error
          handle_bundler_errors(error)
        end

        def dependency_source
          return nil unless gemfile

          @dependency_source ||=
            SharedHelpers.in_a_temporary_directory do
              write_temporary_dependency_files

              SharedHelpers.in_a_forked_process do
                ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))

                ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
                  find { |dep| dep.name == dependency.name }&.source
              end
            end
        rescue SharedHelpers::ChildProcessFailed => error
          handle_bundler_errors(error)
        end

        def handle_bundler_errors(error)
          case error.error_class
          when "Bundler::Dsl::DSLError"
            # We couldn't evaluate the Gemfile, let alone resolve it
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotEvaluatable, msg
          when "Bundler::VersionConflict", "Bundler::GemNotFound",
               "Gem::InvalidSpecificationException"
            # We successfully evaluated the Gemfile, but couldn't resolve it
            # (e.g., because a gem couldn't be found in any of the specified
            # sources, or because it specified conflicting versions)
            msg = error.error_class + " with message: " + error.error_message
            raise Dependabot::DependencyFileNotResolvable, msg
          when "Bundler::Source::Git::GitCommandError"
            # Check if the error happened during branch / commit selection
            if error.error_message.match?(/git reset --hard/)
              raise DependencyFileNotResolvable
            end

            # Check if there are any repos we don't have access to, and raise an
            # error with details if so. Otherwise re-raise.
            raise unless inaccessible_git_dependencies.any?
            raise(
              Dependabot::GitDependenciesNotReachable,
              inaccessible_git_dependencies.map { |s| s.source.uri }
            )
          else raise
          end
        end

        def inaccessible_git_dependencies
          SharedHelpers.in_a_temporary_directory do
            write_temporary_dependency_files

            SharedHelpers.in_a_forked_process do
              ::Bundler.instance_variable_set(:@root, Pathname.new(Dir.pwd))
              ::Bundler.settings["github.com"] =
                "x-access-token:#{github_access_token}"

              ::Bundler::Definition.build("Gemfile", nil, {}).dependencies.
                select do |spec|
                  next false unless spec.source.is_a?(::Bundler::Source::Git)

                  # Piggy-back off some private Bundler methods to configure the
                  # URI with auth details in the same way Bundler does.
                  git_proxy = spec.source.send(:git_proxy)
                  uri = git_proxy.send(:configured_uri_for, spec.source.uri)
                  Excon.get(uri).status == 404
                end
            end
          end
        end

        def latest_rubygems_version
          # Note: Rubygems excludes pre-releases from the `Gems.info` response,
          # so no need to filter them out.
          latest_info = Gems.info(dependency.name)

          return nil if latest_info["version"].nil?
          Gem::Version.new(latest_info["version"])
        rescue JSON::ParserError
          nil
        end

        def latest_private_version(dependency_source)
          dependency_source.
            fetchers.flat_map do |fetcher|
              fetcher.
                specs_with_retry([dependency.name], dependency_source).
                search_all(dependency.name).
                map(&:version).
                reject(&:prerelease?)
            end.
            sort.last
        rescue ::Bundler::Fetcher::AuthenticationRequiredError => error
          regex = /bundle config (?<repo>.*) username:password/
          source = error.message.match(regex)[:repo]
          raise Dependabot::PrivateSourceNotReachable, source
        end

        def gemfile
          dependency_files.find { |f| f.name == "Gemfile" }
        end

        def lockfile
          dependency_files.find { |f| f.name == "Gemfile.lock" }
        end

        def gemspec
          dependency_files.find { |f| f.name.match?(%r{^[^/]*\.gemspec$}) }
        end

        def ruby_version_file
          dependency_files.find { |f| f.name == ".ruby-version" }
        end

        def path_gemspecs
          all = dependency_files.select { |f| f.name.end_with?(".gemspec") }
          all - [gemspec]
        end

        def write_temporary_dependency_files
          File.write("Gemfile", gemfile_for_update_check) if gemfile
          File.write("Gemfile.lock", lockfile.content) if lockfile

          write_updated_gemspec if gemspec
          write_ruby_version_file if ruby_version_file

          path_gemspecs.compact.each do |file|
            path = file.name
            FileUtils.mkdir_p(Pathname.new(path).dirname)
            File.write(path, sanitized_gemspec_content(file.content))
          end
        end

        def gemfile_for_update_check
          content = update_dependency_requirement(gemfile.content)
          content
        end

        def write_updated_gemspec
          path = gemspec.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, sanitized_gemspec_content(updated_gemspec_content))
        end

        def write_ruby_version_file
          path = ruby_version_file.name
          FileUtils.mkdir_p(Pathname.new(path).dirname)
          File.write(path, ruby_version_file.content)
        end

        def updated_gemspec_content
          return gemspec.content unless original_gemspec_declaration_string
          gemspec.content.gsub(
            original_gemspec_declaration_string,
            updated_gemspec_declaration_string
          )
        end

        def original_gemspec_declaration_string
          @original_gemspec_declaration_string ||=
            begin
              matches = []
              regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX
              gemspec.content.scan(regex) { matches << Regexp.last_match }

              matches.find { |match| match[:name] == dependency.name }&.to_s
            end
        end

        def updated_gemspec_declaration_string
          regex = FileUpdaters::Ruby::Bundler::DEPENDENCY_DECLARATION_REGEX
          original_requirement =
            regex.match(original_gemspec_declaration_string)[:requirements]

          original_gemspec_declaration_string.
            sub(original_requirement, '">= 0"')
        end

        def sanitized_gemspec_content(gemspec_content)
          # No need to set the version correctly - this is just an update
          # check so we're not going to persist any changes to the lockfile.
          gemspec_content.
            gsub(/^\s*require.*$/, "").
            gsub(/=.*VERSION.*$/, "= '0.0.1'")
        end

        # Replace the original gem requirements with a ">=" requirement to
        # unlock the gem during version checking
        def update_dependency_requirement(gemfile_content)
          gemfile_content.
            to_enum(:scan, Gemnasium::Parser::Patterns::GEM_CALL).
            find { Regexp.last_match[:name] == dependency.name }

          original_gem_declaration_string = Regexp.last_match.to_s
          updated_gem_declaration_string =
            original_gem_declaration_string.
            sub(Gemnasium::Parser::Patterns::REQUIREMENTS) do |old_req|
              matcher_regexp = /(=|!=|>=|<=|~>|>|<)[ \t]*/
              if old_req.match?(matcher_regexp)
                old_req.sub(matcher_regexp, ">= ")
              else
                old_req.sub(Gemnasium::Parser::Patterns::VERSION) do |old_v|
                  ">= #{old_v}"
                end
              end
            end

          gemfile_content.gsub(
            original_gem_declaration_string,
            updated_gem_declaration_string
          )
        end
      end
    end
  end
end
