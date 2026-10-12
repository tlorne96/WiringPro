#!/bin/bash
# VS Code tooling for WiringPro — run AFTER setup.sh and 02-android-core.sh,
# from inside the 'wiringpro' folder.
# Adds: gradlew/gradlew.bat launcher scripts, gradle.properties (AndroidX fix),
# gradle-wrapper.properties, .vscode/tasks.json, and README-VSCODE.md.
#
# NOTE: this does NOT include the actual gradle-wrapper.jar binary — that has
# to be fetched with network access. See README-VSCODE.md for the one-time fix.
set -e

mkdir -p "$(dirname "android-app/gradlew")"
cat > android-app/gradlew << 'VSC_EOF'
#!/bin/sh
# Minimal Gradle wrapper launcher. Locates gradle-wrapper.jar next to this
# script and delegates to it. Missing the jar itself? See README-VSCODE.md —
# it has to be fetched once with network access, which this environment
# didn't have when this file was generated.
DIR="$(cd "$(dirname "$0")" && pwd)"
CLASSPATH="$DIR/gradle/wrapper/gradle-wrapper.jar"

if [ ! -f "$CLASSPATH" ]; then
  echo "gradle-wrapper.jar is missing — see README-VSCODE.md for the one-time fix." >&2
  exit 1
fi

if [ -n "$JAVA_HOME" ]; then
  JAVACMD="$JAVA_HOME/bin/java"
else
  JAVACMD="java"
fi

exec "$JAVACMD" -classpath "$CLASSPATH" org.gradle.wrapper.GradleWrapperMain "$@"

VSC_EOF
echo "Wrote android-app/gradlew"

mkdir -p "$(dirname "android-app/gradlew.bat")"
cat > android-app/gradlew.bat << 'VSC_EOF'
@echo off
set DIR=%~dp0
set CLASSPATH=%DIR%gradle\wrapper\gradle-wrapper.jar

if not exist "%CLASSPATH%" (
  echo gradle-wrapper.jar is missing — see README-VSCODE.md for the one-time fix.
  exit /b 1
)

if defined JAVA_HOME (
  set JAVA_EXE=%JAVA_HOME%\bin\java.exe
) else (
  set JAVA_EXE=java.exe
)

"%JAVA_EXE%" -classpath "%CLASSPATH%" org.gradle.wrapper.GradleWrapperMain %*

VSC_EOF
echo "Wrote android-app/gradlew.bat"

mkdir -p "$(dirname "android-app/gradle.properties")"
cat > android-app/gradle.properties << 'VSC_EOF'
org.gradle.jvmargs=-Xmx2048m
# Required — every AndroidX dependency in this project assumes this is set.
# Without it, the build fails at the first androidx.* import.
android.useAndroidX=true
kotlin.code.style=official

VSC_EOF
echo "Wrote android-app/gradle.properties"

mkdir -p "$(dirname "android-app/gradle/wrapper/gradle-wrapper.properties")"
cat > android-app/gradle/wrapper/gradle-wrapper.properties << 'VSC_EOF'
distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionUrl=https\://services.gradle.org/distributions/gradle-8.5-bin.zip
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists

VSC_EOF
echo "Wrote android-app/gradle/wrapper/gradle-wrapper.properties"

mkdir -p "$(dirname "android-app/.vscode/tasks.json")"
cat > android-app/.vscode/tasks.json << 'VSC_EOF'
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Build debug APK",
      "type": "shell",
      "command": "./gradlew assembleDebug",
      "options": { "cwd": "${workspaceFolder}" },
      "group": { "kind": "build", "isDefault": true },
      "problemMatcher": []
    },
    {
      "label": "Install to connected device",
      "type": "shell",
      "command": "./gradlew installDebug",
      "options": { "cwd": "${workspaceFolder}" },
      "group": "build",
      "problemMatcher": []
    },
    {
      "label": "Build & install",
      "dependsOrder": "sequence",
      "dependsOn": ["Build debug APK", "Install to connected device"],
      "problemMatcher": []
    },
    {
      "label": "View logs (WiringPro)",
      "type": "shell",
      "command": "adb logcat --pid=$(adb shell pidof -s com.timlorne.wiringpro)",
      "options": { "cwd": "${workspaceFolder}" },
      "problemMatcher": []
    }
  ]
}

VSC_EOF
echo "Wrote android-app/.vscode/tasks.json"

mkdir -p "$(dirname "android-app/README-VSCODE.md")"
cat > android-app/README-VSCODE.md << 'VSC_EOF'
# Building this from VS Code instead of Android Studio

## One-time setup: fetch the real Gradle wrapper jar

This scaffold includes `gradlew` / `gradlew.bat` / `gradle-wrapper.properties`,
but not the actual `gradle-wrapper.jar` binary — it has to come from
Gradle's servers, which this scaffolding script didn't have access to.
Fix it once, from this `android-app/` folder, with either:

- **You have Gradle installed** (`brew install gradle`, `sdk install gradle`, etc):
  run `gradle wrapper --gradle-version 8.5` — it downloads the real jar
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

VSC_EOF
echo "Wrote android-app/README-VSCODE.md"

chmod +x android-app/gradlew
echo ""
echo "Done. Read android-app/README-VSCODE.md for the one remaining manual step."
