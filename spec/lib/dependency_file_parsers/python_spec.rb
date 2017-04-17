# frozen_string_literal: true
require "spec_helper"
require "bump/dependency_file"
require "bump/dependency_file_parsers/python"

RSpec.describe Bump::DependencyFileParsers::Python do
  let(:files) { [requirements] }
  let(:requirements) do
    Bump::DependencyFile.new(
      name: "requirements.txt",
      content: requirements_body
    )
  end
  let(:requirements_body) { fixture("requirements", "version_specified.txt") }
  let(:parser) { described_class.new(dependency_files: files) }

  describe "parse" do
    subject(:dependencies) { parser.parse }

    its(:length) { is_expected.to eq(2) }

    context "with a version specified" do
      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with comments" do
      let(:requirements_body) { fixture("requirements", "comments.txt") }
      its(:length) { is_expected.to eq(2) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with extras" do
      let(:requirements_body) { fixture("requirements", "extras.txt") }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with invalid lines" do
      let(:requirements_body) { fixture("requirements", "invalid_lines.txt") }
      its(:length) { is_expected.to eq(1) }

      describe "the first dependency" do
        subject { dependencies.first }

        it { is_expected.to be_a(Bump::Dependency) }
        its(:name) { is_expected.to eq("psycopg2") }
        its(:version) { is_expected.to eq("2.6.1") }
      end
    end

    context "with no version specified" do
      let(:requirements_body) do
        fixture("requirements", "version_not_specified.txt")
      end

      # If no version is specified, Python will always use the latest, and we
      # don't need to attempt to bump the dependency.
      its(:length) { is_expected.to eq(1) }
    end

    context "with a version specified as between two constraints" do
      let(:requirements_body) do
        fixture("requirements", "version_between_bounds.txt")
      end

      # TODO: For now we ignore dependencies with multiple requirements, because
      # they'd cause trouble at the dependency update step.
      its(:length) { is_expected.to eq(1) }
    end
  end

  describe Bump::DependencyFileParsers::Python::LineParser do
    subject(:parser) { described_class.new(line) }

    describe "parse" do
      subject { parser.parse }

      context "with a blank line" do
        let(:line) { "" }
        it { is_expected.to be_nil }
      end

      context "with just a line break" do
        let(:line) { "\n" }
        it { is_expected.to be_nil }
      end

      context "with a non-requirement line" do
        let(:line) { "# This is just a comment" }
        it { is_expected.to be_nil }
      end

      context "with no specification" do
        let(:line) { "luigi" }
        its([:name]) { is_expected.to eq "luigi" }
        its([:requirements]) { is_expected.to eq [] }

        context "with a comment" do
          let(:line) { "luigi # some comment" }
          its([:name]) { is_expected.to eq "luigi" }
          its([:requirements]) { is_expected.to eq [] }
        end
      end

      context "with a simple specification" do
        let(:line) { "luigi == 0.1.0" }
        its([:requirements]) { is_expected.to eq ["== 0.1.0"] }

        context "without spaces" do
          let(:line) { "luigi==0.1.0" }
          its([:name]) { is_expected.to eq "luigi" }
          its([:requirements]) { is_expected.to eq ["==0.1.0"] }
        end
      end

      context "with multiple specifications" do
        let(:line) { "luigi == 0.1.0, <= 1" }
        its([:requirements]) { is_expected.to eq ["== 0.1.0", "<= 1"] }

        context "with a comment" do
          let(:line) { "luigi == 0.1.0, <= 1 # some comment" }
          its([:requirements]) { is_expected.to eq ["== 0.1.0", "<= 1"] }
        end
      end
    end
  end
end
