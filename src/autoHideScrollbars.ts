const visibleClass = "scrollbar-visible";
const hideDelay = 850;

export function installAutoHideScrollbars() {
  const timers = new Map<Element, number>();

  const hideLater = (element: Element) => {
    const previous = timers.get(element);
    if (previous) window.clearTimeout(previous);
    const timer = window.setTimeout(() => {
      element.classList.remove(visibleClass);
      timers.delete(element);
    }, hideDelay);
    timers.set(element, timer);
  };

  const showForScroll = (event: Event) => {
    const target =
      event.target instanceof Element
        ? event.target
        : document.scrollingElement;
    if (!target) return;
    target.classList.add(visibleClass);
    hideLater(target);
  };

  document.addEventListener("scroll", showForScroll, true);

  return () => {
    document.removeEventListener("scroll", showForScroll, true);
    for (const [element, timer] of timers) {
      window.clearTimeout(timer);
      element.classList.remove(visibleClass);
    }
    timers.clear();
  };
}
