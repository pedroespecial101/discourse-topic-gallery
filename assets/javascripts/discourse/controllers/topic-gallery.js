import { tracked } from "@glimmer/tracking";
import Controller from "@ember/controller";
import { action } from "@ember/object";
import { cancel, later } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";

export default class TopicGalleryController extends Controller {
  @service router;

  @tracked images = [];
  @tracked hasMore = false;
  @tracked isLoading = false;
  @tracked total = null;
  @tracked postsCount = 0;
  @tracked scope = "topic";
  @tracked scopeTitle = "";
  @tracked scopeUrl = "";
  @tracked title = "";
  @tracked slug = "";
  @tracked topicId = null;
  @tracked categoryId = null;
  @tracked username = "";
  @tracked from_date = "";
  @tracked to_date = "";
  @tracked post_number = "";
  @tracked filtersVisible = false;
  @tracked metadataSettings = {};

  queryParams = ["username", "post_number"];
  apiPath = "";
  pagePath = "";
  page = 0;
  nextCursor = null;
  _fetchId = 0;
  _filterTimer = null;

  _scheduleFetch() {
    cancel(this._filterTimer);
    this._filterTimer = later(this, this._fetchAndSyncUrl, 50);
  }

  _syncUrl() {
    const params = this._filterParams;
    const qs = params.toString();
    window.history.replaceState(null, "", `${this.pagePath}${qs ? `?${qs}` : ""}`);
  }

  async _fetchAndSyncUrl() {
    await this.fetchImages();
    this._syncUrl();
  }

  setupModel(model) {
    this.apiPath = model.apiPath;
    this.pagePath = model.pagePath;
    this.from_date = model.from_date || "";
    this.to_date = model.to_date || "";
    this._applyResult(model.result);
  }

  _applyResult(result) {
    this.images = result.images;
    this.hasMore = result.hasMore;
    this.nextCursor = result.nextCursor;
    this.page = result.page || 0;
    this.total = result.total ?? null;
    this.postsCount = result.postsCount || 0;
    this.scope = result.scope || "topic";
    this.scopeTitle = result.scopeTitle || result.title || "";
    this.scopeUrl = result.scopeUrl || "";
    this.title = result.title || this.scopeTitle;
    this.slug = result.slug || "";
    this.topicId = result.topicId || result.id || null;
    this.categoryId = result.categoryId || null;
    this.metadataSettings = result.metadataSettings || {};
    this.isLoading = false;
  }

  get _filterParams() {
    const params = new URLSearchParams();
    if (this.username) {
      params.set("username", this.username);
    }
    if (this.from_date) {
      params.set("from_date", this.from_date);
    }
    if (this.to_date) {
      params.set("to_date", this.to_date);
    }
    if (this.showPostNumberFilter && this.hasPostNumberFilter) {
      params.set("post_number", this.post_number);
    }
    return params;
  }

  buildApiUrl(cursor = null) {
    const params = this._filterParams;
    if (cursor) {
      params.set("cursor", cursor);
    }
    const qs = params.toString();
    return `${this.apiPath}${qs ? `?${qs}` : ""}`;
  }

  async fetchImages() {
    const fetchId = ++this._fetchId;
    this.isLoading = true;

    try {
      const result = await ajax(this.buildApiUrl());
      if (fetchId !== this._fetchId) {
        return;
      }
      this._applyResult(result);
    } catch (error) {
      if (fetchId !== this._fetchId) {
        return;
      }
      popupAjaxError(error);
    } finally {
      if (fetchId === this._fetchId) {
        this.isLoading = false;
      }
    }
  }

  @action
  async loadMore() {
    if (this.isLoading || !this.hasMore || !this.nextCursor) {
      return;
    }

    this.isLoading = true;

    try {
      const result = await ajax(this.buildApiUrl(this.nextCursor));
      this.images = [...this.images, ...result.images];
      this.hasMore = result.hasMore;
      this.nextCursor = result.nextCursor;
      this.page = result.page || this.page + 1;
      this.total = result.total ?? this.total;
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isLoading = false;
    }
  }

  get showPostNumberFilter() {
    return this.scope === "topic";
  }

  get hasKnownTotal() {
    return this.total !== null && this.total !== undefined;
  }

  get hasScopeBackLink() {
    return this.scope !== "site" && this.scopeUrl;
  }

  get hasPostNumberFilter() {
    return this.post_number && parseInt(this.post_number, 10) > 1;
  }

  get showPostNumberChip() {
    return this.showPostNumberFilter && this.hasPostNumberFilter;
  }

  get hasFilters() {
    return (
      this.username ||
      this.from_date ||
      this.to_date ||
      (this.showPostNumberFilter && this.hasPostNumberFilter)
    );
  }

  @action
  clearFilters() {
    this.username = "";
    this.from_date = "";
    this.to_date = "";
    this.post_number = "";
    this._scheduleFetch();
  }

  @action
  navigateToScope(event) {
    event.preventDefault();
    this.router.transitionTo(event.currentTarget.getAttribute("href"));
  }

  @action
  toggleFilters() {
    this.filtersVisible = !this.filtersVisible;
  }

  @action
  clearPostNumber() {
    this.post_number = "";
    this._scheduleFetch();
  }

  @action
  updatePostNumber(event) {
    this.post_number = event.target.value || "";
    this._scheduleFetch();
  }

  @action
  updateUsername(val) {
    const selected = Array.isArray(val) ? val[0] : val;
    this.username = selected || "";
    this._scheduleFetch();
  }

  @action
  updateFromDate(date) {
    this.from_date = date || "";
    this._scheduleFetch();
  }

  @action
  updateToDate(date) {
    this.to_date = date || "";
    this._scheduleFetch();
  }
}
