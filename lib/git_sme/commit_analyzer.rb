module GitSme
  class CommitAnalyzer
    attr_reader :valid, :error_message, :analysis, :analyzed

    alias_method :valid?, :valid
    alias_method :analyzed?, :analyzed

    def initialize(commit_loader, enable_cache: true)
      @enable_cache = true
      @commit_loader = commit_loader
      @analyzed = false
      @valid = @commit_loader.valid?
      @error_message = @commit_loader.error_message

      @analysis = {}
      @cache = GitSme::Cache.new(@commit_loader.repo.path.gsub('/.git/', ''),
        enabled: @enable_cache, file_suffix: "#{@commit_loader.branch}-analysis"
      )
    end

    def analyze(force: false)
      return unless valid?
      return if analyzed? && !force

      @commit_loader.load
      @analysis = @cache.load
      new_analysis = []

      if !@commit_loader.new_commits? || !@analysis.any?
        if block_given?
          @analysis = analyze_new_commits(@commit_loader.commits) do |commit_count, total_commits|
            yield(commit_count, total_commits)
          end
        else
          @analysis = analyze_new_commits(@commit_loader.commits)
        end
      elsif @commit_loader.new_commits?
        new_analysis = if block_given?
          analyze_new_commits(@commit_loader.new_commits) do |commit_count, total_commits|
            yield(commit_count, total_commits)
          end
        else
          analyze_new_commits(@commit_loader.new_commits)
        end

        summed_merge(@analysis[:by_user], new_analysis[:by_user])
        summed_merge(@analysis[:by_file], new_analysis[:by_file])
      end

      @cache.save(@analysis)
      @analyzed = true
    end

    private

    def analyze_new_commits(commits_to_process)
      user_stats = {}
      file_stats = {}
      now = Time.now.to_i
      commit_count = commits_to_process.size

      commits_to_process.each_with_index do |commit, current_commit_idx|
        author = commit[:author]
        time_delta = now - commit[:timestamp]

        commit[:file_changes].each do |filename, change_details|
          all_affected_paths(filename).each do |path|
            change_value = weighted_value(change_details[:changes], time_delta)

            user_stats[author] = {} unless user_stats.key?(author)
            user_stats[author][path] = 0 unless user_stats[author].key?(path)

            file_stats[path] = {} unless file_stats.key?(path)
            file_stats[path][author] = 0 unless file_stats[path].key?(author)

            user_stats[author][path] += change_value
            file_stats[path][author] += change_value
          end
        end

        if block_given?
          yield(current_commit_idx, commit_count)
        end
      end

      {
        by_user: user_stats,
        by_file: file_stats
      }
    end

    def summed_merge(cached_data, new_data)
      return if new_data.nil? || cached_data.nil?

      new_data.each do |key, value_hash|
        if cached_data.key?(key)
          value_hash.each do |value_key, value|
            if cached_data[key].key?(value_key)
              cached_data[key][value_key] += value
            else
              cached_data[key][value_key] = value
            end
          end
        else
          cached_data[key] = value_hash
        end
      end
    end

    def all_affected_paths(filename)
      ['/'] + filename.split('/').each_with_object([]) do |path_part, path_list|
        path_list << [path_list[-1], path_part].join('/')
      end
    end

    def weighted_value(value, time_delta)
      # value_attenuator = 1.0
      # value_attenuation = value_attenuator * time_delta / time_delta
      value_attenuation = time_delta > 0 ? time_delta ** (-1/3) : 1

      (value * value_attenuation).to_f
    end

  end
end
