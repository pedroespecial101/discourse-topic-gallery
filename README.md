# Discourse Topic Gallery

Adds image gallery pages to Discourse using images attached to visible posts.

The plugin keeps the original per-topic gallery and also supports latest image
galleries for a whole site or a category.

![topic gallery](https://d11a6trkgmumsb.cloudfront.net/original/4X/2/6/c/26cd39b7206c407d0f8dc10040e212686823603d.jpeg)

## Features

- Topic galleries for images posted in one topic.
- Sitewide latest image gallery.
- Category latest image gallery, with optional subcategory inclusion.
- Latest-first ordering by post date and post/upload reference.
- Cursor pagination for sitewide, category, and topic galleries.
- Deduplication so one upload appears once, linked to its latest visible post.
- Filters by username and post date range in all scopes.
- Optional topic-only filter by starting post number.
- Admin settings for displayed metadata.
- Respects Discourse visibility rules for topics, posts, categories, private
  messages, whispers, ignored users, and excluded categories.

## Gallery URLs

Sitewide latest images:

```text
/gallery
```

Category gallery:

```text
/gallery/c/:category-slug/:category-id
```

For example:

```text
/gallery/c/support/12
```

Category galleries can also be opened by appending `/gallery` to a normal
category URL:

```text
/c/support/12/gallery
/c/parent-category/support/12/gallery
```

Topic gallery:

```text
/gallery/:topic-slug/:topic-id
/gallery/:topic-id
```

The legacy JSON endpoint is still available:

```text
/topic-gallery/:topic-id.json
```

## Settings

Enable the plugin with `topic_gallery_enabled`.

Access can be limited with `topic_gallery_allowed_groups`. Categories can be
excluded with `topic_gallery_excluded_categories`.

The following settings control metadata shown on gallery cards and in lightbox
captions:

- `topic_gallery_show_author`
- `topic_gallery_show_post_date`
- `topic_gallery_show_topic_title`
- `topic_gallery_topic_title_links_to_post`
- `topic_gallery_show_category`
- `topic_gallery_show_post_link`
- `topic_gallery_show_image_details`

Category galleries include direct child categories by default. Disable
`topic_gallery_category_include_subcategories` to show only images from the
selected category.

Use `topic_gallery_minimum_image_size` to exclude small images such as icons.

## Visibility and access

Gallery pages only include uploads from posts the current visitor is allowed to
see. Hidden and deleted posts are excluded, private messages are excluded from
sitewide and category galleries, and private or excluded categories are not
included. Logged-in users do not see images from users they have ignored.

Use `topic_gallery_allowed_groups` if gallery discovery should be limited to
staff or another group.

## Performance

Sitewide and category galleries are built from live Discourse post/upload data
and use cursor pagination rather than exact counts. This avoids maintaining a
separate gallery index while keeping the first implementation small.

The live query approach has been smoke-tested on a Discourse site with roughly
39,000 topics, 361,000 posts, 67,000 uploads, and 50,000 post image references
above the configured minimum image size. On that dataset, warm JSON requests for
the first page of the sitewide gallery returned in about one second, with
category and topic galleries in the same range. A cold sitewide request can be
slower because the database still has to find, rank, and deduplicate eligible
post image references before returning the first page.

Forums with substantially larger image histories, for example hundreds of
thousands of post image references, should validate the query on their own data.
Cursor pagination keeps page traversal stable and avoids expensive exact counts,
but it does not replace the ranking work needed to build the gallery page.

For very large forums, a future implementation could add a precomputed gallery
index table populated by jobs/hooks when posts and uploads change.

## Installation

Follow the Discourse plugin installation guide:

https://meta.discourse.org/t/install-a-plugin/19157

## Documentation

Read the plugin topic at meta.discourse.org:

https://meta.discourse.org/t/topic-gallery-plugin/394953?u=canapin

## Development

This repository includes server request specs and Ember acceptance tests. The
GitHub Actions workflow uses Discourse's reusable plugin CI workflow.

Useful local checks:

```bash
pnpm lint:prettier
pnpm lint:js
pnpm lint:hbs
pnpm lint:css
pnpm lint:types
```

Run the Rails and QUnit plugin tests from a Discourse development environment.

## License

MIT
