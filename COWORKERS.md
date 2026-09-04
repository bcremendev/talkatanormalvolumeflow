# talkatanormalvolumeflow — quick start

A free dictation app for Mac. Hold a key, talk normally, let go: your words appear wherever your cursor is.
Everything runs on your own Mac. No account, no subscription, no audio sent anywhere.

Works on Apple Silicon Macs (M1 or newer) running macOS 14 or later.

## Install (2 minutes)

1. Download the `.dmg` from **https://github.com/bcremendev/talkatanormalvolumeflow/releases/latest**.
2. Double-click the downloaded file. A window opens with the app on the left and an Applications folder on the right. **Drag the app onto the Applications folder.**
3. Open your **Applications** folder and double-click **talkatanormalvolumeflow**.
   - If macOS says it *"could not verify"* the app: click **Done**, open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then double-click the app again. This happens once.
4. The app window opens with a **4-step setup** checklist. Do the steps in order; each turns green when done:
   - **Allow Microphone**: click the button, then click *Allow* in the macOS prompt.
   - **Open Accessibility Settings**: click the button, then in the System Settings window that opens, turn **ON** the switch next to *talkatanormalvolumeflow*.
   - **Download Speech Model**: about 490 MB, one time. This is what turns your voice into text.
   - **Download AI Polish** (recommended, about 2 GB, one time): speech-to-text types exactly what you say, including "um", repeated words, and "Tuesday, no wait, Wednesday". AI polish rewrites each sentence into what you meant. It runs on your Mac, nothing goes to the internet, and it's free. You can click *Skip for now* and turn it on later.
5. When the checklist says **"You're all set"**, you're done. Close the window. The app keeps running as a mic icon in your menu bar (top right of your screen).

Recommended: System Settings → Keyboard → **"Press 🌐 key to"** → **Do Nothing**, so the emoji picker stops popping up when you use the Fn key.

## Use it

1. Click into any text box (Slack, Gmail, Notes, anywhere).
2. **Hold the Fn / 🌐 key** (bottom-left of your keyboard), speak, **let go**.
3. Text appears about a second later.

- Press **Esc** while talking to cancel.
- Say **"new line"**, **"new paragraph"**, or **"scratch that"** while dictating.
- Want to practice? Open the app (double-click it in Applications, or click the menu bar mic icon → *Open talkatanormalvolumeflow*) and use the **"Try it right here"** box on the Home screen.

## Make it yours

Open the app and use the sidebar:

- **Shortcut**: pick Fn, Right Option, Right Command, or record any key. Choose *hold to talk* or *press to toggle*. Turn on *Open automatically when I log in*.
- **Cleanup & AI Polish**: turn AI polish on or off, and teach it words it gets wrong (e.g. "zen made" → "ZenMaid").
- **History**: every dictation is saved locally so you can copy it again.

## If something's off

- **Nothing happens when I hold the key** → open the app → *Permissions & About*. Accessibility must show a green check. If it's green and still nothing, quit the app (menu bar icon → Quit) and open it again.
- **I don't see the menu bar icon** → if your menu bar is crowded, macOS or a menu-bar tidying app may hide it. Just double-click the app in Applications to bring up the window.
- **Text pastes into the wrong place** → click where you want the text *before* holding the key.
