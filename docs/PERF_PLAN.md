# Performance plan (no visual change)

Branch: `perf/whole-app-opt`  
Backup: `backup/perf-before-2026-11-09`

## Done

### Splash
- Cache splat blob Paths, skip idle shine frames, medium filter, path steps 30→24

### Routes
- Removed ScaleTransition from slideUpRoute

### Ambient
- Default everyFrames 3→4

### Lock
- AmbientVsync on glass decorative loop

### Ada overlay (patch)
- AmbientVsync on typing-bubble dots

## Open
1. Settings ListenableBuilder scopes
2. JSON/AES not on slider preview frames (audit)
3. Any remaining continuous CustomPaint without AmbientVsync

## Measure
JankProbe: `/sdcard/Android/data/com.wetidom.keramika/files/perf/keramika_jank.txt`
