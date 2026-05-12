module ApplicationHelper
  # Retorna true quando a requisição vem do app iOS via Hotwire Native.
  # O Turbo Native injeta "Turbo Native iOS" no User-Agent automaticamente.
  def turbo_native_app?
    request.user_agent.to_s.include?("Turbo Native")
  end
end
