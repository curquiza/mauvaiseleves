# Loads collect/.env into ENV (without overriding variables already set).
module Env
  FILE = File.expand_path("../.env", __dir__)

  def self.load
    return unless File.exist?(FILE)

    File.readlines(FILE, chomp: true).each do |line|
      line = line.sub(/\s+#.*\z/, "").strip
      next if line.empty? || line.start_with?("#")

      key, value = line.split("=", 2)
      next if value.nil?

      ENV[key.strip] ||= value.strip.delete_prefix('"').delete_suffix('"')
    end
  end

  def self.fetch(key)
    ENV.fetch(key) { abort "Missing #{key} in collect/.env" }
  end
end
