# talkatanormalvolumeflow — quick start

A free dictation app for Mac. Hold a key, talk normally, let go: your words appear wherever your cursor is.
Everything runs on your own Mac. No account, no subscription, no audio sent anywhere.

## Install (2 minutes)

1. Download: **https://github.com/bcremendev/talkatanormalvolumeflow/releases/latest** (grab the `.dmg`).
2. Open the `.dmg` and drag **talkatanormalvolumeflow** to **Applications**.
3. Launch it. If macOS says it "could not verify" the app: open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then launch again. (Only needed until the build is notarized.)
4. A microphone icon appears in your menu bar (top right).
5. Follow the three-step welcome screen:
   - **Microphone**: click Allow.
   - **Accessibility**: macOS opens System Settings. Turn on **talkatanormalvolumeflow**. (This is what lets it see your shortcut key in any app and paste the text.)
   - **Speech model**: click Download (about 490 MB, one time).
6. Recommended: System Settings → Keyboard → **"Press 🌐 key to"** → **Do Nothing**, so the emoji picker stops popping up when you use the Fn key.

## Use it

- Click into any text field (Slack, Gmail, Notes, anywhere).
- **Hold the Fn / 🌐 key**, speak, **release**. Text appears about a second later.
- Press **Esc** while talking to cancel.
- Say **"new line"**, **"new paragraph"**, or **"scratch that"** while dictating.

## Make it yours (menu bar icon → Settings)

- **Shortcut**: Fn, Right Option, Right Command, or record any key combo. Choose *hold to talk* or *press to toggle*.
- **Cleanup**: filler-word removal is on by default. Add fixes for words it mishears (e.g. "zen made" → "ZenMaid").
- **AI polish (optional)**: turn on "Rewrite with a local AI model" for grammar fixes and "no wait, I meant…" corrections. Downloads a ~2 GB model the first time. Adds about half a second. Still 100% on your Mac and still free.
- **History**: every dictation is saved locally so you can copy it again.

## If something's off

- **Nothing happens when I hold the key** → menu bar icon → Settings → Permissions. Accessibility must be on. If you just updated the app, remove it from the Accessibility list and add it back.
- **Text pastes into the wrong place** → click where you want the text *before* holding the key.
- **Needs an Apple Silicon Mac (M1 or newer) on macOS 14 or later.**
