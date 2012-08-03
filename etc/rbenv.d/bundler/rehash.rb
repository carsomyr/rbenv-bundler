#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# Copyright (C) 2012 Roy Liu
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#   * Redistributions of source code must retain the above copyright notice,
#     this list of conditions and the following disclaimer.
#   * Redistributions in binary form must reproduce the above copyright notice,
#     this list of conditions and the following disclaimer in the documentation
#     and/or other materials provided with the distribution.
#   * Neither the name of the author nor the names of any contributors may be
#     used to endorse or promote products derived from this software without
#     specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

SEMANTIC_RUBY_VERSION = RUBY_VERSION.split(".", -1).map { |s| s.to_i }

# Ruby 1.8 compatibility: Explicitly require RubyGems.
require "rubygems" if (SEMANTIC_RUBY_VERSION <=> [1, 9]) < 0
require "bundler"
require "digest/md5"
require "logger"
require "optparse"
require "ostruct"
require "pathname"

# Monkey patch Bundler to make it more stateless.
module Bundler
  class << self
    attr_accessor :ruby_profile
  end

  def self.bundle_path
    Pathname.new(settings.path).expand_path(root)
  end

  def self.settings
    Settings.new(app_config_path)
  end

  def self.ruby_scope
    Pathname.new(ruby_profile.gem_ruby_engine).join(ruby_profile.gem_ruby_version).to_s
  end
end

