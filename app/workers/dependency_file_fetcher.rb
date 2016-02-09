require "shoryuken"
require "./app/boot"
require "./app/dependency_file_fetchers/ruby"
require "./app/dependency_file_fetchers/node"

$stdout.sync = true

module Workers
  class DependencyFileFetcher
    include Shoryuken::Worker

    shoryuken_options(
      queue: "bump-repos_to_fetch_files_for",
      body_parser: :json,
      auto_delete: true,
      retry_intervals: [60, 300, 3_600, 36_000] # specified in seconds
    )

    def perform(_sqs_message, body)
      file_fetcher = file_fetcher_for(body["repo"]["language"])

      dependency_files =
        file_fetcher.new(body["repo"]["name"]).files.map do |file|
          { "name" => file.name, "content" => file.content }
        end

      Workers::DependencyFileParser.perform_async(
        "repo" => body["repo"],
        "dependency_files" => dependency_files
      )
    rescue => error
      Raven.capture_exception(error, extra: { body: body })
      raise
    end

    private

    def file_fetcher_for(language)
      case language
      when "ruby" then DependencyFileFetchers::Ruby
      when "node" then DependencyFileFetchers::Node
      else raise "Invalid language #{language}"
      end
    end
  end
end
