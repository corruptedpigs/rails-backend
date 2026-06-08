class ArticleFilterJob < ApplicationJob
  queue_as :default

  def perform(article_id)
    article = Article.find_by(id: article_id)
    unless article
      Rails.logger.warn "[ArticleFilterJob] Article #{article_id} not found, skipping"
      return
    end

    unless article.status == "pending"
      Rails.logger.info "[ArticleFilterJob] Article #{article_id} status=#{article.status}, skipping"
      return
    end

    config    = Rails.application.config_for(:news_bot)
    threshold = config[:relevance_threshold].to_f

    # --- Step A: Relevance scoring (AI or keyword fallback) ---
    if ai_configured?
      ai = AiFilter.new
      score = ai.score_relevance(article)
      Rails.logger.info "[ArticleFilterJob] Article #{article_id} AI relevance_score=#{score.round(2)}"
    else
      score, matched = KeywordFilter.score_relevance(article)
      Rails.logger.info "[ArticleFilterJob] Article #{article_id} keyword relevance_score=#{score.round(2)} matched=#{matched.join(', ')}"
    end

    article.update!(relevance_score: score)
    article.update!(relevance_score: score)
    Rails.logger.info "[ArticleFilterJob] Article #{article_id} relevance_score=#{score.round(2)}"

    if score < threshold
      article.update!(status: "rejected")
      Rails.logger.info "[ArticleFilterJob] Article #{article_id} rejected (score below threshold)"
      return
    end

    # --- Step B: Story clustering ---
    recent = Article.approved
                    .recent
                    .for_language(article.language)
                    .where.not(story_key: nil)
                    .order(published_at: :desc)
                    .limit(30)
                    .pluck(:id, :story_key, :title)

    result = ai.cluster(article, recent)
    Rails.logger.info "[ArticleFilterJob] Article #{article_id} cluster=#{result.inspect}"

    article.update!(story_key: result[:story_key])

    if result[:duplicate]
      article.update!(status: "rejected")
      Rails.logger.info "[ArticleFilterJob] Article #{article_id} rejected as duplicate"
      return
    end

    if result[:supersede] && result[:superseded_id].present?
      old_article = Article.find_by(id: result[:superseded_id])

      if old_article
        old_article.update!(status: "superseded")
        article.update!(
          status:           "approved",
          telegram_channel: old_article.telegram_channel
        )
        Rails.logger.info "[ArticleFilterJob] Article #{article_id} supersedes #{old_article.id}"
        TelegramNotifierJob.perform_later(article.id, replace_message_id: old_article.telegram_message_id)
      else
        article.update!(status: "approved")
        TelegramNotifierJob.perform_later(article.id)
      end
    else
      article.update!(status: "approved")
      TelegramNotifierJob.perform_later(article.id)
    end
  rescue AiFilter::Error => e
    Rails.logger.error "[ArticleFilterJob] AI error for article #{article_id}: #{e.message}"
    # Leave article in 'pending' state — will be retried if job retries
    raise
  end

  private

  def ai_configured?
    Rails.application.credentials.openai_api_key.present? ||
      ENV["OPENAI_API_KEY"].present?
  end
end
