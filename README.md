# GlanceHUD

A small macOS helper that runs in the background. Press a shortcut and it captures the main screen, sends the image to Claude, and shows the answer as text in the bottom-right corner of the screen. The background is transparent and there is no box; the text is grey and semi-transparent so it stays out of the way. The text lets clicks through to the app underneath, never takes focus, and appears on every desktop and above full-screen apps. The older dark-box look can be turned on in the settings.

| Shortcut | What it does |
|---|---|
| ⌃I | Captures the screen and asks Claude. The answer is prepared in the background and does not appear by itself |
| ⌃, | Shows or hides the answer in the bottom-right corner. Sends no new request; the last answer stays in memory |
| ⌃⌥↑ / ⌃⌥↓ | Makes the text half a point larger / smaller. The new size is saved to the settings file |
| ⌃⌥← | Resets the text to 9 points |
| ⌃⌥K | Quits the app |

Nothing appears on screen by itself, errors included. Pressing ⌃I clears the text on screen and prepares the answer in the background; press ⌃, to see it. If the answer has not arrived yet you see a faint "…", which is replaced when the answer comes in. Text you have opened stays on screen until you press ⌃, again. If you want answers to appear by themselves, turn on `autoShow` in the settings.

The interface text and the default prompt are in Turkish. The answer comes back in the language of the prompt, so set `prompt` in the settings file to use another language.

## Install

Requires macOS 14 or later and a Swift 6 toolchain (Xcode 16 or the matching command line tools).

```bash
git clone https://github.com/D0ktay/GlanceHUD.git
cd GlanceHUD
./scripts/build-app.sh                 # creates build/GlanceHUD.app
cp -R build/GlanceHUD.app /Applications/
open /Applications/GlanceHUD.app
```

There is no Dock icon; a small icon appears in the menu bar (quit and the settings file are there).

### 1. API key

Add your Anthropic API key to the Keychain (the command prompts for the key, so it is not written to your shell history):

```bash
security add-generic-password -s GlanceHUD -a anthropic-api-key -w
```

On first use macOS asks "GlanceHUD wants to use the Keychain"; choose "Always Allow". The question can come up once more after you rebuild the app.

The app looks for the key in this order: the `ANTHROPIC_API_KEY` environment variable → the Keychain → the `"apiKey"` field in the settings file.

### 2. Screen recording permission

macOS asks for permission on the first ⌃I. Turn GlanceHUD on under System Settings > Privacy & Security > Screen & System Audio Recording, then quit and reopen the app.

Open the app with `open`, not by running the bare binary (`.../MacOS/GlanceHUD`) from Terminal; otherwise the permission prompt is addressed to Terminal or VS Code.

### 3. About the shortcuts

System shortcuts take priority over app shortcuts. If one of the app's shortcuts collides with a system shortcut, the app shows a warning on screen at launch.

The font-size shortcuts include Option because macOS uses ⌃↑, ⌃↓ and ⌃← for Mission Control and switching desktops.

The shortcuts are set up for the Turkish Q keyboard layout. ⌃I works on both the I and İ keys. ⌃, is the comma key, not the Ö key. While GlanceHUD is running, these keys go to GlanceHUD in every app. For example, ⌃I no longer acts as Tab in Terminal.

### Start at login

Add `/Applications/GlanceHUD.app` under System Settings > General > Login Items with "+".

## Settings

`~/Library/Application Support/GlanceHUD/config.json` (created on first launch; the menu bar item "Ayar dosyasını aç" opens it). Changes take effect on the next ⌃I, with no restart. Missing or invalid fields fall back to the default.

| Field | Default | Description |
|---|---|---|
| `model` | `claude-opus-5-5` | Claude model to use |
| `effort` | `low` | Thinking depth: `low`, `medium`, `high`, `xhigh`, `max`. Lower means a faster answer. Leave empty for the model's default |
| `prompt` | (Turkish prompt) | The question sent along with the image. The answer comes back in the language of this text |
| `autoShow` | `false` | If `true`, answers (and errors) appear by themselves as soon as they arrive |
| `autoHideSeconds` | `10` | Only with `autoShow` on: seconds after the answer finishes before it hides. `0` turns this off |
| `maxTokens` | `16000` | Upper limit for the answer (thinking included) |
| `maxImageLongEdge` | `2048` | Maximum length of the image's long edge, in pixels |
| `jpegQuality` | `0.85` | Image quality (0.3 to 1) |
| `hudWidth` | `480` | Maximum width of the text; longer lines wrap (points) |
| `fontSize` | `11` | Text size (points, from 6 to 32). ⌃⌥↑ and ⌃⌥↓ change it too |
| `textGray` | `0.5` | Text tone: `0` black, `1` white (when the box is off) |
| `textOpacity` | `0.7` | Text visibility: `0.15` very faint … `1` fully solid (when the box is off) |
| `showBox` | `false` | If `true`, the text is shown inside a dark, semi-transparent box with the model name underneath |
| `showMenuBarIcon` | `true` | Menu bar icon |
| `apiKey` | — | Optional; the Keychain is preferred |

## Things to know

- If you have chosen a capture region, only that region is sent (menu bar > "Yakalama bölgesini seç…"; "Tüm ekranı yakala" returns to the full screen). Otherwise every ⌃I sends an image of the whole main screen to the Anthropic API. Do not press it while confidential information is on screen.
- The text window asks to be left out of screen recordings and screen sharing with `sharingType = .none`. Whether that is honoured depends on the recording app; some newer recording tools can capture it anyway.
- Because the text lets clicks through, it cannot be scrolled. Very long answers are cut off at 70% of the screen height ("…").
- If Claude declines a request for safety reasons, the server retries automatically with another model that Anthropic suggests; if that one declines too, an explanation appears on screen.

## Development

```bash
./scripts/test.sh                                         # unit tests (quiet; full log in build/logs/test.log)
./scripts/build-app.sh                                    # app bundle
build/GlanceHUD.app/Contents/MacOS/GlanceHUD --snapshot /tmp/hud.png   # sample image (on light and dark backgrounds), needs no permission

# One request against the real API (a small generated image, not the screen; costs less than a cent)
GLANCE_LIVE_TEST=1 ANTHROPIC_API_KEY="$(security find-generic-password -s GlanceHUD -a anthropic-api-key -w)" \
  swift test --filter LiveAPITests
```

Layout: `Sources/GlanceCore` holds everything that does not need AppKit (settings, request, stream parsing, state machine) together with its tests; `Sources/GlanceHUD` holds the window, shortcuts, screen capture and menu.
