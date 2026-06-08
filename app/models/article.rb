class Article < ApplicationRecord
  audited max_audits: 10

  STATUSES = %w[pending approved rejected superseded].freeze

  before_create :assign_public_id

  validates :external_id, presence: true, uniqueness: true
  validates :public_id, uniqueness: true, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :language, presence: true

  scope :pending_filter, -> { where(status: "pending") }
  scope :approved,       -> { where(status: "approved") }
  scope :notified,       -> { where.not(notified_at: nil) }
  scope :recent,         -> { where(published_at: 7.days.ago..) }
  scope :for_language,   ->(lang) { where(language: lang) }

  def short_url
    base = ENV.fetch("SHORT_URL_BASE", "https://cpigs.to")
    "#{base}/#{public_id}"
  end

  private

  def assign_public_id
    self.public_id ||= loop do
      candidate = SecureRandom.alphanumeric(8).downcase
      break candidate unless Article.exists?(public_id: candidate)
    end
  end
end
