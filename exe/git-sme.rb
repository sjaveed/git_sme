#!/usr/bin/env ruby

require 'optparse'
require 'yaml'
require 'fileutils'

require 'rubygems'
require 'rugged'
require 'ruby-progressbar'
require 'byebug'

PREFERENCES_HOME = "#{Dir.home()}/.gitsme"

@options = {
  branch: 'master',
  cache: false,
  ignore_cache: true,
  results_to_show: 10,
  users: [],
  files: [],
  fuzzy: false
}

@last_cached_commit = nil

opt_parser = OptionParser.new do |opt|
  opt.banner = "Usage: git-sme [OPTIONS]"

  opt.on('-b', '--branch <branch_name>', 'the branch to process, default: master') do |branch|
    @options[:branch] = branch
  end

  opt.on('-c', '--use-cache', 'use a cache to store processed git commits between runs of the tool') do
    @options[:cache] = true
    @options[:ignore_cache] = false
  end

  opt.on('-f', '--file /path/to/file', 'the full relative path from the repo root for the file/directory you want to limit analysis to') do |file|
    @options[:files] << (@options[:fuzzy] ? Regexp.new(file) : file)
  end

  opt.on('-h', '--help', 'help') do
    puts opt_parser
  end

  opt.on('-i', '--ignore-cache', 'ignore any existing cache for the given repository') do
    @options[:ignore_cache] = true
  end

  opt.on('-r', '--repo /path/to/repo', 'the path to the git repository') do |repo|
    @options[:repo] = File.expand_path(repo)
  end

  opt.on('-t', '--top <count>', 'the number of users/files to show in analysis') do |results_to_show|
    @options[:results_to_show] = results_to_show
  end

  opt.on('-u', '--user <username>', 'the username you want to limit analysis to') do |user|
    @options[:users] << (@options[:fuzzy] ? Regexp.new(user) : user)
  end

  opt.on('-z', '--fuzzy', 'the users and filenames are regular expressions (minus the /)') do |user|
    @options[:fuzzy] = true
  end
end

def cache_directory
  "#{PREFERENCES_HOME}/cache"
end

def analysis_cache_filename
  "#{cache_directory}/analysis-#{@options[:repo].gsub(/[^a-zA-Z]/, '')}#{@options[:branch]}.yml"
end

def read_analysis_from_cache
  return {} unless File.exists?(analysis_cache_filename)

  puts 'Cached analysis found; loading...'
  YAML.load(File.read(analysis_cache_filename))
end

def write_analysis_to_cache(data)
  FileUtils.mkdir_p(cache_directory) unless File.exists?(cache_directory)

  puts 'Updating cached analysis...'
  File.open(analysis_cache_filename, 'w') { |f| f.write(YAML.dump(data)) }
end

def commits_cache_filename
  "#{cache_directory}/commits-#{@options[:repo].gsub(/[^a-zA-Z]/, '')}#{@options[:branch]}.yml"
end

def read_commits_from_cache
  return [] unless File.exists?(commits_cache_filename)

  puts 'Cached commits found; loading...'
  YAML.load(File.read(commits_cache_filename))
end

def write_commits_to_cache(data)
  FileUtils.mkdir_p(cache_directory) unless File.exists?(cache_directory)

  puts 'Updating cached commits...'
  File.open(commits_cache_filename, 'w') { |f| f.write(YAML.dump(data)) }
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

def commit_should_be_loaded?(commit)
  commit.parents.size == 1
end

def load_commits_from_cache(cached_commits, progress, walker)
  # We have some commits cached in order of commit which means the last commit is the latest
  # let's attempt to preserve that order but start from the most recent commit on the repo to
  # minimize work

  new_commits = []

  oldest_cached_commit_sha = if @options[:cache]
    oldest_cached_commit = cached_commits[-1]
    oldest_cached_commit ? oldest_cached_commit[:sha1] : nil
  end

  walker.each do |commit|
    break if commit.oid == oldest_cached_commit_sha
    next unless commit_should_be_loaded?(commit)

    commit_details = get_commit_details(commit)

    new_commits << commit_details
    progress.increment
  end

  walker.reset

  if new_commits.any?
    cached_commits.concat(new_commits.reverse)
    write_commits_to_cache(cached_commits) if @options[:cache]
  else
    @last_cached_commit = nil
    @last_cached_commit_index = nil
  end
end

def load_commits_without_cache(all_commits, progress, walker)
  # We don't have any commits cached => let's populate this using the walker starting with the
  # oldest commits on the repo first

  walker.sorting(Rugged::SORT_REVERSE)

  walker.each do |commit|
    next unless commit_should_be_loaded?(commit)

    commit_details = get_commit_details(commit)

    all_commits << commit_details
    progress.increment
  end

  walker.reset
  write_commits_to_cache(all_commits) if @options[:cache]
