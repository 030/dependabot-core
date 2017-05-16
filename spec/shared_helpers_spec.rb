# frozen_string_literal: true
require "spec_helper"
require "bump/shared_helpers"

RSpec.describe Bump::SharedHelpers do
  describe ".in_a_forked_process" do
    subject(:run_sub_process) do
      Bump::SharedHelpers.in_a_forked_process { task.call }
    end

    context "when the forked process returns a value" do
      let(:task) { -> { "all good" } }

      it "returns the return value of the sub-process" do
        expect(run_sub_process).to eq("all good")
      end
    end

    context "when the forked process sets an environment variable" do
      let(:task) { -> { @bundle_setting = "new" } }

      it "doesn't persist the change" do
        expect { run_sub_process }.to_not(change { @bundle_setting })
      end
    end

    context "when the forked process raises an error" do
      let(:task) { -> { raise Exception, "hell" } }

      it "raises a ChildProcessFailed error" do
        expect { run_sub_process }.
          to raise_error(Bump::SharedHelpers::ChildProcessFailed)
      end
    end
  end

  describe ".run_helper_subprocess" do
    let(:method) { "example" }
    let(:args) { ["foo"] }

    subject(:run_subprocess) do
      project_root = File.join(File.dirname(__FILE__), "..")
      bin_path = File.join(project_root, "helpers/test/run.rb")
      command = "ruby #{bin_path}"
      Bump::SharedHelpers.run_helper_subprocess(command, method, args)
    end

    context "when the subprocess is successful" do
      it "returns the result" do
        expect(run_subprocess).to eq("method" => method, "args" => args)
      end
    end

    context "when the subprocess fails" do
      let(:method) { "error" }

      it "raises a HelperSubprocessFailed error" do
        expect { run_subprocess }.
          to raise_error(Bump::SharedHelpers::HelperSubprocessFailed)
      end
    end
  end
end
