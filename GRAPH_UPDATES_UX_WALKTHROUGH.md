# Graph Updates UX — Phase 4 foundation

## Included

- `ResearchUpdate` and `MonitoredGraphSummary` Flutter models.
- API client methods for:
  - listing monitoring subscriptions;
  - loading graph updates;
  - pause/resume;
  - mark as read;
  - mark an update as added to the graph.
- `ResearchMonitoringCubit` with loading, empty, error, action, and unread state.
- `GraphUpdatesView` with:
  - monitoring status card;
  - pause/resume/stop controls;
  - unread count;
  - relevance score;
  - relation type and explanation;
  - published/detected date;
  - open paper;
  - mark as read;
  - add-to-graph intent state.
- Library graph cards now expose an `Updates` action and a `Research updates` menu item.
- Focused model/state tests.

## Important behavior

The current backend `add-to-graph` endpoint records the user's explicit add intent.
It does not silently mutate the local graph snapshot. Automatic graph mutation is
intentionally not implemented.

FCM, deep links from system notifications, and unread badges on the library card
are intentionally deferred until the notification transport and summary endpoint
are finalized.

## Verification

Flutter tooling was not available in the build sandbox, so `flutter analyze` and
`flutter test` must be run on the Windows project after applying the patch:

```powershell
cd "C:\Users\hp\AndroidStudioProjects\Flutter Pro\flutter_app"
flutter analyze
flutter test
```
