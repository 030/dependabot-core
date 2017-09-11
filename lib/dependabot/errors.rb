# frozen_string_literal: true

module Dependabot
  class DependabotError < StandardError; end

  #####################
  # File level errors #
  #####################

  class DependencyFileNotFound < DependabotError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotParseable < DependabotError
    attr_reader :file_path

    def initialize(file_path, msg = nil)
      @file_path = file_path
      super(msg)
    end

    def file_name
      file_path.split("/").last
    end

    def directory
      # Directory should always start with a `/`
      file_path.split("/")[0..-2].join("/").sub(%r{^/*}, "/")
    end
  end

  class DependencyFileNotEvaluatable < DependabotError; end
  class DependencyFileNotResolvable < DependabotError; end

  ###########################
  # Dependency level errors #
  ###########################

  class GitDependenciesNotReachable < DependabotError
    attr_reader :dependency_urls

    def initialize(*dependency_urls)
      @dependency_urls =
        dependency_urls.flatten.map { |uri| uri.gsub(/x-access-token.*?@/, "") }

      msg = "The following git URLs could not be retrieved: "\
            "#{dependency_urls.join(', ')}"
      super(msg)
    end
  end

  class GitDependencyBranchNotFound < DependabotError
    attr_reader :dependency, :branch

    def initialize(dependency:, branch:)
      @dependency = dependency
      @branch = branch

      msg = "The branch '#{branch}' could not be retrieved for #{dependency}"
      super(msg)
    end
  end

  class PathDependenciesNotReachable < DependabotError
    attr_reader :dependencies

    def initialize(*dependencies)
      @dependencies = dependencies.flatten
      msg = "The following path based dependencies could not be retrieved: "\
            "#{dependencies.join(', ')}"
      super(msg)
    end
  end

  class PrivateSourceNotReachable < DependabotError
    attr_reader :source

    def initialize(source)
      @source = source
      msg = "The following source could not be reached as it requires "\
            "authentication (and any provided details were invalid): #{source}"
      super(msg)
    end
  end
end
