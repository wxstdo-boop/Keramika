# How to Run the Preview

## Reproduce uncommitted artifacts
1. Ensure Flutter SDK is available on PATH
2. Run `flutter build web --release` to produce `build/web/`

## Run the server
Serve the static files from `build/web/` on port 8084:

```powershell
powershell -NoProfile -Command "(Start-Process -FilePath 'python' -ArgumentList '-m','http.server','8084','--bind','127.0.0.1','--directory','build\web' -RedirectStandardOutput 'C:\Games\keramika\.freebuff\preview-a5f03a4d-0de4-47ee-a471-d9e32e2a45c4.log' -RedirectStandardError 'C:\Games\keramika\.freebuff\preview-a5f03a4d-0de4-47ee-a471-d9e32e2a45c4.log.err' -WindowStyle Hidden -PassThru).Id"
```

Confirm: `powershell -NoProfile -Command "Get-Process -Id <pid>"`
Verify: `curl http://127.0.0.1:8084/`
