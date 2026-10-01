require_relative "test_helper"
class HeadlessDraftTest < ActiveSupport::TestCase
  def config(binary, backend = "codex")
    Struct.new(:settings).new({"suggestions" => {"backend" => backend, "codex_binary" => binary, "claude_binary" => binary}})
  end
  def with_cli(response)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "fake-cli")
      File.write(path, "#!#{RbConfig.ruby}\nSTDIN.read\nSTDOUT.write(#{response.inspect})\n")
      File.chmod(0700, path)
      yield path
    end
  end
  test "structured drafts use stdin, isolation flags and no session resume" do
    with_cli('{"answers":{"choice":"Ask for clarification"}}') do |binary|
      runner = HeadlessDraft.new(config(binary))
      result = runner.call([{"id" => "choice", "question" => "Which approach?"}], context: "Only a generic example")
      assert_equal({"choice" => "Ask for clarification"}, result)
      args = runner.command("/tmp/example", "/tmp/schema.json")
      %w[--no-daemon --ephemeral --ignore-user-config --ignore-rules read-only shell_tool apps plugins hooks memories multi_agent].each { |flag| assert_includes args, flag }
      assert_not_includes args, "resume"
      assert_equal "-", args.last
    end
  end
  test "secret, oversized and mismatched responses fail closed" do
    with_cli('{"answers":{"unrelated":"Wrong route"}}') do |binary|
      runner = HeadlessDraft.new(config(binary))
      assert_raises(HeadlessDraft::Failure) { runner.call([{"id" => "x", "isSecret" => true}]) }
      assert_raises(HeadlessDraft::Failure) { runner.call([{"id" => "x", "question" => "a" * 11_000}]) }
      assert_raises(HeadlessDraft::Failure) { runner.call([{"id" => "x", "question" => "Question"}]) }
    end
  end
  test "Claude command removes tools and customizations while using existing login" do
    Dir.mktmpdir do |dir|
      schema = File.join(dir, "schema.json"); File.write(schema, '{}')
      args = HeadlessDraft.new(config("claude", "claude")).command(dir, schema)
      assert_equal "", args[args.index("--tools") + 1]
      %w[--safe-mode --restricted --strict-mcp-config --disable-slash-commands --no-session-persistence].each { |flag| assert_includes args, flag }
      assert_not_includes args, "--bare" # Bare mode does not reuse subscription login.
    end
  end
  test "cancellation terminates only the dedicated drafting subprocess" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "waiting-cli")
      File.write(path, "#!#{RbConfig.ruby}\nSTDIN.read\nsleep 30\n")
      File.chmod(0700, path)
      runner = HeadlessDraft.new(config(path))
      thread = Thread.new do
        begin
          runner.call([{"id" => "q", "question" => "Generic test"}])
        rescue HeadlessDraft::Failure => e
          e.message
        end
      end
      Timeout.timeout(2) { sleep 0.01 until runner.pid }
      runner.cancel
      assert thread.join(2), "Cancelled child must exit promptly"
      assert_match(/failed|cancelled/, thread.value)
      assert_nil runner.pid
    end
  end
  test "Claude primary succeeds or falls back once with provenance" do
    with_cli('{"answers":{"q":"Codex draft"}}') do |binary|
      settings = Struct.new(:settings).new({"suggestions" => {"backend" => "claude", "fallback" => "codex", "claude_binary" => "/missing/claude", "codex_binary" => binary}})
      runner = HeadlessDraft.new(settings)
      assert_equal({"q" => "Codex draft"}, runner.call([{"id" => "q", "question" => "Generic example"}]))
      assert_equal "codex", runner.provider_used
      assert runner.fallback_used
    end
    with_cli('{"structured_output":{"answers":{"q":"Claude draft"}}}') do |binary|
      runner = HeadlessDraft.new(config(binary, "claude"))
      assert_equal({"q" => "Claude draft"}, runner.call([{"id" => "q", "question" => "Generic example"}]))
      assert_equal "claude", runner.provider_used
      assert_not runner.fallback_used
    end
  end
  test "access restriction never falls back and raw diagnostics stay private" do
    Dir.mktmpdir do |dir|
      path = File.join(dir, "denied-cli")
      File.write(path, "#!#{RbConfig.ruby}\nSTDIN.read\nSTDERR.write('access denied: private diagnostic')\nexit 1\n")
      File.chmod(0700, path)
      with_cli('{"answers":{"q":"Should never be used"}}') do |fallback|
        settings = Struct.new(:settings).new({"suggestions" => {"backend" => "claude", "fallback" => "codex", "claude_binary" => path, "codex_binary" => fallback}})
        runner = HeadlessDraft.new(settings)
        error = assert_raises(HeadlessDraft::Failure) { runner.call([{"id" => "q", "question" => "Generic"}]) }
        assert_not error.fallback_allowed?
        assert_not_includes error.message, "private diagnostic"
        assert_nil runner.provider_used
      end
    end
  end
end
