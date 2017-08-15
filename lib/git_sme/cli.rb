require 'thor'
require 'ruby-progressbar'
require 'git_sme'

module GitSme
  class CLI < Thor
    desc 'analyze <repository> [--branch <branch>] [--user <username>] [--file </path/to/file>] [--cache | --no-cache] [--results <count>]',
      'Analyze the repository and determine the subject matter experts for the given files, limiting them to the users provided if needed'

    method_option :branch, type: :string, default: 'master'
    method_option :user, type: :array, default: []
    method_option :file, type: :array, default: ['/']
    method_option :cache, type: :boolean, default: true
    method_option :results, type: :numeric, default: 10

    def analyze(repository)
      loader = GitSme::CommitLoader.new(repository, branch: options[:branch], enable_cache: options[:cache])
      unless loader.valid?
        puts "Error: #{loader.error_message}"
        return
      end

      puts "Repository: #{loader.repo.path.gsub('/.git/', '')}"

      loader_progress = ProgressBar.create(starting_at: 0, format: 'Loaded: %c (%R/s) %P%% %f |%B|')
      loader.load do |new_commit_count, processed_commit_count, all_commit_count|
        loader_progress.total = all_commit_count
        loader_progress.increment
      end

      analyzer = GitSme::CommitAnalyzer.new(loader, enable_cache: false)
      unless analyzer.valid?
        puts "Error: #{analyzer.error_message}"
        return
      end

      analyzer_progress = ProgressBar.create(starting_at: 0, total: loader.commits.size, format: 'Analyzed: %c (%R/s) %P%% %f |%B|')
      analyzer.analyze do |commit_count, total_commits|
        analyzer_progress.increment
      end

      presenter = AnalysisPresenter.new(analyzer, options[:user], options[:file])
      analyses = presenter.get_relevant_analyses(options[:results].to_i)

      puts

      if !analyses.empty?
        analyses.each do |result|
          result.each do |path, users|
            puts "#{path}: #{users.join(', ')}"
          end
        end
      else
        puts 'No data found!'
      end
    end

    default_task :analyze
  end
end
