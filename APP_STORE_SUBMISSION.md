# VoiceFlow App Store Submission Notes

## Privacy Position

VoiceFlow performs speech transcription on device using the speech model bundled in the app. It does not upload microphone audio or transcripts to a server, does not track users, and does not include advertising or analytics code.

## Permissions

- Microphone: used only while the user starts a dictation session.
- Accessibility: used only to paste the completed transcript into the currently focused app. VoiceFlow does not read screen contents, inspect keystrokes, or monitor other apps.
- Pasteboard: used transiently as the transport for Command-V insertion. VoiceFlow restores the previous pasteboard contents after paste when the pasteboard has not changed.

## Data Handling

- Temporary WAV recordings are created in the app temporary directory and removed after transcription completes or fails.
- Transcripts remain local in the app UI until the user clears them or quits the app.
- User preferences, including shortcuts and startup-guide completion, are stored in the app's own UserDefaults domain.

## Suggested App Review Notes

VoiceFlow is a local dictation utility. To test system-wide insertion:

1. Launch VoiceFlow.
2. Grant Microphone permission when prompted.
3. Grant Accessibility permission in System Settings > Privacy & Security > Accessibility.
4. Place the cursor in TextEdit, Terminal, Spotlight, or another editable text field.
5. Press Control + Shift + J to start recording.
6. Press Control + Shift + K to stop recording.
7. The transcript is pasted into the focused text field.

The speech model is included in the app bundle under Contents/Resources/Models. No network access is required for transcription.

## App Store Connect Privacy Answers

- Tracking: No.
- Data linked to the user: No, unless you later add accounts, analytics, diagnostics, or cloud sync.
- Data used for tracking: No.
- Audio Data: Not collected by the developer if it remains local and is deleted after transcription.
- User Content: Not collected by the developer if transcripts remain local and are not transmitted.

Revisit these answers if you add analytics, crash reporting, support upload, account login, cloud sync, remote model download, or telemetry.
