module SharedHelpers
  BUMP_TMP_FILE_PREFIX = "bump_".freeze
  BUMP_TMP_DIR_PATH = "tmp".freeze

  def self.in_a_temporary_directory
    Dir.mkdir(BUMP_TMP_DIR_PATH) unless Dir.exist?(BUMP_TMP_DIR_PATH)
    Dir.mktmpdir(BUMP_TMP_FILE_PREFIX, BUMP_TMP_DIR_PATH) do |dir|
      yield dir
    end
  end
end
