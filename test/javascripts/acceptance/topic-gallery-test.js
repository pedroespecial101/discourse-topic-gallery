import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import topicFixtures from "discourse/tests/fixtures/topic";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";

acceptance("Topic Gallery", function (needs) {
  needs.user();
  needs.settings({ topic_gallery_enabled: true });

  needs.pretender((server, helper) => {
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

    server.get("/gallery.json", () =>
      helper.response({
        scope: "site",
        scopeTitle: "Latest images",
        scopeUrl: "/gallery",
        images: [],
        hasMore: false,
        nextCursor: null,
        metadataSettings: {},
      })
    );

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

  test("visiting the category gallery route displays the category title", async function (assert) {
    await visit("/gallery/c/general/10");

    assert.dom(".topic-gallery-page h1").hasText("General");
  });
});
