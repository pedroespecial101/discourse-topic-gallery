import TopicGalleryBaseRoute from "./topic-gallery-base";

export default class TopicGalleryRoute extends TopicGalleryBaseRoute {
  buildPath(params) {
    return `/gallery/${params.slug}/${params.id}`;
  }

  buildApiPath(params) {
    return `/topic-gallery/${params.id}`;
  }
}
