import { settled, visit } from "@ember/test-helpers";
import { test } from "qunit";
import topicFixtures from "discourse/tests/fixtures/topic";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

acceptance("Topic Gallery", function (needs) {
  needs.user();
  needs.settings({ topic_gallery_enabled: true });

  needs.pretender((server, helper) => {
    const image = (id, attrs = {}) => ({
      id,
      thumbnailUrl: "data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA=",
      url: `https://example.com/uploads/${id}.jpg`,
      width: 800,
      height: 600,
      downloadUrl: `https://example.com/uploads/${id}.jpg`,
      postId: id,
      topicId: 280,
      topicTitle: "Internationalization / localization",
      topicUrl: "/t/internationalization-localization/280",
      postUrl: `/t/internationalization-localization/280/${id}`,
      postNumber: id,
      postCreatedAt: "2026-01-01T12:00:00Z",
      username: "eviltrout",
      category: {
        id: 10,
        name: "General",
        slug: "general",
        color: "0088cc",
        textColor: "ffffff",
        url: "/c/general/10",
      },
      ...attrs,
    });

    const topicResponse = topicFixtures["/t/280/1.json"];
    server.get("/t/280.json", () => helper.response(topicResponse));

    server.get("/topic-gallery/:topic_id", () =>
      helper.response({
        scope: "topic",
        id: 280,
        topicId: 280,
        title: "Internationalization / localization",
        scopeTitle: "Internationalization / localization",
        scopeUrl: "/t/internationalization-localization/280",
        slug: "internationalization-localization",
        images: [],
        page: 0,
        hasMore: false,
        nextCursor: null,
        total: 0,
        postsCount: 20,
        metadataSettings: {},
      })
    );

    server.get("/gallery.json", (request) => {
      if (request.queryParams.cursor) {
        return helper.response({
          scope: "site",
          scopeTitle: "Latest images",
          scopeUrl: "/gallery",
          images: [image(2)],
          hasMore: false,
          nextCursor: null,
          metadataSettings: {
            showAuthor: true,
            showPostDate: true,
            showTopicTitle: true,
            showCategory: true,
            showPostLink: true,
            showImageDetails: true,
          },
        });
      }

      return helper.response({
        scope: "site",
        scopeTitle: "Latest images",
        scopeUrl: "/gallery",
        images: [image(1)],
        hasMore: true,
        nextCursor: "next-page",
        metadataSettings: {
          showAuthor: true,
          showPostDate: true,
          showTopicTitle: true,
          showCategory: true,
          showPostLink: true,
          showImageDetails: true,
        },
      });
    });

    server.get("/gallery/c/general/10.json", () =>
      helper.response({
        scope: "category",
        categoryId: 10,
        categorySlug: "general",
        scopeTitle: "General",
        scopeUrl: "/c/general/10",
        images: [],
        hasMore: false,
        nextCursor: null,
        metadataSettings: {},
      })
    );

    server.get("/gallery/c/meta/11.json", () =>
      helper.response({
        scope: "category",
        categoryId: 11,
        categorySlug: "meta",
        scopeTitle: "Meta",
        scopeUrl: "/c/meta/11",
        images: [image(3)],
        hasMore: false,
        nextCursor: null,
        metadataSettings: {
          showAuthor: false,
          showPostDate: false,
          showTopicTitle: false,
          showCategory: false,
          showPostLink: false,
          showImageDetails: false,
        },
      })
    );

    server.get("/c/the-garage/technical/10/gallery.json", () =>
      helper.response({
        scope: "category",
        categoryId: 10,
        categorySlug: "technical",
        scopeTitle: "Technical",
        scopeUrl: "/c/the-garage/technical/10",
        images: [],
        hasMore: false,
        nextCursor: null,
        metadataSettings: {},
      })
    );
  });

  test("visiting the gallery route displays the topic title", async function (assert) {
    await visit("/gallery/internationalization-localization/280");

    assert
      .dom(".topic-gallery-page h1")
      .hasText("Internationalization / localization");
  });

  test("can navigate to gallery from topic page", async function (assert) {
    await visit("/t/internationalization-localization/280");

    await visit("/gallery/internationalization-localization/280");

    assert.dom(".topic-gallery-page").exists();
    assert
      .dom(".topic-gallery-page h1")
      .hasText("Internationalization / localization");
  });

  test("visiting the site gallery route displays latest images", async function (assert) {
    await visit("/gallery");

    assert.dom(".topic-gallery-page h1").hasText("Latest images");
  });

  test("load more uses the next cursor", async function (assert) {
    const originalObserver = window.IntersectionObserver;
    window.IntersectionObserver = class {
      observe() {}
      disconnect() {}
    };

    try {
      await visit("/gallery");

      const controller = this.owner.lookup("controller:topic-gallery");
      await controller.loadMore();
      await settled();

      assert.dom(".gallery-card").exists({ count: 2 });
      assert.strictEqual(controller.nextCursor, null);
      assert.false(controller.hasMore);
    } finally {
      window.IntersectionObserver = originalObserver;
    }
  });

  test("visiting the category gallery route displays the category title", async function (assert) {
    await visit("/gallery/c/general/10");

    assert.dom(".topic-gallery-page h1").hasText("General");
  });

  test("category galleries hide the topic-only post number filter", async function (assert) {
    await visit("/gallery/c/general/10");

    assert.dom(".post-number-input").doesNotExist();
  });

  test("metadata settings hide disabled card metadata", async function (assert) {
    await visit("/gallery/c/meta/11");

    assert.dom(".gallery-card").exists({ count: 1 });
    assert.dom(".mention").doesNotExist();
    assert.dom(".gallery-post-date").doesNotExist();
    assert.dom(".gallery-post-link").doesNotExist();
    assert.dom(".gallery-topic-link").doesNotExist();
    assert.dom(".gallery-category").doesNotExist();
    assert.dom(".informations").doesNotExist();
  });

  test("visiting a category URL with gallery appended displays the category title", async function (assert) {
    await visit("/c/the-garage/technical/10/gallery");

    assert.dom(".topic-gallery-page h1").hasText("Technical");
  });
});
