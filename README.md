# J-Notes

A modern, feature-rich notes application for iOS and iPadOS built with SwiftUI.

## Features

### 📝 Core Functionality

- **Create and manage notes** with rich text support
- **Color-coded notes** for better organization
- **Pin important notes** to keep them at the top
- **Search and filter** through your notes effortlessly

### 📅 Calendar Integration

- View notes organized by creation date
- Calendar view for easy temporal navigation

### 🗺️ Location-Based Notes

- Add location information to your notes
- View notes on an interactive map
- Location-aware note management

### ⏰ Reminders

- Set reminders for your notes
- Local notifications to keep you on track
- Never miss important tasks

### 🌐 Localization

- Multi-language support (English, Czech)
- Localized interface and content

### 🔐 Privacy & Security

- Data stored locally on your device
- File-based storage with complete file protection
- Privacy-focused design with PrivacyInfo manifest

## Technical Stack

- **Framework**: SwiftUI
- **Language**: Swift
- **Platforms**: iOS, iPadOS
- **Architecture**: MVVM with Observable Objects
- **Storage**: File-based JSON with encryption
- **Services**:
  - CoreLocation for location tracking
  - UserNotifications for reminders
  - MapKit for map visualization

## Project Structure

```
notes/
├── Models/              # Data models
│   └── NoteModel.swift
├── Views/               # SwiftUI views
│   ├── ContentView.swift
│   ├── NotesView.swift
│   ├── CalendarView.swift
│   ├── MapView.swift
│   └── Notes/
│       ├── NoteListView.swift
│       ├── NoteDetailView.swift
│       ├── NoteFormView.swift
│       └── NoteRowView.swift
├── Stores/              # State management
│   └── NotesStore.swift
├── Managers/            # Service managers
│   ├── LocationManager.swift
│   └── NotificationManager.swift
├── Intents/             # Siri Shortcuts
│   └── CreateNoteIntent.swift
└── Localizations/       # i18n resources
    ├── en.lproj/
    └── cs.lproj/
```

## Requirements

- iOS 15.0+
- iPadOS 15.0+
- Xcode 14.0+
- Swift 5.7+

## Installation

1. Clone the repository:

```bash
git clone https://github.com/RobertLib/j-notes.git
cd j-notes
```

2. Open the project in Xcode:

```bash
open notes.xcodeproj
```

3. Select your target device or simulator

4. Build and run the project (⌘R)

## Usage

### Creating a Note

1. Tap the "+" button in the notes view
2. Enter a title and content
3. Optionally add:
   - A color tag
   - A reminder date/time
   - Location information
4. Save your note

### Organizing Notes

- **Pin**: Tap the pin icon to keep important notes at the top
- **Color code**: Assign colors to categorize your notes
- **Search**: Use the search bar to find specific notes

### Views

- **List View**: See all your notes in a list format
- **Calendar View**: Browse notes by their creation date
- **Map View**: Visualize notes with location data on a map

## Testing

The project includes comprehensive unit tests:

```bash
# Run tests in Xcode
⌘U
```

Test coverage includes:

- Note model functionality
- Notes store operations
- Location manager
- Notification manager

## Data Migration

The app automatically migrates data from UserDefaults (legacy storage) to file-based storage on first launch, ensuring backward compatibility.

## Privacy

J-Notes respects your privacy:

- All data is stored locally on your device
- No data is sent to external servers
- Location data is only used when explicitly enabled
- Notifications require user permission

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the terms specified in the [LICENSE](LICENSE) file.

## Author

Created by Robert Libšanský

## Acknowledgments

- Built with SwiftUI
- Uses Apple's native frameworks for a seamless iOS experience
