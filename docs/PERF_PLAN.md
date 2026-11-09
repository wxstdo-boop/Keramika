# Performance plan (no visual changes)

Backup: `backup/perf-before-2026-11-09`
Branch: `perf/whole-app-opt`

## Done / ready

### Splash (`docs/patches/splash_perf.patch`)
Apply:
```bash
git checkout perf/whole-app-opt
git apply docs/patches/splash_perf.patch
```

- Cache splat blob Paths (shape independent of t)
- Skip shine CustomPaint when t≈0/1
- Hoist AnimatedBuilder child
- FilterQuality.medium for 94px logo
- Path steps 30→24 on tiny blobs

## Next (same rules: no visual change)

1. **Home** — verify keepAlive cost; avoid full setState on RC toggle if possible
2. **Habits / Alarms / Tasks** — audit remaining non-builder lists; more RepaintBoundary on cards
3. **Services** — batch notifyListeners; debounce preview saves (sliders already partially handled)
4. **Settings** — split ListenableBuilder scopes (file is huge)
5. **Lock + Ada overlay** — isolate continuous painters with AmbientVsync / boundaries
6. **JSON+AES** — never encrypt on slider preview frames

## How to measure

Use existing `JankProbe` on device:
`/sdcard/Android/data/com.wetidom.keramika/files/perf/keramika_jank.txt`

Look at `build=` vs `raster=` over 16.6ms budget.
