require 'fileutils'
require 'yaml'

require 'rugged'

require_relative 'cache'

module GitSme
  class CommitLoader
    attr_reader :valid, :error_message, :branch, :commits, :loaded, :repo

    alias_method :valid?, :valid
    alias_method :loaded?, :loaded

    def initialize(path_to_repo, branch: 'master', enable_cache: true)
      @branch = branch
      @enable_cache = enable_cache
      @commits = []
      @loaded = false
      @valid = true

      begin
        @repo = Rugged::Repository.new(File.expand_path(path_to_repo))
        @branch = 'master' if @repo.branches[@branch].nil?

        @cache = GitSme::Cache.new(@repo.path.gsub('/.git/', ''),
          enabled: @enable_cache, file_suffix: "#{@branch}-commits"
        )
      rescue Rugged::RepositoryError => e
        @valid = false
        @error_message = e.message
      end
    end

    def load(force: false)
      return unless valid?
      return if loaded? && !force

      @commits = @cache.load
      @last_commit_idx = @commits.size - 1
      @commit_count = `cd #{@repo.path.gsub('/.git/', '')} && git rev-list --count #{@branch}`.to_i

      walker = Rugged::Walker.new(@repo)
      walker.push(@repo.branches[@branch].target_id)

      if @enable_cache && @commits.size > 0
        appending_to_cache = true
        oldest_cached_commit = @commits[-1]
        oldest_cached_commit_sha = oldest_cached_commit ? oldest_cached_commit[:sha1] : nil

        walker.sorting(Rugged::SORT_REVERSE)
      end

      new_commits = []

      walker.each do |commit|
        break if appending_to_cache && commit.oid == oldest_cached_commit_sha

        process_commit(appending_to_cache, commit, new_commits) do |new_commit_count, processed_commit_count, all_commit_count|
          yield(new_commit_count, processed_commit_count, all_commit_count)
        end
      end

      walker.reset

      @commits.concat(new_commits.reverse) if new_commits.any?

      @cache.save(@commits)

      @loaded = true
    end

    def load!
      load(force: true)
    end
    alias_method :reload!, :load!

    def new_commits?
      return false if @last_commit_idx.nil?

      @last_commit_idx > 0 && @last_commit_idx < (@commits.size - 1)
    end

    def new_commits
      return [] unless new_commits?

      @commits.slice(@last_commit_idx, @commits.size)
    end

    private

    def process_commit(appending_to_cache, commit, new_commits)
      return if merge_commit?(commit)

      commit_details = get_commit_details(commit)

      if appending_to_cache
        new_commits << commit_details
      else
        @commits << commit_details
      end

      # To aid in tracking progress since this process can take some time
      yield(new_commits.size, @commits.size, @commit_count) if block_given?
    end

    def merge_commit?(commit)
      commit.parents.size > 1
    end

    def get_patch_details(patch)
      filename = patch.header.split("\n")[0].split[-1].split('/', 2)[-1]
      additions, deletions = patch.stat

      {
        filename => {
          additions: additions,
          deletions: deletions,
          changes: patch.changes
        }
      }
    end

    def get_commit_details(commit)
      patches = commit.diff(commit.parents.first)
      additions = deletions = 0
      file_changes = patches.each_with_object({}) do |patch, hash|
        patch_details = get_patch_details(patch)
        changes = patch_details.values.first

        hash.merge!(patch_details)

        additions += changes[:additions]
        deletions += changes[:deletions]
      end

      {
        sha1: commit.oid,
        timestamp: commit.epoch_time,
        author: commit.author[:email].split('@')[0],
        files_changed: file_changes.keys.size,
        file_changes: file_changes,
        additions: additions,
        deletions: deletions,
        changes: additions + deletions
      }
    end
  end
end
