const assert = require("node:assert/strict");
const fs = require("node:fs");
const test = require("node:test");
const vm = require("node:vm");

function loadTracker() {
  const listeners = {};
  const registrations = [];
  const requests = [];
  class Element {
    constructor(link = null) {
      this.link = link;
    }
    closest(selector) {
      assert.equal(selector, "a[data-entry-id][data-open-target]");
      return this.link;
    }
  }
  const context = {
    Element,
    document: {
      addEventListener(type, callback, options) {
        registrations.push({ type, options });
        listeners[type] = callback;
      },
    },
    fetch(url, options) {
      requests.push({ url, options });
      return Promise.reject(new Error("offline"));
    },
    encodeURIComponent,
  };
  vm.runInNewContext(
    fs.readFileSync("priv/static/js/entry-opens.js", "utf8"),
    context,
  );
  return { Element, listeners, registrations, requests };
}

function link(entryId = "entry /1", openTarget = "content") {
  return { dataset: { entryId, openTarget } };
}

test("registers exactly one capture-phase listener per event type", () => {
  const { registrations } = loadTracker();
  assert.deepEqual(registrations.map(({ type }) => type), ["click", "auxclick"]);
  assert.ok(registrations.every(({ options }) => options?.capture === true));
});

test("tracks regular, Cmd-click, Ctrl-click, and keyboard click activations", () => {
  const { Element, listeners, requests } = loadTracker();
  const event = {
    type: "click",
    button: 0,
    detail: 1,
    target: new Element(link()),
    preventDefault() {
      assert.fail("navigation must not be prevented");
    },
  };
  listeners.click(event);
  listeners.click({ ...event, metaKey: true, target: new Element(link("cmd")) });
  listeners.click({ ...event, ctrlKey: true, target: new Element(link("ctrl")) });
  listeners.click({ ...event, detail: 0, target: new Element(link("key", "comments")) });
  assert.deepEqual(requests.map(({ url }) => url), [
    "/entry/entry%20%2F1/open/content",
    "/entry/cmd/open/content",
    "/entry/ctrl/open/content",
    "/entry/key/open/comments",
  ]);
  assert.ok(requests.every(({ options }) => options.method === "POST" && options.keepalive));
});

test("ignores right clicks and invalid or missing link data", () => {
  const { Element, listeners, requests } = loadTracker();
  listeners.click({ type: "click", button: 2, target: new Element(link()) });
  listeners.auxclick({ type: "auxclick", button: 2, target: new Element(link()) });
  listeners.click({ type: "click", button: 0, target: new Element(link("", "content")) });
  listeners.click({ type: "click", button: 0, target: new Element(link("id", "unknown")) });
  listeners.click({ type: "click", button: 0, target: new Element(null) });
  assert.deepEqual(requests, []);
});

test("delegated listeners track links added or replaced after initialization", () => {
  const { Element, listeners, requests } = loadTracker();
  let currentLink = link("original");
  const event = () => ({
    type: "click",
    button: 0,
    target: new Element(currentLink),
  });
  listeners.click(event());
  currentLink = link("replacement", "comments");
  listeners.click(event());
  assert.deepEqual(requests.map(({ url }) => url), [
    "/entry/original/open/content",
    "/entry/replacement/open/comments",
  ]);
});

test("tracks only middle auxclicks and ignores unrelated links", () => {
  const { Element, listeners, requests } = loadTracker();
  listeners.auxclick({ type: "auxclick", button: 0, target: new Element(link()) });
  listeners.auxclick({ type: "auxclick", button: 1, target: new Element(link("c", "comments")) });
  listeners.click({ type: "click", button: 0, target: new Element(null) });
  assert.deepEqual(requests.map(({ url }) => url), ["/entry/c/open/comments"]);
});
