import Component from "@glimmer/component";
import { on } from "@ember/modifier";
import { service } from "@ember/service";
import { modifier } from "ember-modifier";
import ConditionalLoadingSpinner from "discourse/components/conditional-loading-spinner";
import { helperContext } from "discourse/lib/helpers";
import DiscourseURL from "discourse/lib/url";
import formatDate from "discourse/ui-kit/helpers/d-format-date";
import { i18n } from "discourse-i18n";
import PhotoSwipe from "../lib/photoswipe";
import PhotoSwipeLightbox from "../lib/photoswipe-lightbox";

function initGridLightbox(gridElement, { onLastSlide }) {
  const siteSettings = helperContext().siteSettings;
  const currentUser = helperContext()?.currentUser;
  const caps = helperContext().capabilities;
  const canDownload =
    !siteSettings.prevent_anons_from_downloading_files || !!currentUser;

  const lb = new PhotoSwipeLightbox({
    gallery: gridElement,
    children: "a.lightbox",
    showHideAnimationType: "zoom",
    counter: false,
    escKey: false,
    loop: false,
    tapAction(pt, event) {
      if (event.target.classList.contains("pswp__img")) {
        lb.pswp?.element?.classList.toggle("pswp--ui-visible");
      } else {
        lb.pswp?.close();
      }
    },
    paddingFn(viewportSize) {
      if (viewportSize.x < 1200 || caps.isMobileDevice) {
        return { top: 0, bottom: 0, left: 0, right: 0 };
      }
      return { top: 20, bottom: 75, left: 20, right: 20 };
    },
    pswpModule: PhotoSwipe,
  });

  lb.addFilter("itemData", (data) => {
    const el = data.element;
    if (!el) {
      return data;
    }

    const width = Number(el.getAttribute("data-target-width"));
    const height = Number(el.getAttribute("data-target-height"));

    data.thumbCropped = true;
    data.src = el.getAttribute("href");
    data.title = el.title;
    data.details = el.querySelector(".informations")?.textContent || "";
    data.w = data.width = width;
    data.h = data.height = height;

    return data;
  });

  lb.on("afterInit", () => {
    lb.pswp.element.addEventListener("keydown", (event) => {
      if (event.key === "Escape") {
        event.stopPropagation();
        event.preventDefault();
        lb.pswp.close();
      }
    });
  });

  lb.on("change", () => {
    const pswp = lb.pswp;
    if (pswp.currIndex >= pswp.getNumItems() - 1) {
      onLastSlide?.();
    }
  });

  lb.on("uiRegister", () => {
    const escapeHtml = (text) =>
      text.replace(/[<>&"]/g, (c) => `&#${c.charCodeAt(0)};`);

    lb.pswp.ui.registerElement({
      name: "custom-counter",
      order: 6,
      isButton: false,
      appendTo: "bar",
      onInit: (el, pswp) => {
        pswp.on("change", () => {
          el.textContent = `${pswp.currIndex + 1} / ${pswp.getNumItems()}`;
        });
      },
    });

    if (canDownload) {
      lb.pswp.ui.registerElement({
        name: "download-image",
        order: 7,
        isButton: true,
        tagName: "a",
        title: i18n("lightbox.download"),
        html: {
          isCustomSVG: true,
          inner:
            '<path d="M20.5 14.3 17.1 18V10h-2.2v7.9l-3.4-3.6L10 16l6 6.1 6-6.1ZM23 23H9v2h14Z" id="pswp__icn-download"/>',
          outlineID: "pswp__icn-download",
        },
        onInit: (el, pswp) => {
          el.setAttribute("download", "");
          el.setAttribute("target", "_blank");
          el.setAttribute("rel", "noopener");
          pswp.on("change", () => {
            el.href = pswp.currSlide.data.element?.dataset.downloadHref || "";
          });
        },
      });
    }

    lb.pswp.ui.registerElement({
      name: "caption",
      order: 11,
      isButton: false,
      appendTo: "root",
      html: "",
      onInit: (caption, pswp) => {
        pswp.on("change", () => {
          const { title, details, element } = pswp.currSlide.data;
          const parts = [];

          // Build title with inline post info
          if (title || element) {
            let titleHtml = "";

            if (title) {
              const escaped = title.replace(
                /[<>&"]/g,
                (c) => `&#${c.charCodeAt(0)};`
              );
              titleHtml = `<span class='pswp__caption-text'>${escaped}</span>`;
            }

            // Add post link inline
            if (element) {
              const card = element.closest(".gallery-card");
              if (card) {
                const username = card.querySelector(".mention")?.textContent;
                const postLink = card.querySelector(".gallery-post-link");
                const postDate =
                  card.querySelector(".gallery-post-date")?.textContent;
                const topicLink = card.querySelector(".gallery-topic-link");
                const category = card.querySelector(".gallery-category");
                const postBits = [username, postDate, category?.textContent]
                  .filter(Boolean)
                  .join(" · ");

                if (postBits || postLink || topicLink) {
                  const postInfoBits = [];
                  if (postBits) {
                    postInfoBits.push(escapeHtml(postBits));
                  }
                  if (topicLink) {
                    postInfoBits.push(escapeHtml(topicLink.textContent));
                  }
                  if (postLink) {
                    const postNumber = postLink.textContent;
                    const postUrl = postLink.getAttribute("href");
                    postInfoBits.push(
                      `<a href="${postUrl}" class="pswp__caption-post-link">${postNumber}</a>`
                    );
                  }

                  const postInfo =
                    `<span class='pswp__caption-post'>` +
                    postInfoBits.join(" · ") +
                    `</span>`;
                  titleHtml = titleHtml ? `${titleHtml} ${postInfo}` : postInfo;
                }
              }
            }

            if (titleHtml) {
              parts.push(`<div class='pswp__caption-title'>${titleHtml}</div>`);
            }
          }

          if (details) {
            parts.push(`<div class='pswp__caption-details'>${details}</div>`);
          }

          caption.innerHTML = parts.join("");
        });
      },
    });
  });

  lb.init();
  return lb;
}

// Applies CSS classes to visually group consecutive images from the same post,
// accounting for the current number of grid columns and row wrapping.
function applyGroupBorders(grid) {
  const cards = Array.from(grid.querySelectorAll(".gallery-card"));
  if (!cards.length) {
    return;
  }

  const cols = getComputedStyle(grid)
    .getPropertyValue("grid-template-columns")
    .split(" ").length;

  cards.forEach((card, index) => {
    const group = card.dataset.postId;
    const col = index % cols;
    const prev = index > 0 ? cards[index - 1].dataset.postId : null;
    const next =
      index < cards.length - 1 ? cards[index + 1].dataset.postId : null;

    const sameGroupLeftInRow = col > 0 && prev === group;
    const isGroupStart = prev !== group;
    const isGroupEnd = next !== group;
    const isGroupFirst = !sameGroupLeftInRow;
    const isRowStart = col === 0 && !isGroupStart;
    const isRowEnd =
      (col === cols - 1 || index === cards.length - 1) && !isGroupEnd;

    card.classList.toggle("group-start", isGroupStart);
    card.classList.toggle("group-end", isGroupEnd);
    card.classList.toggle("group-first", isGroupFirst);
    card.classList.toggle("row-start", isRowStart);
    card.classList.toggle("row-end", isRowEnd);
  });
}

// Renders the image grid with lightbox support, infinite scroll, and
// hover highlighting of same-post image groups.
export default class TopicGalleryGrid extends Component {
  @service router;

  observer = null;

  // Infinite scroll: triggers loadMore when the sentinel element becomes visible
  sentinel = modifier((element) => {
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !this.args.isLoading) {
          this.args.loadMore?.();
        }
      },
      { rootMargin: "300px" }
    );
    this.observer.observe(element);

    return () => {
      this.observer?.disconnect();
      this.observer = null;
    };
  });

  stopShimmer = (event) => {
    event.target.closest(".image-wrapper")?.classList.add("no-shimmer");
  };

  // Sets up post-group borders, lightbox, hover highlighting, and internal link navigation
  groupBorders = modifier((element) => {
    const run = () => applyGroupBorders(element);
    let lb = null;
    let loadingMore = false;
    let needsRebuild = false;

    const buildLightbox = () => {
      lb?.destroy();
      lb = initGridLightbox(element, {
        onLastSlide: async () => {
          if (loadingMore) {
            return;
          }
          loadingMore = true;
          try {
            await this.args.loadMore?.();
          } finally {
            loadingMore = false;
          }
        },
      });
      lb.on("close", () => {
        if (needsRebuild) {
          needsRebuild = false;
          buildLightbox();
        }
      });
    };

    const mutationObserver = new MutationObserver(() => {
      run();
      if (lb?.pswp) {
        const pswp = lb.pswp;
        pswp.options.dataSource.items = [
          ...element.querySelectorAll("a.lightbox"),
        ];
        const idx = pswp.currIndex;
        if (idx > 0) {
          pswp.refreshSlideContent(idx - 1);
        }
        pswp.refreshSlideContent(idx);
        pswp.refreshSlideContent(idx + 1);
        needsRebuild = true;
      } else {
        buildLightbox();
      }
    });
    mutationObserver.observe(element, { childList: true });

    const resizeObserver = new ResizeObserver(run);
    resizeObserver.observe(element);

    let hoveredGroup = null;

    const onOver = (e) => {
      const card = e.target.closest(".gallery-card");
      const group = card?.dataset.postId ?? null;
      if (group === hoveredGroup) {
        return;
      }
      if (hoveredGroup) {
        element
          .querySelectorAll(".gallery-card.group-hover")
          .forEach((c) => c.classList.remove("group-hover"));
      }
      hoveredGroup = group;
      if (group) {
        element
          .querySelectorAll(`.gallery-card[data-post-id="${group}"]`)
          .forEach((c) => c.classList.add("group-hover"));
      }
    };

    const onLeave = () => {
      if (hoveredGroup) {
        element
          .querySelectorAll(".gallery-card.group-hover")
          .forEach((c) => c.classList.remove("group-hover"));
        hoveredGroup = null;
      }
    };

    const onClick = (e) => {
      if (e.target.closest("[data-user-card]")) {
        return;
      }
      const link = e.target.closest("a.gallery-post-link");
      if (!link) {
        return;
      }
      const href = link.getAttribute("href");
      if (href && DiscourseURL.isInternal(href)) {
        e.preventDefault();
        e.stopPropagation();
        this.router.transitionTo(href);
      }
    };

    element.addEventListener("mouseover", onOver);
    element.addEventListener("mouseleave", onLeave);
    element.addEventListener("click", onClick);

    run();
    buildLightbox();

    return () => {
      lb?.destroy();
      mutationObserver.disconnect();
      resizeObserver.disconnect();
      element.removeEventListener("mouseover", onOver);
      element.removeEventListener("mouseleave", onLeave);
      element.removeEventListener("click", onClick);
    };
  });

  <template>
    <div class="topic-gallery-container">
      {{#if @images.length}}
        <div class="gallery-grid" {{this.groupBorders}}>
          {{#each @images as |image|}}
            <div class="gallery-card" data-post-id={{image.postId}}>
              <a
                href={{image.url}}
                class="lightbox image-preview-link"
                title={{image.topicTitle}}
                data-download-href={{image.downloadUrl}}
                data-target-width={{image.width}}
                data-target-height={{image.height}}
              >
                <span class="image-wrapper">
                  <img
                    src={{image.thumbnailUrl}}
                    class="gallery-image"
                    loading="lazy"
                    alt=""
                    {{on "load" this.stopShimmer}}
                    {{on "error" this.stopShimmer}}
                  />
                </span>
                {{#if @metadataSettings.showImageDetails}}
                  <span class="informations">{{image.width}}×{{image.height}}
                    {{image.filesize}}</span>
                {{/if}}
              </a>
              <div class="gallery-meta">
                {{#if @metadataSettings.showAuthor}}
                  {{#if image.username}}
                    <a
                      href="/u/{{image.username}}"
                      data-user-card={{image.username}}
                      class="mention"
                    >@{{image.username}}</a>
                  {{/if}}
                {{/if}}

                {{#if @metadataSettings.showPostDate}}
                  {{#if image.postCreatedAt}}
                    <span class="gallery-post-date">{{formatDate
                        image.postCreatedAt
                      }}</span>
                  {{/if}}
                {{/if}}

                {{#if @metadataSettings.showPostLink}}
                  {{#if image.postUrl}}
                    <a
                      href={{image.postUrl}}
                      class="gallery-post-link"
                    >#{{image.postNumber}}</a>
                  {{/if}}
                {{/if}}

                {{#if @metadataSettings.showTopicTitle}}
                  {{#if image.topicUrl}}
                    <a
                      href={{image.topicUrl}}
                      class="gallery-topic-link"
                    >{{image.topicTitle}}</a>
                  {{/if}}
                {{/if}}

                {{#if @metadataSettings.showCategory}}
                  {{#if image.category}}
                    <a
                      href={{image.category.url}}
                      class="gallery-category"
                    >{{image.category.name}}</a>
                  {{/if}}
                {{/if}}
              </div>
            </div>
          {{/each}}
        </div>

        {{#if @hasMore}}
          <div class="gallery-sentinel" {{this.sentinel}}>
            <ConditionalLoadingSpinner @condition={{@isLoading}} />
          </div>
        {{/if}}
      {{else if @isLoading}}
        <ConditionalLoadingSpinner @condition={{true}} />
      {{else}}
        <div class="no-images-message">
          <p>{{i18n "discourse_topic_gallery.no_images_found"}}</p>
        </div>
      {{/if}}
    </div>
  </template>
}
