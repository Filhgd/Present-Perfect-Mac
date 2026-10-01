# Present Perfect

Connect your Mac to a projector, TV or meeting room screen and be ready in two key presses.
No searching through System Settings for mirroring, and no hunting for the sound icon in the menu bar.

When you plug in a screen your Mac doesn't know yet, a panel appears in the middle of your screen:

<img src="assets/screenshot.png" alt="The Present Perfect panel: Present, Mirror or Desk, and where the sound plays" width="518">

- **Present** (1): the projector shows your slides, your Mac keeps the presenter notes.
- **Mirror** (2): the same picture on both screens.
- **Desk** (3): a normal monitor. Present Perfect stays out of the way and leaves everything to macOS.

In the same panel you choose where the sound plays: the projector or TV, your Mac, or your headphones.
A **Test** button plays a short sound, so you know it works before the room hears your video.

If the picture isn't right, choose a **Resolution**:

- **Automatic**: what macOS chooses. This is the default.
- **Larger text**: for a large screen where everything looks tiny.
- **Safe**: a standard resolution for a projector that flickers, stays black or shows no signal.
- **Other…**: every resolution the screen offers.

After a change, Present Perfect asks whether to keep it. Without an answer, the previous resolution comes back after 15 seconds.

Press **Return** and the choice is remembered for that screen. The next time you connect it,
Present Perfect does the same thing by itself and shows a short note with what it did.
At your own desk it stays completely quiet.

## Installation

1. Download `Present-Perfect-macOS.zip` from the [latest release](../../releases/latest).
2. Double-click the zip to unpack it.
3. Drag **Present Perfect** to your **Applications** folder and open it.

The app is signed and notarized by Apple. The first time, macOS asks whether you want to open an
app downloaded from the internet: click **Open**.

Requires macOS 14 (Sonoma) or later, on Apple silicon or Intel.

## How to use it

| What you want                          | What to do                                                        |
|----------------------------------------|-------------------------------------------------------------------|
| Choose how to use a new screen         | Plug it in. The panel opens. Press **1**, **2** or **3**.         |
| Choose where the sound plays           | Click a sound output in the panel (**T** plays a test sound), or pick one under **Sound Output** in the menu bar icon's menu. This works at any time, also without a screen. |
| Remember the choice for this screen    | Leave **Remember as** on, give it a name and press **Return**.    |
| Open the panel at any moment           | Press **Control-Option-P** (⌃⌥P), or click the menu bar icon.     |
| Fix a picture that is too small, flickers or stays black | In Present or Mirror, choose **Larger text** or **Safe** under **Resolution** in the panel, then click **Keep**. |
| Black out the projector for a moment   | In Present, press **C** in the panel (or click **Curtain**).      |
| See which screen the audience sees     | While the panel is open in Present, the other screen says so.     |
| Change or forget a remembered screen   | **Settings…** in the menu bar icon's menu or under **⋯** in the panel lists every remembered screen. |

When you unplug, the sound moves off the screen's speakers and a short note tells you where it plays now.
While a projector or TV is connected for presenting, your Mac doesn't fall asleep.

## Good to know

- **No permissions needed.** Present Perfect uses standard macOS features to arrange screens and
  choose the sound output. It needs no access to your files, camera, microphone or screen.
- **Updates.** Once a day Present Perfect checks this page for a new version and installs it by itself,
  but never while you're presenting. It only reads the public release page; nothing about you is sent.
  Before installing, it checks that the new version is signed by the same developer and notarized by Apple.
  Use **Check for Updates…** in the menu to check now, or turn off **Update Automatically** there.
- **Welcome.** The first time you open it, a short welcome explains the basics and asks whether
  Present Perfect may open at login (recommended, so it's ready when you plug in). You can change this
  later in the **⋯** menu or the menu bar icon's menu, where **How It Works…** shows the welcome again.
- **Resolution.** Present Perfect only uses the resolutions that the screen, cable and adapter report to macOS.
  Some adapters (VGA in particular) can't pass on the projector's details. macOS then offers a general list, and
  **Safe** picks 1024 × 768 when it's available.
- **Volume.** Many projectors and TVs don't let your Mac change their volume. Use the screen's own remote.
- **ClickShare.** If the ClickShare app adds a sound output to your Mac, it appears in the panel's sound choices.
- **Teams and Zoom.** These apps have their own setting to share your computer's sound when you share
  your screen ("Include sound" in Teams, "Share sound" in Zoom). Turn it on there when you play a video.
- **Languages.** English, Dutch and French. Present Perfect follows your Mac's language, or choose one in **Settings…**.

## Something not working?

Open the menu bar icon's menu (or **⋯** in the panel) and choose **Copy Diagnostics**. This copies a
short report of the screens, their resolutions and the sound devices your Mac sees. Paste it in an issue on this page.

## Uninstall

Quit Present Perfect from its menu, then drag it from Applications to the Trash.
If it still shows up in **System Settings > General > Login Items**, remove it there.

## Building from source

Requires Xcode command line tools. Run `./build_app.sh`; the app appears in `dist/`.

## Support

Present Perfect is free. If it saves you time, you can [buy me a coffee](https://buymeacoffee.com/filiphaegdorens).

## License

[MIT](LICENSE) © Filip Haegdorens
