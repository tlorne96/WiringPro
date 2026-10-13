# Building this from VS Code instead of Android Studio

## One-time setup: fetch the real Gradle wrapper jar

This scaffold includes `gradlew` / `gradlew.bat` / `gradle-wrapper.properties`,
but not the actual `gradle-wrapper.jar` binary — it has to come from
Gradle's servers, which this scaffolding script didn't have access to.
Fix it once, from this `android-app/` folder, with either:

- **You have Gradle installed** (`brew install gradle`, `sdk install gradle`, etc):
  run `gradle wrapper --gradle-version 8.13` — it downloads the real jar
  into `gradle/wrapper/`.
- **You don't**: open this folder in Android Studio once — it generates
  the wrapper automatically on import — then go back to VS Code for
  everything after that.

Either way it's a one-time fix; the jar gets committed to your repo like
any other project file after that.

## Day to day

- Install the "Kotlin Language" extension (fwcd.kotlin) for syntax
  highlighting and completion.
- `Cmd/Ctrl+Shift+B` runs "Build debug APK" (the default build task).
- Run the "Build & install" task to push straight to a connected
  tablet/emulator over `adb`.
- The "View logs" task tails logcat filtered to just this app's process.
- You will not get Compose Preview in VS Code — there's no equivalent
  extension. Fastest workaround: keep a debug build installed on the
  tablet and use `./gradlew installDebug` liberally instead of
  eyeballing UI changes before deploying.

