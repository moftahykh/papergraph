# PaperGraph — Flutter Client

Mobile and web interface for PaperGraph, featuring an interactive literature graph canvas, custom animations, and offline-first reading library.

## Architecture

- **State Management:** `flutter_bloc` / Cubit (Strict unidirectional data flow).
- **Network:** Communicates exclusively with PaperGraph FastAPI Backend via `Dio`.
- **Canvas Rendering:** `CustomPainter` + `InteractiveViewer` with smooth 60fps pan/zoom and edge differentiation (citation arrows vs undirected similarity links).
- **Local Persistence:** `Hive` binary key-value storage for offline graph viewing and bookmarks.

## Verification

```bash
flutter analyze
flutter test
```