# Contains class methods that support rbenv-bundler's rehash hook.
#
# @author Roy Liu
class RbenvBundler
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
  # @param [Pathname] gemfile the Gemfile.
  #
  # @return [Array] the gemspecs resolved by Bundler.
  def self.gemspecs(gemfile)
    # Save old environment variables so that they can be restored later.
    old_bundle_gemfile = ENV.delete("BUNDLE_GEMFILE")
    old_gem_home = ENV.delete("GEM_HOME")
    old_gem_path = ENV.delete("GEM_PATH")

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

    Bundler.rubygems.clear_paths
    Bundler.rubygems.refresh

    runtime = Bundler::Runtime.new(bundler_gemfile.parent,
                                   Bundler::Definition.build(bundler_gemfile, bundler_lockfile, nil))

    begin
      # We need to fork here: Bundler may load .gemspec files that irreversibly modify the Ruby state.
      child_in, child_out = IO.pipe

      pid = Process.fork

      if !pid.nil?
        child_out.close
        gemspecs = YAML.load(child_in) || []
        child_in.close

        Process.waitpid2(pid)

        gemspecs
      else
        child_in.close

        begin
          YAML.dump(runtime.specs.map { |gemspec| OpenStruct.new(:bin_dir => gemspec.bin_dir,
                                                                 :executables => gemspec.executables) }, child_out)
        rescue Bundler::GemNotFound, Bundler::GitError => e
          logger.warn("Bundler gave the error #{e.message.dump} while processing #{bundler_gemfile.to_s.dump}." \
            " Perhaps you forgot to run \"bundle install\"?")
        ensure
          child_out.close
        end

        exit!
      end
    ensure
      # Restore old environment variables for later reuse.
      ENV["BUNDLE_GEMFILE"] = old_bundle_gemfile
      ENV["GEM_HOME"] = old_gem_home
      ENV["GEM_PATH"] = old_gem_path

      Bundler.rubygems.clear_paths
      Bundler.rubygems.refresh
    end
  end

  # Finds the Bundler Gemfile starting from the given directory.
  #
  # @param [Pathname] dir the directory to start searching from.
  #
  # @return [Pathname] the Gemfile, or nil if it doesn't exist.
  def self.gemfile(dir = Pathname.new("."))
    dir = dir.expand_path

    while (parent = dir.parent) != dir
      gemfile = Pathname.new("Gemfile").expand_path(dir)

      return gemfile if gemfile.exist?

      dir = parent
    end

    nil
  end

  # Finds the rbenv Ruby version starting from the given directory.
  #
  # @param [Pathname] dir the directory to start searching from.
  #
  # @return [String] the rbenv Ruby version, or "system" if an rbenv Ruby could not be found.
  def self.rbenv_version(dir = Pathname.new("."))
    dir = dir.expand_path

    version_files = []

    while (parent = dir.parent) != dir
      version_files << Pathname.new(".rbenv-version").expand_path(dir)
      dir = parent
    end

    version_files << Pathname.new("version").expand_path(ENV["RBENV_ROOT"])

    version_files.each do |version_file|
      return version_file.open("r") { |f| f.read.chomp("\n") } if version_file.exist?
    end

    "system"
  end

  # Rehashes the given Bundler-controlled directories and builds a manifest from them, so that the Bash side of
  # rbenv-bundler can use it to answer "rbenv which" queries.
  #
  # @param [Hash] manifest_map the Hash from Bundler-controlled directories to gemspec manifests.
  # @param [Pathname] out_dir the output directory.
  def self.rehash(ruby_profile_map, manifest_map, out_dir = Pathname.new("."))
    raise "The output directory does not exist" if !out_dir.exist?

    Pathname.new("manifest.txt").expand_path(out_dir).open("w") do |f|
      manifest_map.each do |dir, manifest_file|
        gemfile = gemfile(dir)
        manifest_file.expand_path(out_dir).delete if !manifest_file.nil?

        next if gemfile.nil?

        dir = gemfile.parent
        ruby_profile = ruby_profile_map[rbenv_version(dir)]

        next if ruby_profile.nil?

        # Fake the Ruby implementation to induce correct Bundler search behavior.
        Bundler.ruby_profile = ruby_profile

        manifest_file = Pathname.new("#{Digest::MD5.hexdigest(dir.to_s)}.txt")

        f.write(dir.to_s + "\n")
        f.write(manifest_file.to_s + "\n")

        manifest_file.expand_path(out_dir).open("w") do |f|
          gemspecs(gemfile).each do |gemspec|
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

    nil
  end

  # Reads in the current manifest if it exists.
  #
  # @param [Pathname] out_dir the output directory where the current manifest file might reside.
  #
  # @return [Hash] a Hash from Bundler-controlled directories to gemspec manifests.
  def self.read_manifest(out_dir = Pathname.new("."))
    manifest_file = Pathname.new("manifest.txt").expand_path(out_dir)

    return {} if !manifest_file.exist?

    manifest_file.open("r") do |f|
      Hash[*(f.read.split("\n", -1)[0...-1].map { |pathname| Pathname.new(pathname) })]
    end
  end

  # Builds rbenv Ruby profiles. With comprehensive knowledge of each Ruby(Gems) implementation's version information and
  # directory structure, the script can configure Bundler to exhibit the correct search behavior, despite it being meant
  # for operation with just the script Ruby(Gems).
  #
  # @param [Pathname] out_dir the output directory where the current Ruby profiles file might reside.
  #
  # @return [Hash] a Hash from rbenv version names to Ruby profiles.
  def self.build_ruby_profiles(out_dir = Pathname.new("."))
    ruby_profiles_file = Pathname.new("ruby_profiles.yml").expand_path(out_dir)
    rbenv_versions_dir = Pathname.new("versions").expand_path(ENV["RBENV_ROOT"])
    rbenv_version_dirs = rbenv_versions_dir.children

    if ruby_profiles_file.exist? && rbenv_versions_dir.mtime <= ruby_profiles_file.mtime
      ruby_profiles_file.open("r") do |f|
        YAML.load(f)
      end
    else
      return {} if (SEMANTIC_RUBY_VERSION <=> [1, 9]) < 0

      rbenv_versions = rbenv_version_dirs.map { |rbenv_version_dir| rbenv_version_dir.basename.to_s }.push("system")

      ruby_profile_map = Hash[rbenv_versions.map do |rbenv_version|
        child_env = ENV.to_hash
        child_env.delete("PWD")
        child_env.delete("RBENV_DIR")
        child_env.delete("RBENV_HOOK_PATH")
        child_env.delete("RBENV_ROOT")

        # Pop off the first bin directory, which contains the script Ruby.
        child_env["PATH"] = child_env["PATH"].split(":", -1)[1..-1].join(":")
        child_env["RBENV_VERSION"] = rbenv_version

        ruby_profile = IO.popen([child_env, "ruby",
                                 "-r", "rubygems",
                                 "-e", "puts RUBY_VERSION\n" \
                                  "puts Gem.dir\n" \
                                  "puts Gem.ruby_engine\n" \
                                  "puts Gem::ConfigMap[:ruby_version]\n",
                                 # Ruby 1.8 compatibility: Declare Hashes explicitly when embedded in Array literals.
                                 {:unsetenv_others => true}]) do |child_out|
          child_out_s = child_out.read

          # If the child's output is empty, the rbenv Ruby is likely nonexistent.
          next nil if child_out_s.empty?

          values = child_out_s.split("\n", -1)[0...-1]
          OpenStruct.new(:ruby_version => values[0].split(".", -1).map { |s| s.to_i },
                         :gem_dir => Pathname.new(values[1]),
                         :gem_ruby_engine => values[2],
                         :gem_ruby_version => values[3])
        end

        next nil if ruby_profile.nil?

        [rbenv_version, ruby_profile]
      end.select { |entry| !entry.nil? }]

      ruby_profiles_file.open("w") do |f|
        YAML.dump(ruby_profile_map, f)
      end

      ruby_profile_map
    end
  end

  # Ensures that we are running a capable Ruby implementation. If the script Ruby version is inappropriate, the given
  # Ruby profiles will be searched and, if located, an appropriate one will be Kernel.exec'd.
  #
  # @param [Hash] ruby_profile_map a Hash from rbenv version names to Ruby profiles.
  def self.ensure_capable_ruby(ruby_profile_map)
    # Check if the current Ruby is capable.
    return nil if (SEMANTIC_RUBY_VERSION <=> [1, 9]) >= 0 && Gem.ruby_engine != "jruby"

    # Find all Rubies that are 1.9+ and are not JRuby (no Kernel.fork).
    rbenv_versions = ruby_profile_map.select do |_, ruby_profile|
      (ruby_profile.ruby_version <=> [1, 9]) >= 0 && ruby_profile.gem_ruby_engine != "jruby"
    end.map do |entry|
      entry[0]
    end.sort

    if !rbenv_versions.empty?
      # Ruby 1.8 compatibility: Kernel.exec does not accept a Hash of environment variables.
      ENV.delete("PWD")
      ENV.delete("RBENV_DIR")
      ENV.delete("RBENV_HOOK_PATH")
      ENV.delete("RBENV_ROOT")

      ENV["PATH"] = ENV["PATH"].split(":", -1)[1..-1].join(":")
      ENV["RBENV_VERSION"] = rbenv_versions[0]

      exec("rbenv", "exec", "ruby", "--", __FILE__, *ARGV)
    else
      raise "Could not locate a Ruby capable of running this script"
    end
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
      opts[:out_dir] = Pathname.new(out_dir)
    end
  end.parse(ARGV)

  RbenvBundler.logger.level = Logger::WARN if opts[:verbose]

  ruby_profile_map = RbenvBundler.build_ruby_profiles(opts[:out_dir])

  # Try to use a modern Ruby so that the rest of the script doesn't crash and burn.
  RbenvBundler.ensure_capable_ruby(ruby_profile_map)

  dirs = positional_args.map { |arg| RbenvBundler.gemfile(Pathname.new(arg)) }.compact.map { |gemfile| gemfile.parent }

  # Merge in the contents of the current manifest if the "refresh" switch is provided.
  manifest_map = Hash[dirs.zip([nil] * dirs.size)]
  manifest_map = manifest_map.merge(RbenvBundler.read_manifest(opts[:out_dir])) if opts[:refresh]

  RbenvBundler.rehash(ruby_profile_map, manifest_map, opts[:out_dir])
end
