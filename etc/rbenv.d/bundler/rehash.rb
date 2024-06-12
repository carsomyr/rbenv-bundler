#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# Copyright 2012-2021 Roy Liu
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

SEMANTIC_RUBY_VERSION = RUBY_VERSION.split(".", -1).map { |s| s.to_i }

# Ruby 1.8 compatibility: Explicitly require RubyGems.
require "rubygems" if (SEMANTIC_RUBY_VERSION <=> [1, 9]) < 0
require "digest/md5"
require "logger"
require "optparse"
require "ostruct"
require "pathname"
require "yaml"

# Contains module methods that support rbenv-bundler's rehash hook.
#
# @author Roy Liu
module RbenvBundler
  class << self
    attr_reader :logger
  end

  @logger = Logger.new(STDERR)
  @logger.level = Logger::ERROR
  @logger.formatter = Proc.new do |_, _, _, message|
    message.chomp("\n") + "\n"
  end

  # Gets the gemspecs associated with the given Gemfile.
  #
  # Word of warning: This method manipulates Bundler internals in obscure ways and is not guaranteed to work in the
  # future.
  #
  # @param gemfile [Pathname] the Gemfile.
  #
  # @return [Array] the gemspecs resolved by Bundler.
  def self.gemspecs(gemfile)
    # Save old environment variables so that they can be restored later.
    env_old = {"BUNDLE_GEMFILE" => ENV.delete("BUNDLE_GEMFILE"),
               "GEM_HOME" => ENV.delete("GEM_HOME"),
               "GEM_PATH" => ENV.delete("GEM_PATH")}

    # Override the Gemfile location.
    ENV["BUNDLE_GEMFILE"] = gemfile.expand_path.to_s

    bundler_settings = Bundler::Settings.new(Bundler.app_config_path)
    bundler_ruby_profile = Bundler.ruby_profile
    rubygems_dir = Bundler.rubygems.gem_dir
    rubygems_path = Bundler.rubygems.gem_path
    bundler_gemfile = Bundler.default_gemfile
    bundler_lockfile = Bundler.default_lockfile

    if !bundler_settings[:path].nil?
      # The user specified a bundle path.
      bundle_path = Bundler.bundle_path

      if !bundler_settings[:disable_shared_gems].nil?
        # Shared gems are disabled; search only the bundle path.
        ENV["GEM_HOME"] = bundle_path.to_s
        ENV["GEM_PATH"] = ""
      else
        # Shared gems are enabled; search the bundle path and existing paths.
        ENV["GEM_HOME"] = bundle_path.to_s
        ENV["GEM_PATH"] = [bundler_ruby_profile.gem_dir.to_s, *rubygems_path.select { |dir| dir != rubygems_dir }] \
          .compact.uniq \
          .select { |dir| !dir.empty? } \
          .join(File::PATH_SEPARATOR)
      end
    else
      # The user didn't specify a bundle path.
      ENV["GEM_HOME"] = bundler_ruby_profile.gem_dir.to_s
      ENV["GEM_PATH"] = rubygems_path.select { |dir| dir != rubygems_dir } \
        .compact.uniq \
        .select { |dir| !dir.empty? } \
        .join(File::PATH_SEPARATOR)
    end

    Bundler.reset!

    begin
      # We need to fork here: Bundler may load .gemspec files that irreversibly modify the Ruby state.
      child_in, child_out = IO.pipe

      pid = Process.fork

      if !pid.nil?
        child_out.close
        gemspecs = YAML.load(child_in, permitted_classes: [OpenStruct]) || []
        child_in.close

        _, status = Process.waitpid2(pid)

        status.exitstatus == 0 ? gemspecs : nil
      else
        child_in.close

        begin
          YAML.dump(Bundler.definition.specs.map do |gemspec|
            OpenStruct.new(:bin_dir => gemspec.bin_dir, :executables => gemspec.executables)
          end, child_out)

          success = true
        rescue Bundler::GemNotFound, Bundler::GitError => e
          logger.warn("Bundler gave the error #{e.message.dump} while processing #{bundler_gemfile.to_s.dump}." \
            " Perhaps you forgot to run \"bundle install\"?")

          success = false
        ensure
          child_out.close
        end

        exit!(success)
      end
    ensure
      # Restore old environment variables for later reuse.
      ENV.update(env_old)

      Bundler.reset!
    end
  end

  # Finds the Gemfile starting from the given directory.
  #
  # @param dir [Pathname] the directory to start searching from.
  #
  # @return [Pathname] the Gemfile, or nil if it doesn't exist.
  def self.gemfile(dir = Pathname.new("."))
    dir = dir.expand_path

    while (parent = dir.parent) != dir
      gemfile = Pathname.new("Gemfile").expand_path(dir)

      return gemfile if gemfile.file?

      dir = parent
    end

    nil
  end

  # Finds the rbenv Ruby version starting from the given directory.
  #
  # @param dir [Pathname] the directory to start searching from.
  #
  # @return [String] the rbenv Ruby version, or "system" if an rbenv Ruby could not be found.
  def self.rbenv_version(dir = Pathname.new("."))
    dir = dir.expand_path

    version_files = []

    while (parent = dir.parent) != dir
      version_files \
        .push(Pathname.new(".ruby-version").expand_path(dir)) \
        .push(Pathname.new(".rbenv-version").expand_path(dir))
      dir = parent
    end

    version_files.push(Pathname.new("version").expand_path(ENV["RBENV_ROOT"]))

    version_files.each do |version_file|
      return version_file.open("rb") { |f| f.read.chomp("\n") } if version_file.file?
    end

    "system"
  end

  # Rehashes the given Bundler-controlled directories and builds a manifest from them, so that the Bash side of
  # rbenv-bundler can use it to answer "rbenv which" queries.
  #
  # @param manifest_map [Hash] the `Hash` from Bundler-controlled directories to gemspec manifests.
  # @param out_dir [Pathname] the output directory.
  def self.rehash(ruby_profile_map, manifest_map, out_dir = Pathname.new("."))
    Pathname.new("manifest.txt").expand_path(out_dir).open("wb") do |f|
      manifest_map.each do |gemfile, manifest_file|
        next if !gemfile.file?

        manifest_file.expand_path(out_dir).delete if !manifest_file.nil?

        ruby_profile = ruby_profile_map[rbenv_version(gemfile.parent)]

        next if ruby_profile.nil?

        # Fake the Ruby implementation to induce correct Bundler search behavior.
        Bundler.ruby_profile = ruby_profile

        gemspecs = gemspecs(gemfile)

        if !gemspecs.nil?
          manifest_file = Pathname.new("#{Digest::MD5.hexdigest(gemfile.to_s)}.txt")

          f.write(gemfile.to_s + "\n")
          f.write(manifest_file.to_s + "\n")

          manifest_file.expand_path(out_dir).open("wb") do |f|
            gemspecs.each do |gemspec|
              gemspec.executables.each do |executable|
                # We don't rehash the Bundler executable; otherwise, undesirable recursion would result.
                next if executable == "bundle"

                f.write(executable + "\n")
                f.write(gemspec.bin_dir + "\n")
              end
            end
          end
        end
      end
    end

    nil
  end

  # Reads in the current manifest if it exists.
  #
  # @param out_dir [Pathname] the output directory where the current manifest file might reside.
  #
  # @return [Hash] a `Hash` from Bundler-controlled directories to gemspec manifests.
  def self.read_manifest(out_dir = Pathname.new("."))
    manifest_file = Pathname.new("manifest.txt").expand_path(out_dir)

    return {} if !manifest_file.file?

    manifest_file.open("rb") do |f|
      Hash[*(f.read.split("\n", -1)[0...-1].map { |pathname| Pathname.new(pathname) })]
    end
  end

  # Trim the first component of the `PATH` environment variable if it belongs to an rbenv Ruby.
  def self.trim_path!
    return nil if !ENV["RBENV_VERSION"] || ENV["RBENV_VERSION"] == "system"

    path_dirs = ENV["PATH"].split(":", -1).map { |s| Pathname.new(s) }

    ENV["PATH"] = path_dirs[1..-1].map { |dir| dir.to_s }.join(":") \
      if path_dirs[0] == Pathname.new("versions").join(ENV["RBENV_VERSION"], "bin").expand_path(ENV["RBENV_ROOT"])

    nil
  end

  # Builds rbenv Ruby profiles. With comprehensive knowledge of each Ruby(Gems) implementation's version information and
  # directory structure, the script can configure Bundler to exhibit the correct search behavior, despite it being meant
  # for operation with just the script Ruby(Gems).
  #
  # @param out_dir [Pathname] the output directory where the current Ruby profiles file might reside.
  #
  # @return [Hash] a `Hash` from rbenv version names to Ruby profiles.
  def self.build_ruby_profiles(out_dir = Pathname.new("."))
    ruby_profiles_file = Pathname.new("ruby_profiles.yml").expand_path(out_dir)

    if ruby_profiles_file.file?
      ruby_profile_map = ruby_profiles_file.open("rb") do |f|
        YAML.load(f, permitted_classes: [OpenStruct, Pathname])
      end
    else
      ruby_profile_map = {}
    end

    ruby_profile_map_old = ruby_profile_map.clone

    rbenv_versions_dir = Pathname.new("versions").expand_path(ENV["RBENV_ROOT"])
    rbenv_versions_dir.mkpath

    rbenv_versions_dir.children \
      .map { |rbenv_version_dir| rbenv_version_dir.basename.to_s } \
      .push("system") \
      .select { |rbenv_version| !ruby_profile_map.include?(rbenv_version) } \
      .each do |rbenv_version|
      env_old = {"PATH" => ENV["PATH"],
                 "PWD" => ENV.delete("PWD"),
                 "RBENV_DIR" => ENV.delete("RBENV_DIR"),
                 "RBENV_HOOK_PATH" => ENV.delete("RBENV_HOOK_PATH"),
                 "RBENV_VERSION" => ENV["RBENV_VERSION"]}
      trim_path!

      ENV["RBENV_VERSION"] = rbenv_version

      begin
        IO.popen("rbenv exec ruby -r rubygems -e \"" \
                  "puts RUBY_VERSION\n" \
                  "puts Gem.dir\n" \
                  "puts Gem.ruby_engine\n" \
                  "puts Gem::ConfigMap[:ruby_version]\n" \
                  "\"") do |child_out|
          child_out_s = child_out.read

          # If the child's output is empty, the rbenv Ruby is likely nonexistent.
          next if child_out_s.empty?

          values = child_out_s.split("\n", -1)[0...-1]
          ruby_profile_map[rbenv_version] = OpenStruct.new(
              :ruby_version => values[0].split(".", -1).map { |s| s.to_i },
              :gem_dir => Pathname.new(values[1]),
              :gem_ruby_engine => values[2],
              :gem_ruby_version => values[3]
          )
        end
      ensure
        ENV.update(env_old)
      end
    end

    ruby_profile_map = ruby_profile_map.select do |rbenv_version, _|
      Pathname.new(rbenv_version).expand_path(rbenv_versions_dir).directory? || rbenv_version == "system"
    end

    # Ugh, Ruby 1.8 quirks.
    ruby_profile_map = Hash[ruby_profile_map] if ruby_profile_map.is_a?(Array)

    if ruby_profile_map != ruby_profile_map_old
      ruby_profiles_file.open("w") do |f|
        YAML.dump(ruby_profile_map, f)
      end
    end

    ruby_profile_map
  end

  # Ensures that we are running a capable Ruby implementation. If the script Ruby version is inappropriate, the given
  # Ruby profiles will be searched and, if located, an appropriate one will be `Kernel#exec`'d.
  #
  # @param ruby_profile_map [Hash] a `Hash` from rbenv version names to Ruby profiles.
  def self.ensure_capable_ruby(ruby_profile_map)
    # Check if the current Ruby is capable.
    return nil if (SEMANTIC_RUBY_VERSION <=> [1, 9]) >= 0 && Gem.ruby_engine != "jruby"

    # Find all Rubies that are 1.9+ and are not JRuby (no Kernel#fork).
    rbenv_versions = ruby_profile_map.select do |_, ruby_profile|
      (ruby_profile.ruby_version <=> [1, 9]) >= 0 && ruby_profile.gem_ruby_engine != "jruby"
    end.map do |entry|
      entry[0]
    end.sort

    if !rbenv_versions.empty?
      # Ruby 1.8 compatibility: Kernel#exec does not accept a Hash of environment variables.
      ENV.delete("PWD")
      ENV.delete("RBENV_DIR")
      ENV.delete("RBENV_HOOK_PATH")

      trim_path!

      ENV["RBENV_VERSION"] = rbenv_versions[0]

      exec("rbenv", "exec", "ruby", "--", __FILE__, *ARGV)
    else
      raise "Could not locate a Ruby capable of running this script"
    end
  end

  # Monkey patches Bundler and RubyGems to allow repeated use over multiple Gemfiles.
  def self.patch_bundler_and_rubygems
    begin
      require "bundler"
    rescue LoadError
      logger.warn("Could not load the bundler gem for Ruby version #{RUBY_VERSION}-p#{RUBY_PATCHLEVEL}.")
      exit!(false)
    end

    # Monkey patch Bundler to make it more stateless.
    Bundler.module_eval do
      class << self
        attr_accessor :ruby_profile
      end

      def self.bundle_path
        path = settings.path

        # Special handling for Bundler version 1.16 and later.
        if defined?(Bundler::Settings::Path) && path.instance_of?(Bundler::Settings::Path)
          path = path.path
        end

        Pathname.new(path).expand_path(root)
      end

      def self.settings
        Bundler::Settings.new(app_config_path)
      end

      def self.ruby_scope
        Pathname.new(ruby_profile.gem_ruby_engine).join(ruby_profile.gem_ruby_version).to_s
      end
    end

    # Spoof the RubyGems platform. This is necessary because the Ruby parsing the Gemfile may have a platform different
    # from the project Ruby.

    Gem.class_eval do
      def self.platforms
        [Gem::Platform::RUBY, Gem::Platform.local]
      end
    end

    Gem::Platform.class_eval do
      class << self
        alias_method :original_local, :local
      end

      def self.local
        gem_ruby_engine = Bundler.ruby_profile.gem_ruby_engine

        case gem_ruby_engine
        when "ruby", "rbx"
          original_local
        when "jruby"
          Gem::Platform::JAVA
        else
          raise "Unknown gem Ruby engine #{gem_ruby_engine.dump}"
        end
      end
    end

    nil
  end
