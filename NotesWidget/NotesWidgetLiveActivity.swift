//
//  NotesWidgetLiveActivity.swift
//  NotesWidget
//
//  Created by Robert Libšanský on 06.07.2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct NotesWidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct NotesWidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NotesWidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension NotesWidgetAttributes {
    fileprivate static var preview: NotesWidgetAttributes {
        NotesWidgetAttributes(name: "World")
    }
}

extension NotesWidgetAttributes.ContentState {
    fileprivate static var smiley: NotesWidgetAttributes.ContentState {
        NotesWidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: NotesWidgetAttributes.ContentState {
         NotesWidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: NotesWidgetAttributes.preview) {
   NotesWidgetLiveActivity()
} contentStates: {
    NotesWidgetAttributes.ContentState.smiley
    NotesWidgetAttributes.ContentState.starEyes
}
