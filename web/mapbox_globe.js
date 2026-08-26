// Mapbox GL JS bridge for ExplorIfe.
// Each Flutter platform-view element owns its own map instance, stored on the
// element as `el._mb`. Dart calls these global functions via dart:js_interop.
(function () {
  'use strict';

  function libReady() {
    return typeof mapboxgl !== 'undefined';
  }

  // (Re-)draws the route lines from el._routeGeojson (a FeatureCollection,
  // one LineString feature per day, each carrying its own `color` property),
  // if any. Called after the map/style has finished loading — a GL
  // source+layer (unlike the DOM markers in explorifeMapSetGems) does NOT
  // survive a full style swap, so this needs to be re-applied every time
  // style.load fires, not just once. `line-color` reads each feature's own
  // `color` property (data-driven paint) so multiple days render in their
  // own distinct colors from a single source+layer, rather than needing one
  // layer per day.
  function applyRoute(el) {
    var map = el._mb;
    if (!map || !el._routeGeojson) return;
    var srcId = 'ex-route-src', layerId = 'ex-route-line';
    if (map.getSource(srcId)) {
      map.getSource(srcId).setData(el._routeGeojson);
    } else {
      map.addSource(srcId, { type: 'geojson', data: el._routeGeojson });
      map.addLayer({
        id: layerId,
        type: 'line',
        source: srcId,
        layout: { 'line-join': 'round', 'line-cap': 'round' },
        paint: {
          'line-color': ['get', 'color'],
          'line-width': 3,
          'line-opacity': 0.85,
        },
      });
    }
  }

  // Registers Mapbox's terrain-DEM source and turns on elevation relief —
  // invisible at pitch 0 (looking straight down), but pops into real 3D
  // mountain/valley shape the moment the camera tilts (pinch/two-finger-drag,
  // or window.explorifeMapSetTilt below). Ambient, not gated behind the tilt
  // toggle: registering the source is cheap and source+terrain do NOT survive
  // a style swap (same reason applyFog/applyRoute re-run on every
  // 'style.load'), so this must be re-applied there too, not just once at init.
  function applyTerrain(el) {
    var map = el._mb;
    if (!map) return;
    try {
      if (!map.getSource('ex-terrain-dem')) {
        map.addSource('ex-terrain-dem', {
          type: 'raster-dem',
          url: 'mapbox://mapbox.mapbox-terrain-dem-v1',
          tileSize: 512,
          maxzoom: 14,
        });
      }
      map.setTerrain({ source: 'ex-terrain-dem', exaggeration: 1.5 });
    } catch (e) { /* style may not support terrain */ }
  }

  // Applies el._lightPreset (set via window.explorifeMapSetLightPreset) to
  // Mapbox Standard Style's built-in dynamic-lighting config — 'dawn' | 'day'
  // | 'dusk' | 'night'. A Standard-only concept (setConfigProperty targets a
  // config schema that only Standard/Standard Satellite declare), so this is
  // wrapped in try/catch and silently does nothing on any other style rather
  // than erroring. Re-applied on every 'style.load' below since config
  // properties, like fog/terrain/routes, don't survive a style swap.
  function applyLightPreset(el) {
    var map = el._mb;
    if (!map || !el._lightPreset) return;
    try {
      map.setConfigProperty('basemap', 'lightPreset', el._lightPreset);
    } catch (e) { /* active style has no 'basemap' config (not Standard) */ }
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
      applyTerrain(el);
      applyLightPreset(el);
      el._loaded = true;
      if (el._pendingGems != null) {
        var pending = el._pendingGems;
        el._pendingGems = null;
        window.explorifeMapSetGems(el, pending);
      }
      applyRoute(el);
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
      var sel = el._selectedId;
      var kind = g.kind || 'pin';

      if (kind === 'arrow') {
        // Direction arrow along a day's route segment — small, not a pin,
        // not tappable.
        node.className = 'ex-arrow';
        node.style.color = g.color || '#6b4a3a';
        node.style.transform = 'rotate(' + (g.rotation || 0) + 'deg)';
        node.innerHTML =
          '<svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">' +
          '<path d="M12 2L4 22l8-6 8 6z"/></svg>';
        var arrowMarker = new mapboxgl.Marker({ element: node })
          .setLngLat([g.lng, g.lat])
          .addTo(map);
        el._markers[g.id] = arrowMarker;
        return;
      }

      if (kind === 'dayChip') {
        // "DAY N" pill along a day's route — small, not a pin, not tappable.
        node.className = 'ex-daychip';
        node.style.background = g.color || '#1a1a1a';
        node.textContent = g.label || '';
        var chipMarker = new mapboxgl.Marker({ element: node })
          .setLngLat([g.lng, g.lat])
          .addTo(map);
        el._markers[g.id] = chipMarker;
        return;
      }

      node.className = 'ex-gem' +
        (sel === g.id ? ' selected' : (sel ? ' dimmed' : ''));
      var isPhotoPin = !g.label;
      if (g.label) {
        // Numbered pin (e.g. a trip route stop) — takes precedence over
        // photo/emoji, and stays the plain circle: sequence legibility
        // matters more here than a photo. Colored per its own `color` (e.g.
        // that stop's day) when given, falling back to the CSS default
        // otherwise.
        node.classList.add('ex-numbered');
        node.textContent = g.label;
        if (g.color) node.style.background = g.color;
      } else {
        // Plain gem-browsing pin: the gradient-bordered teardrop "photo
        // pin". `node` is a plain sized wrapper (NOT the circle itself) —
        // needed so anchor:'bottom' below (see marker construction) points
        // the pin's actual visual tip at the coordinate, not some smaller
        // inner element's center. Tail is appended BEFORE the head so it
        // paints behind it via plain DOM order — deliberately NOT a
        // z-index trick: confirmed live that a negative z-index here
        // escapes this marker's own stacking context (Mapbox gives the
        // marker position:absolute but no z-index of its own, so it never
        // contains a negative-z-index child) and paints behind the map
        // canvas instead of just behind the pin's head.
        node.classList.add('ex-photopin-wrap');
        var tail = document.createElement('div');
        tail.className = 'ex-photopin-tail';
        var head = document.createElement('div');
        head.className = 'ex-photopin';
        var gap = document.createElement('div');
        gap.className = 'ex-photopin-gap';
        var inner = document.createElement('div');
        inner.className = 'ex-photopin-photo';
        if (g.photo) {
          inner.style.backgroundImage = 'url("' + g.photo + '")';
        } else {
          inner.textContent = g.emoji || '📍';
        }
        gap.appendChild(inner);
        head.appendChild(gap);
        node.appendChild(tail);
        node.appendChild(head);
      }
      node.addEventListener('click', function (e) {
        e.stopPropagation();
        window.explorifeMapSelect(el, g.id);
        if (el._onTap) { try { el._onTap(g.id); } catch (err) {} }
      });
      var marker = new mapboxgl.Marker({
        element: node,
        // The photo pin's visual tip sits at the bottom of its box (unlike
        // every other marker kind here, anchored at their own center) —
        // 'bottom' is what keeps that tip pointing at the actual
        // coordinate instead of the head circle floating above it.
        anchor: isPhotoPin ? 'bottom' : 'center',
      })
        .setLngLat([g.lng, g.lat])
        .addTo(map);
      marker._exNode = node;
      el._markers[g.id] = marker;
    });
  };

  window.explorifeMapSelect = function (el, id) {
    el._selectedId = id;
    // A truthy id means a selection is active → highlight that pin and dim the
    // rest. A null/empty id clears selection → no highlight, no dimming.
    var hasSelection = !!id;
    Object.keys(el._markers).forEach(function (mid) {
      var node = el._markers[mid]._exNode;
      if (!node) return;
      var isSel = mid === id;
      node.classList.toggle('selected', isSel);
      node.classList.toggle('dimmed', hasSelection && !isSel);
    });
  };

  window.explorifeMapZoom = function (el, delta) {
    var map = el._mb; if (!map) return;
    map.easeTo({ zoom: map.getZoom() + delta, duration: 300 });
  };

  window.explorifeMapSetStyle = function (el, style) {
    var map = el._mb; if (!map) return;
    // DOM markers persist across setStyle; the route line does NOT (it's a
    // real GL source+layer, wiped along with the old style) — applyRoute
    // re-adds it from el._routeGeojson once the new style has loaded.
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
      applyTerrain(el);
      applyLightPreset(el);
      applyRoute(el);
    });
  };

  // 'dawn' | 'day' | 'dusk' | 'night' — see applyLightPreset above. Settable
  // any time, whether or not the map/style has finished loading yet (the
  // value is stashed on the element either way, applied immediately if
  // possible, and re-applied on every future style.load).
  window.explorifeMapSetLightPreset = function (el, preset) {
    el._lightPreset = preset;
    applyLightPreset(el);
  };

  // Draws (or clears, with an empty array) one connecting route line per
  // day, each in its own color — a GeoJSON FeatureCollection of LineStrings
  // (one per day), distinct from the DOM marker pins. `routesJson` is a JSON
  // array of {color, points: [{lat,lng}, ...]}; an entry with fewer than 2
  // points is skipped (nothing to draw a line through).
  window.explorifeMapSetRoute = function (el, routesJson) {
    var map = el._mb;
    if (!map) return;
    var routes = [];
    try { routes = JSON.parse(routesJson) || []; } catch (e) { routes = []; }
    var features = [];
    routes.forEach(function (r) {
      if (!r.points || r.points.length < 2) return;
      features.push({
        type: 'Feature',
        properties: { color: r.color || '#6b4a3a' },
        geometry: {
          type: 'LineString',
          coordinates: r.points.map(function (p) { return [p.lng, p.lat]; }),
        },
      });
    });
    if (!features.length) {
      el._routeGeojson = null;
      if (map.getLayer('ex-route-line')) map.removeLayer('ex-route-line');
      if (map.getSource('ex-route-src')) map.removeSource('ex-route-src');
      return;
    }
    el._routeGeojson = { type: 'FeatureCollection', features: features };
    if (!el._loaded) return; // applied by applyRoute once style.load fires
    applyRoute(el);
  };

  window.explorifeMapFlyTo = function (el, lat, lng, zoom) {
    var map = el && el._mb;
    console.log('[flyto] 4 js flyTo map=', !!map, 'lat=', lat, 'lng=', lng,
      'zoom=', zoom);
    if (!map) { console.warn('[flyto] 4! no map bound to el'); return; }
    // easeTo interpolates centre + zoom LINEARLY — unlike flyTo it has no
    // van-Wijk zoom-out arc, so on the globe a long jump can't crest at the
    // black "space" apex (which left the map black). It always settles exactly
    // at the requested city zoom. essential:true keeps it under reduced-motion.
    try {
      map.easeTo({
        center: [lng, lat], zoom: zoom, duration: 900, essential: true,
      });
      console.log('[flyto] 5 easeTo issued; centre now', map.getCenter(),
        'zoom', map.getZoom());
      map.once('moveend', function () {
        console.log('[flyto] 6 moveend; centre', map.getCenter(),
          'zoom', map.getZoom());
      });
    } catch (e) {
      console.error('[flyto] 5! easeTo threw', e);
    }
  };

  // Fly to a gem but lift it into the visible slice ABOVE the bottom sheet.
  // Mapbox's `offset` is a pixel-space shift of the target relative to the
  // container centre (projection handled internally, so it's correct at any
  // zoom/latitude). Negative y moves the target up by sheetPx/2.
  window.explorifeMapFocusGem = function (el, lat, lng, zoom, sheetPx) {
    var map = el._mb; if (!map) return;
    var off = (typeof sheetPx === 'number' && sheetPx > 0) ? sheetPx / 2 : 0;
    map.flyTo({
      center: [lng, lat],
      zoom: zoom,
      offset: [0, -off],
      duration: 1200,
    });
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

    // Clamp padding to the canvas so fitBounds can't throw
    // "Map cannot fit within canvas with the given bounds, padding, and/or offset."
    var canvas = map.getCanvas();
    var w = canvas.clientWidth || canvas.width || 0;
    var h = canvas.clientHeight || canvas.height || 0;
    var padX = Math.max(0, Math.min(60, Math.floor(w / 2) - 20));
    var padTop = Math.max(0, Math.min(120, Math.floor(h * 0.18)));
    var padBottom = Math.max(0, Math.min(320, Math.floor(h * 0.42)));
    if (h > 0 && padTop + padBottom > h - 40) {
      padTop = Math.floor((h - 40) * 0.25);
      padBottom = Math.floor((h - 40) * 0.55);
    }
    try {
      map.fitBounds(b, {
        padding: { top: padTop, bottom: padBottom, left: padX, right: padX },
        maxZoom: 11,
        duration: 1000,
      });
    } catch (e) {
      try { map.flyTo({ center: b.getCenter(), zoom: 3, duration: 1000 }); } catch (e2) {}
    }
  };

  // Notify Dart whenever the camera comes to rest (used by placement mode to
  // read the centre coordinate under the fixed pin). Fires once immediately so
  // the caller has an initial centre before the first gesture.
  window.explorifeMapOnIdle = function (el, fn) {
    var map = el._mb; if (!map) return;
    el._onIdle = fn;
    function emit() {
      if (!el._onIdle) return;
      var c = map.getCenter();
      // assumes non-wrapping bounds (W <= E); the app's regions never straddle
      // the antimeridian, so getWest()/getEast() stay ordered.
      var b = map.getBounds();
      try {
        el._onIdle(c.lat, c.lng,
            b.getWest(), b.getSouth(), b.getEast(), b.getNorth());
      } catch (e) {}
    }
    map.on('moveend', emit);
    // Emit an initial centre as soon as the map is ready.
    if (el._loaded) { emit(); } else { map.once('idle', emit); }
  };

  // Fixed centre "drop" pin rendered INSIDE the map container, so it shares the
  // map canvas's compositing surface and stays glued to centre with zero lag
  // while panning/rotating (unlike a Flutter overlay, which trails on web).
  window.explorifeMapSetCenterPin = function (el, show) {
    if (!el) return;
    if (!show) {
      if (el._centerPin) { el._centerPin.remove(); el._centerPin = null; }
      return;
    }
    if (el._centerPin) return;
    // Ensure absolute children anchor to the container.
    if (getComputedStyle(el).position === 'static') {
      el.style.position = 'relative';
    }
    var wrap = document.createElement('div');
    wrap.className = 'ex-center-pin';
    wrap.style.cssText =
      'position:absolute;left:50%;top:50%;width:0;height:0;' +
      'pointer-events:none;z-index:5;';
    wrap.innerHTML =
      // Ground-shadow ellipse, centred on the exact map centre.
      '<div style="position:absolute;left:0;top:0;width:14px;height:5px;' +
      'background:rgba(0,0,0,0.35);border-radius:50%;' +
      'transform:translate(-50%,-50%);"></div>' +
      // Location pin (Material "location_on"), tip resting on the centre.
      '<svg width="44" height="44" viewBox="0 0 24 24" fill="#FF6B2B" ' +
      'style="position:absolute;left:0;top:0;' +
      'transform:translate(-50%,-90%);' +
      'filter:drop-shadow(0 2px 3px rgba(0,0,0,0.4));">' +
      '<path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5c-1.38 0-2.5-1.12-2.5-2.5s1.12-2.5 2.5-2.5 2.5 1.12 2.5 2.5-1.12 2.5-2.5 2.5z"/>' +
      '</svg>';
    el.appendChild(wrap);
    el._centerPin = wrap;
  };

  // Gesture shield: a transparent layer pinned to the BOTTOM of the map
  // container covering the region the Flutter bottom sheet occupies. Mapbox
  // binds its drag/zoom handlers to its own `.mapboxgl-canvas-container`; this
  // shield is a SIBLING of that element (also a child of `el`) stacked on top,
  // so any pointer/touch/wheel event that reaches the map's DOM inside the
  // sheet area lands on the shield — never on the canvas container — and the
  // map cannot pan or zoom. It's a deterministic DOM-level backstop that does
  // not depend on Flutter's platform-view pointer routing. `coverPx` is the
  // sheet height in CSS pixels (measured from the bottom edge); 0 hides it so
  // the whole map stays interactive.
  // Build a transparent shield div. It deliberately adds NO listeners and does
  // NOT call stopPropagation. Its only job is to be the element the browser
  // hit-tests at that location, so the pointer event never originates inside
  // Mapbox's `.mapboxgl-canvas-container` subtree (where the pan/zoom/wheel
  // handlers are bound) — the map stays put. Crucially, the event still
  // BUBBLES up through `el` to Flutter's glass-pane ancestor, so the overlay
  // (sheet, chips, deck) keeps receiving its own drag/scroll gestures. (An
  // earlier version called stopPropagation here, which also severed the sheet
  // from Flutter and froze it.)
  function makeShield(className) {
    var s = document.createElement('div');
    s.className = className;
    s.style.cssText =
      'position:absolute;z-index:6;pointer-events:auto;background:transparent;' +
      // Disable the browser's own touch gestures (so a vertical drag isn't
      // hijacked as page scroll) without blocking event bubbling — same trick
      // Flutter uses on its glass-pane so it receives the full pointer stream.
      'touch-action:none;';
    return s;
  }

  // Gesture shield over the bottom sheet strip — pinned to the BOTTOM of the
  // map container, full width, `coverPx` tall.
  window.explorifeMapSetShield = function (el, coverPx) {
    if (!el) return;
    if (getComputedStyle(el).position === 'static') {
      el.style.position = 'relative';
    }
    var shield = el._gestureShield;
    if (!shield) {
      shield = makeShield('ex-gesture-shield');
      shield.style.left = '0';
      shield.style.right = '0';
      shield.style.bottom = '0';
      el.appendChild(shield);
      el._gestureShield = shield;
    }
    var h = (typeof coverPx === 'number' && coverPx > 0) ? Math.round(coverPx) : 0;
    shield.style.height = h + 'px';
    shield.style.pointerEvents = h > 0 ? 'auto' : 'none';
  };

  // Gesture shields over the floating overlays that are NOT the bottom sheet —
  // the filter chip row and the card deck. `rectsJson` is a JSON array of
  // {top,left,width,height} in CSS px from the map's top-left; an empty array
  // clears them. We keep a pool of divs and diff it so swipes on those overlays
  // are absorbed exactly like the sheet strip, never reaching the canvas.
  window.explorifeMapSetOverlayShields = function (el, rectsJson) {
    if (!el) return;
    if (getComputedStyle(el).position === 'static') {
      el.style.position = 'relative';
    }
    var rects;
    try { rects = JSON.parse(rectsJson) || []; } catch (e) { rects = []; }
    var pool = el._overlayShields || (el._overlayShields = []);
    // Grow the pool to match the rect count.
    while (pool.length < rects.length) {
      var s = makeShield('ex-overlay-shield');
      el.appendChild(s);
      pool.push(s);
    }
    // Position the shields we need; hide any surplus.
    for (var i = 0; i < pool.length; i++) {
      var d = pool[i];
      if (i < rects.length) {
        var r = rects[i];
        d.style.left = Math.round(r.left) + 'px';
        d.style.top = Math.round(r.top) + 'px';
        d.style.width = Math.round(r.width) + 'px';
        d.style.height = Math.round(r.height) + 'px';
        d.style.pointerEvents = 'auto';
        d.style.display = 'block';
      } else {
        d.style.display = 'none';
        d.style.pointerEvents = 'none';
      }
    }
  };

  // "You are here" blue dot. Created once, then just repositioned on updates.
  window.explorifeMapSetUserLocation = function (el, lat, lng) {
    var map = el._mb; if (!map) return;
    if (el._userMarker) {
      el._userMarker.setLngLat([lng, lat]);
      return;
    }
    var node = document.createElement('div');
    node.className = 'ex-userdot';
    node.style.cssText =
      'width:18px;height:18px;border-radius:50%;background:#1A8CFF;' +
      'border:3px solid #fff;' +
      'box-shadow:0 0 0 4px rgba(26,140,255,0.30),0 1px 4px rgba(0,0,0,0.4);';
    el._userMarker = new mapboxgl.Marker({ element: node })
      .setLngLat([lng, lat])
      .addTo(map);
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

  // North orientation reset: animate the camera back to bearing 0 (north-up)
  // and pitch 0 (no tilt), keeping the current centre and zoom.
  window.explorifeMapResetNorth = function (el) {
    var map = el && el._mb; if (!map) return;
    map.easeTo({ bearing: 0, pitch: 0, duration: 300 });
  };

  // Toggles the 3D terrain tilt: pitched (60°) reveals the relief
  // applyTerrain() already registered ambiently; flat (0°) is the original
  // straight-down view. Bearing is untouched — this is a pure pitch toggle,
  // unlike explorifeMapResetNorth which also re-levels rotation.
  window.explorifeMapSetTilt = function (el, tilted) {
    var map = el && el._mb; if (!map) return;
    map.easeTo({ pitch: tilted ? 60 : 0, duration: 500 });
  };

  // Reports the map bearing (degrees) to Dart on every rotation, so the compass
  // control can appear only when the map is turned off north and fade out once
  // it snaps back. Mirrors explorifeMapOnIdle's callback pattern.
  window.explorifeMapOnRotate = function (el, fn) {
    var map = el && el._mb; if (!map) return;
    el._onRotate = fn;
    function emit() {
      if (!el._onRotate) return;
      try { el._onRotate(map.getBearing()); } catch (e) {}
    }
    map.on('rotate', emit);
    map.on('rotateend', emit);
    // Emit the initial bearing so Dart starts in sync (usually 0).
    if (el._loaded) { emit(); } else { map.once('idle', emit); }
  };

  function escapeHtml(s) {
    return String(s == null ? '' : s)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
  }

  // Shows the trip-route map's tap-a-pin callout — a native Mapbox GL Popup
  // (white rounded box + pointed tail is its own default styling, tuned via
  // the .ex-callout CSS in index.html), auto-anchored so Mapbox flips it to
  // stay in view near an edge instead of clipping. Only one is ever open:
  // replacing el._callout BEFORE removing the old one makes the old popup's
  // own 'close' event (fired by .remove()) see it's already been superseded
  // and skip notifying Dart — only a REAL standalone close (explicit
  // explorifeMapHideCallout, or the user tapping empty map space via
  // closeOnClick) should do that.
  window.explorifeMapShowCallout = function (el, lat, lng, title, subtitle) {
    var map = el._mb; if (!map) return;
    var old = el._callout;
    var html = '<div class="ex-callout-title">' + escapeHtml(title) + '</div>' +
      (subtitle ? '<div class="ex-callout-sub">' + escapeHtml(subtitle) + '</div>' : '');
    var popup = new mapboxgl.Popup({
      closeButton: false,
      closeOnClick: true,
      className: 'ex-callout',
      offset: 14,
    }).setLngLat([lng, lat]).setHTML(html);
    el._callout = popup;
    if (old) old.remove();
    popup.on('close', function () {
      if (el._callout === popup) {
        el._callout = null;
        if (el._onCalloutClose) { try { el._onCalloutClose(); } catch (e) {} }
      }
    });
    popup.addTo(map);
  };

  window.explorifeMapHideCallout = function (el) {
    if (!el) return;
    var popup = el._callout;
    el._callout = null;
    if (popup) popup.remove();
  };

  // Registers Dart's callback for "the callout closed for a reason Dart
  // didn't initiate" (e.g. the user tapped empty map space) — see the
  // el._callout === popup guard above for why a programmatic replace/hide
  // doesn't also fire this.
  window.explorifeMapOnCalloutClose = function (el, fn) {
    el._onCalloutClose = fn;
  };
})();
