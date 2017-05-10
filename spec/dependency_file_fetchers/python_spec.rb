# frozen_string_literal: true
require "bump/dependency_file_fetchers/python"
require_relative "./shared_examples_for_file_fetchers"

RSpec.describe Bump::DependencyFileFetchers::Python do
  it_behaves_like "a dependency file fetcher"
end
