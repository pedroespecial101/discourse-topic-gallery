import TopicGalleryBaseRoute from "./topic-gallery-base";

export default class TopicGalleryCategoryRoute extends TopicGalleryBaseRoute {
  buildPath(params) {
    return `/gallery/c/${params.slug}/${params.id}`;
  }
}
