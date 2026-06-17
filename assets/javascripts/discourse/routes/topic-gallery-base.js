import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class TopicGalleryBaseRoute extends DiscourseRoute {
  controllerName = "topic-gallery";
  templateName = "topic-gallery";

  queryParams = {
    username: { refreshModel: false, replace: true },
    post_number: { refreshModel: false, replace: true },
  };

  titleToken() {
    const model = this.modelFor(this.routeName);
    if (model?.result?.scopeTitle) {
      return i18n("discourse_topic_gallery.page_title", {
        title: model.result.scopeTitle,
      });
    }
  }

  buildPath() {
    return "/gallery";
  }

  buildApiPath() {
    return `${this.buildPath()}.json`;
  }

  async model(params, transition) {
    const qp = transition.to?.queryParams || {};
    const urlParams = new URLSearchParams(window.location.search);
    const qs = new URLSearchParams();

    for (const [key, value] of Object.entries(qp)) {
      if (value) {
        qs.set(key, value);
      }
    }

    for (const key of ["from_date", "to_date"]) {
      const value = urlParams.get(key);
      if (value) {
        qs.set(key, value);
      }
    }

    const qsStr = qs.toString();
    const apiPath = this.buildApiPath(params);
    const result = await ajax(`${apiPath}${qsStr ? `?${qsStr}` : ""}`);

    return {
      apiPath,
      pagePath: this.buildPath(params),
      result,
      from_date: qs.get("from_date") || "",
      to_date: qs.get("to_date") || "",
    };
  }

  resetController(controller, isExiting) {
    if (isExiting) {
      controller.filtersVisible = false;
      controller.username = "";
      controller.from_date = "";
      controller.to_date = "";
      controller.post_number = "";
    }
  }

  setupController(controller, model) {
    super.setupController(controller, model);
    window.scrollTo(0, 0);
    controller.setupModel(model);
  }
}
