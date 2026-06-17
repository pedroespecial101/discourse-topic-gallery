# frozen_string_literal: true

module DiscourseTopicGallery
  class TopicGalleryController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    PAGE_SIZE = 30

    # Serves the Ember app shell for direct browser visits.
    def page
      gallery_context
      render html: "".html_safe
    end

    def show
      context = gallery_context
      visible_posts = apply_filters(visible_posts_scope(context), context)
      results = gallery_results(visible_posts, context)

      render json: response_payload(context, results)
    end

    private

    GalleryContext = Struct.new(:scope, :topic, :category, keyword_init: true)

    def gallery_context
      authorize_gallery_access!

      case gallery_scope
      when "site"
        GalleryContext.new(scope: "site")
      when "category"
        category = Category.find_by(id: params[:category_id])
        raise Discourse::NotFound unless category
        raise Discourse::NotFound unless guardian.can_see_category?(category)
        raise Discourse::NotFound if excluded_category_ids.include?(category.id)

        GalleryContext.new(scope: "category", category: category)
      else
        topic = Topic.find_by(id: params[:topic_id])
        raise Discourse::NotFound unless topic
        raise Discourse::NotFound unless guardian.can_see?(topic)
        raise Discourse::NotFound if excluded_category_ids.include?(topic.category_id)

        GalleryContext.new(scope: "topic", topic: topic)
      end
    end

    def gallery_scope
      params[:gallery_scope].presence || (params[:category_id].present? ? "category" : "topic")
    end

    def authorize_gallery_access!
      allowed_groups = SiteSetting.topic_gallery_allowed_groups_map
      everyone_allowed = allowed_groups.include?(Group::AUTO_GROUPS[:everyone])
      return if everyone_allowed || current_user&.in_any_groups?(allowed_groups)

      raise Discourse::NotFound
    end

    def excluded_category_ids
      SiteSetting.topic_gallery_excluded_categories_map
    end

    def visible_posts_scope(context)
      allowed_types = [Post.types[:regular]]
      allowed_types << Post.types[:whisper] if guardian.can_see_whispers?

      scope =
        Post
          .joins("INNER JOIN topics ON topics.id = posts.topic_id")
          .where(posts: { deleted_at: nil, hidden: false, post_type: allowed_types })
          .where(topics: { deleted_at: nil })
          .where.not(topics: { archetype: Archetype.private_message })

      if context.scope == "topic"
        scope = scope.where(posts: { topic_id: context.topic.id })
      else
        scope = scope.where(topics: { visible: true })
        scope = guardian.filter_allowed_categories(scope)
      end

      if context.scope == "category"
        scope = scope.where("topics.category_id IN (?)", scoped_category_ids(context.category))
      end

      if excluded_category_ids.present?
        scope =
          scope.where(
            "topics.category_id IS NULL OR topics.category_id NOT IN (?)",
            excluded_category_ids,
          )
      end

      if current_user
        ignored_ids = IgnoredUser.where(user_id: current_user.id).select(:ignored_user_id)
        scope = scope.where.not(user_id: ignored_ids)
      end

      scope
    end

    def scoped_category_ids(category)
      return [category.id] unless SiteSetting.topic_gallery_category_include_subcategories

      [category.id] + Category.where(parent_category_id: category.id).pluck(:id)
    end

    def apply_filters(visible_posts, context)
      if params[:username].present?
        filter_user = User.find_by_username(params[:username])
        visible_posts = filter_user ? visible_posts.where(user_id: filter_user.id) : visible_posts.none
      end

      if context.scope == "topic" && params[:post_number].present?
        visible_posts = visible_posts.where("posts.post_number >= ?", params[:post_number].to_i)
      end

      if params[:from_date].present?
        from = parse_date(params[:from_date])
        visible_posts = visible_posts.where("posts.created_at >= ?", from.beginning_of_day) if from
      end

      if params[:to_date].present?
        to = parse_date(params[:to_date])
        visible_posts = visible_posts.where("posts.created_at <= ?", to.end_of_day) if to
      end

      visible_posts
    end

    def parse_date(value)
      Date.parse(value)
    rescue ArgumentError
      nil
    end

    def gallery_results(visible_posts, context)
      ranked_sql = ranked_upload_references_sql(visible_posts)
      query =
        UploadReference
          .from("(#{ranked_sql}) AS ranked_refs")
          .where("row_num = 1")
          .select(
            "upload_id",
            "ref_id",
            "post_id",
            "post_number",
            "post_created_at",
            "post_user_id",
            "topic_id",
            "topic_title",
            "topic_slug",
            "category_id",
            "category_name",
            "category_slug",
            "category_color",
            "category_text_color",
          )

      if (cursor = decoded_cursor)
        query =
          query.where(
            <<~SQL.squish,
              post_created_at < :post_created_at OR
              (post_created_at = :post_created_at AND post_id < :post_id) OR
              (post_created_at = :post_created_at AND post_id = :post_id AND ref_id < :ref_id)
            SQL
            post_created_at: cursor[:post_created_at],
            post_id: cursor[:post_id],
            ref_id: cursor[:ref_id],
          )
      end

      query = query.order("post_created_at DESC, post_id DESC, ref_id DESC")

      if params[:page].present? && params[:cursor].blank?
        query = query.offset([params[:page].to_i, 0].max * PAGE_SIZE)
      end

      refs_array = query.limit(PAGE_SIZE + 1).to_a
      has_more = refs_array.length > PAGE_SIZE
      refs_array = refs_array.first(PAGE_SIZE)

      {
        refs: refs_array,
        has_more: has_more,
        next_cursor: has_more ? encoded_cursor(refs_array.last) : nil,
        total: context.scope == "topic" ? topic_total(ranked_sql) : nil,
      }
    end

    def ranked_upload_references_sql(visible_posts)
      visible_posts_sub = visible_posts.select(:id)

      system_exclusion = <<~SQL
        NOT EXISTS (
          SELECT 1 FROM upload_references ur2
          WHERE ur2.upload_id = upload_references.upload_id
            AND ur2.target_type IN (
              'CustomEmoji', 'UserAvatar', 'User', 'UserProfile',
              'ThemeField', 'ThemeSetting', 'ThemeSiteSetting',
              'SiteSetting', 'Badge', 'Group'
            )
        )
      SQL

      UploadReference
        .joins("INNER JOIN posts ON posts.id = upload_references.target_id")
        .joins("INNER JOIN uploads ON uploads.id = upload_references.upload_id")
        .joins("INNER JOIN topics ON topics.id = posts.topic_id")
        .joins("LEFT JOIN categories ON categories.id = topics.category_id")
        .where(target_type: "Post", target_id: visible_posts_sub)
        .where.not(uploads: { width: nil })
        .where.not(uploads: { height: nil })
        .where("uploads.width >= ?", SiteSetting.topic_gallery_minimum_image_size)
        .where("uploads.height >= ?", SiteSetting.topic_gallery_minimum_image_size)
        .where(system_exclusion)
        .select(
          "upload_references.upload_id",
          "upload_references.id AS ref_id",
          "posts.id AS post_id",
          "posts.post_number",
          "posts.created_at AS post_created_at",
          "posts.user_id AS post_user_id",
          "topics.id AS topic_id",
          "topics.title AS topic_title",
          "topics.slug AS topic_slug",
          "categories.id AS category_id",
          "categories.name AS category_name",
          "categories.slug AS category_slug",
          "categories.color AS category_color",
          "categories.text_color AS category_text_color",
          <<~SQL.squish,
            ROW_NUMBER() OVER (
              PARTITION BY uploads.id
              ORDER BY posts.created_at DESC, posts.id DESC, upload_references.id DESC
            ) AS row_num
          SQL
        )
        .to_sql
    end

    def decoded_cursor
      return if params[:cursor].blank?

      payload = JSON.parse(Base64.urlsafe_decode64(params[:cursor])).symbolize_keys
      {
        post_created_at: Time.zone.at(payload[:post_created_at].to_f / 1_000_000),
        post_id: payload[:post_id].to_i,
        ref_id: payload[:ref_id].to_i,
      }
    rescue ArgumentError, JSON::ParserError
      nil
    end

    def encoded_cursor(ref)
      Base64.urlsafe_encode64(
        {
          post_created_at: (ref.post_created_at.to_f * 1_000_000).to_i,
          post_id: ref.post_id,
          ref_id: ref.ref_id,
        }.to_json,
        padding: false,
      )
    end

    def topic_total(ranked_sql)
      UploadReference.from("(#{ranked_sql}) AS ranked_refs").where("row_num = 1").count
    end

    def response_payload(context, results)
      refs = results[:refs]
      uploads = Upload.where(id: refs.map(&:upload_id)).includes(:optimized_images).index_by(&:id)
      users = User.where(id: refs.map(&:post_user_id).uniq).index_by(&:id)

      payload = {
        scope: context.scope,
        scopeTitle: scope_title(context),
        scopeUrl: scope_url(context),
        images: serialize_uploads_from_refs(refs, uploads, users),
        hasMore: results[:has_more],
        nextCursor: results[:next_cursor],
        metadataSettings: metadata_settings,
      }

      if context.scope == "topic"
        payload.merge!(
          title: context.topic.title,
          slug: context.topic.slug,
          id: context.topic.id,
          topicId: context.topic.id,
          postsCount: context.topic.posts_count,
          total: results[:total],
          page: [params[:page].to_i, 0].max,
        )
      elsif context.scope == "category"
        payload.merge!(
          categoryId: context.category.id,
          categorySlug: context.category.slug,
          category: category_payload(context.category),
        )
      end

      payload
    end

    def scope_title(context)
      case context.scope
      when "site"
        I18n.t("discourse_topic_gallery.site_gallery_title")
      when "category"
        context.category.name
      else
        context.topic.title
      end
    end

    def scope_url(context)
      case context.scope
      when "site"
        "/gallery"
      when "category"
        "/c/#{context.category.slug}/#{context.category.id}"
      else
        "/t/#{context.topic.slug}/#{context.topic.id}"
      end
    end

    def metadata_settings
      {
        showAuthor: SiteSetting.topic_gallery_show_author,
        showPostDate: SiteSetting.topic_gallery_show_post_date,
        showTopicTitle: SiteSetting.topic_gallery_show_topic_title,
        showCategory: SiteSetting.topic_gallery_show_category,
        showPostLink: SiteSetting.topic_gallery_show_post_link,
        showImageDetails: SiteSetting.topic_gallery_show_image_details,
      }
    end

    def serialize_uploads_from_refs(refs, uploads, users)
      refs
        .map do |ref|
          upload = uploads[ref.upload_id]
          next unless upload

          thumb_w = upload.thumbnail_width || upload.width
          thumb_h = upload.thumbnail_height || upload.height
          ext = ".#{upload.extension}"

          optimized =
            upload.optimized_images.detect do |oi|
              oi.width == thumb_w && oi.height == thumb_h && oi.extension == ext
            end
          optimized ||= OptimizedImage.create_for(upload, thumb_w, thumb_h)
          thumbnail_raw_url = optimized&.url || upload.url

          image = {
            id: upload.id,
            thumbnailUrl:
              UrlHelper.cook_url(thumbnail_raw_url, secure: upload.secure?, local: true),
            url: UrlHelper.cook_url(upload.url, secure: upload.secure?, local: true),
            width: upload.width,
            height: upload.height,
            downloadUrl: upload.short_path,
            postId: ref.post_id,
            topicId: ref.topic_id,
          }

          if SiteSetting.topic_gallery_show_author
            user = users[ref.post_user_id]
            image[:username] = user&.username
            image[:name] = user&.name
          end

          image[:postCreatedAt] = ref.post_created_at&.iso8601 if SiteSetting.topic_gallery_show_post_date

          if SiteSetting.topic_gallery_show_post_link
            image[:postNumber] = ref.post_number
            image[:postUrl] = "/t/#{ref.topic_slug}/#{ref.topic_id}/#{ref.post_number}"
          end

          if SiteSetting.topic_gallery_show_topic_title
            image[:topicTitle] = ref.topic_title
            image[:topicUrl] = "/t/#{ref.topic_slug}/#{ref.topic_id}"
          end

          if SiteSetting.topic_gallery_show_category && ref.category_id
            image[:category] =
              category_payload(
                {
                  id: ref.category_id,
                  name: ref.category_name,
                  slug: ref.category_slug,
                  color: ref.category_color,
                  text_color: ref.category_text_color,
                },
              )
          end

          image[:filesize] = upload.human_filesize if SiteSetting.topic_gallery_show_image_details

          image
        end
        .compact
    end

    def category_payload(category)
      {
        id: category[:id] || category.id,
        name: category[:name] || category.name,
        slug: category[:slug] || category.slug,
        color: category[:color] || category.color,
        textColor: category[:text_color] || category.text_color,
        url: "/c/#{category[:slug] || category.slug}/#{category[:id] || category.id}",
      }
    end
  end
end
