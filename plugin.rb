# frozen_string_literal: true

# name: discourse-topic-gallery
# about: Adds a gallery view to topics.
# meta_topic_id: 394953
# version: 0.0.2
# authors: Canapin & AI
# url: https://github.com/Canapin/discourse-topic-gallery
# required_version: 2.7.0

enabled_site_setting :topic_gallery_enabled

register_svg_icon "images"
register_asset "stylesheets/topic-gallery.scss"

module ::DiscourseTopicGallery
  PLUGIN_NAME = "discourse-topic-gallery"
end

after_initialize do
  require_relative "app/controllers/discourse_topic_gallery/topic_gallery_controller"

  # Expose gallery permission to the client so the UI can show/hide the button
  add_to_serializer(:site, :can_view_topic_gallery) do
    allowed = SiteSetting.topic_gallery_allowed_groups_map
    if scope.user
      scope.user.in_any_groups?(allowed)
    else
      allowed.include?(Group::AUTO_GROUPS[:everyone])
    end
  end

  # Inject gallery-specific title and description for gallery pages
  register_modifier(:meta_data_content) do |content, property, opts|
    url = opts[:url]
    if url == "/gallery"
      case property
      when :title
        next I18n.t("discourse_topic_gallery.site_gallery_title") + " - " + SiteSetting.title
      when :description
        next I18n.t("discourse_topic_gallery.site_gallery_description")
      end
    elsif url&.match?(%r{\A/gallery/c/})
      category_id = url.match(%r{/(\d+)(?:\?|$)})&.[](1)
      if category_id
        category = Category.find_by(id: category_id)
        if category
          case property
          when :title
            next(
              I18n.t("js.discourse_topic_gallery.page_title", title: category.name) + " - " +
                SiteSetting.title
            )
          when :description
            next I18n.t("discourse_topic_gallery.category_gallery_description", title: category.name)
          end
        end
      end
    elsif url&.match?(%r{\A/gallery/})
      topic_id = url.match(%r{/(\d+)(?:\?|$)})&.[](1)
      if topic_id
        topic = Topic.find_by(id: topic_id)
        if topic
          case property
          when :title
            next(
              I18n.t("js.discourse_topic_gallery.page_title", title: topic.title) + " - " +
                SiteSetting.title
            )
          when :description
            next I18n.t("discourse_topic_gallery.gallery_description", title: topic.title)
          end
        end
      end
    end
    content
  end

  # All routes use /gallery/ prefix — no conflict with Discourse's /t/ catch-all,
  # so no need to prepend. HTML routes serve the Ember app shell; JSON routes
  # return gallery data.
  Discourse::Application.routes.prepend do
    constraints(->(req) { !req.path.end_with?(".json") }) do
      get "c/*category_slug_path/:category_id/gallery" =>
            "discourse_topic_gallery/topic_gallery#page",
          :constraints => {
            category_id: /\d+/,
          },
          :defaults => {
            gallery_scope: "category",
          }
    end

    get "c/*category_slug_path/:category_id/gallery" =>
          "discourse_topic_gallery/topic_gallery#show",
        :constraints => {
          category_id: /\d+/,
        },
        :defaults => {
          format: :json,
          gallery_scope: "category",
        }
  end

  Discourse::Application.routes.append do
    # HTML routes (Ember app shell)
    constraints(->(req) { !req.path.end_with?(".json") }) do
      get "gallery" => "discourse_topic_gallery/topic_gallery#page",
          :defaults => {
            gallery_scope: "site",
          }
      get "gallery/c/:category_slug/:category_id" => "discourse_topic_gallery/topic_gallery#page",
          :constraints => {
            category_id: /\d+/,
          },
          :defaults => {
            gallery_scope: "category",
          }
      scope constraints: { topic_id: /\d+/ } do
        get "gallery/:slug/:topic_id" => "discourse_topic_gallery/topic_gallery#page"
        get "gallery/:topic_id" => "discourse_topic_gallery/topic_gallery#page"
      end
    end

    # JSON routes (gallery data)
    get "gallery" => "discourse_topic_gallery/topic_gallery#show",
        :defaults => {
          format: :json,
          gallery_scope: "site",
        }
    get "gallery/c/:category_slug/:category_id" => "discourse_topic_gallery/topic_gallery#show",
        :constraints => {
          category_id: /\d+/,
        },
        :defaults => {
          format: :json,
          gallery_scope: "category",
        }
    scope constraints: { topic_id: /\d+/ } do
      get "gallery/:slug/:topic_id" => "discourse_topic_gallery/topic_gallery#show",
          :defaults => {
            format: :json,
          }
      get "gallery/:topic_id" => "discourse_topic_gallery/topic_gallery#show",
          :defaults => {
            format: :json,
          }
      get "/topic-gallery/:topic_id" => "discourse_topic_gallery/topic_gallery#show"
    end
  end
end
