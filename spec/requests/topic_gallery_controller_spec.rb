# frozen_string_literal: true

require "rails_helper"

describe "TopicGalleryController" do
  fab!(:user)
  fab!(:admin)
  fab!(:other_user, :user)
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, user: user, category: category) }

  fab!(:post1) { Fabricate(:post, topic: topic, user: user, post_number: 1) }
  fab!(:post2) { Fabricate(:post, topic: topic, user: other_user, post_number: 2) }

  fab!(:upload1) { Fabricate(:upload, user: user, width: 800, height: 600) }
  fab!(:upload2) { Fabricate(:upload, user: other_user, width: 1024, height: 768) }

  before do
    SiteSetting.topic_gallery_enabled = true
    SiteSetting.topic_gallery_allowed_groups = Group::AUTO_GROUPS[:everyone]
    post1.update!(created_at: 2.days.ago)
    post2.update!(created_at: 1.day.ago)
    UploadReference.create!(target: post1, upload: upload1)
    UploadReference.create!(target: post2, upload: upload2)
  end

  describe "GET /gallery.json" do
    before { sign_in(user) }

    it "returns latest visible images sitewide" do
      get "/gallery.json"

      json = response.parsed_body
      expect(json["scope"]).to eq("site")
      expect(json["scopeTitle"]).to be_present
      expect(json["total"]).to be_nil
      expect(json["nextCursor"]).to be_nil
      expect(json["images"].map { |i| i["id"] }).to eq([upload2.id, upload1.id])
    end

    it "excludes images from restricted categories" do
      restricted_group = Fabricate(:group)
      restricted_category = Fabricate(:private_category, group: restricted_group)
      restricted_topic = Fabricate(:topic, category: restricted_category)
      restricted_post = Fabricate(:post, topic: restricted_topic, user: other_user)
      restricted_upload = Fabricate(:upload, user: other_user, width: 800, height: 600)
      UploadReference.create!(target: restricted_post, upload: restricted_upload)

      get "/gallery.json"

      ids = response.parsed_body["images"].map { |i| i["id"] }
      expect(ids).not_to include(restricted_upload.id)
    end
  end

  describe "GET /gallery/c/:slug/:category_id.json" do
    before { sign_in(user) }

    it "returns latest images for the category" do
      get "/gallery/c/#{category.slug}/#{category.id}.json"

      json = response.parsed_body
      expect(json["scope"]).to eq("category")
      expect(json["categoryId"]).to eq(category.id)
      expect(json["images"].map { |i| i["id"] }).to eq([upload2.id, upload1.id])
    end

    it "includes subcategories by default" do
      child_category = Fabricate(:category, parent_category_id: category.id)
      child_topic = Fabricate(:topic, category: child_category)
      child_post = Fabricate(:post, topic: child_topic, user: user, created_at: Time.zone.now)
      child_upload = Fabricate(:upload, user: user, width: 800, height: 600)
      UploadReference.create!(target: child_post, upload: child_upload)

      get "/gallery/c/#{category.slug}/#{category.id}.json"

      ids = response.parsed_body["images"].map { |i| i["id"] }
      expect(ids).to include(child_upload.id)
    end
  end

  describe "GET /topic-gallery/:topic_id" do
    context "when plugin is disabled" do
      before { SiteSetting.topic_gallery_enabled = false }

      it "returns 404" do
        sign_in(user)
        get "/topic-gallery/#{topic.id}.json"
        expect(response.status).to eq(404)
      end
    end

    context "with group-based access control" do
      it "allows anonymous users when everyone group is allowed" do
        get "/topic-gallery/#{topic.id}.json"
        expect(response.status).to eq(200)
      end

      it "returns 404 when user is not in allowed group" do
        group = Fabricate(:group)
        SiteSetting.topic_gallery_allowed_groups = group.id.to_s
        sign_in(user)

        get "/topic-gallery/#{topic.id}.json"
        expect(response.status).to eq(404)
      end

      it "allows user who is in the allowed group" do
        group = Fabricate(:group)
        group.add(user)
        SiteSetting.topic_gallery_allowed_groups = group.id.to_s
        sign_in(user)

        get "/topic-gallery/#{topic.id}.json"
        expect(response.status).to eq(200)
      end
    end

    context "with topic-level access" do
      it "returns 404 for nonexistent topic" do
        sign_in(user)
        get "/topic-gallery/999999.json"
        expect(response.status).to eq(404)
      end

      it "returns 404 for topic in a restricted category" do
        restricted_category = Fabricate(:private_category, group: Fabricate(:group))
        restricted_topic = Fabricate(:topic, category: restricted_category)
        sign_in(user)

        get "/topic-gallery/#{restricted_topic.id}.json"
        expect(response.status).to eq(404)
      end

      it "returns 404 for topic in an excluded category" do
        SiteSetting.topic_gallery_excluded_categories = topic.category_id.to_s
        sign_in(user)

        get "/topic-gallery/#{topic.id}.json"
        expect(response.status).to eq(404)
      end

      it "allows topic when its category is not excluded" do
        other_category = Fabricate(:category)
        SiteSetting.topic_gallery_excluded_categories = other_category.id.to_s
        sign_in(user)

        get "/topic-gallery/#{topic.id}.json"
        expect(response.status).to eq(200)
      end
    end

    context "with post visibility" do
      before { sign_in(user) }

      it "excludes uploads from soft-deleted posts" do
        post2.update!(deleted_at: Time.zone.now)
        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).to contain_exactly(upload1.id)
      end

      it "excludes uploads from hidden posts" do
        post2.update!(hidden: true)
        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).to contain_exactly(upload1.id)
      end

      it "excludes whisper images for regular users" do
        post2.update!(post_type: Post.types[:whisper])
        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).to contain_exactly(upload1.id)
      end

      it "includes whisper images for staff" do
        post2.update!(post_type: Post.types[:whisper])
        SiteSetting.whispers_allowed_groups = "#{Group::AUTO_GROUPS[:staff]}"
        sign_in(admin)
        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).to contain_exactly(upload1.id, upload2.id)
      end

      it "excludes uploads from posts by ignored users" do
        Fabricate(:ignored_user, user: user, ignored_user: other_user)
        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).to contain_exactly(upload1.id)
      end

      it "excludes non-regular post types" do
        small_action =
          Fabricate(:post, topic: topic, user: user, post_type: Post.types[:small_action])
        upload3 = Fabricate(:upload, user: user, width: 100, height: 100)
        UploadReference.create!(target: small_action, upload: upload3)

        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).not_to include(upload3.id)
      end
    end

    context "with upload filtering" do
      before { sign_in(user) }

      it "excludes uploads without dimensions" do
        no_dims = Fabricate(:upload, user: user, width: nil, height: 100)
        UploadReference.create!(target: post1, upload: no_dims)

        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).not_to include(no_dims.id)
      end

      it "excludes images smaller than the minimum size" do
        small = Fabricate(:upload, user: user, width: 16, height: 16)
        UploadReference.create!(target: post1, upload: small)
        SiteSetting.topic_gallery_minimum_image_size = 32

        get "/topic-gallery/#{topic.id}.json"

        ids = response.parsed_body["images"].map { |i| i["id"] }
        expect(ids).to contain_exactly(upload1.id, upload2.id)
      end
    end

    context "with response format" do
      before { sign_in(user) }

      it "returns correct top-level fields" do
        get "/topic-gallery/#{topic.id}.json"

        json = response.parsed_body
        expect(json["scope"]).to eq("topic")
        expect(json["id"]).to eq(topic.id)
        expect(json["title"]).to eq(topic.title)
        expect(json["scopeTitle"]).to eq(topic.title)
        expect(json["slug"]).to eq(topic.slug)
        expect(json["total"]).to eq(2)
        expect(json["page"]).to eq(0)
        expect(json["hasMore"]).to eq(false)
      end

      it "returns correct image fields" do
        get "/topic-gallery/#{topic.id}.json"

        image = response.parsed_body["images"].find { |i| i["id"] == upload1.id }
        expect(image["width"]).to eq(800)
        expect(image["height"]).to eq(600)
        expect(image["postNumber"]).to eq(1)
        expect(image["postCreatedAt"]).to be_present
        expect(image["username"]).to eq(user.username)
        expect(image["postUrl"]).to eq("/t/#{topic.slug}/#{topic.id}/1")
        expect(image["topicTitle"]).to eq(topic.title)
        expect(image["category"]["name"]).to eq(category.name)
        expect(image["url"]).to be_present
        expect(image["thumbnailUrl"]).to be_present
        expect(image["downloadUrl"]).to be_present
      end

      it "orders images latest first" do
        get "/topic-gallery/#{topic.id}.json"

        expect(response.parsed_body["images"].map { |i| i["id"] }).to eq([upload2.id, upload1.id])
      end

      it "uses the latest visible post when deduplicating uploads" do
        UploadReference.create!(target: post2, upload: upload1)

        get "/topic-gallery/#{topic.id}.json"

        image = response.parsed_body["images"].find { |i| i["id"] == upload1.id }
        expect(image["postId"]).to eq(post2.id)
        expect(image["postNumber"]).to eq(2)
      end

      it "respects metadata display settings" do
        SiteSetting.topic_gallery_show_author = false
        SiteSetting.topic_gallery_show_post_date = false
        SiteSetting.topic_gallery_show_topic_title = false
        SiteSetting.topic_gallery_show_category = false
        SiteSetting.topic_gallery_show_post_link = false
        SiteSetting.topic_gallery_show_image_details = false

        get "/topic-gallery/#{topic.id}.json"

        image = response.parsed_body["images"].first
        expect(image).not_to have_key("username")
        expect(image).not_to have_key("postCreatedAt")
        expect(image).not_to have_key("topicTitle")
        expect(image).not_to have_key("category")
        expect(image).not_to have_key("postUrl")
        expect(image).not_to have_key("filesize")
      end

      it "can make topic title links point to the specific post" do
        SiteSetting.topic_gallery_show_post_link = false
        SiteSetting.topic_gallery_topic_title_links_to_post = true

        get "/topic-gallery/#{topic.id}.json"

        image = response.parsed_body["images"].find { |i| i["id"] == upload1.id }
        expect(image["topicTitle"]).to eq(topic.title)
        expect(image["topicUrl"]).to eq("/t/#{topic.slug}/#{topic.id}/1")
        expect(image).not_to have_key("postUrl")
      end

      it "returns empty images for page beyond results" do
        get "/topic-gallery/#{topic.id}.json", params: { page: 100 }

        expect(response.parsed_body["images"]).to be_empty
        expect(response.parsed_body["hasMore"]).to eq(false)
      end
    end
  end

  describe "GET /gallery/:slug/:topic_id (HTML)" do
    it "serves the Ember app shell with correct slug" do
      sign_in(user)
      get "/gallery/#{topic.slug}/#{topic.id}"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end

    it "serves the page even with a wrong slug" do
      sign_in(user)
      get "/gallery/wrong-slug/#{topic.id}"
      expect(response.status).to eq(200)
    end
  end

  describe "GET /gallery/:topic_id (HTML, slugless)" do
    it "serves the Ember app shell without a slug" do
      sign_in(user)
      get "/gallery/#{topic.id}"
      expect(response.status).to eq(200)
      expect(response.media_type).to eq("text/html")
    end
  end
end
