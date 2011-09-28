# rbenv-bundler: A Bundler Plugin for rbenv

This plugin transparently makes rbenv's shims aware of bundle installation
paths. It saves you from the hassle of having to type `bundle exec ${command}`
when working with per-project gemsets and will enable `rbenv which ${command}`
to report Bundler-installed gem executables if available.

### Installation

1. Get [rbenv](https://github.com/sstephenson/rbenv) working. Read the
   documentation thoroughly and be sure to set up your Bash environment
   correctly.

2. Install the plugin.

        $ git clone -- git@github.com:carsomyr/rbenv-bundler \
          ~/.rbenv/plugins/bundler

### Usage

1. Just as you would run `rbenv rehash` upon installation of a new Ruby
   distribution or a gem with associated executable, you will also need to run
   it inside Bundler-controlled project directories with local, rbenv-installed
   Ruby versions set.

        $ # Suppose the project uses Ruby version 1.8.7-p352.
        $ rbenv local 1.8.7-p352

        $ # Install the version-specific Bundler gem.
        $ gem install bundler

        $ # Suppose you already have a Gemfile.
        $ bundle install --path vendor/local

        $ # Don't forget to rehash!
        $ rbenv rehash

        $ # If "rake" is a Bundler-installed gem executable, report its location
        $ # with "rbenv which". The result should look like
        $ # "${PWD}/vendor/local/ruby/1.8/bin/rake"
        $ rbenv which rake

        $ # Run "rake" without having to type "bundle exec rake".
        $ rake

2. If you wish to disable the plugin, type `rbenv bundler off`. Type `rbenv
   bundler on` to enable.

### Version History

**0.90** (September 28, 2011)

* Update plugin scripts to use the RBENV_DIR environment variable.
* Start release tagging.
