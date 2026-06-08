class TelegramNotifierJob < ApplicationJob
  queue_as :default

  def perform(article_id, replace_message_id: nil)
    article = Article.find_by(id: article_id)
    unless article
      Rails.logger.warn "[TelegramNotifierJob] Article #{article_id} not found"
      return
    end

    lang_config = language_config(article.language)
    unless lang_config
      Rails.logger.error "[TelegramNotifierJob] No channel config for language=#{article.language}"
      return
    end

    client       = TelegramClient.new
    chat_id      = lang_config[:telegram_chat_id]
    topic_id     = lang_config[:telegram_topic_id]
    text         = format_message(article)

    # Try to edit an existing message if this article supersedes a previous one
    if replace_message_id.present?
      begin
        client.edit_message_text(
          chat_id:           chat_id,
          message_id:        replace_message_id,
          text:              text,
          message_thread_id: topic_id
        )
        article.update!(notified_at: Time.current, telegram_channel: chat_id.to_s)
        Rails.logger.info "[TelegramNotifierJob] Edited message #{replace_message_id} in #{chat_id}"
        return
      rescue TelegramClient::Error => e
        Rails.logger.warn "[TelegramNotifierJob] Could not edit message #{replace_message_id}: #{e.message}. Sending new message instead."
      end
    end

    result = client.send_message(
      chat_id:              chat_id,
      text:                 text,
      link_preview_options: link_preview_options(article.short_url),
      message_thread_id:    topic_id
    )

    article.update!(
      notified_at:        Time.current,
      telegram_message_id: result["message_id"],
      telegram_channel:   chat_id.to_s
    )

    Rails.logger.info "[TelegramNotifierJob] Sent message #{result['message_id']} to #{chat_id} for article #{article_id}"
  rescue TelegramClient::Error => e
    Rails.logger.error "[TelegramNotifierJob] Telegram error for article #{article_id}: #{e.message}"
    raise # Let Sidekiq retry
  end

  private

  def language_config(language)
    config = Rails.application.config_for(:news_bot)
    config[:languages].find { |l| l[:code] == language }
  end

  # Only request a link preview when the URL is publicly reachable.
  # Passing a localhost URL to Telegram causes WEBPAGE_URL_INVALID (400).
  def link_preview_options(url)
    uri = URI.parse(url)
    return nil if uri.host == "localhost" || uri.host&.start_with?("127.")

    { url: url, prefer_large_media: false }
  rescue URI::InvalidURIError
    nil
  end

  # Formats message in Telegram MarkdownV2.
  # MarkdownV2 requires escaping: _ * [ ] ( ) ~ ` > # + - = | { } . !
  def format_message(article)
    date = article.published_at&.strftime("%b %-d, %Y") || "Today"

    <<~MSG.strip
      🐷 *#{escape(article.title)}*

      #{escape(article.description.to_s.truncate(300))}

      🗞 #{escape(article.source_name.to_s)} · #{escape(date)}
      🔗 #{article.short_url}
    MSG
  end

  def escape(text)
    text.to_s.gsub(/([_*\[\]()~`>#+\-=|{}.!])/, '\\\\\1')
  end
end
