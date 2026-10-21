# frozen_string_literal: true

# Generate Homebrew API metadata for every cask in this tap
# Usage: brew ruby scripts/generate-cask-api.rb
#
# Writes api/cask/<token>.json in the format formulae.brew.sh serves for
# homebrew/cask, which is where tools that install casks without Homebrew
# (such as mise) look for a tap's metadata. Homebrew only loads casks from
# an installed tap, so the d12frosted/emacs-plus tap must be installed, or
# this checkout linked into its location, with the same Casks/ contents.

require "cask/cask"
require "cask/cask_loader"
require "fileutils"

module CaskApi
  REPO_ROOT = Pathname(__dir__).parent.realpath.freeze
  API_DIR = (REPO_ROOT / "api" / "cask").freeze

  module_function

  # Write api/cask/<token>.json for every cask in the tap
  def generate(tap)
    abort "#{tap.name} is not installed" unless tap.installed?
    tap.cask_files.each { |path| ensure_matches_checkout(path, tap) }

    FileUtils.rm_rf API_DIR
    FileUtils.mkdir_p API_DIR

    host_macos = MacOS.full_version.to_s
    latest_macos = MacOSVersion.new(HOMEBREW_MACOS_NEWEST_SUPPORTED)

    Homebrew::API.with_no_api_env do
      Cask::Cask.generating_hash!

      tap.cask_files.each do |path|
        hash = cask_hash(path, latest_macos)
        hash["variations"] = hash["variations"].merge(macos_variations(path, latest_macos, hash))
        token = hash.fetch("token")
        (API_DIR / "#{token}.json").write("#{JSON.pretty_generate(hash)}\n")
        puts "Generated api/cask/#{token}.json"
      end
    ensure
      MacOS.full_version = host_macos
    end
  end

  # Abort unless the tap's cask is the one in this checkout
  def ensure_matches_checkout(path, tap)
    local = REPO_ROOT / "Casks" / path.basename
    return if local.exist? && local.read == path.read

    abort "#{path} differs from #{local}; update the tap or link this checkout into #{tap.path}"
  end

  # Load the cask as Homebrew sees it on the given macOS release
  def cask_hash(path, macos)
    MacOS.full_version = macos.to_s
    Homebrew::SimulateSystem.with(os: macos.to_sym, arch: :arm) do
      Cask::CaskLoader.load(path).to_hash_with_variations
    end
  end

  # The casks choose their prebuilt binary with `MacOS.version` instead of
  # on_system blocks, so to_hash_with_variations only sees the host release
  # and leaves `variations` empty. Load every older release the cask
  # supports and record what differs from the newest one, keyed by bottle
  # tag like the official API.
  def macos_variations(path, latest_macos, latest_hash)
    requirement = Cask::CaskLoader.load(path).depends_on.macos
    MacOSVersion::SYMBOLS.filter_map do |symbol, version|
      macos = MacOSVersion.new(version)
      next if macos >= latest_macos
      next if requirement && !requirement.allows?(macos)

      diff = cask_hash(path, macos).reject do |key, value|
        key == "variations" || value.to_s == latest_hash[key].to_s
      end
      ["arm64_#{symbol}", diff] unless diff.empty?
    end.to_h
  end
end

CaskApi.generate(Tap.fetch("d12frosted", "emacs-plus"))
