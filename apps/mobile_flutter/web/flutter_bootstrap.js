{{flutter_js}}
{{flutter_build_config}}

// Disable service worker caching during development to prevent stale CDN requests
_flutter.loader.load({
  serviceWorkerSettings: null,
  config: {
    canvasKitBaseUrl: "/canvaskit/"
  }
});
