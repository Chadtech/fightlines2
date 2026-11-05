// One bounded queue for background images and audio. Gameplay never awaits it.
function createAssetLoader({ concurrency = 4, timeoutMs = 15000, retryDelayMs = 1000 } = {}) {
  const entries = new Map();
  const queue = [];
  let active = 0;

  function drain() {
    while (active < concurrency && queue.length) {
      queue.sort((a, b) => a.priority - b.priority);
      const entry = queue.shift();
      active += 1;
      void attempt(entry);
    }
  }

  async function attempt(entry) {
    const controller = new AbortController();
    let timer;
    try {
      const timeout = new Promise((_, reject) => {
        timer = setTimeout(() => {
          reject(new Error(`asset timed out after ${timeoutMs}ms: ${entry.key}`));
          controller.abort();
        }, timeoutMs);
      });
      const value = await Promise.race([entry.start(controller.signal), timeout]);
      entry.resolve(value);
    } catch (error) {
      entry.failures += 1;
      if (entry.failures < 3) {
        // Backoff does not occupy a download slot or hold up other assets.
        setTimeout(() => {
          queue.push(entry);
          drain();
        }, retryDelayMs * entry.failures);
      } else {
        entries.delete(entry.key);
        entry.reject(error);
      }
    } finally {
      clearTimeout(timer);
      active -= 1;
      drain();
    }
  }

  function load(key, start, priority = 0) {
    let entry = entries.get(key);
    if (!entry) {
      entry = { key, start, priority, failures: 0 };
      entry.promise = new Promise((resolve, reject) => {
        entry.resolve = resolve;
        entry.reject = reject;
      });
      entries.set(key, entry);
      queue.push(entry);
    }
    entry.priority = Math.min(entry.priority, priority);
    drain();
    return entry.promise;
  }

  function preloadImages(paths) {
    for (const path of paths) {
      void load(`image ${path}`, signal => new Promise((resolve, reject) => {
        const image = new Image();
        image.fetchPriority = "low";
        function cleanup() {
          image.onload = null;
          image.onerror = null;
          signal.removeEventListener("abort", abort);
        }
        function abort() {
          cleanup();
          image.src = "";
          reject(new Error(`image loading aborted: ${path}`));
        }
        image.onload = async () => {
          try {
            await image.decode();
            cleanup();
            resolve();
          } catch (error) {
            cleanup();
            reject(error);
          }
        };
        image.onerror = () => {
          cleanup();
          reject(new Error(`image loading failed: ${path}`));
        };
        signal.addEventListener("abort", abort, { once: true });
        image.src = path;
      }), 1).catch(error => console.warn(`Asset ${path}:`, error));
    }
  }

  return { load, preloadImages };
}
