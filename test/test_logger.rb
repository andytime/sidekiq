# frozen_string_literal: true

require_relative 'helper'
require 'sidekiq/logger'

class TestLogger < Minitest::Test
  def setup
    @output = StringIO.new
    @logger = Sidekiq::Logger.new(@output)

    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  def teardown
    Thread.current[:sidekiq_context] = nil
    Thread.current[:sidekiq_tid] = nil
  end

  def test_format_selection
    assert_kind_of Sidekiq::Logger::Formatters::Pretty, Sidekiq::Logger.new(STDOUT).formatter
    begin
      ENV['DYNO'] = 'dyno identifier'
      assert_kind_of Sidekiq::Logger::Formatters::WithoutTimestamp, Sidekiq::Logger.new(STDOUT).formatter
    ensure
      ENV['DYNO'] = nil
    end

    begin
      Sidekiq.log_format = :json
      assert_kind_of Sidekiq::Logger::Formatters::JSON, Sidekiq::Logger.new(STDOUT).formatter
    ensure
      Sidekiq.log_format = nil
    end
  end

  def test_with_context
    subject = @logger
    assert_equal({}, subject.ctx)

    subject.with_context(a: 1) do
      assert_equal({ a: 1 }, subject.ctx)
    end

    assert_equal({}, subject.ctx)
  end

  def test_nested_contexts
    subject = @logger
    assert_equal({}, subject.ctx)

    subject.with_context(a: 1) do
      assert_equal({ a: 1 }, subject.ctx)

      subject.with_context(b: 2, c: 3) do
        assert_equal({ a: 1, b: 2, c: 3 }, subject.ctx)
      end

      assert_equal({ a: 1 }, subject.ctx)
    end

    assert_equal({}, subject.ctx)
  end

  def test_formatted_output
    @logger.info("hello world")
    assert_match(/INFO: hello world/, @output.string)
    reset(@output)

    formats = [ Sidekiq::Logger::Formatters::Pretty,
                Sidekiq::Logger::Formatters::WithoutTimestamp,
                Sidekiq::Logger::Formatters::JSON, ]
    formats.each do |fmt|
      @logger.formatter = fmt.new
      @logger.with_context(class: 'HaikuWorker', bid: 'b-1234abc') do
        @logger.info("hello context")
      end
      assert_match(/INFO/, @output.string)
      assert_match(/hello context/, @output.string)
      assert_match(/b-1234abc/, @output.string)
      reset(@output)
    end
  end

  def test_json_output_is_parsable
    @logger.formatter = Sidekiq::Logger::Formatters::JSON.new

    @logger.debug("boom")
    @logger.with_context(class: 'HaikuWorker', jid: '1234abc') do
      @logger.info("json format")
    end
    a, b = @output.string.lines
    hash = JSON.parse(a)
    keys = hash.keys.sort
    assert_equal ["lvl", "msg", "pid", "tid", "ts"], keys
    assert_nil hash["ctx"]
    assert_equal hash["lvl"], "DEBUG"

    hash = JSON.parse(b)
    keys = hash.keys.sort
    assert_equal ["ctx", "lvl", "msg", "pid", "tid", "ts"], keys
    refute_nil hash["ctx"]
    assert_equal "1234abc", hash["ctx"]["jid"]
    assert_equal "INFO", hash["lvl"]
  end

  def reset(io)
    io.truncate(0)
    io.rewind
  end
end