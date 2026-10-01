require_relative "test_helper"
require "base64"
require "cgi"

class TodosTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5f8AAAAASUVORK5CYII=")
  setup { host! "127.0.0.1" }

  test "custom todo edit checklist complete and reopen remain independent" do
    post todos_path, params: { todo: { title: "Follow up", project_id: "example", source_link: "https://example.com/task", notes: "<div><strong>Details</strong> <a href='https://example.com'>Link</a></div>", checklist_text: "Review\n[x] Reproduce" } }
    assert_response :see_other
    todo = Todo.last
    assert_nil todo.origin_source
    assert_equal [false, true], todo.checklist.pluck("done")
    follow_redirect!
    assert_select ".todo-notes strong", text: "Details"
    assert_select '.todo-notes a[href="https://example.com"]', text: "Link"
    assert_select '.todo-checklist input[type="checkbox"]', count: 2
    patch check_todo_path(todo), params: { entry_id: todo.checklist.first["id"], done: "1" }
    assert todo.reload.checklist.first["done"]
    patch todo_path(todo), params: { todo: { title: "Updated", checklist_text: "[x] Review\n[x] Reproduce\nShip" } }
    assert_response :see_other
    assert_equal "Updated", todo.reload.title
    get todo_path(todo), headers: {"Accept" => "text/vnd.turbo-stream.html, text/html"}
    assert_equal "text/html", response.media_type
    patch complete_todo_path(todo)
    assert todo.reload.completed?
    get todos_path
    assert_select '.todo-row', count: 0
    get todos_path, params: { completed: "1", project: "example" }
    assert_select '.todo-row h2 a', text: "Updated"
    patch reopen_todo_path(todo)
    assert_not todo.reload.completed?
  end

  test "source snapshots survive archive completion and deletion of every source type" do
    Item::SOURCES.each do |source|
      item = row("durable-#{source}", source, source_url: source == "codex" ? "codex://threads/id" : "https://example.com/#{source}", project_id: "example")
      get new_todo_path(from_item: item.id)
      assert_select 'input[name="from_item"]', count: 1
      assert_select 'input[name="todo[title]"][value="Source title"]'
      post todos_path, params: { from_item: item.id, todo: { title: "Independent #{source}", notes: "Notes" } }
      todo = Todo.last
      assert_equal source, todo.origin_source
      assert_equal item.external_id, todo.origin_external_id
      assert_equal "Source title", todo.origin_title
      assert_equal item.source_url, todo.origin_url
      patch complete_todo_path(todo)
      assert_not item.reload.dismissed
      item.update!(facts: { "archived" => true, "agent_finished" => true }, dismissed: true)
      patch reopen_todo_path(todo)
      assert_not todo.reload.completed?
      item.destroy!
      get todo_path(todo)
      assert_response :success
      assert_select '.todo-origin code', text: "durable-#{source}"
    end
  end

  test "invalid project title links and excessive content cannot be saved" do
    [ {title: ""}, {title: "x" * 301}, {title: "Task", project_id: "unknown"},
      {title: "Task", source_link: "javascript:alert(1)"}, {title: "Task", source_link: "file:///etc/passwd"},
      {title: "Task", source_link: "https://user:pass@example.com"},
      {title: "Task", checklist_text: (1..101).map { |i| "Task #{i}" }.join("\n")},
      {title: "Task", notes: "x" * 201.kilobytes} ].each do |attrs|
      assert_no_difference "Todo.count" do
        post todos_path, params: {todo: attrs}
        assert_response :unprocessable_entity
      end
    end
  end

  test "notes sanitize executable HTML and discard remote image URLs" do
    post todos_path, params: { todo: { title: "Safe", notes: '<div onclick="alert(1)"><script>alert(1)</script><iframe src="https://evil.example"></iframe><img src="https://evil.example/tracker.png"><a href="javascript:alert(1)">Bad link</a><b>Safe text</b></div>' } }
    assert_response :see_other
    follow_redirect!
    assert_select '.todo-notes script, .todo-notes iframe, .todo-notes img, .todo-notes [onclick], .todo-notes a[href^="javascript:"]', count: 0
    assert_select '.todo-notes b', text: "Safe text"
    assert_not Todo.last.notes.body.to_html.include?("evil.example")
  end

  test "upload real image bytes and render a local attachment in notes" do
    with_upload(PNG, "../../Screenshot.png", "image/png") do |upload|
      post todo_attachments_path, params: {file: upload}
    end
    assert_response :created
    attachment = response.parsed_body
    assert_equal "Screenshot.png", attachment.fetch("filename")
    assert_match %r{\A/todo_attachments/}, attachment.fetch("url")
    post todos_path, params: {todo: {title: "Image notes", notes: "<div>Screenshot</div><action-text-attachment sgid='#{attachment['sgid']}'></action-text-attachment>"}}
    assert_response :see_other
    follow_redirect!
    assert_select '.todo-notes img[src^="/todo_attachments/"]', count: 1
    assert_equal 1, Todo.last.notes.embeds.size
    get edit_todo_path(Todo.last)
    assert_select 'input[name="todo[notes]"]' do |fields|
      assert_includes CGI.unescapeHTML(fields.first["value"]), '"url":"/todo_attachments/'
    end
    get attachment.fetch("url")
    assert_response :success
    assert_equal PNG, response.body.b
    assert_equal "image/png", response.media_type
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "size mime and unsupported attachment checks run on server" do
    [ ["<svg onload='alert(1)'></svg>", "fake.png", "image/png"],
      ["<html>executable</html>", "fake.jpg", "image/jpeg"],
      [PNG + "x" * 10.megabytes, "big.png", "image/png"] ].each do |bytes, name, type|
      assert_no_difference "ActiveStorage::Blob.count" do
        with_upload(bytes, name, type) { |upload| post todo_attachments_path, params: {file: upload} }
        assert_response :unprocessable_entity
      end
    end
    blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(PNG), filename: "outside.png", content_type: "image/png", identify: false)
    get todo_attachment_path(blob.signed_id)
    assert_response :not_found
    post todos_path, params: {todo: {title: "Invalid embed", notes: "<action-text-attachment sgid='#{blob.attachable_sgid}'></action-text-attachment>"}}
    assert_response :unprocessable_entity
    get todo_attachment_path("invalid-signature")
    assert_response :not_found
    assert_raises(ActionController::RoutingError) { post "/rails/active_storage/direct_uploads", params: {} }
  end

  test "uploads and mutations require loopback and same-origin CSRF" do
    post todos_path, params: {todo: {title: "Denied"}}, env: {"REMOTE_ADDR" => "192.0.2.12"}
    assert_response :forbidden
    with_upload(PNG, "screenshot.png", "image/png") do |upload|
      post todo_attachments_path, params: {file: upload}, env: {"REMOTE_ADDR" => "192.0.2.12"}
    end
    assert_response :forbidden
    old = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    assert_raises(ActionController::InvalidAuthenticityToken) do
      post todos_path, params: {todo: {title: "Denied"}}, headers: {"Origin" => "https://evil.example"}
    end
    assert_raises(ActionController::InvalidAuthenticityToken) do
      with_upload(PNG, "screenshot.png", "image/png") { |upload| post todo_attachments_path, params: {file: upload}, headers: {"Origin" => "https://evil.example"} }
    end
  ensure
    ActionController::Base.allow_forgery_protection = old
  end

  private
  def with_upload(bytes, name, type)
    Tempfile.create(["todo-upload", ".bin"]) do |file|
      file.binmode; file.write(bytes); file.flush
      yield Rack::Test::UploadedFile.new(file.path, type, true, original_filename: name)
    end
  end
end
