class QuestionsController < ApplicationController
  def index
    @broker = QuestionBroker.instance
    @questions = AgentQuestion.order(created_at: :desc).limit(50)
  end
  def reply
    row = AgentQuestion.find(params[:id])
    raise ArgumentError, "Sensitive questions must be answered in the original agent" if row.secret?
    answers = params.require(:answers).permit!.to_h
    QuestionBroker.instance.answer(row, answers)
    redirect_to questions_path, notice: "Reply submitted on the original connection; awaiting runtime confirmation.", status: :see_other
  rescue ArgumentError, ActionController::ParameterMissing => e
    redirect_to questions_path, alert: e.message, status: :see_other
  end
  def suggest
    started = QuestionSuggestions.instance.start(AgentQuestion.find(params[:id]), context: params[:context].to_s.first(2000))
    render json: {state: "running", started: started}, status: :accepted
  rescue ArgumentError => e
    render json: {state: "unavailable", message: e.message}, status: :unprocessable_entity
  end
  def suggestion_status
    render json: QuestionSuggestions.instance.status(AgentQuestion.find(params[:id]))
  end
  def cancel_suggestion
    QuestionSuggestions.instance.cancel(AgentQuestion.find(params[:id]))
    render json: {state: "cancelled", message: "Cancelled. No reply was sent."}
  end
end