end

def matching_files_from_commit(commit)
  commit[:file_changes].keys.select do |filename|
    @options[:files].map { |pattern| filename.start_with?(pattern) }.any? { |value| value }
  end
end

# def commit_matches_requirements(commit)
#   return false if !@options[:users].empty? && !@options[:users].include?(commit[:author])
#   return false if !@options[:files].empty? && matching_files_from_commit(commit).empty?
#
#   true
# end

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

def analyze_new_commits(all_commits)
  user_stats = {}
  file_stats = {}
  progress = ProgressBar.create(starting_at: 0, total: all_commits.size, format: 'Commits processed: %c (%R/s)%f |%B| %P%%')
  now = Time.now.to_i

  all_commits.each do |commit|
    # unless commit_matches_requirements(commit)
    #   progress.increment
    #   next
    # end

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

    progress.increment
  end

  {
    by_user: user_stats,
    by_file: file_stats
  }
end

def read_from_cache?
  @options[:cache] && !@options[:ignore_cache]
end

def load_commits(repo)
  all_commits = read_from_cache? ? read_commits_from_cache : []

  walker = Rugged::Walker.new(repo)
  walker.push(repo.branches[@options[:branch]].target_id)

  commit_count = `git rev-list --count #{@options[:branch]}`.to_i
  progress = ProgressBar.create(starting_at: all_commits.size, total: commit_count, format: 'Commits loaded: %c (%R/s)%f |%B| %P%%')

  if all_commits.size > 0
    @last_cached_commit = all_commits[-1]
    @last_cached_commit_index = all_commits.size - 1
    load_commits_from_cache(all_commits, progress, walker)
  else
    load_commits_without_cache(all_commits, progress, walker)
  end

  puts "Total commits loaded: #{all_commits.size}"
  all_commits
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

def analyze_commits(all_commits)
  cached_analysis = read_analysis_from_cache
  new_commits = []

  analysis = if @last_cached_commit.nil? || cached_analysis.none?
    analyze_new_commits(all_commits)
  else
    new_commits = all_commits.slice(@last_cached_commit_index, all_commits.size) || []

    if new_commits.any?
      new_analysis = analyze_new_commits(new_commits)

      summed_merge(cached_analysis[:by_user], new_analysis[:by_user])
      summed_merge(cached_analysis[:by_file], new_analysis[:by_file])
    end

    cached_analysis
  end

  write_analysis_to_cache(analysis) if @options[:cache]

  puts "Total commits processed: #{new_commits.size}"
  analysis
end

def sort_keys_by_value(data)
  data.keys.sort_by { |k| data[k] }.reverse
end

def presentable_file_or_user(data, key)
  stats = data[key]
  info_to_show = sort_keys_by_value(stats).first(@options[:results_to_show])
  return if info_to_show.empty?

  "#{key}: #{info_to_show.join(', ')}"
end

def get_matching_keys(all_keys, keys_to_match)
  all_keys.select do |key|
    keys_to_match.map { |matcher| matcher.match?(key) }.any? { |val| val }
  end
end

def present_analysis(analysis)
  @options[:files] = ['/'] unless @options[:users].any? || @options[:files].any?

  users_to_match = @options[:users].any? ? get_matching_keys(analysis[:by_user].keys, @options[:users]) : []
  files_to_match = @options[:files].any? ? get_matching_keys(analysis[:by_file].keys, @options[:files]) : []

  if users_to_match.any? && files_to_match.any?
    users_to_match.each do |user|
      user_data = analysis[:by_user][user].select { |k, v| files_to_match.include?(k) }
      presentable_str = presentable_file_or_user({ user => user_data }, user)
      puts presentable_str if presentable_str
    end

    puts

    files_to_match.each do |file|
      user_data = analysis[:by_file][file].select { |k, v| users_to_match.include?(k) }
      presentable_str = presentable_file_or_user({ file => user_data }, file)
      puts presentable_str if presentable_str
    end
  elsif users_to_match.any?
    get_matching_keys(analysis[:by_user].keys, users_to_match).each do |user|
      presentable_str = presentable_file_or_user(analysis[:by_user], user)
      puts presentable_str if presentable_str
    end
  elsif files_to_match.any?
    get_matching_keys(analysis[:by_file].keys, files_to_match).each do |path|
      presentable_str = presentable_file_or_user(analysis[:by_file], path)
      puts presentable_str if presentable_str
    end
  end
end

###
# Main
#

opt_parser.parse!

unless @options[:repo]
  puts "Please specify a repository!"
  puts
  puts opt_parser
  exit(1)
end

puts "Processing repo: #{@options[:repo]}, Branch: #{@options[:branch]}"
repo = Rugged::Repository.new(@options[:repo])
all_commits = load_commits(repo)
analysis = analyze_commits(all_commits)

present_analysis(analysis)
