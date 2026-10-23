// Align direct CSS transforms when Elm creates tiles or inspection portraits.
// The invisible CSS timeline also pauses for combat and respects reduced motion.
// No JavaScript runs on animation frames after a sprite has been aligned.
(() => {
  const WATER_SPRITE_CLASS = "fightlines-water-frames";
  const WATER_TIMELINE_HTML_ID = "fightlines-water-timeline";
  const WATER_TIMELINE_ANIMATION = "fightlines-water-clock";
  const spriteSelector = `.${WATER_SPRITE_CLASS}`;

  function synchronizeSprites(sprites) {
    if (sprites.size === 0) return;

    const timelineElement = document.getElementById(WATER_TIMELINE_HTML_ID);
    // Read the document's animation list once. Reading each SVG sprite's list
    // separately can repeatedly flush styles while a large map is mounting.
    const activeAnimations = document.getAnimations();
    const timeline = activeAnimations.find(animation =>
      animation.effect?.target === timelineElement &&
      animation.animationName === WATER_TIMELINE_ANIMATION);
    if (!timeline) return;

    const animations = activeAnimations.filter(animation =>
      animation.animationName === WATER_SPRITE_CLASS &&
      sprites.has(animation.effect?.target));
    for (const animation of animations) {
      if (timeline.playState === "running" && timeline.startTime !== null) {
        animation.startTime = timeline.startTime;
      } else {
        // A sprite inserted while paused must show the held frame immediately.
        animation.currentTime = timeline.currentTime;
      }
    }
  }

  const observer = new MutationObserver(records => {
    const sprites = new Set();
    for (const record of records) {
      for (const node of record.addedNodes) {
        if (!(node instanceof Element)) continue;
        if (node.matches(spriteSelector)) sprites.add(node);
        for (const sprite of node.querySelectorAll(spriteSelector)) {
          sprites.add(sprite);
        }
      }
    }
    synchronizeSprites(sprites);
  });

  observer.observe(document.documentElement, { childList: true, subtree: true });
  synchronizeSprites(new Set(document.querySelectorAll(spriteSelector)));
})();
