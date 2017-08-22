# frozen_string_literal: true
require "spec_helper"
require "bundler/compact_index_client"
require "bundler/compact_index_client/updater"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/ruby/bundler"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler do
  it_behaves_like "an update checker"

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      github_access_token: github_token
    )
  end
  let(:dependency_files) { [gemfile, lockfile] }
  let(:github_token) { "token" }

  let(:dependency) do
    Dependabot::Dependency.new(
      name: "business",
      version: "1.3",
      requirement: ">= 0",
      package_manager: "bundler",
      groups: []
    )
  end

  let(:gemfile) do
    Dependabot::DependencyFile.new(content: gemfile_body, name: "Gemfile")
  end
  let(:lockfile) do
    Dependabot::DependencyFile.new(content: lockfile_body, name: "Gemfile.lock")
  end
  let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
  let(:lockfile_body) { fixture("ruby", "lockfiles", "Gemfile.lock") }

  before do
    allow_any_instance_of(Bundler::CompactIndexClient::Updater).
      to receive(:etag_for).
      and_return("")
  end

  describe "#latest_version" do
    subject { checker.latest_version }

    before do
      stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
        to_return(status: 200, body: fixture("ruby", "rubygems_response.json"))
    end

    it { is_expected.to eq(Gem::Version.new("1.5.0")) }

    it "only hits Rubygems once" do
      checker.latest_version

      expect(WebMock).
        to have_requested(
          :get,
          "https://rubygems.org/api/v1/gems/business.json"
        ).once
    end

    context "given a Gemfile with a non-rubygems source" do
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "specified_source.lock")
      end
      let(:gemfile_body) { fixture("ruby", "gemfiles", "specified_source") }
      let(:registry_url) { "https://repo.fury.io/greysteil/" }
      let(:gemfury_business_url) do
        "https://repo.fury.io/greysteil/api/v1/dependencies?gems=business"
      end
      before do
        stub_request(:get, registry_url + "versions").to_return(status: 404)
        stub_request(:get, registry_url + "api/v1/dependencies").
          to_return(status: 200)
        # Note: returns details of three versions: 1.5.0, 1.9.0, and 1.10.0.beta
        stub_request(:get, gemfury_business_url).
          to_return(status: 200, body: fixture("ruby", "gemfury_response"))
      end

      it { is_expected.to eq(Gem::Version.new("1.9.0")) }

      context "that we don't have authentication details for" do
        before do
          stub_request(:get, registry_url + "versions").to_return(status: 401)
          stub_request(:get, registry_url + "api/v1/dependencies").
            to_return(status: 401)
          stub_request(:get, registry_url + "specs.4.8.gz").
            to_return(status: 401)
        end

        it "blows up with a useful error" do
          expect { checker.latest_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::PrivateSourceNotReachable)
              expect(error.source).to eq("repo.fury.io")
            end
        end
      end

      context "that only implements the old Bundler index format..." do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "sidekiq_pro") }
        let(:lockfile_body) { fixture("ruby", "lockfiles", "sidekiq_pro.lock") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "sidekiq-pro",
            version: "1.3",
            requirement: ">= 0",
            package_manager: "bundler",
            groups: []
          )
        end
        let(:registry_url) { "https://gems.contribsys.com/" }
        before do
          stub_request(:get, registry_url + "versions").to_return(status: 404)
          stub_request(:get, registry_url + "api/v1/dependencies").
            to_return(status: 404)
          stub_request(:get, registry_url + "specs.4.8.gz").
            to_return(
              status: 200,
              body: fixture("ruby", "contribsys_old_index_response")
            )
          stub_request(:get, registry_url + "prerelease_specs.4.8.gz").
            to_return(
              status: 200,
              body: fixture("ruby", "contribsys_old_index_prerelease_response")
            )
        end

        it { is_expected.to eq(Gem::Version.new("3.5.2")) }
      end
    end

    context "given an unreadable Gemfile" do
      let(:gemfile) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemfiles", "includes_requires"),
          name: "Gemfile"
        )
      end

      it "blows up with a useful error" do
        expect { checker.latest_version }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "given a git source" do
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "git_source.lock")
      end
      let(:gemfile_body) { fixture("ruby", "gemfiles", "git_source") }

      context "that is the gem we're checking for" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "prius",
            version: "0.9",
            requirement: ">= 0",
            package_manager: "bundler",
            groups: []
          )
        end

        it { is_expected.to be_nil }
      end

      context "that is not the gem we're checking" do
        it { is_expected.to eq(Gem::Version.new("1.5.0")) }

        context "that is private" do
          let(:gemfile_body) do
            fixture("ruby", "gemfiles", "private_git_source")
          end
          let(:lockfile_body) do
            fixture("ruby", "lockfiles", "private_git_source.lock")
          end

          it { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end
      end
    end

    context "given a path source" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source") }
      let(:lockfile_body) { fixture("ruby", "lockfiles", "path_source.lock") }

      context "with a downloaded gemspec" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
        let(:gemspec) do
          Dependabot::DependencyFile.new(
            content: gemspec_body,
            name: "plugins/example/example.gemspec"
          )
        end
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: [gemfile, lockfile, gemspec],
            github_access_token: github_token
          )
        end

        context "that is not the gem we're checking" do
          it { is_expected.to eq(Gem::Version.new("1.5.0")) }
        end

        context "that is the gem we're checking" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "example",
              version: "0.9.3",
              requirement: ">= 0",
              package_manager: "bundler",
              groups: []
            )
          end

          it { is_expected.to be_nil }
        end
      end
    end

    context "given a Gemfile that specifies a Ruby version" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "explicit_ruby") }
      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end

    context "given a Gemfile that loads a .ruby-version file" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "ruby_version_file") }
      let(:ruby_version_file) do
        Dependabot::DependencyFile.new(content: "2.2.0", name: ".ruby-version")
      end
      let(:checker) do
        described_class.new(
          dependency: dependency,
          dependency_files: [gemfile, lockfile, ruby_version_file],
          github_access_token: github_token
        )
      end

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end

    context "when the gem isn't on Rubygems" do
      before do
        stub_request(:get, "https://rubygems.org/api/v1/gems/business.json").
          to_return(status: 404, body: "This rubygem could not be found.")
      end

      it { is_expected.to be_nil }
    end

    context "with a gemspec and a Gemfile" do
      let(:dependency_files) { [gemfile, gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "imports_gemspec") }

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }

      context "with a dependency that only appears in the gemspec" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "octokit",
            requirement: "~> 4.6",
            package_manager: "bundler",
            groups: []
          )
        end

        before do
          stub_request(:get, "https://rubygems.org/api/v1/gems/octokit.json").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems_response.json")
            )
        end

        it { is_expected.to eq(Gem::Version.new("1.5.0")) }
      end
    end

    context "with only a gemspec" do
      let(:dependency_files) { [gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end

    context "with only a Gemfile" do
      let(:dependency_files) { [gemfile] }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

      it { is_expected.to eq(Gem::Version.new("1.5.0")) }
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }

    before do
      stub_request(:get, "https://index.rubygems.org/versions").
        to_return(status: 200, body: fixture("ruby", "rubygems-index"))

      stub_request(:get, "https://index.rubygems.org/info/business").
        to_return(
          status: 200,
          body: fixture("ruby", "rubygems-info-business")
        )

      stub_request(:get, "https://index.rubygems.org/info/statesman").
        to_return(
          status: 200,
          body: fixture("ruby", "rubygems-info-statesman")
        )
    end

    context "given a gem from rubygems" do
      it { is_expected.to eq(Gem::Version.new("1.8.0")) }

      context "with a version conflict at the latest version" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "version_conflict") }
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "version_conflict.lock")
        end
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "ibandit",
            version: "0.1.0",
            requirement: ">= 0",
            package_manager: "bundler",
            groups: []
          )
        end

        before do
          stub_request(:get, "https://index.rubygems.org/info/i18n").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-info-i18n")
            )

          stub_request(:get, "https://index.rubygems.org/info/ibandit").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-info-ibandit")
            )
        end

        # The latest version of ibandit is 0.8.5, but 0.3.4 is the latest
        # version compatible with the version of i18n in the Gemfile.
        it { is_expected.to eq(Gem::Version.new("0.3.4")) }
      end

      context "with a legacy Ruby which disallows the latest version" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "legacy_ruby") }
        let(:lockfile_body) { fixture("ruby", "lockfiles", "legacy_ruby.lock") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "public_suffix",
            version: "1.0.1",
            requirement: ">= 0",
            package_manager: "bundler",
            groups: []
          )
        end

        before do
          stub_request(:get, "https://index.rubygems.org/info/public_suffix").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-info-public_suffix")
            )
        end

        # The latest version of public_suffic is 2.0.5, but requires Ruby 2.0
        # or greater.
        it { is_expected.to eq(Gem::Version.new("1.4.6")) }
      end

      context "with no version specified" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "version_not_specified")
        end
        let(:lockfile_body) do
          fixture("ruby", "lockfiles", "version_not_specified.lock")
        end

        it { is_expected.to eq(Gem::Version.new("1.8.0")) }
      end

      context "with a greater than or equal to matcher" do
        let(:gemfile_body) { fixture("ruby", "gemfiles", "gte_matcher") }
        let(:lockfile_body) { fixture("ruby", "lockfiles", "gte_matcher.lock") }

        it { is_expected.to eq(Gem::Version.new("1.8.0")) }
      end
    end

    context "given a gem from a private gem source" do
      let(:lockfile_body) do
        fixture("ruby", "lockfiles", "specified_source.lock")
      end
      let(:gemfile_body) { fixture("ruby", "gemfiles", "specified_source") }
      let(:gemfury_url) { "https://repo.fury.io/greysteil/" }
      before do
        stub_request(:get, gemfury_url + "versions").
          to_return(status: 200, body: fixture("ruby", "gemfury-index"))

        stub_request(:get, gemfury_url + "info/business").
          to_return(status: 404)

        stub_request(:get, gemfury_url + "api/v1/dependencies").
          to_return(status: 200)

        stub_request(
          :get,
          gemfury_url + "api/v1/dependencies?gems=business,statesman"
        ).to_return(status: 200, body: fixture("ruby", "gemfury_response"))
      end

      it { is_expected.to eq(Gem::Version.new("1.9.0")) }
    end

    context "given a gem with a path source" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "path_source") }
      let(:lockfile_body) { fixture("ruby", "lockfiles", "path_source.lock") }

      context "with a downloaded gemspec" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
        let(:gemspec) do
          Dependabot::DependencyFile.new(
            content: gemspec_body,
            name: "plugins/example/example.gemspec"
          )
        end
        let(:checker) do
          described_class.new(
            dependency: dependency,
            dependency_files: [gemfile, lockfile, gemspec],
            github_access_token: github_token
          )
        end

        before do
          stub_request(:get, "https://index.rubygems.org/info/i18n").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-info-i18n")
            )
          stub_request(:get, "https://index.rubygems.org/info/public_suffix").
            to_return(
              status: 200,
              body: fixture("ruby", "rubygems-info-public_suffix")
            )
        end

        it { is_expected.to eq(Gem::Version.new("1.8.0")) }

        it "doesn't persist any temporary changes to Bundler's root" do
          expect { checker.latest_resolvable_version }.
            to_not(change { ::Bundler.root })
        end

        context "that requires other files" do
          let(:gemspec_body) { fixture("ruby", "gemspecs", "with_require") }

          it { is_expected.to eq(Gem::Version.new("1.8.0")) }
        end

        context "that is the gem we're checking" do
          let(:dependency) do
            Dependabot::Dependency.new(
              name: "example",
              version: "0.9.3",
              requirement: ">= 0",
              package_manager: "bundler",
              groups: []
            )
          end

          it { is_expected.to be_nil }
        end
      end
    end

    context "when a gem has been yanked" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      let(:lockfile_body) { fixture("ruby", "lockfiles", "yanked_gem.lock") }

      context "and it's that gem that we're attempting to bump" do
        it "finds an updated version just fine" do
          expect(checker.latest_resolvable_version).
            to eq(Gem::Version.new("1.8.0"))
        end
      end

      context "and it's another gem that we're attempting to bump" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "statesman",
            version: "1.2",
            requirement: ">= 0",
            package_manager: "ruby",
            groups: []
          )
        end

        it "raises a Dependabot::SharedHelpers::ChildProcessFailed error" do
          expect { checker.latest_resolvable_version }.
            to raise_error(Dependabot::DependencyFileNotResolvable)
        end
      end
    end

    context "when the Gem can't be found" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "unavailable_gem") }

      it "raises a Dependabot::SharedHelpers::ChildProcessFailed error" do
        expect { checker.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotResolvable)
      end
    end

    context "given a gem with a git source" do
      let(:lockfile_body) { fixture("ruby", "lockfiles", "git_source.lock") }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "git_source") }

      context "that is the gem we're checking" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "prius",
            version: "0.9",
            requirement: ">= 0",
            package_manager: "bundler",
            groups: []
          )
        end

        it { is_expected.to be_nil }
      end

      context "that is not the gem we're checking" do
        it { is_expected.to eq(Gem::Version.new("1.8.0")) }

        context "that is private" do
          let(:gemfile_body) do
            fixture("ruby", "gemfiles", "private_git_source")
          end
          let(:lockfile_body) do
            fixture("ruby", "lockfiles", "private_git_source.lock")
          end
          let(:token) do
            Base64.encode64("x-access-token:#{github_token}").strip
          end
          around { |example| capture_stderr { example.run } }

          before do
            stub_request(:get, "https://github.com/fundingcircle/prius").
              with(headers: { "Authorization" => "Basic #{token}" }).
              to_return(status: 404)
          end

          it "raises a helpful error" do
            expect { checker.latest_resolvable_version }.
              to raise_error do |error|
                expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
                expect(error.dependency_urls).
                  to eq(["git@github.com:fundingcircle/prius"])
              end
          end
        end

        context "that has a bad branch" do
          let(:gemfile_body) { fixture("ruby", "gemfiles", "bad_branch") }
          let(:lockfile_body) do
            fixture("ruby", "lockfiles", "bad_branch.lock")
          end
          around { |example| capture_stderr { example.run } }

          before do
            stub_request(:get, "https://github.com/gocardless/prius").
              to_return(status: 200)
          end

          it "raises a helpful error" do
            expect { checker.latest_resolvable_version }.
              to raise_error(Dependabot::DependencyFileNotResolvable)
          end
        end
      end
    end

    context "given an unreadable Gemfile" do
      let(:gemfile) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemfiles", "includes_requires"),
          name: "Gemfile"
        )
      end

      it "blows up with a useful error" do
        expect { checker.latest_resolvable_version }.
          to raise_error(Dependabot::DependencyFileNotEvaluatable)
      end
    end

    context "given a Gemfile that specifies a Ruby version" do
      let(:gemfile_body) { fixture("ruby", "gemfiles", "explicit_ruby") }
      it { is_expected.to eq(Gem::Version.new("1.8.0")) }
    end

    context "with a gemspec and a Gemfile" do
      let(:dependency_files) { [gemfile, gemspec] }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "imports_gemspec") }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: fixture("ruby", "gemspecs", "small_example"),
          name: "example.gemspec"
        )
      end

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(Gem::Version.new("0.5.0"))
      end

      it "doesn't just fall back to latest_version" do
        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("1.8.0"))
      end
    end

    context "with only a gemspec" do
      let(:dependency_files) { [gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }

      it "falls back to latest_version" do
        dummy_version = Gem::Version.new("0.5.0")
        expect(checker).to receive(:latest_version).and_return(dummy_version)
        expect(checker.latest_resolvable_version).to eq(dummy_version)
      end
    end

    context "with only a Gemfile" do
      let(:dependency_files) { [gemfile] }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

      before do
        allow(checker).
          to receive(:latest_version).
          and_return(Gem::Version.new("0.5.0"))
      end

      it "doesn't just fall back to latest_version" do
        expect(checker.latest_resolvable_version).
          to eq(Gem::Version.new("1.8.0"))
      end

      context "given a gem with a private git source" do
        let(:gemfile_body) do
          fixture("ruby", "gemfiles", "private_git_source")
        end
        let(:token) do
          Base64.encode64("x-access-token:#{github_token}").strip
        end
        around { |example| capture_stderr { example.run } }

        before do
          stub_request(:get, "https://github.com/fundingcircle/prius").
            with(headers: { "Authorization" => "Basic #{token}" }).
            to_return(status: 404)
        end

        it "raises a helpful error" do
          expect { checker.latest_resolvable_version }.
            to raise_error do |error|
              expect(error).to be_a(Dependabot::GitDependenciesNotReachable)
              expect(error.dependency_urls).
                to eq(["git@github.com:fundingcircle/prius"])
            end
        end
      end
    end
  end

  describe "#updated_requirement" do
    subject { checker.updated_requirement }

    let(:dependency) do
      Dependabot::Dependency.new(
        name: "business",
        version: "1.3",
        requirement: original_requirement,
        package_manager: "bundler",
        groups: []
      )
    end

    let(:original_requirement) { ">= 0" }
    let(:latest_resolvable_version) { nil }

    before do
      allow(checker).
        to receive(:latest_resolvable_version).
        and_return(latest_resolvable_version)
    end

    context "when there is no resolvable version" do
      let(:latest_resolvable_version) { nil }
      it { is_expected.to be_nil }
    end

    context "when there is a resolvable version" do
      let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

      context "and a full version was previously specified" do
        let(:original_requirement) { "~> 1.4.0" }
        it { is_expected.to eq("~> 1.5.0") }
      end

      context "and a pre-release was previously specified" do
        let(:original_requirement) { "~> 1.5.0.beta" }
        it { is_expected.to eq("~> 1.5.0") }
      end

      context "and a minor version was previously specified" do
        let(:original_requirement) { "~> 1.4" }
        it { is_expected.to eq("~> 1.5") }
      end

      context "and a greater than or equal to matcher was used" do
        let(:original_requirement) { ">= 1.4.0" }
        it { is_expected.to eq(">= 1.5.0") }
      end

      context "and a less than matcher was used" do
        let(:original_requirement) { "< 1.4.0" }
        it { is_expected.to eq("~> 1.5.0") }
      end
    end

    context "with a gemspec and a gemfile" do
      let(:dependency_files) { [gemspec, gemfile] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }
      let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirement: old_requirement,
          package_manager: "bundler",
          groups: []
        )
      end

      let(:old_requirement) { "~> 0.9" }
      let(:latest_version) { Gem::Version.new("1.5.0") }

      before do
        allow(checker).to receive(:latest_version).and_return(latest_version)
      end

      it "picks the gemspec to update the requirement in" do
        expect(checker.updated_requirement).to eq(">= 0.9, < 2.0")
      end

      context "with a dependency that only appears in the gemspec" do
        let(:gemspec_body) { fixture("ruby", "gemspecs", "example") }
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "octokit",
            requirement: "~> 4.6",
            package_manager: "bundler",
            groups: []
          )
        end
        let(:latest_version) { Gem::Version.new("5.0.0") }

        it "successfully updates the requirement" do
          expect(checker.updated_requirement).to eq(">= 4.6, < 6.0")
        end
      end
    end

    context "with only a Gemfile" do
      let(:dependency_files) { [gemfile] }
      let(:gemfile_body) { fixture("ruby", "gemfiles", "Gemfile") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirement: original_requirement,
          package_manager: "bundler",
          groups: []
        )
      end

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to be_nil }
      end

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { Gem::Version.new("1.5.0") }

        context "and a full version was previously specified" do
          let(:original_requirement) { "~> 1.4.0" }
          it { is_expected.to eq("~> 1.5.0") }
        end
      end
    end

    context "with only a gemspec" do
      let(:dependency_files) { [gemspec] }
      let(:gemspec) do
        Dependabot::DependencyFile.new(
          content: gemspec_body,
          name: "example.gemspec"
        )
      end
      let(:gemspec_body) { fixture("ruby", "gemspecs", "small_example") }

      let(:dependency) do
        Dependabot::Dependency.new(
          name: "business",
          requirement: old_requirement,
          package_manager: "bundler",
          groups: []
        )
      end
      let(:old_requirement) { ">= 1.0.0" }
      let(:latest_version) { Gem::Version.new("1.5.0") }

      before do
        allow(checker).to receive(:latest_version).and_return(latest_version)
      end

      context "when an = specifier was used" do
        let(:old_requirement) { "= 1.4.0" }
        it { is_expected.to eq(">= 1.4.0") }
      end

      context "when no specifier was used" do
        let(:old_requirement) { "1.4.0" }
        it { is_expected.to eq(">= 1.4.0") }
      end

      context "when a < specifier was used" do
        let(:old_requirement) { "< 1.4.0" }
        it { is_expected.to eq("< 1.6.0") }
      end

      context "when a <= specifier was used" do
        let(:old_requirement) { "<= 1.4.0" }
        it { is_expected.to eq("<= 1.6.0") }
      end

      context "when a ~> specifier was used" do
        let(:old_requirement) { "~> 1.4.0" }
        it { is_expected.to eq(">= 1.4, < 1.6") }

        context "with two zeros" do
          let(:old_requirement) { "~> 1.0.0" }
          it { is_expected.to eq(">= 1.0, < 1.6") }
        end

        context "with no zeros" do
          let(:old_requirement) { "~> 1.0.1" }
          it { is_expected.to eq(">= 1.0.1, < 1.6.0") }
        end

        context "with minor precision" do
          let(:old_requirement) { "~> 0.1" }
          it { is_expected.to eq(">= 0.1, < 2.0") }
        end
      end

      context "when there are multiple requirements" do
        let(:old_requirement) { "> 1.0.0, <= 1.4.0" }
        it { is_expected.to eq("> 1.0.0, <= 1.6.0") }

        context "that could cause duplication" do
          let(:old_requirement) { "~> 0.5, >= 0.5.2" }
          it { is_expected.to eq(">= 0.5.2, < 2.0") }
        end
      end

      context "when a beta version was used in the old requirement" do
        let(:old_requirement) { "< 1.4.0.beta" }
        it { is_expected.to be_nil }
      end

      context "when a != specifier was used" do
        let(:old_requirement) { "!= 1.5.0" }
        it { is_expected.to be_nil }
      end

      context "when a >= specifier was used" do
        let(:old_requirement) { ">= 1.6.0" }
        it { is_expected.to be_nil }
      end

      context "when a > specifier was used" do
        let(:old_requirement) { "> 1.6.0" }
        it { is_expected.to be_nil }
      end

      context "for a development dependency" do
        let(:dependency) do
          Dependabot::Dependency.new(
            name: "business",
            requirement: old_requirement,
            package_manager: "bundler",
            groups: ["development"]
          )
        end

        context "when an = specifier was used" do
          let(:old_requirement) { "= 1.4.0" }
          it { is_expected.to eq("= 1.5.0") }
        end

        context "when no specifier was used" do
          let(:old_requirement) { "1.4.0" }
          it { is_expected.to eq("= 1.5.0") }
        end

        context "when a < specifier was used" do
          let(:old_requirement) { "< 1.4.0" }
          it { is_expected.to eq("< 1.6.0") }
        end

        context "when a <= specifier was used" do
          let(:old_requirement) { "<= 1.4.0" }
          it { is_expected.to eq("<= 1.6.0") }
        end

        context "when a ~> specifier was used" do
          let(:old_requirement) { "~> 1.4.0" }
          it { is_expected.to eq("~> 1.5.0") }

          context "with minor precision" do
            let(:old_requirement) { "~> 0.1" }
            it { is_expected.to eq("~> 1.5") }
          end
        end

        context "when there are multiple requirements" do
          let(:old_requirement) { "> 1.0.0, <= 1.4.0" }
          it { is_expected.to eq("> 1.0.0, <= 1.6.0") }
        end

        context "when a beta version was used in the old requirement" do
          let(:old_requirement) { "< 1.4.0.beta" }
          it { is_expected.to be_nil }
        end

        context "when a != specifier was used" do
          let(:old_requirement) { "!= 1.5.0" }
          it { is_expected.to be_nil }
        end

        context "when a >= specifier was used" do
          let(:old_requirement) { ">= 1.6.0" }
          it { is_expected.to be_nil }
        end

        context "when a > specifier was used" do
          let(:old_requirement) { "> 1.6.0" }
          it { is_expected.to be_nil }
        end
      end
    end
  end
end
