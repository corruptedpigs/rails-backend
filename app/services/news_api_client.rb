class NewsApiClient
  BASE_URL = "https://newsapi.org/v2"

  class Error < StandardError; end

  def initialize(api_key: Rails.application.credentials.news_api_key || ENV.fetch("NEWS_API_KEY"))
    @conn = Faraday.new(url: BASE_URL) do |f|
      f.headers["X-Api-Key"] = api_key
      f.request :retry, max: 3, interval: 5, retry_statuses: [429, 500, 502, 503]
      f.response :json
      f.adapter Faraday.default_adapter
    end
  end

  # Returns an array of raw article hashes from NewsAPI.
  # Raises NewsApiClient::Error on non-OK responses.
  def everything(query:, language:, from: Date.today, page_size: 100)
    response = @conn.get("/v2/everything", {
      q:        query,
      language: language,
      from:     from.iso8601,
      sortBy:   "publishedAt",
      pageSize: page_size
    })

    body = response.body
    raise Error, "NewsAPI error (#{response.status}): #{body['message']}" unless body["status"] == "ok"

    body["articles"] || []
  rescue Faraday::Error => e
    raise Error, "HTTP error calling NewsAPI: #{e.message}"
  end
end
