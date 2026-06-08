class NewsFetcherJob < ApplicationJob
  queue_as :default

  LAST_RUN_KEY = "cpigs:news_fetcher:last_run"

  def perform
    config  = Rails.application.config_for(:news_bot)
    client  = NewsApiClient.new
    fetched = 0
    queued  = 0

    from = last_run_time(config)
    Sidekiq.redis { |r| r.set(LAST_RUN_KEY, Time.current.iso8601) }
    Rails.logger.info "[NewsFetcherJob] Fetching articles since #{from.iso8601}"

    config[:languages].each do |lang_config|
      raw_articles = client.everything(
        query:    lang_config[:keywords],
        language: lang_config[:code],
        from:     from
      )

      raw_articles.each do |raw|
        new_record, changed = upsert_article(raw, lang_config[:code])
        fetched += 1

        if new_record || changed
          ArticleFilterJob.perform_later(Article.find_by!(external_id: raw["url"]).id)
          queued += 1
        end
      end

      Rails.logger.info "[NewsFetcherJob] #{lang_config[:code].upcase}: #{raw_articles.size} articles fetched"
    rescue NewsApiClient::Error => e
      Rails.logger.error "[NewsFetcherJob] #{lang_config[:code].upcase} fetch failed: #{e.message}"
    end

    Rails.logger.info "[NewsFetcherJob] Done — fetched=#{fetched} queued_for_filter=#{queued}"
  end

  private

  def last_run_time(config)
    stored = Sidekiq.redis { |r| r.get(LAST_RUN_KEY) }
    stored ? Time.zone.parse(stored) : config[:fetch_interval_minutes].to_i.minutes.ago
  end

  def upsert_article(raw, language)
    url = raw["url"].to_s
    return [false, false] if url.blank? || raw["title"].blank?

    article    = Article.find_or_initialize_by(external_id: url)
    new_record = article.new_record?

    article.assign_attributes(
      title:        raw["title"],
      description:  raw["description"],
      content:      raw["content"],
      url:          url,
      image_url:    raw["urlToImage"],
      source_name:  raw.dig("source", "name"),
      author:       raw["author"],
      language:     language,
      published_at: raw["publishedAt"].present? ? Time.zone.parse(raw["publishedAt"]) : nil
    )

    changed = !new_record && article.changed?

    # Only re-queue for filtering if the article is still pending or has new content
    if new_record || changed
      article.status = "pending" if changed && article.status == "rejected"
      article.save!
    end

    [new_record, changed]
  end
end
