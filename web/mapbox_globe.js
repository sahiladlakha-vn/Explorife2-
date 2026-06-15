// Mapbox GL JS bridge for ExplorIfe.
// Each Flutter platform-view element owns its own map instance, stored on the
// element as `el._mb`. Dart calls these global functions via dart:js_interop.
(function () {
  'use strict';

  function libReady() {
    return typeof mapboxgl !== 'undefined';
  }

  window.explorifeMapInit = function (el, token, style, onTap) {
    if (!libReady()) {
      console.error('[explorife] mapbox-gl not loaded');
      return;
    }
    if (el._mb) {
      return; // already initialised
    }
    mapboxgl.accessToken = token;
    var map = new mapboxgl.Map({
      container: el,
      style: 'mapbox://styles/mapbox/' + style,
      center: [110.0, 16.0],
      zoom: 2.6,
      projection: 'globe',
      attributionControl: false,
    });

    el._mb = map;
    el._markers = {};
    el._onTap = onTap;
    el._pendingGems = null;
    el._loaded = false;
    el._selectedId = null;

    function applyFog() {
      try {
        map.setFog({
          'color': 'rgb(186, 210, 235)',
          'high-color': 'rgb(36, 92, 223)',
          'horizon-blend': 0.02,
          'space-color': 'rgb(11, 11, 25)',
          'star-intensity': 0.6,
        });
      } catch (e) { /* style may not support fog */ }
    }

    map.on('style.load', function () {
      applyFog();
      el._loaded = true;
      if (el._pendingGems != null) {
        var pending = el._pendingGems;
        el._pendingGems = null;
        window.explorifeMapSetGems(el, pending);
      }
    });

    var ro = new ResizeObserver(function () { map.resize(); });
    ro.observe(el);
    setTimeout(function () { map.resize(); }, 250);
  };

  window.explorifeMapSetGems = function (el, gemsJson) {
    var map = el._mb;
    if (!map) return;
    if (!el._loaded) { el._pendingGems = gemsJson; return; }

    var gems = [];
    try { gems = JSON.parse(gemsJson); } catch (e) { return; }

    var incoming = {};
    gems.forEach(function (g) { incoming[g.id] = g; });

    // Remove markers no longer present.
    Object.keys(el._markers).forEach(function (id) {
      if (!incoming[id]) {
        el._markers[id].remove();
        delete el._markers[id];
      }
    });

    // Add new markers.
    gems.forEach(function (g) {
      if (el._markers[g.id]) return;
      var node = document.createElement('div');
      node.className = 'ex-gem' + (el._selectedId === g.id ? ' selected' : '');
      node.textContent = g.emoji || '📍';
      node.addEventListener('click', function (e) {
        e.stopPropagation();
        window.explorifeMapSelect(el, g.id);
        if (el._onTap) { try { el._onTap(g.id); } catch (err) {} }
      });
      var marker = new mapboxgl.Marker({ element: node })
        .setLngLat([g.lng, g.lat])
        .addTo(map);
      marker._exNode = node;
      el._markers[g.id] = marker;
    });
  };

  window.explorifeMapSelect = function (el, id) {
    el._selectedId = id;
    Object.keys(el._markers).forEach(function (mid) {
      var node = el._markers[mid]._exNode;
      if (!node) return;
      if (mid === id) node.classList.add('selected');
      else node.classList.remove('selected');
    });
  };

  window.explorifeMapZoom = function (el, delta) {
    var map = el._mb; if (!map) return;
    map.easeTo({ zoom: map.getZoom() + delta, duration: 300 });
  };

  window.explorifeMapSetStyle = function (el, style) {
    var map = el._mb; if (!map) return;
    // DOM markers persist across setStyle; only re-apply fog.
    map.setStyle('mapbox://styles/mapbox/' + style);
    map.once('style.load', function () {
      try {
        map.setFog({
          'color': 'rgb(186, 210, 235)',
          'high-color': 'rgb(36, 92, 223)',
          'horizon-blend': 0.02,
          'space-color': 'rgb(11, 11, 25)',
          'star-intensity': 0.6,
        });
      } catch (e) {}
    });
  };

  window.explorifeMapFlyTo = function (el, lat, lng, zoom) {
    var map = el._mb; if (!map) return;
    map.flyTo({ center: [lng, lat], zoom: zoom, duration: 1200 });
  };

  window.explorifeMapFitGems = function (el, gemsJson) {
    var map = el._mb; if (!map) return;
    var gems = [];
    try { gems = JSON.parse(gemsJson); } catch (e) { return; }
    if (!gems.length) return;
    if (gems.length === 1) {
      map.flyTo({ center: [gems[0].lng, gems[0].lat], zoom: 11, duration: 1000 });
      return;
    }
    var b = new mapboxgl.LngLatBounds();
    gems.forEach(function (g) { b.extend([g.lng, g.lat]); });
    map.fitBounds(b, {
      padding: { top: 120, bottom: 320, left: 60, right: 60 },
      maxZoom: 11,
      duration: 1000,
    });
  };

  window.explorifeMapLocate = function (el) {
    var map = el._mb; if (!map || !navigator.geolocation) return;
    navigator.geolocation.getCurrentPosition(function (pos) {
      map.flyTo({
        center: [pos.coords.longitude, pos.coords.latitude],
        zoom: 12, duration: 1200,
      });
    });
  };
})();