end

if __FILE__ == $0
  opts = {
      :out_dir => Pathname.new("."),
      :refresh => false,
      :verbose => false
  }

  positional_args = OptionParser.new do |opt_spec|
    opt_spec.banner = "usage: #{Pathname.new(__FILE__).basename} [<options>] [[--] <dir>...]"

    opt_spec.separator ""
    opt_spec.separator "optional arguments:"

    opt_spec.on("-r", "--refresh", "refresh the manifest by merging in previous values") do
      opts[:refresh] = true
    end

    opt_spec.on("-v", "--verbose", "be verbose") do
      opts[:verbose] = true
    end

    opt_spec.on("-o", "--out-dir OUT_DIR", "output metadata files to this directory") do |out_dir|
      p = Pathname.new(out_dir)
      p.mkpath

      opts[:out_dir] = p
    end
  end.parse(ARGV)

  RbenvBundler.logger.level = Logger::WARN if opts[:verbose]

  ruby_profile_map = RbenvBundler.build_ruby_profiles(opts[:out_dir])

  # Try to use a modern Ruby so that the rest of the script doesn't crash and burn.
  RbenvBundler.ensure_capable_ruby(ruby_profile_map)

  # Time to require Bundler and override some of its functionality.
  RbenvBundler.patch_bundler_and_rubygems

  gemfiles = (ENV.has_key?("BUNDLE_GEMFILE") ? [Pathname.new(ENV["BUNDLE_GEMFILE"]).expand_path] : []) \
    .concat(positional_args.map { |arg| RbenvBundler.gemfile(Pathname.new(arg)) }).compact

  # Merge in the contents of the current manifest if the "refresh" switch is provided.
  manifest_map = Hash[gemfiles.zip([nil] * gemfiles.size)]
  manifest_map = manifest_map.merge(RbenvBundler.read_manifest(opts[:out_dir])) if opts[:refresh]

  RbenvBundler.rehash(ruby_profile_map, manifest_map, opts[:out_dir])
end
