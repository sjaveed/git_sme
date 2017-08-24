module GitSme
  class AnalysisPresenter
    attr_reader :valid, :error_message

    alias_method :valid?, :valid

    def initialize(commit_analyzer, users = [], files = [])
      @commit_analyzer = commit_analyzer
      @users = users
      @files = files
      @files = ['/'] unless @users.any? || @files.any?
      @files.map! { |f| f.start_with?("/") ? "/#{f}" : f }

      @valid = @commit_analyzer.valid?
      @error_message = @commit_analyzer.error_message
    end

    def get_relevant_analyses(results_to_show = 10)
      @commit_analyzer.analyze unless @commit_analyzer.analyzed?

      users_to_match = @users.any? ? get_matching_keys(@commit_analyzer.analysis[:by_user].keys, @users) : []
      files_to_match = @files.any? ? get_matching_keys(@commit_analyzer.analysis[:by_file].keys, @files) : []
      presentable_data = []

      if users_to_match.any? && files_to_match.any?
        users_to_match.each do |user|
          user_data = @commit_analyzer.analysis[:by_user][user].select { |k, v| files_to_match.include?(k) }
          presentable_data << presentable_file_or_user({ user => user_data }, user, results_to_show: results_to_show)
        end

        puts

        files_to_match.each do |file|
          user_data = @commit_analyzer.analysis[:by_file][file].select { |k, v| users_to_match.include?(k) }
          presentable_data << presentable_file_or_user({ file => user_data }, file)
        end
      elsif users_to_match.any?
        get_matching_keys(@commit_analyzer.analysis[:by_user].keys, users_to_match).each do |user|
          presentable_data << presentable_file_or_user(@commit_analyzer.analysis[:by_user], user)
        end
      elsif files_to_match.any?
        get_matching_keys(@commit_analyzer.analysis[:by_file].keys, files_to_match).each do |path|
          presentable_data << presentable_file_or_user(@commit_analyzer.analysis[:by_file], path)
        end
      end

      presentable_data.compact
    end

    private

    def presentable_file_or_user(data, key, results_to_show: 10)
      stats = data[key]
      info_to_show = sort_keys_by_value(stats).first(results_to_show)
      return if info_to_show.empty?

      {
        key => info_to_show
      }
    end

    def sort_keys_by_value(data)
      data.keys.sort_by { |k| data[k] }.reverse
    end

    def get_matching_keys(all_keys, keys_to_match)
      all_keys.select do |key|
        keys_to_match.map { |matcher| matcher.match?(key) }.any? { |val| val }
      end
    end
  end
end
