# Performance plan (no visual change)

Branch: `perf/whole-app-opt`  
Backup: `backup/perf-before-2026-11-09`

## Done in this branch

### Splash (`lib/screens/splash_screen.dart`)
- Cache splat blob Paths across shine frames
- Skip CustomPaint when shine t≈0/1
- Hoist AnimatedBuilder child for shine layer
- FilterQuality.medium for 94px logo
- Path steps 30→24 on tiny blobs

### Routes (`lib/utils/page_transitions.dart`)
- Removed ScaleTransition from `slideUpRoute` (slide+fade only)

### Ambient loops (`lib/utils/ambient_loop.dart`)
- Default `everyFrames` 3→4 (~15 fps decorative ticks)

## Still open (next commits)

1. **Home** — narrow RC toggle rebuild (avoid full setState if possible)
2. **Habits / Alarms / Tasks** — audit any remaining non-builder lists
3. **Settings** — split ListenableBuilder scopes
4. **Lock + Ada overlay** — ensure continuous painters use AmbientVsync
5. **JSON+AES** — never encrypt on slider preview frames

## Measure

JankProbe log on device:
`/sdcard/Android/data/com.wetidom.keramika/files/perf/keramika_jank.txt`

Budget 16.6ms at 60Hz. Watch `build=` vs `raster=`.
