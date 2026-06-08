class TelegramClient
  BASE_URL = "https://api.telegram.org"

  class Error < StandardError; end

  def initialize(token: Rails.application.credentials.telegram_bot_token || ENV.fetch("TELEGRAM_BOT_TOKEN"))
    @conn = Faraday.new(url: "#{BASE_URL}/bot#{token}/") do |f|
      f.request :json
      f.request :retry, max: 3, interval: 2, retry_statuses: [429, 500, 502, 503]
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  # Send a new message. Returns the Telegram Message object hash.
  def send_message(chat_id:, text:, parse_mode: "MarkdownV2", link_preview_options: nil, message_thread_id: nil)
    params = { chat_id: chat_id, text: text, parse_mode: parse_mode }
    params[:link_preview_options] = link_preview_options if link_preview_options
    params[:message_thread_id] = message_thread_id if message_thread_id

    post!("sendMessage", params)
  end

  # Edit an existing message in-place. Returns the updated Message hash.
  def edit_message_text(chat_id:, message_id:, text:, parse_mode: "MarkdownV2", message_thread_id: nil)
    params = {
      chat_id:    chat_id,
      message_id: message_id,
      text:       text,
      parse_mode: parse_mode
    }
    params[:message_thread_id] = message_thread_id if message_thread_id

    post!("editMessageText", params)
  end

  private

  def post!(method, params)
    response = @conn.post(method, params)
    body     = response.body

    raise Error, "Telegram #{method} failed: #{body['description']} (error_code=#{body['error_code']})" unless body["ok"]

    body["result"]
  rescue Faraday::Error => e
    raise Error, "HTTP error calling Telegram #{method}: #{e.message}"
  end
end
