class AiFilter
  class Error < StandardError; end

  RELEVANCE_PROMPT = <<~PROMPT
    You are a news relevance classifier for a corruption watchdog.

    Determine whether the following article is genuinely about corruption, bribery,
    embezzlement, fraud, kickbacks, nepotism, or related misconduct by a public figure,
    politician, official, or institution.

    Title: %<title>s
    Description: %<description>s

    Score 0.0 (completely irrelevant) to 1.0 (directly and clearly about corruption).
    Be strict: opinion pieces about corruption in general, metaphorical usage,
    or unrelated business news should score below 0.5.

    Respond ONLY with valid JSON: {"score": <float>, "reason": "<one sentence>"}
  PROMPT

  CLUSTER_PROMPT = <<~PROMPT
    You are a news deduplication engine for a corruption watchdog.

    NEW ARTICLE:
    Title: %<title>s
    Description: %<description>s

    RECENT APPROVED ARTICLES (last 7 days, format: [story_key|article_id] title):
    %<recent>s

    Does the new article report on the SAME underlying event as any listed article?

    Rules:
    - "Same event" means the same specific incident, person charged, or verdict — not just the same topic.
    - If it is the same event AND the new article contains MORE detail or is a follow-up, set supersede=true.
    - If it is the same event but NOT more detailed, set duplicate=true (it should be silently dropped).
    - If it is a genuinely new event, generate a short kebab-case slug (max 6 words).

    Respond ONLY with valid JSON (one of these shapes):
      {"match": false, "story_key": "new-slug-here"}
      {"match": true, "story_key": "existing-key", "superseded_id": <int>, "supersede": true}
      {"match": true, "story_key": "existing-key", "superseded_id": <int>, "duplicate": true}
  PROMPT

  def initialize(api_key: Rails.application.credentials.openai_api_key || ENV.fetch("OPENAI_API_KEY"), model: "gpt-4o-mini")
    @client = OpenAI::Client.new(access_token: api_key)
    @model  = model
  end

  def score_relevance(article)
    prompt = format(RELEVANCE_PROMPT,
      title:       article.title.to_s,
      description: article.description.to_s.truncate(500))

    result = chat_json(prompt, max_tokens: 120)
    result["score"].to_f
  rescue => e
    raise Error, "Relevance scoring failed: #{e.message}"
  end

  # Returns a hash:
  #   { story_key:, superseded_id:, supersede:, duplicate: }
  def cluster(article, recent_articles)
    if recent_articles.empty?
      return { story_key: slugify(article.title), superseded_id: nil,
               supersede: false, duplicate: false }
    end

    recent_list = recent_articles.map do |id, key, title|
      "  [#{key}|#{id}] #{title}"
    end.join("\n")

    prompt = format(CLUSTER_PROMPT,
      title:       article.title.to_s,
      description: article.description.to_s.truncate(400),
      recent:      recent_list)

    result = chat_json(prompt, max_tokens: 160)

    {
      story_key:     result["story_key"],
      superseded_id: result["superseded_id"],
      supersede:     result["supersede"]  == true,
      duplicate:     result["duplicate"] == true
    }
  rescue => e
    raise Error, "Story clustering failed: #{e.message}"
  end

  private

  def chat_json(prompt, max_tokens:)
    response = @client.chat(
      parameters: {
        model:           @model,
        messages:        [{ role: "user", content: prompt }],
        response_format: { type: "json_object" },
        max_tokens:      max_tokens,
        temperature:     0.1
      }
    )
    JSON.parse(response.dig("choices", 0, "message", "content"))
  end

  def slugify(text)
    text.to_s
        .downcase
        .gsub(/[^a-z0-9\s-]/, "")
        .gsub(/\s+/, "-")
        .slice(0, 60)
        .sub(/-+$/, "")
  end
end
