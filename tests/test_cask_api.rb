#!/usr/bin/env ruby
# frozen_string_literal: true

# Test suite for the published cask API metadata in api/cask
#
# Tools that install casks without Homebrew (such as mise) read
# api/cask/<token>.json instead of the cask. The release jobs regenerate it
# with scripts/generate-cask-api.rb; these tests catch a cask that changed
# without its metadata following.
#
# Run with: ruby tests/test_cask_api.rb

require 'minitest/autorun'
require 'json'

class TestCaskApi < Minitest::Test
  REPO_ROOT = File.expand_path('..', __dir__)
  CASKS = Dir[File.join(REPO_ROOT, 'Casks', '*.rb')].sort

  def cask_source(path)
    File.read(path)
  end

  def api_json(path)
    JSON.parse(File.read(File.join(REPO_ROOT, 'api', 'cask', "#{File.basename(path, '.rb')}.json")))
  end

  def api_values(json, key)
    [json[key], *json.fetch('variations').values.map { |variation| variation[key] }].compact
  end

  def test_every_cask_has_metadata
    CASKS.each do |path|
      token = File.basename(path, '.rb')
      assert File.exist?(File.join(REPO_ROOT, 'api', 'cask', "#{token}.json")),
             "api/cask/#{token}.json is missing; run brew ruby scripts/generate-cask-api.rb"
    end
  end

  def test_metadata_version_matches_cask
    CASKS.each do |path|
      version = cask_source(path)[/^\s*version "([^"]+)"/, 1]
      assert_equal version, api_json(path)['version'], "#{File.basename(path)} version"
    end
  end

  def test_metadata_covers_every_cask_sha
    CASKS.each do |path|
      shas = cask_source(path).scan(/sha256 "(\h{64})"/).flatten.sort
      assert_equal shas, api_values(api_json(path), 'sha256').sort, "#{File.basename(path)} sha256"
    end
  end

  def test_metadata_urls_point_at_the_cask_build
    CASKS.each do |path|
      build = api_json(path)['version'].split('-').last
      api_values(api_json(path), 'url').each do |url|
        assert_match %r{/download/cask-[a-z]+-#{build}/}, url, "#{File.basename(path)} url"
      end
    end
  end
end
