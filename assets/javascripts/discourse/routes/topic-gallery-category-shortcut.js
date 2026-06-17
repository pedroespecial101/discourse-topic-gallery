import TopicGalleryBaseRoute from "./topic-gallery-base";

export default class TopicGalleryCategoryShortcutRoute extends TopicGalleryBaseRoute {
  buildPath(params) {
    return `/c/${params.categoryPath}/${params.id}/gallery`;
  }

  buildApiPath(params) {
    return `${this.buildPath(params)}.json`;
  }
}
