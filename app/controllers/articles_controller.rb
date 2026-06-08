class ArticlesController < ApplicationController
  def show
    @article = Article.find_by!(public_id: params[:public_id])
    @article.increment!(:preview_views)
    expires_in 10.minutes, public: true
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
