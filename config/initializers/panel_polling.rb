if ENV["WORK_PANEL_BACKGROUND"] == "1" && !Rails.env.test?
  Rails.application.config.after_initialize do
    require Rails.root.join("lib/panel_polling")
    PanelPolling.start
  end
end
