# PaperGraph Phase 3 — FCM research-update notifications

## What this patch does

- Adds an explicit **Research update notifications** switch in Settings.
- Does not request notification permission during app startup.
- Registers the FCM token only after the user opts in and is authenticated.
- Deactivates the token when the user opts out or signs out.
- Shows a foreground update in PaperGraph's notification center/toast.
- Uses a data-only FCM payload and PaperGraph's local renderer for
  background/terminated delivery, so the app controls the notification
  presentation instead of Android's generic FCM renderer.
- Opens the correct `Graph Updates` screen when the notification is tapped.
- Sends one push per active device after the scanner creates new research updates.
- Keeps scanning and the in-app update history working when FCM credentials are
  not configured.

## Required configuration

### GitHub Actions scheduler

The scanner currently runs in GitHub Actions, not inside the Render Free web
service. Add a **repository secret** with this exact name:

```text
FIREBASE_SERVICE_ACCOUNT_JSON
```

Its value must be the complete JSON content of a Firebase service-account key
for the same Firebase project as `FIREBASE_PROJECT_ID`. Do not commit the JSON
file or paste it into GitHub issues/chat.

The workflow passes this secret to the scanner worker. `FIREBASE_PROJECT_ID`
must already exist as a GitHub Actions secret too. The backend uses the
service-account JSON only in the scanner worker to call FCM HTTP v1. Adding it
to Render is optional unless the worker is later moved into Render.

### Flutter machine

From the Flutter project directory:

```powershell
flutter pub get
flutter analyze
flutter test
```

The Android project already contains `google-services.json` and the Firebase
Messaging dependency. iOS still requires normal Firebase APNs setup in the
Apple project before iOS delivery can be tested.

## FCM message contract

The backend sends a **data-only** message. The title and body are inside the
data map so the Flutter background handler can render the notification with
PaperGraph's branding:

```json
{
  "type": "research_updates",
  "title": "New research for Saved graph",
  "body": "3 relevant papers found. Tap to review the updates.",
  "local_graph_id": "graph_...",
  "graph_id": "graph_...",
  "graph_title": "Saved graph",
  "update_count": "3"
}
```

`local_graph_id` is the device's saved-graph ID. It is intentionally different
from the backend monitoring row ID, because the Flutter app uses it to open the
right saved graph's updates screen.

## Safe verification order

1. Apply the patch and run `flutter pub get`.
2. Run Flutter analyze/tests.
3. Deploy the backend.
4. Add `FIREBASE_SERVICE_ACCOUNT_JSON` to Render and redeploy.
5. Sign in on a physical Android device.
6. Open **Settings → Research Monitoring → Research update notifications** and
   enable it.
7. Confirm the backend has an active row in `device_tokens`.
8. Run the GitHub Actions scanner manually once.
9. Confirm a new update exists, then verify the push opens **Research updates**.

Do not use the old temporary Firebase ID-token smoke-test variable as an FCM
service-account secret. They are different credentials with different roles.

## One-graph navigation smoke test

The all-device broadcast test is removed after delivery verification. The safe
replacement is a temporary workflow:

```text
One-graph research notification navigation test
```

It requires an existing `LOCAL_GRAPH_ID` and this exact confirmation:

```text
I_UNDERSTAND_SEND_ONE_GRAPH_TEST
```

The script selects the graph's most recently seen active device token and
requires that the graph already has at least one persisted
`research_updates` row. It sends one data-only `research_updates` message to
that one device. It does not create a paper, modify the graph, or broadcast to
other users. Delete the temporary workflow and script after navigation
verification.

If the `local_graph_id` is not known, first run the separate temporary
workflow `List research notification test candidates`. It prints Graph IDs,
titles, status, update counts, next scan time, and active-device count; it does
not send any notification or print FCM tokens.

If the graph has no persisted update yet, use the temporary
`Scan one monitored graph now` workflow with:

```text
I_UNDERSTAND_SCAN_ONE_GRAPH
```

It makes the selected active graph due, runs the real provider scan, persists
only updates that pass the scanner precision gate, and sends FCM only when at
least one real update is created. If no eligible paper is found, no
notification is expected.

## Precision gate and notification presentation

The scanner now uses a precision-first rule before persisting an update:

- Direct citations are eligible because the relation is explicit.
- A recommendation alone is not eligible for an update notification.
- Non-direct candidates need a score of at least `0.84` and corroboration
  from at least two providers.
- Existing graph papers and duplicate candidates remain excluded.
- Android notifications are tagged per graph so repeated scans can collapse
  into the same graph notification instead of stacking indefinitely.
- The normal notification copy is:
  `New research for <graph title>` and
  `<count> relevant papers found. Tap to review the updates.`
- Background/terminated notifications are rendered by
  `flutter_local_notifications` with the full PaperGraph mark as the large
  icon. The small status-bar glyph remains a monochrome PaperGraph silhouette
  because Android requires notification small icons to be transparent
  monochrome assets.
- Foreground in-app toasts use the full `PaperGraphMark` and follow the
  app's dark/light theme. Android's collapsed system row may still show the
  small OS-sized glyph; expanding the notification shows the branded large
  mark.

This improves precision, but no provider can guarantee zero false positives.
The scanner should continue to be evaluated with real Graph Updates feedback.
## Cold-start notification tap fix

A notification tap that launches a fully terminated Android process must be
read through `getNotificationAppLaunchDetails()`. The local notification
service now forwards that launch payload to the same research deep-link handler
used for warm/background taps, so the app opens `Graph Updates` instead of
stopping at the home screen.
