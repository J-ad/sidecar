class TodosController < ApplicationController
  before_action :configuration
  before_action :find_todo, only: [:show, :edit, :update, :complete, :reopen, :check]

  def index
    @completed = params[:completed] == "1"
    @todos = Todo.where(@completed ? "completed_at IS NOT NULL" : "completed_at IS NULL").order(updated_at: :desc)
    @todos = @todos.where(project_id: params[:project]) if params[:project].present?
    @open_count = Todo.where(completed_at: nil).count
  end

  def new
    @source_item = Item.find(params[:from_item]) if params[:from_item].present?
    @todo = @source_item ? Todo.from_item(@source_item) : Todo.new
  end

  def create
    @source_item = Item.find(params[:from_item]) if params[:from_item].present?
    @todo = @source_item ? Todo.from_item(@source_item) : Todo.new
    @todo.assign_attributes(todo_params)
    if @todo.save
      redirect_to @todo, notice: "Todo saved locally.", status: :see_other
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show; end
  def edit; end

  def update
    if @todo.update(todo_params)
      redirect_to @todo, notice: "Todo saved locally.", status: :see_other
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def complete
    @todo.update!(completed_at: Time.current)
    redirect_to @todo, notice: "Todo completed.", status: :see_other
  end

  def reopen
    @todo.update!(completed_at: nil)
    redirect_to @todo, notice: "Todo reopened.", status: :see_other
  end

  def check
    entries = @todo.checklist.deep_dup
    entry = entries.find { |e| e["id"] == params[:entry_id] }
    return head :not_found unless entry
    entry["done"] = params[:done] == "1"
    @todo.update!(checklist: entries)
    redirect_to @todo, status: :see_other
  end

  private

  def configuration
    request.format = :html
    @config = PanelConfig.new
    response.headers["Cache-Control"] = "no-store"
  end

  def find_todo
    @todo = Todo.find(params[:id])
  end

  def todo_params
    params.require(:todo).permit(:title, :project_id, :source_link, :notes, :checklist_text)
  end
end
