require 'fileutils'

require_relative 'preferences'

module GitSme
  class Cache
    def initialize(name, enabled: true, directory: 'cache', file_prefix: '', file_suffix: '')
      raise "Invalid cache name: [#{name}]" if name.nil? || name =~ /^\s+$/

      @name = name.gsub(/[^a-zA-Z-]/, '').strip
      @enabled = enabled
      @cache_directory = File.join(PREFERENCES_HOME, directory)
      @file_prefix = file_prefix
      @file_suffix = file_suffix

      FileUtils.mkdir_p(@cache_directory) unless File.exist?(@cache_directory)
    end

    def load
      return [] unless @enabled && File.exist?(cache_filename)

      YAML.load(File.read(cache_filename))
    end

    def save(data)
      return unless @enabled

      File.open(cache_filename, 'w') { |f| f.write(YAML.dump(data)) }
    end

    private

    def prefix
      return '' if @file_prefix =~ /^\s*$/

      "#{@file_prefix}-"
    end

    def suffix
      return '' if @file_suffix =~ /^\s*$/

      "-#{@file_suffix}"
    end

    def cache_filename
      filename = @name

      File.join(@cache_directory, "#{prefix}#{filename}#{suffix}.yml")
    end
  end
end
