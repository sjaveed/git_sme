# Git SME

Git SME allows you to analyze your git repository and identify subject matter experts for any file
or directory that you would like to know more about.  It does this by analyzing all commits made to
all files in your git repository over time and finding out who made the most changes to each file
and directory.

Commits are weighted so recent commits are more significant than past commits which should mitigate
the effect a legacy coder would have on these reports.

## Installation

Install the gem for commandline usage in the appropriate version of ruby:

    $ gem install git_sme
    
This will install the git-sme command which should now be available from everywhere assuming your
PATH is setup appropriately.

## Usage

Basic usage of git-sme is as follows:

    git-sme </path/to/repository> [flags]

This will throw an error if the path is not a git repository.  As a rule, you don't have to point to
the `.git` folder in your checked out code because `git-sme` will know to look for that folder as a
child of the folder you **do** provide it.

`git-sme` will output a list of paths (files and directories) and the list of users who it thinks
are the subject matter experts on each of those paths.  Users are listed in decreasing order of
expertise:

    $ bundle exec git-sme ~/rails/dinghy --file ~/rails/dinghy/cli/dinghy/preferences.rb ~/rails/dinghy/cli/dinghy/machine.rb
    Repository: /Users/sjaveed/rails/dinghy
    Analyzed: 317 (0/s) 100.00% Time: 00:00:00 |=======================================================================================================|
    
    /: brianp, ryan, brian, adrian.falleiro, sally, dev, markse, fgrehm, kallin.nagelberg, matt
    /cli: brianp, ryan, markse, sally, adrian.falleiro, fgrehm, matt, kallin.nagelberg, brian, dev
    /cli/dinghy: brianp, markse, ryan, sally, fgrehm, matt, adrian.falleiro, brian, aisipos, paul.moelders
    /cli/dinghy/machine.rb: brianp, markse, sally, brian, fgrehm, ryan, robertc
    /cli/dinghy/preferences.rb: brianp
    /cli/dinghy/machine: brianp, ryan, fgrehm
    /dinghy: brianp

Based on analysis of a checked out copy of dinghy, I can see that, for the files I'm interested in,
brianp would be a subject matter expert but I'll probably find some useful information from ryan and
markse as well since it looks like ryan has touched enough files in the `/cli/dinghy/machine`
directory

### Flags

Flag | Description
-----|------------
`--branch <branch>` | The branch you want to analyze on the given repository.  Defaults to 'master'.
`--user <username1 [username2 ...]>` | An optional list of users to whom you'd like to restrict the analysis.  This allows you to see e.g. who might know more about a file given their history of working with it over time.
`--file </path/to/file [/path/to/other/file ...]` | An optional list of files/directories for which you'd like analysis.  Defaults to /.  The analysis will also include all directories between a subdirectory and the root of the repository.  All file paths are relative to the repository root.
`--cache` | This is a default specification which caches all commits that the tool loads for a git repository.  This allows you to e.g. `git pull` on a large repository and only incur the cost of loading the additional commits from the repository while previously seen commits are loaded a lot quicker from a cache.
`--no-cache` | Specify this if you do *not* want caching.  You'll probably never need to use this.
`--results <count>` | The number of subject matter experts you'd like to see for each path.  Defaults to 10.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sjaveed/git_sme. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [GPLv3 License](https://www.gnu.org/licenses/gpl-3.0.en.html).

## Code of Conduct

Everyone interacting in the GitSme project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/sjaveed/git_sme/blob/master/CODE_OF_CONDUCT.md).
