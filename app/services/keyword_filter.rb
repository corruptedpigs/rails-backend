class KeywordFilter
  CORRUPTION_KEYWORDS = {
    high: [
      "corrupção", "suborno", "desvio de dinheiro", "fraude", "nepotismo",
      "propina", "lavagem de dinheiro", "peculato", "concussão",
      "tráfico de influência", "enriquecimento ilícito", "caixa dois",
      "kickback", "propinas", "rachadinha", "mensalão", "petrolão"
    ],
    medium: [
      "investigação", "inquérito", "polícia federal", "ministério público",
      "operação", "delação", "colaboração premiada", "preso", "prisão",
      "indiciado", "réu", "condenação", "sentença", "tribunal",
      "suspeito", "alvo", "mandado", "busca e apreensão", "quebra de sigilo"
    ],
    low: [
      "política", "governo", "prefeito", "governador", "deputado", "senador",
      "vereador", "secretário", "ministro", "presidente", "câmara",
      "assembleia", "congresso", "prefeitura", "estado", "município",
      "licitação", "contrato", "obra pública", "emenda", "orçamento"
    ]
  }.freeze

  WEIGHTS = { high: 1.0, medium: 0.5, low: 0.2 }.freeze

  def self.score_relevance(article)
    text = [article.title, article.description, article.content].compact.join(" ").downcase
    return 0.0 if text.blank?

    score = 0.0
    matched = []

    CORRUPTION_KEYWORDS.each do |level, keywords|
      keywords.each do |kw|
        if text.include?(kw.downcase)
          score += WEIGHTS[level]
          matched << kw
        end
      end
    end

    [score.clamp(0.0, 1.0), matched.uniq]
  end
end