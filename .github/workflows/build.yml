name: Build Flutter APK

on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4

      - name: Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: 'temurin'
          java-version: '17'

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
          channel: 'stable'
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze code (не блокирует сборку)
        run: flutter analyze || true

      - name: Build release APK
        run: flutter build apk --release --split-per-abi

      - name: Upload APKs as artifact
        uses: actions/upload-artifact@v4
        with:
          name: iptv-player-apk
          path: build/app/outputs/flutter-apk/*.apk
          retention-days: 30
