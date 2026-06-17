export default function () {
  this.route("topicGalleryIndex", { path: "/gallery" });
  this.route("topicGalleryCategory", { path: "/gallery/c/:slug/:id" });
  this.route("topicGalleryCategoryShortcut", {
    path: "/c/*categoryPath/:id/gallery",
  });
  this.route("topicGallery", { path: "/gallery/:slug/:id" });
  this.route("topicGallerySlugless", { path: "/gallery/:id" });
}
