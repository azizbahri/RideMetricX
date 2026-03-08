{{flutter_js}}
{{flutter_build_config}}

// Selects the optimal Flutter web renderer for the current environment.
//
// CanvasKit uses WebGL/WASM for hardware-accelerated canvas rendering, which
// significantly improves performance for the telemetry charts and 3-D
// suspension visualizer at high data volumes.
//
// The HTML renderer is used as a fallback when:
//   • the device is mobile (smaller viewports; CanvasKit WASM overhead is
//     disproportionate, and the HTML renderer handles touch better)
//   • WebGL is unavailable (headless browsers, older hardware, privacy settings)
function _rmxSelectRenderer() {
  if (/Android|iPhone|iPad|iPod/i.test(navigator.userAgent)) {
    return 'html';
  }
  try {
    const canvas = document.createElement('canvas');
    const gl = canvas.getContext('webgl2') || canvas.getContext('webgl');
    if (!gl) return 'html';
  } catch (_) {
    return 'html';
  }
  return 'canvaskit';
}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  onEntrypointLoaded: async function(engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine({
      renderer: _rmxSelectRenderer(),
    });
    await appRunner.runApp();
  },
});
