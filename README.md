# Sentient

A macOS Desktop Overlay app for voice-powered AI assistance using on-device speech recognition and xAI Grok.

<img width="625" height="462" alt="Screenshot 2025-12-17 at 9 45 40 PM" src="https://github.com/user-attachments/assets/706bde0f-603a-4faf-9dc3-889bb9c27b41" />

[App Store](https://apps.apple.com/us/app/sentient-desktop-overlay/id6756657396?mt=12)

Notice: This app is no longer available on the App Store. The final stats are below.

<img width="1007" height="386" alt="Screenshot 2026-06-02 at 5 05 42 PM" src="https://github.com/user-attachments/assets/2f39e252-32e5-46a9-9de3-732b614c2113" />
<img width="984" height="384" alt="Screenshot 2026-06-02 at 5 38 42 PM" src="https://github.com/user-attachments/assets/46aac6b7-ba9b-47b0-ab7c-6711d8c196f3" />

Archived. Final security/privacy pass (Keychain, mic lifetime, confirm-before-send, TLS pin, privacy manifest) done with Cursor before archive.

## Features

- On-device speech-to-text with WhisperKit
- AI responses via xAI Grok API
- Global keyboard shortcuts
- Spotlight-style floating overlay

## Requirements

- macOS 14.0 or later
- xAI API key from https://console.x.ai

## Installation

1. Clone and open in Xcode
2. Build and run
3. Enter your API key in Settings

Shortcuts can be customized in Settings.

## Data Flow

```
User speaks
    |
    v
AVAudioEngine (captures audio)
    |
    v
AudioProcessor (converts to 16kHz mono)
    |
    v
WhisperKit (transcribes to text)
    |
    v
GrokService (sends to xAI API)
    |
    v
Streaming response displayed in UI
```

## Configuration

### API Key

The xAI API key can be configured in two ways:

1. **In-App Settings**: Open the overlay, click the gear icon, and enter your API key.
2. **Environment Variable**: Set `XAI_API_KEY` in your environment (useful for development).

### Grok Model

The app uses the `grok-4-1-fast-reasoning` model by default. To change this, modify the `model` constant in `GrokService.swift`.

## Acknowledgments

- [WhisperKit](https://github.com/argmaxinc/whisperkit) by Argmax for on-device speech recognition
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus for global hotkey management
- [xAI](https://x.ai) for the Grok API
