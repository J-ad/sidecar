require_relative "test_helper"
class TodoSidebarTest < ActionDispatch::IntegrationTest
  setup { host! "127.0.0.1" }
  test "open sticky notes stay visible across all source filters independently of search" do
    todo = Todo.create!(title: "Keep this task visible", project_id: "example", checklist: [{"id" => "one", "label" => "Check result", "done" => false}])
    completed = Todo.create!(title: "Completed note", completed_at: Time.current)
    [nil, "codex", "claude", "github"].each do |source|
      get root_path, params: {source: source, q: "unrelated-search", project: "unrelated-project", hidden: "1"}
      assert_response :success
      assert_select '.app-layout > .app-main', count: 1
      assert_select 'aside.todo-sidebar[aria-labelledby="todo-sidebar-heading"]', count: 1
      assert_select "#sidebar-todo-#{todo.id}.sticky-note h3", text: todo.title
      assert_select "#sidebar-todo-#{completed.id}", count: 0
      assert_select '.todo-sidebar-scroll[tabindex="0"]', count: 1
      assert_select '.todo-quick-add[href="/todos/new"]', count: 1
    end
    get edit_todo_path(todo)
    assert_select "#sidebar-todo-#{todo.id}", count: 1
    assert_select '.todo-sidebar button', count: 0
    get questions_path
    assert_select "#sidebar-todo-#{todo.id}", count: 1
  end
  test "sidebar completion returns to the same dashboard filters and preserves todo content" do
    todo = Todo.create!(title: "Complete independently", source_link: "https://example.com/task", notes: "Rich notes")
    patch complete_todo_path(todo), params: {return_to: "dashboard", source: "claude", q: "query", hidden: "1"}
    assert_redirected_to root_path(source: "claude", q: "query", hidden: "1")
    assert todo.reload.completed?
    assert_equal "Rich notes", todo.notes.to_plain_text
    assert_equal "https://example.com/task", todo.source_link
    follow_redirect!
    assert_select "#sidebar-todo-#{todo.id}", count: 0
    patch reopen_todo_path(todo)
    get root_path
    assert_select "#sidebar-todo-#{todo.id}", count: 1
  end
  test "empty sidebar has a clear add action and Todo changes update the revision" do
    get root_path
    assert_select '.todo-sidebar-empty a[href="/todos/new"]', text: "Create your first todo"
    get '/sync-status'
    previous = response.parsed_body['revision']
    Todo.create!(title: "New local note")
    get '/sync-status'
    assert_not_equal previous, response.parsed_body['revision']
  end
end
