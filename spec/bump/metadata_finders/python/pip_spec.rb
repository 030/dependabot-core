# frozen_string_literal: true
require "octokit"
require "spec_helper"
require "bump/dependency"
require "bump/metadata_finders/python/pip"
require_relative "../shared_examples_for_metadata_finders"

RSpec.describe Bump::MetadataFinders::Python::Pip do
  it_behaves_like "a dependency metadata finder"

  let(:dependency) do
    Bump::Dependency.new(
      name: dependency_name,
      version: "1.0",
      package_manager: "pip"
    )
  end
  subject(:finder) do
    described_class.new(dependency: dependency, github_client: github_client)
  end
  let(:github_client) { Octokit::Client.new(access_token: "token") }
  let(:dependency_name) { "luigi" }

  describe "#github_repo" do
    subject(:github_repo) { finder.github_repo }
    let(:pypi_url) { "https://pypi.python.org/pypi/luigi/json" }

    before do
      stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
    end

    context "when there is a github link in the pypi response" do
      let(:pypi_response) { fixture("python", "pypi_response.json") }

      it { is_expected.to eq("spotify/luigi") }

      it "caches the call to pypi" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when there is not a github link in the pypi response" do
      let(:pypi_response) { fixture("python", "pypi_response_no_github.json") }

      it { is_expected.to be_nil }

      it "caches the call to pypi" do
        2.times { github_repo }
        expect(WebMock).to have_requested(:get, pypi_url).once
      end
    end

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) { "https://pypi.python.org/pypi/LuiGi/json" }
      let(:pypi_response) { fixture("python", "pypi_response.json") }

      before do
        stub_request(:get, pypi_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq("spotify/luigi") }
    end
  end
end
