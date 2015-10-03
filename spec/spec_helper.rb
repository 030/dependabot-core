require "rspec/its"
require "webmock/rspec"
require "dotenv"

Dotenv.load("dummy-env")

def fixture(name)
  File.read(File.join("spec", "fixtures", name))
end

def github_fixture(name)
  fixture(File.join("github", name))
end
