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

require "bundler"
require "digest/md5"
require "logger"
require "optparse"
require "ostruct"
require "pathname"

# Contains class methods that support rbenv-bundler's rehash hook.
#
# @author Roy Liu
class RbenvBundler
  class << self
    attr_reader :logger
  end

  @logger = Logger.new(STDERR)
  @logger.level = Logger::ERROR
  @logger.formatter = proc do |severity, datetime, progname, message|
    message.chomp("\n") + "\n"
  end

  # Gets the gemspecs associated with the given Gemfile.
  #
  # Word of warning: This method manipulates Bundler internals in obscure ways and is not guaranteed to work in the
  # future.
  #
  # @param [Pathname] gemfile the Gemfile.
  # @param [Pathname] gem_dir the additional gem directory to search.
  #
  # @return [Array] the gemspecs resolved by Bundler.
  def self.gemspecs(gemfile, gem_dir = Pathname.new(""))
    # Save old environment variables so that they can be restored later.
    old_bundle_gemfile = ENV.delete("BUNDLE_GEMFILE")
    old_gem_home = ENV.delete("GEM_HOME")
    old_gem_path = ENV.delete("GEM_PATH")

    # Override the Gemfile location.
    ENV["BUNDLE_GEMFILE"] = gemfile.expand_path.to_s

    bundler_settings = Bundler::Settings.new(Bundler.app_config_path)
    bundle_path = Pathname.new(bundler_settings.path).expand_path(Bundler.root)
    rubygems_dir = Bundler.rubygems.gem_dir
    rubygems_path = Bundler.rubygems.gem_path
    bundler_gemfile = Bundler.default_gemfile
    bundler_lockfile = Bundler.default_lockfile

    if bundle_path.to_s != rubygems_dir
      # The user specified a bundle path.
      if bundler_settings[:disable_shared_gems]
        # Shared gems are disabled; search only the bundle path.
        ENV["GEM_HOME"] = bundle_path.to_s
        ENV["GEM_PATH"] = ""
      else
        # Shared gems are enabled; search the bundle path and existing paths.
        ENV["GEM_HOME"] = bundle_path.to_s
        ENV["GEM_PATH"] = [gem_dir.to_s, *rubygems_path.select { |dir| dir != rubygems_dir }] \
          .compact.uniq \
          .select { |dir| !dir.empty? } \
          .join(File::PATH_SEPARATOR)
      end
    else
      # The user didn't specify a bundle path.
      ENV["GEM_HOME"] = gem_dir.to_s
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

      if pid = Process.fork
        child_out.close
        gemspecs = YAML::load(child_in)
        child_in.close

        Process.waitpid2(pid)

        gemspecs
      else
        child_in.close

        begin
          gemspecs = runtime.specs
        rescue Bundler::GemNotFound => e
          logger.warn("Bundler gave the error \"#{e.message.gsub("\"", "\\\"")}\"" \
            " while processing \"#{bundler_gemfile.to_s.gsub("\"", "\\\"")}\"." \
            " Perhaps you forgot to run \"bundle install\"?")
          gemspecs = []
        end

        gemspecs = gemspecs.map { |gemspec| OpenStruct.new(:bin_dir => gemspec.bin_dir,
                                                           :executables => gemspec.executables) }

        YAML::dump(gemspecs, child_out)
        child_out.close

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
  def self.rehash(manifest_map, out_dir = Pathname.new("."))
    raise "The output directory does not exist" if !out_dir.exist?

    Pathname.new("manifest.txt").expand_path(out_dir).open("w") do |f|
      manifest_map.each do |dir, gemspec_manifest|
        gemfile = gemfile(dir)
        gemspec_manifest.expand_path(out_dir).delete if gemspec_manifest

        next if !gemfile || !ENV["RBENV_ROOT"]

        dir = gemfile.parent
        rbenv_version = rbenv_version(dir)

        # Derive the gem directory of the active Ruby, which isn't necessarily the same as the Ruby running this script.
        if rbenv_version != "system"
          # If the Ruby is rbenv-based, we'll use RBENV_ROOT.
          gem_dir = Pathname.new("versions") \
            .join(rbenv_version, "lib", "ruby", "gems") \
            .expand_path(ENV["RBENV_ROOT"]) \
            .children[0]
        else
          # If the Ruby is the system Ruby, we'll ask the system RubyGems for its "gemdir" property.
          child_env = ENV.to_hash
          child_env.delete("PWD")
          child_env.delete("RBENV_DIR")
          child_env.delete("RBENV_HOOK_PATH")
          child_env.delete("RBENV_ROOT")

          # Pop off the first bin directory, which contains the script Ruby.
          child_env["PATH"] = child_env["PATH"].split(":", -1)[1..-1].join(":")

          gem_dir = Pathname.new(IO.popen([child_env, "gem", "environment", "gemdir",
                                           :chdir => dir,
                                           :unsetenv_others => true]) { |child_out| child_out.read.chomp("\n") })
        end

        gemspec_manifest = Pathname.new("#{Digest::MD5.hexdigest(dir.to_s)}.txt")

        f.write(dir.to_s + "\n")
        f.write(gemspec_manifest.to_s + "\n")

        gemspec_manifest.expand_path(out_dir).open("w") do |f|
          gemspecs(gemfile, gem_dir).each do |gemspec|
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
end

if __FILE__ == $0
  opts = {
      :out_dir => Pathname.new("."),
      :refresh => false,
      :verbose => false
  }

  positional_args = OptionParser.new do |opt_spec|
    opt_spec.banner = "usage: #{File.basename(__FILE__)} [<options>] [[--] <dir>...]"

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

  dirs = positional_args.map { |arg| RbenvBundler.gemfile(Pathname.new(arg)) }.compact.map { |gemfile| gemfile.parent }

  # Merge in the contents of the current manifest if the "refresh" switch is provided.
  manifest_map = Hash[dirs.zip([nil] * dirs.size)]
  manifest_map = manifest_map.merge(RbenvBundler.read_manifest(opts[:out_dir])) if opts[:refresh]

  RbenvBundler.rehash(manifest_map, opts[:out_dir])
end
