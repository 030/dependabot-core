# frozen_string_literal: true
require "spec_helper"
require "dependabot/update_checkers/ruby/bundler/requirements_updater"

RSpec.describe Dependabot::UpdateCheckers::Ruby::Bundler::RequirementsUpdater do
  let(:updater) do
    described_class.new(
      requirements: requirements,
      existing_version: existing_version,
      latest_version: latest_version,
      latest_resolvable_version: latest_resolvable_version
    )
  end

  let(:requirements) { [gemfile_requirement, gemspec_requirement].compact }
  let(:gemfile_requirement) do
    {
      file: "Gemfile",
      requirement: gemfile_requirement_string,
      groups: gemfile_groups
    }
  end
  let(:gemspec_requirement) do
    {
      file: "some.gemspec",
      requirement: gemspec_requirement_string,
      groups: gemspec_groups
    }
  end
  let(:gemfile_requirement_string) { "~> 1.4.0" }
  let(:gemfile_groups) { [] }
  let(:gemspec_requirement_string) { "~> 1.4.0" }
  let(:gemspec_groups) { [] }

  let(:existing_version) { "1.4.0" }
  let(:latest_version) { "1.8.0" }
  let(:latest_resolvable_version) { "1.5.0" }

  describe "#updated_requirements" do
    subject(:updated_requirements) { updater.updated_requirements }

    context "for a Gemfile dependency" do
      subject { updated_requirements.find { |r| r[:file] == "Gemfile" } }

      context "when there is no resolvable version" do
        let(:latest_resolvable_version) { nil }
        it { is_expected.to eq(gemfile_requirement) }
      end

      context "when there is a resolvable version" do
        let(:latest_resolvable_version) { "1.5.0" }

        context "and a full version was previously specified" do
          let(:gemfile_requirement_string) { "~> 1.4.0" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        context "and a pre-release was previously specified" do
          let(:gemfile_requirement_string) { "~> 1.5.0.beta" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        context "and a minor version was previously specified" do
          let(:gemfile_requirement_string) { "~> 1.4" }
          its([:requirement]) { is_expected.to eq("~> 1.5") }
        end

        context "and a greater than or equal to matcher was used" do
          let(:gemfile_requirement_string) { ">= 1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.5.0") }
        end

        context "and a less than matcher was used" do
          let(:gemfile_requirement_string) { "< 1.4.0" }
          its([:requirement]) { is_expected.to eq("~> 1.5.0") }
        end

        context "when there is no `existing_version`" do
          # In this case we don't have a Gemfile.lock for this repo, so want
          # slightly different updating behaviour.
          let(:existing_version) { nil }

          context "and the new version satisfies the old requirements" do
            let(:gemfile_requirement_string) { "~> 1.4" }
            it { is_expected.to eq(gemfile_requirement) }
          end

          context "and the new version does not satisfy the old requirements" do
            let(:gemfile_requirement_string) { "~> 1.4.0" }
            its([:requirement]) { is_expected.to eq("~> 1.5.0") }
          end
        end
      end
    end

    context "for a gemspec dependency" do
      subject { updated_requirements.find { |r| r[:file].end_with?("emspec") } }

      context "when there is no latest version" do
        let(:latest_version) { nil }
        it { is_expected.to eq(gemspec_requirement) }
      end

      context "when there is a latest version" do
        let(:latest_version) { "1.5.0" }

        context "when an = specifier was used" do
          let(:gemspec_requirement_string) { "= 1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.4.0") }
        end

        context "when no specifier was used" do
          let(:gemspec_requirement_string) { "1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.4.0") }
        end

        context "when a < specifier was used" do
          let(:gemspec_requirement_string) { "< 1.4.0" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "when a <= specifier was used" do
          let(:gemspec_requirement_string) { "<= 1.4.0" }
          its([:requirement]) { is_expected.to eq("<= 1.6.0") }
        end

        context "when a ~> specifier was used" do
          let(:gemspec_requirement_string) { "~> 1.4.0" }
          its([:requirement]) { is_expected.to eq(">= 1.4, < 1.6") }

          context "with two zeros" do
            let(:gemspec_requirement_string) { "~> 1.0.0" }
            its([:requirement]) { is_expected.to eq(">= 1.0, < 1.6") }
          end

          context "with no zeros" do
            let(:gemspec_requirement_string) { "~> 1.0.1" }
            its([:requirement]) { is_expected.to eq(">= 1.0.1, < 1.6.0") }
          end

          context "with minor precision" do
            let(:gemspec_requirement_string) { "~> 0.1" }
            its([:requirement]) { is_expected.to eq(">= 0.1, < 2.0") }
          end
        end

        context "when there are multiple requirements" do
          let(:gemspec_requirement_string) { "> 1.0.0, <= 1.4.0" }
          its([:requirement]) { is_expected.to eq("> 1.0.0, <= 1.6.0") }

          context "that could cause duplication" do
            let(:gemspec_requirement_string) { "~> 0.5, >= 0.5.2" }
            its([:requirement]) { is_expected.to eq(">= 0.5.2, < 2.0") }
          end
        end

        context "when a beta version was used in the old requirement" do
          let(:gemspec_requirement_string) { "< 1.4.0.beta" }
          its([:requirement]) { is_expected.to eq("< 1.6.0") }
        end

        context "when a != specifier was used" do
          let(:gemspec_requirement_string) { "!= 1.5.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "when a >= specifier was used" do
          let(:gemspec_requirement_string) { ">= 1.6.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "when a > specifier was used" do
          let(:gemspec_requirement_string) { "> 1.6.0" }
          its([:requirement]) { is_expected.to eq(:unfixable) }
        end

        context "for a development dependency" do
          let(:requirements) do
            [
              {
                file: "some.gemspec",
                requirement: gemspec_requirement_string,
                groups: ["development"]
              }
            ]
          end

          context "when an = specifier was used" do
            let(:gemspec_requirement_string) { "= 1.4.0" }
            its([:requirement]) { is_expected.to eq("= 1.5.0") }
          end

          context "when no specifier was used" do
            let(:gemspec_requirement_string) { "1.4.0" }
            its([:requirement]) { is_expected.to eq("= 1.5.0") }
          end

          context "when a < specifier was used" do
            let(:gemspec_requirement_string) { "< 1.4.0" }
            its([:requirement]) { is_expected.to eq("< 1.6.0") }
          end

          context "when a <= specifier was used" do
            let(:gemspec_requirement_string) { "<= 1.4.0" }
            its([:requirement]) { is_expected.to eq("<= 1.6.0") }
          end

          context "when a ~> specifier was used" do
            let(:gemspec_requirement_string) { "~> 1.4.0" }
            its([:requirement]) { is_expected.to eq("~> 1.5.0") }

            context "with minor precision" do
              let(:gemspec_requirement_string) { "~> 0.1" }
              its([:requirement]) { is_expected.to eq("~> 1.5") }
            end
          end

          context "when there are multiple requirements" do
            let(:gemspec_requirement_string) { "> 1.0.0, <= 1.4.0" }
            its([:requirement]) { is_expected.to eq("> 1.0.0, <= 1.6.0") }
          end

          context "when a beta version was used in the old requirement" do
            let(:gemspec_requirement_string) { "< 1.4.0.beta" }
            its([:requirement]) { is_expected.to eq("< 1.6.0") }
          end

          context "when a != specifier was used" do
            let(:gemspec_requirement_string) { "!= 1.5.0" }
            its([:requirement]) { is_expected.to eq(:unfixable) }
          end

          context "when a >= specifier was used" do
            let(:gemspec_requirement_string) { ">= 1.6.0" }
            its([:requirement]) { is_expected.to eq(:unfixable) }
          end

          context "when a > specifier was used" do
            let(:gemspec_requirement_string) { "> 1.6.0" }
            its([:requirement]) { is_expected.to eq(:unfixable) }
          end
        end
      end
    end

    context "with both a Gemfile and a gemspec" do
      let(:gemfile_requirement_string) { "~> 1.4.0" }
      let(:gemfile_groups) { [] }
      let(:gemspec_requirement_string) { ">= 1.0, < 1.5" }
      let(:gemspec_groups) { [] }

      it "updates both files" do
        expect(updated_requirements).to match_array(
          [
            { file: "Gemfile", requirement: "~> 1.5.0", groups: [] },
            { file: "some.gemspec", requirement: ">= 1.0, < 1.9", groups: [] }
          ]
        )
      end
    end
  end
end
