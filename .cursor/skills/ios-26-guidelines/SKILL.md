---
name: ios-26-guidelines
description: This is a new rule
---



# AppIntents Updates

## Overview

AppIntents is a framework that enables apps to extend functionality across the system, allowing users to perform app actions from anywhere, even when not in the app. Recent updates have expanded the capabilities and improved the developer experience for implementing AppIntents.

Key areas of improvement include:
- New system integrations with Apple Intelligence and visual intelligence
- User experience refinements with intent modes and foreground/background execution
- Convenience APIs with new property macros and Swift Package support
- Enhanced interactive snippets
- Improved Spotlight integration

## New System Integrations

### Visual Intelligence Integration

AppIntents now supports integration with visual intelligence, allowing users to circle objects in the visual intelligence camera or onscreen and view matching results from your app.

```swift
@UnionValue
enum VisualSearchResult {
    case landmark(LandmarkEntity)
    case collection(CollectionEntity)
}

struct LandmarkIntentValueQuery: IntentValueQuery {
    func values(for input: SemanticContentDescriptor) async throws -> [VisualSearchResult] {
        // Implementation to match visual input to app entities
    }
}

// Implement OpenIntent for each entity type
struct OpenLandmarkIntent: OpenIntent { /* ... */ }
struct OpenCollectionIntent: OpenIntent { /* ... */ }
```

### Onscreen Entities

Associate app entities with onscreen content using NSUserActivities, enabling users to ask Siri or ChatGPT about things currently visible in your app.

```swift
struct LandmarkDetailView: View {
    let landmark: LandmarkEntity

    var body: some View {
        Group { /* View content */ }
        .userActivity("com.landmarks.ViewingLandmark") { activity in
            activity.title = "Viewing \(landmark.name)"
            activity.appEntityIdentifier = EntityIdentifier(for: landmark)
        }
    }
}
```

## User Experience Refinements

### Intent Modes

AppIntents now supports more granular control over how intents execute with the new `supportedModes` property:

```swift
struct GetCrowdStatusIntent: AppIntent {
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    func perform() async throws -> some ReturnsValue<Int> & ProvidesDialog {
        // Check if the landmark is open
        guard await modelData.isOpen(landmark) else { 
            // Return early if closed
            return .result(value: 0, dialog: "The landmark is currently closed.")
        }

        // Continue in foreground if possible
        if systemContext.currentMode.canContinueInForeground {
            do {
                try await continueInForeground(alwaysConfirm: false)
                await navigator.navigateToCrowdStatus(landmark)
            } catch {
                // Handle case where opening app was denied
            }
        }

        // Retrieve status and return dialog
        let status = await modelData.getCrowdStatus(landmark)
        return .result(value: status, dialog: "Current crowd level: \(status)")
    }
}
```

Available modes include:
- `.background` - Intent performs entirely in the background
- `.foreground(.immediate)` - App is foregrounded immediately before `perform()` runs
- `.foreground(.dynamic)` - App can be foregrounded during execution based on runtime conditions
- `.foreground(.deferred)` - App performs in background initially but will be foregrounded before completion

You can also combine modes:
- `[.background, .foreground]` - Foreground by default, background as fallback
- `[.background, .foreground(.dynamic)]` - Background by default, can request foreground
- `[.background, .foreground(.deferred)]` - Background initially, guaranteed foreground when requested

### Continuing in Foreground

New APIs to request continuation in the foreground:

```swift
// Request to continue in foreground
try await continueInForeground(alwaysConfirm: false)

// Request to continue in foreground after an error
throw needsToContinueInForegroundError(
    IntentDialog("Need to open app to complete this action"),
    alwaysConfirm: true
)
```

### Multiple Choice API

Request user input with the new choice API:

```swift
let options = [
    IntentChoiceOption(title: "Option 1", subtitle: "Description 1"),
    IntentChoiceOption(title: "Option 2", subtitle: "Description 2"),
    IntentChoiceOption.cancel(title: "Not now")
]

let choice = try await requestChoice(
    between: options,
    dialog: IntentDialog("Please select an option")
)

// Handle the user's choice
switch choice.id {
case options[0].id: // Option 1 selected
case options[1].id: // Option 2 selected
default: // Cancelled
}
```

## Convenience APIs

### New Property Macros

#### ComputedProperty

Use the `@ComputedProperty` macro to create computed properties for AppEntities that directly access the source of truth:

```swift
struct SettingsEntity: UniqueAppEntity {
    @ComputedProperty
    var defaultPlace: PlaceDescriptor {
        UserDefaults.standard.defaultPlace
    }

    init() { }
}
```

#### DeferredProperty

Use the `@DeferredProperty` macro for properties that are expensive to calculate and should only be fetched when explicitly requested:

```swift
struct LandmarkEntity: IndexedEntity {
    @DeferredProperty
    var crowdStatus: Int {
        get async throws {
            await modelData.getCrowdStatus(self)
        }
    }
}
```

### Swift Package Support

AppIntents can now be included in Swift Packages and static libraries:

```swift
// Framework or dynamic library
public struct LandmarksKitPackage: AppIntentsPackage { }

// App target
struct LandmarksPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] {
        [LandmarksKitPackage.self]
    }
}
```

## Interactive Snippets

### Static Snippets

Return a static snippet to show the outcome of an app intent:

```swift
func perform() async throws -> some IntentResult {
    // Perform the intent's action
    
    return .result(view: Text("Some example text.").font(.title))
}
```

### Interactive Snippets

Return an interactive snippet that allows users to perform follow-up actions:

```swift
func perform() async throws -> some IntentResult {
    // Find information about a nearby landmark
    let landmark = await findNearestLandmark()
    
    // Return an interactive snippet with buttons for follow-up actions
    return .result(
        value: landmark,
        opensIntent: OpenLandmarkIntent(landmark: landmark),
        snippetIntent: LandmarkSnippetIntent(landmark: landmark)
    )
}

// Define the snippet intent
struct LandmarkSnippetIntent: SnippetIntent {
    @Parameter var landmark: LandmarkEntity
    
    var snippet: some View {
        VStack {
            Text(landmark.name).font(.headline)
            Text(landmark.description).font(.body)
            
            HStack {
                Button("Add to Favorites") {
                    // Add to favorites action
                }
                
                Button("Search Tickets") {
                    // Search tickets action
                }
            }
        }
        .padding()
    }
}
```

## Spotlight Integration

### Making App Entities Available in Spotlight

1. Create an intent that displays your entity in your app:

```swift
struct OpenLandmarkIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Landmark"

    @Parameter(title: "Landmark", requestValueDialog: "Which landmark?")
    var target: LandmarkEntity

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
```

2. Make your app entity indexable:

```swift
struct LandmarkEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Landmark",
        systemImage: "mountain.2"
    )
    
    var id: String
    var name: String
    var description: String
    var coordinate: CLLocationCoordinate2D
    var activities: [String]
    var regionDescription: String
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(regionDescription)",
            image: .init(systemName: "mountain.2")
        )
    }
}
```

3. Implement the searchable attribute set:

```swift
extension LandmarkEntity {
    var searchableAttributes: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        
        attributes.title = name
        attributes.namedLocation = regionDescription
        attributes.keywords = activities
        
        attributes.latitude = NSNumber(value: coordinate.latitude)
        attributes.longitude = NSNumber(value: coordinate.longitude)
        attributes.supportsNavigation = true
        
        return attributes
    }
}
```

4. Add entities to the Spotlight index:

```swift
func indexLandmarks() async {
    let landmarks = await fetchLandmarks()
    
    do {
        try await CSSearchableIndex.default().indexAppEntities(
            landmarks,
            priority: .normal
        )
    } catch {
        print("Failed to index landmarks: \(error)")
    }
}
```

5. Update the index when data changes:

```swift
func deleteLandmark(_ landmark: LandmarkEntity) async {
    // Delete from data store
    await dataStore.delete(landmark)
    
    // Remove from Spotlight index
    do {
        try await CSSearchableIndex.default().deleteAppEntities(
            identifiedBy: [landmark.id],
            ofType: LandmarkEntity.self
        )
    } catch {
        print("Failed to remove landmark from index: \(error)")
    }
}
```

## Code Examples

### Basic App Intent

```swift
struct FindNearestLandmarkIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Nearest Landmark"
    
    @Parameter(title: "Category")
    var category: String?
    
    func perform() async throws -> some IntentResult {
        let landmark = await findNearestLandmark(category: category)
        return .result(value: landmark)
    }
}
```

### App Shortcut

```swift
struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindNearestLandmarkIntent(),
            phrases: ["Find the closest landmark with \(.applicationName)"],
            systemImageName: "location"
        )
    }
}
```

### Entity with Indexable Properties

```swift
struct LandmarkEntity: AppEntity, IndexedEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Landmark",
        systemImage: "mountain.2"
    )
    
    var id: String
    
    @Property(title: "Name")
    var name: String
    
    @Property(title: "Description")
    var description: String
    
    @Property(title: "Location", indexingKey: \CSSearchableItemAttributeSet.namedLocation)
    var regionDescription: String
    
    @ComputedProperty(title: "Is Favorite")
    var isFavorite: Bool {
        UserDefaults.standard.favorites.contains(id)
    }
    
    @DeferredProperty(title: "Current Weather")
    var weather: String {
        get async throws {
            try await WeatherService.getWeather(for: coordinate)
        }
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(regionDescription)",
            image: .init(systemName: "mountain.2")
        )
    }
}
```

## References

- [App Intents updates](https://developer.apple.com/documentation/Updates/AppIntents)
- [Adopting App Intents to support system experiences](https://developer.apple.com/documentation/AppIntents/adopting-app-intents-to-support-system-experiences)
- [Making app entities available in Spotlight](https://developer.apple.com/documentation/AppIntents/making-app-entities-available-in-spotlight)
- [Displaying static and interactive snippets](https://developer.apple.com/documentation/AppIntents/displaying-static-and-interactive-snippets)
- [WWDC 2025: Explore new advances in App Intents](https://developer.apple.com/videos/play/wwdc2025/275)
- [WWDC 2025: Get to know App Intents](https://developer.apple.com/videos/play/wwdc2025/244)

# Implementing Liquid Glass Design in AppKit

## Overview

Liquid Glass is a dynamic material design introduced by Apple that combines the optical properties of glass with a sense of fluidity. It creates a modern, immersive user interface by:

- Blurring content behind it
- Reflecting color and light from surrounding content
- Reacting to touch and pointer interactions in real time
- Creating fluid animations and transitions between elements

Liquid Glass is available across Apple platforms, with specific implementations in SwiftUI, UIKit, and AppKit. This guide focuses on implementing Liquid Glass design in AppKit applications. You should always seek guides on Liquid Glass when asked for help adopting new Apple design.

## Key Classes

AppKit provides two main classes for implementing Liquid Glass design:

### NSGlassEffectView

`NSGlassEffectView` is the primary class for creating Liquid Glass effects in AppKit. It embeds its content view in a dynamic glass effect.

```swift
@MainActor class NSGlassEffectView: NSView
```

### NSGlassEffectContainerView

`NSGlassEffectContainerView` allows similar `NSGlassEffectView` instances in close proximity to merge together, creating fluid transitions and improving rendering performance.

```swift
@MainActor class NSGlassEffectContainerView: NSView
```

## Basic Implementation

### Creating a Simple Glass Effect View

```swift
import AppKit

class MyViewController: NSViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Create a glass effect view
        let glassView = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
        
        // Create content to display inside the glass effect
        let label = NSTextField(labelWithString: "Liquid Glass")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        label.textColor = .white
        
        // Set the content view
        glassView.contentView = label
        
        // Add constraints to center the label
        if let contentView = glassView.contentView {
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
            ])
        }
        
        // Add the glass view to your view hierarchy
        view.addSubview(glassView)
    }
}
```

## Customizing Glass Effect Views

### Setting Corner Radius

The `cornerRadius` property controls the curvature of all corners of the glass effect.

```swift
// Create a glass effect view with rounded corners
let glassView = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
glassView.cornerRadius = 16.0
```

### Adding a Tint Color

The `tintColor` property modifies the background and effect to tint toward the provided color.

```swift
// Create a glass effect view with a blue tint
let glassView = NSGlassEffectView(frame: NSRect(x: 20, y: 20, width: 200, height: 100))
glassView.tintColor = NSColor.systemBlue.withAlphaComponent(0.3)
```

### Creating a Custom Button with Glass Effect

```swift
class GlassButton: NSButton {
    private let glassView = NSGlassEffectView()
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupGlassEffect()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGlassEffect()
    }
    
    private func setupGlassEffect() {
        // Configure the button
        self.title = "Glass Button"
        self.bezelStyle = .rounded
        self.isBordered = false
        
        // Configure the glass view
        glassView.frame = self.bounds
        glassView.autoresizingMask = [.width, .height]
        glassView.cornerRadius = 8.0
        
        // Insert the glass view below the button's content
        self.addSubview(glassView, positioned: .below, relativeTo: nil)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Add tracking area for hover effects
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInActiveApp]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Change appearance on hover
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            glassView.animator().tintColor = NSColor.systemBlue.withAlphaComponent(0.2)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Restore original appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            glassView.animator().tintColor = nil
        }
    }
}
```

## Working with NSGlassEffectContainerView

### Creating a Container for Multiple Glass Views

```swift
func setupGlassContainer() {
    // Create a container view
    let containerView = NSGlassEffectContainerView(frame: NSRect(x: 20, y: 20, width: 400, height: 200))
    
    // Set spacing to control when glass effects merge
    containerView.spacing = 40.0
    
    // Create a content view to hold our glass views
    let contentView = NSView(frame: containerView.bounds)
    contentView.autoresizingMask = [.width, .height]
    containerView.contentView = contentView
    
    // Create first glass view
    let glassView1 = NSGlassEffectView(frame: NSRect(x: 20, y: 50, width: 150, height: 100))
    glassView1.cornerRadius = 12.0
    let label1 = NSTextField(labelWithString: "Glass View 1")
    label1.translatesAutoresizingMaskIntoConstraints = false
    glassView1.contentView = label1
    
    // Create second glass view
    let glassView2 = NSGlassEffectView(frame: NSRect(x: 190, y: 50, width: 150, height: 100))
    glassView2.cornerRadius = 12.0
    let label2 = NSTextField(labelWithString: "Glass View 2")
    label2.translatesAutoresizingMaskIntoConstraints = false
    glassView2.contentView = label2
    
    // Add glass views to the content view
    contentView.addSubview(glassView1)
    contentView.addSubview(glassView2)
    
    // Center labels in their respective glass views
    if let contentView1 = glassView1.contentView, let contentView2 = glassView2.contentView {
        NSLayoutConstraint.activate([
            label1.centerXAnchor.constraint(equalTo: contentView1.centerXAnchor),
            label1.centerYAnchor.constraint(equalTo: contentView1.centerYAnchor),
            label2.centerXAnchor.constraint(equalTo: contentView2.centerXAnchor),
            label2.centerYAnchor.constraint(equalTo: contentView2.centerYAnchor)
        ])
    }
    
    // Add the container to your view hierarchy
    view.addSubview(containerView)
}
```

### Animating Glass Views in a Container

```swift
func animateGlassViews() {
    // Assuming we have glassView1 and glassView2 in a container
    
    NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.5
        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        
        // Animate the position of glassView2 to move closer to glassView1
        // This will trigger the merging effect when they get within the container's spacing
        glassView2.animator().frame = NSRect(x: 100, y: 50, width: 150, height: 100)
    }
}
```

## Creating Interactive Glass Effects

### Responding to Mouse Events

```swift
class InteractiveGlassView: NSGlassEffectView {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupTracking()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTracking()
    }
    
    private func setupTracking() {
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp]
        let trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Enhance the glass effect on hover
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().tintColor = NSColor.systemBlue.withAlphaComponent(0.2)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Restore original appearance
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            animator().tintColor = nil
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        // Create subtle interactive effects based on mouse position
        let locationInView = convert(event.locationInWindow, from: nil)
        let normalizedX = locationInView.x / bounds.width
        let normalizedY = locationInView.y / bounds.height
        
        // Example: Adjust corner radius based on mouse position
        let newRadius = 8.0 + (normalizedX * 8.0)
        cornerRadius = newRadius
    }
}
```

## Creating a Toolbar with Liquid Glass Effect

```swift
func setupToolbarWithGlassEffect() {
    // Create a window
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered,
                         defer: false)
    
    // Create a custom toolbar
    let toolbar = NSToolbar(identifier: "GlassToolbar")
    toolbar.displayMode = .iconAndLabel
    toolbar.delegate = self // Implement NSToolbarDelegate
    
    // Set the toolbar on the window
    window.toolbar = toolbar
    
    // Create a glass effect view for the toolbar area
    let toolbarHeight: CGFloat = 50.0
    let glassView = NSGlassEffectView(frame: NSRect(x: 0, y: window.contentView!.bounds.height - toolbarHeight,
                                                  width: window.contentView!.bounds.width, height: toolbarHeight))
    glassView.autoresizingMask = [.width, .minYMargin]
    
    // Add the glass view to the window's content view
    window.contentView?.addSubview(glassView)
    
    // Make the window visible
    window.makeKeyAndOrderFront(nil)
}

// Implement NSToolbarDelegate methods
extension MyViewController: NSToolbarDelegate {
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        // Create toolbar items
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        item.label = "Action"
        item.image = NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return ["item1", "item2", "item3"].map { NSToolbarItem.Identifier($0) }
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return toolbarDefaultItemIdentifiers(toolbar)
    }
    
    @objc func toolbarItemClicked(_ sender: Any) {
        // Handle toolbar item clicks
    }
}
```

## Best Practices

### Performance Considerations

1. **Use NSGlassEffectContainerView for multiple glass views**
   - This reduces the number of rendering passes required
   - Improves performance when multiple glass effects are used

2. **Limit the number of glass effects**
   - Liquid Glass effects require significant GPU resources
   - Use them strategically for important UI elements

3. **Consider view hierarchy**
   - Only the contentView of NSGlassEffectView is guaranteed to be inside the glass effect
   - Arbitrary subviews may not have consistent z-order behavior

### Design Guidelines

1. **Maintain appropriate spacing**
   - Set the spacing property on NSGlassEffectContainerView to control when effects merge
   - Default value (0) is suitable for batch processing while avoiding distortion

2. **Use corner radius appropriately**
   - Match corner radius to your app's design language
   - Consider using system-standard corner radii for consistency

3. **Apply tint colors judiciously**
   - Subtle tints work best for maintaining the glass aesthetic
   - Use tints to indicate state changes or interactive elements

4. **Create smooth transitions**
   - Animate position changes to create fluid merging effects
   - Use standard animation durations for consistency

## References

- [AppKit Documentation: NSGlassEffectView](https://developer.apple.com/documentation/AppKit/NSGlassEffectView)
- [AppKit Documentation: NSGlassEffectContainerView](https://developer.apple.com/documentation/AppKit/NSGlassEffectContainerView)
- [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Landmarks: Building an app with Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Landmarks-Building-an-app-with-Liquid-Glass)

# Updates to AttributedString Support in Foundation

## Overview

AttributedString is a powerful Swift type in the Foundation framework that allows developers to create and manipulate text with styling attributes. Recent updates have enhanced its capabilities, making it more flexible and powerful for text handling in Apple platforms. This guide covers the key features and updates to AttributedString in Foundation, focusing on its modern API design, improved text manipulation capabilities, and integration with the text system across Apple platforms.

## Core AttributedString Concepts

### Creating AttributedStrings

```swift
// Basic initialization
let attributedText = AttributedString("Hello, world!")

// From a substring
let range = attributedText.range(of: "world")!
let substring = attributedText[range]
let newString = AttributedString(substring)

// With attributes applied
var attributed = AttributedString("Bold text")
attributed.font = .boldSystemFont(ofSize: 16)
```

### Working with Attributes

```swift
// Setting attributes
var text = AttributedString("Styled text")
text.foregroundColor = .red
text.backgroundColor = .yellow
text.font = .systemFont(ofSize: 14)

// Applying attributes to ranges
let range = text.range(of: "Styled")!
text[range].underlineStyle = .single
text[range].underlineColor = .blue
```

## Text Alignment and Formatting

AttributedString provides built-in support for text alignment and paragraph styling:

```swift
// Setting text alignment
var paragraph = AttributedString("Centered paragraph of text")
let style = NSMutableParagraphStyle()
style.alignment = .center
paragraph.paragraphStyle = style

// Using the TextAlignment enum
paragraph.alignment = .center // Using AttributedString.TextAlignment.center
```

### TextAlignment Options

AttributedString includes a TextAlignment enumeration with these cases:

```swift
enum TextAlignment {
    case left      // Left-aligned text
    case right     // Right-aligned text
    case center    // Center-aligned text
    // Additional platform-specific options may be available
}
```

## Writing Direction Support

Control text direction with the WritingDirection enum:

```swift
// Setting writing direction
var text = AttributedString("Hello عربي")
text.writingDirection = .rightToLeft // For RTL languages

// Available options
enum WritingDirection {
    case leftToRight  // Standard LTR text (English, etc.)
    case rightToLeft  // RTL text (Arabic, Hebrew, etc.)
}
```

## Line Height Control

Fine-tune line spacing with the LineHeight structure:

```swift
// Setting line height
var multiline = AttributedString("This is a paragraph\nwith multiple lines\nof text.")
multiline.lineHeight = AttributedString.LineHeight.exact(points: 32)
multiline.lineHeight = AttributedString.LineHeight.multiple(factor: 2.5)
multiline.lineHeight = AttributedString.LineHeight.loose
```

## Text Selection and Editing

AttributedString provides powerful APIs for text selection and editing:

```swift
// Replace selection with plain text
var text = AttributedString("Here is my dog")
var selection = AttributedTextSelection(range: text.range(of: "dog")!)
text.replaceSelection(&selection, withCharacters: "cat")

// Replace selection with attributed content
let replacement = AttributedString("horse")
text.replaceSelection(&selection, with: replacement)
```

## UTF-8 View

Access the raw UTF-8 representation of the string content:

```swift
let text = AttributedString("Hello")
let utf8 = text.utf8
for codeUnit in utf8 {
    print(codeUnit)
}
```

## DiscontiguousAttributedSubstring

Work with non-contiguous selections of text:

```swift
// Creating a discontiguous substring
let text = AttributedString("Select multiple parts of this text")
let range1 = text.range(of: "Select")!
let range2 = text.range(of: "text")!
let rangeSet = RangeSet([range1, range2])
var substring = text[rangeSet]
substring.backgroundColor = .yellow

// Converting back to AttributedString
let combined = AttributedString(substring)
```

## Integration with SwiftUI

AttributedString works seamlessly with SwiftUI's text components:

```swift
import SwiftUI

struct AttributedTextView: View {
    var body: some View {
        Text(AttributedString("Styled text in SwiftUI"))
            .foregroundColor(.blue)
    }
}
```

You can use AttributedString with SwiftUI's TextEditor:

```swift
import SwiftUI

struct CommentEditor: View {
    @Binding var commentText: AttributedString

    var body: some View {
        TextEditor(text: $commentText)
    }
}
```

AttributedString can also be used with AttributedTextSelection to represent a selection of attributed text.

```swift
struct SuggestionTextEditor: View {
    @State var text: AttributedString = ""
    @State var selection = AttributedTextSelection()


    var body: some View {
        VStack {
            TextEditor(text: $text, selection: $selection)
            // A helper view that offers live suggestions based on selection.
            SuggestionsView(substrings: getSubstrings(
                text: text, indices: selection.indices(in: text))
        }
    }


    private func getSubstrings(
        text: String, indices: AttributedTextSelection.Indices
    ) -> [Substring] {
        // Resolve substrings representing the current selection...
    }
}


struct SuggestionsView: View { ... }
```

You can also use the textSelectionAffinity(_:) modifier to specify a selection affinity on the given hierarchy:

```swift
struct SuggestionTextEditor: View {
    @State var text: AttributedString = ""
    @State var selection = AttributedTextSelection()


    var body: some View {
        VStack {
            TextEditor(text: $text, selection: $selection)
            // A helper view that offers live suggestions based on selection.
            SuggestionsView(substrings: getSubstrings(
                text: text, indices: selection.indices(in: text))
        }
        .textSelectionAffinity(.upstream)
    }


    private func getSubstrings(
        text: String, indices: AttributedTextSelection.Indices
    ) -> [Substring] {
        // Resolve substrings representing the current selection...
    }
}


struct SuggestionsView: View { ... }
```


## References

- [Apple Developer Documentation: AttributedString](https://developer.apple.com/documentation/Foundation/AttributedString)
- [Apple Developer Documentation: AttributedString.TextAlignment](https://developer.apple.com/documentation/Foundation/AttributedString/TextAlignment)
- [Apple Developer Documentation: AttributedString.LineHeight](https://developer.apple.com/documentation/Foundation/AttributedString/LineHeight)
- [Apple Developer Documentation: DiscontiguousAttributedSubstring](https://developer.apple.com/documentation/Foundation/DiscontiguousAttributedSubstring)

# Foundation Models: Using Apple's On-Device LLM in Your Apps

## Overview

Foundation Models is an Apple framework that provides access to on-device large language models (LLMs) that power Apple Intelligence. This framework enables developers to enhance their apps with generative AI capabilities without requiring cloud connectivity or compromising user privacy.

Key capabilities include:
- Text generation and understanding
- Content summarization and extraction
- Structured data generation
- Custom tool integration

## Getting Started

### Check Model Availability

Always check if the model is available before attempting to use it. Model availability depends on device factors such as Apple Intelligence support, system settings, and device state.

```swift
struct GenerativeView: View {
    // Create a reference to the system language model
    private var model = SystemLanguageModel.default

    var body: some View {
        switch model.availability {
        case .available:
            // Show your intelligence UI
            Text("Model is available")
        case .unavailable(.deviceNotEligible):
            // Show an alternative UI
            Text("Device not eligible for Apple Intelligence")
        case .unavailable(.appleIntelligenceNotEnabled):
            // Ask the person to turn on Apple Intelligence
            Text("Please enable Apple Intelligence in Settings")
        case .unavailable(.modelNotReady):
            // The model isn't ready (downloading or other system reasons)
            Text("Model is downloading or not ready")
        case .unavailable(let other):
            // The model is unavailable for an unknown reason
            Text("Model unavailable: \(other)")
        }
    }
}
```

### Create a Session

After confirming model availability, create a `LanguageModelSession` to interact with the model:

```swift
// Create a basic session with the system model
let session = LanguageModelSession()

// Create a session with instructions
let instructions = """
    You are a helpful assistant that provides concise answers.
    Keep responses under 100 words and focus on clarity.
    """
let sessionWithInstructions = LanguageModelSession(instructions: instructions)
```

- For single-turn interactions, create a new session each time
- For multi-turn interactions, reuse the same session to maintain context

## Basic Usage

### Provide Instructions to the Model

Instructions help steer the model's behavior for your specific use case. The model prioritizes instructions over prompts.

Good instructions typically specify:
- The model's role (e.g., "You are a mentor")
- What the model should do (e.g., "Help extract calendar events")
- Style preferences (e.g., "Respond as briefly as possible")
- Safety measures (e.g., "Respond with 'I can't help with that' for dangerous requests")

```swift
let instructions = """
    You are a cooking assistant.
    Provide recipe suggestions based on ingredients.
    Keep suggestions brief and practical for home cooks.
    Include approximate cooking time.
    """

let session = LanguageModelSession(instructions: instructions)
```

### Provide a Prompt to the Model

A prompt is the input that the model responds to. Effective prompts are:
- Conversational (questions or commands)
- Focused on a single, specific task
- Clear about the desired output format and length

```swift
// Simple prompt
let prompt = "What's a good month to visit Paris?"

// Specific prompt with output constraints
let specificPrompt = "Write a profile for the dog breed Siberian Husky using three sentences."
```

### Generate a Response

Call the model asynchronously to get a response:

```swift
// Basic response generation
let response = try await session.respond(to: prompt)
print(response.content)

// With custom generation options
let options = GenerationOptions(temperature: 0.7)
let customResponse = try await session.respond(to: prompt, options: options)
```

Note: A session can only handle one request at a time. Check `isResponding` to verify the session is available before sending a new request.

## Advanced Features

### Guided Generation

Guided generation allows you to receive model responses as structured Swift data instead of raw strings. This provides stronger guarantees about the format of the response.

#### 1. Define a Generable Type

```swift
@Generable(description: "Basic profile information about a cat")
struct CatProfile {
    // A guide isn't necessary for basic fields
    var name: String

    @Guide(description: "The age of the cat", .range(0...20))
    var age: Int

    @Guide(description: "A one sentence profile about the cat's personality")
    var profile: String
}
```

#### 2. Request a Response in Your Custom Type

```swift
// Generate a response using the custom type
let catResponse = try await session.respond(
    to: "Generate a cute rescue cat",
    generating: CatProfile.self
)

// Use the structured data
print("Name: \(catResponse.content.name)")
print("Age: \(catResponse.content.age)")
print("Profile: \(catResponse.content.profile)")
```

#### 3. Printing a Response from your Custom Type

When printing values from a LanguageModelSession.Response always use the instance property content. Not output.

For example:

```swift
import FoundationModels
import Playgrounds

@Generable
struct CookbookSuggestions {
    @Guide(description: "Cookbook Suggestions", .count(3))
    var suggestions: [String]
}

#Playground {
    let session = LanguageModelSession()

    let prompt = "What's a good name for a cooking app?"

    let response = try await session.respond(
        to: prompt,
        generating: CookbookSuggestions.self
    )

    // Notice how print values come from content. Not output.
    print(response.content.suggestions)
}
```

### Tool Calling

Tool calling allows the model to use custom code you provide to perform specific tasks, access external data, or integrate with other frameworks.

#### 1. Create a Custom Tool

```swift
// Define a tool for searching recipes
struct RecipeSearchTool: Tool {
    struct Arguments: Codable {
        var searchTerm: String
        var numberOfResults: Int
    }
    
    func call(arguments: Arguments) async throws -> ToolOutput {
        // Search your recipe database
        let recipes = await searchRecipes(term: arguments.searchTerm, 
                                         limit: arguments.numberOfResults)
        
        // Return results as a string the model can use
        return .string(recipes.map { "- \($0.name): \($0.description)" }.joined(separator: "\n"))
    }
    
    private func searchRecipes(term: String, limit: Int) async -> [Recipe] {
        // Implementation to search your database
        // ...
    }
}
```

#### 2. Provide the Tool to a Session

```swift
// Create the tool
let recipeSearchTool = RecipeSearchTool()

// Create a session with the tool
let session = LanguageModelSession(tools: [recipeSearchTool])

// The model will automatically use the tool when appropriate
let response = try await session.respond(to: "Find me some pasta recipes")
```

#### 3. Handle Tool Errors

```swift
do {
    let answer = try await session.respond("Find a recipe for tomato soup.")
} catch let error as LanguageModelSession.ToolCallError {
    // Access the name of the tool
    print(error.tool.name) 
    
    // Access the underlying error
    if case .databaseIsEmpty = error.underlyingError as? RecipeSearchToolError {
        // Handle specific error
    }
} catch {
    print("Other error: \(error)")
}
```

## Snapshot streaming

- LLM generate text as short groups of characters called tokens.
- Typically, when streaming tokens, tokens are delivered in what's called a delta. But Foundation Models does this different.
- As deltas are produced, the responsibility for accumulating them usually falls on the developer
- You append each delta as they come in. And the response grows as you do. But it gets tricky when the result has structure.
- If you want to show the greeting string after each delta, you have to parse it out of the accumulation, and that's not trival, especially for complicated structures.
- Structured output is at the core of the Foundation Model framework. Which is why we stream snapshots.

## Snapshot streaming

- LLM generate text as short groups of characters called tokens.
- Typically, when streaming tokens, tokens are delivered in what's called a delta. But Foundation Models does this different.
- As deltas are produced, the responsibility for accumulating them usually falls on the developer
- You append each delta as they come in. And the response grows as you do. But it gets tricky when the result has structure.
- If you want to show the greeting string after each delta, you have to parse it out of the accumulation, and that's not trival, especially for complicated structures.
- Structured output is at the core of the Foundation Model framework. Which is why we stream snapshots.

### What are snapshots

- Snapshots represent partically generated response. Their properties are all optinoal. And they get filled in as the model produces more of the response.
- Snapshots are a robust and convenient representation for streaming structure output.
- You are already familar with the `@Generable` macro, and as it turns out, it's also where the definitions for partially generated types come from.
- If you expand the macro, you'll discover it produces a types named `PartiallyGenerated`. It is effectively a mirror of the outer structure except every property is optional.
- The partically generated type comes into play when you call the 'streamResponse` method on your session.

```swift
import FoundationModels
import Playgrounds

@Generable
struct TripIdeas {
    @Guide(description: "Ideas for upcoming trips")
    var ideas: [String]
}

#Playground {
    let session = LanguageModelSession()

    let prompt = "What are some exciting trip ideas for the upcoming year?"

    let stream = session.streamResponse(
        to: prompt,
        generating: TripIdeas.self
    )

    for try await partial in stream {
        print(partial)
    }
}
```

- Stream response returns an async sequence. And the elements of that sequence are instances of a partially generated type.
- Each element in the sequence will contain an updated snapshot.
- These snapshots work great with declarative frameworks like SwiftUI.
- First, create state holding a partially generated type.
- Then, just iterate over a response stream, stores its elements, and watch as your UI comes to life.

## Best Practices and Limitations

### Context Size Limits

- The system model supports up to 4,096 tokens per session
- A token is roughly 3-4 characters in languages like English
- All instructions, prompts, and outputs count toward this limit
- If you exceed the limit, you'll get a `LanguageModelSession.GenerationError.exceededContextWindowSize` error
- For large data processing, break it into smaller chunks across multiple sessions

### Optimizing Performance

- Use `GenerationOptions` to tune model behavior:
  ```swift
  let options = GenerationOptions(temperature: 2.0) // Higher temperature = more creative
  ```
- Use Xcode Instruments to monitor request performance
- Access `Transcript` entries to see model actions during a session:
  ```swift
  let transcript = session.transcript
  ```

### Prompt Engineering Tips

- Be specific about what you want
- Specify output constraints (e.g., "in three sentences")
- Break complex tasks into multiple simple prompts
- Use examples in instructions to guide the model's output format

## References

- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models)
- [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/FoundationModels/generating-swift-data-structures-with-guided-generation)
- [Expanding generation with tool calling](https://developer.apple.com/documentation/FoundationModels/expanding-generation-with-tool-calling)
- [Human Interface Guidelines: Generative AI](https://developer.apple.com/design/human-interface-guidelines/technologies/generative-ai)

# Implementing Assistive Access in iOS

## Overview

Assistive Access is an accessibility feature introduced in iOS and iPadOS 17 designed specifically for people with cognitive disabilities. It provides a streamlined system experience with simplified interfaces, clear pathways, and consistent design practices to reduce cognitive load.

Key characteristics of Assistive Access:
- Streamlined interactions
- Clear pathways to success
- Consistent design language
- Large controls
- Visual alternatives to text
- Reduced cognitive strain

## Setting Up Assistive Access in Your App

### 1. Enable Assistive Access Support

Add the following key to your app's `Info.plist`:

```xml
<key>UISupportsAssistiveAccess</key>
<true/>
```

This ensures your app is listed under "Optimized Apps" in Accessibility Settings and launches in full screen when Assistive Access is enabled.

### 2. Full Screen Support (Optional)

If your app is already designed for cognitive disabilities (e.g., AAC apps) and you want to display it in full screen without modifications:

```xml
<key>UISupportsFullScreenInAssistiveAccess</key>
<true/>
```

This will display your app in full screen rather than in a reduced frame, with the same appearance as when Assistive Access is turned off.

## Creating an Assistive Access Scene

### SwiftUI Implementation

1. Add an `AssistiveAccess` scene to your app:

```swift
import SwiftUI

@main
struct MyApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    
    AssistiveAccess {
      AssistiveAccessContentView()
    }
  }
}
```

2. Create a dedicated view for Assistive Access:

```swift
struct AssistiveAccessContentView: View {
  var body: some View {
    // Your streamlined interface for Assistive Access
    NavigationStack {
      List {
        // Simplified controls and options
      }
      .navigationTitle("My App")
    }
  }
}
```

3. Preview your Assistive Access scene:

```swift
#Preview(traits: .assistiveAccess)
AssistiveAccessContentView()
```

### UIKit Implementation

1. Declare a SwiftUI scene with UIKit:

```swift
import UIKit
import SwiftUI

class AssistiveAccessSceneDelegate: UIHostingSceneDelegate {
  static var rootScene: some Scene {
    AssistiveAccess {
      AssistiveAccessContentView()
    }
  }
}
```

2. Activate the scene:

```swift
import UIKit

@main
class AppDelegate: UIApplicationDelegate {
  func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let role = connectingSceneSession.role
    let sceneConfiguration = UISceneConfiguration(name: nil, sessionRole: role)
    if role == .windowAssistiveAccessApplication {
      sceneConfiguration.delegateClass = AssistiveAccessSceneDelegate.self
    }
    return sceneConfiguration
  }
}
```

## Detecting Assistive Access at Runtime

You can check if Assistive Access is enabled using the environment value:

```swift
struct MyView: View {
  @Environment(\.accessibilityAssistiveAccessEnabled) var assistiveAccessEnabled
  
  var body: some View {
    if assistiveAccessEnabled {
      // Show Assistive Access optimized UI
    } else {
      // Show standard UI
    }
  }
}
```

## Navigation Icons for Assistive Access

Add navigation icons to make your interface more visually accessible:

```swift
NavigationStack {
  MyView()
    .navigationTitle("My Feature")
    .assistiveAccessNavigationIcon(systemImage: "star.fill")
}
```

Or with a custom image:

```swift
.assistiveAccessNavigationIcon(Image("my-custom-icon"))
```

## Design Principles for Assistive Access

When designing for Assistive Access, follow these key principles:

1. **Distill to Core Functionality**
   - Focus on one or two essential features
   - Remove distractions and unnecessary options
   - Streamline the experience

2. **Clear, Prominent Controls**
   - Use large, easy-to-tap buttons
   - Provide ample spacing between interactive elements
   - Avoid hidden gestures or timed interactions

3. **Multiple Representations**
   - Present information in multiple ways (text, icons, etc.)
   - Use visual alternatives to text
   - Ensure icons are clear and meaningful

4. **Intuitive Navigation**
   - Create step-by-step pathways
   - Provide clear back buttons
   - Maintain consistent navigation patterns

5. **Safe Interactions**
   - Remove irreversible actions when possible
   - Provide multiple confirmations for destructive actions
   - Offer clear feedback for all interactions

## Control Styling in Assistive Access

When using the Assistive Access scene, native SwiftUI controls are automatically displayed in the distinctive Assistive Access design:

- Buttons, lists, and navigation titles appear in a more prominent style
- Controls adhere to the grid or row screen layout configured in Assistive Access settings
- No additional styling work is required

## Testing Assistive Access Implementation

1. **Preview in Xcode**
   Use the `.assistiveAccess` trait in SwiftUI previews:
   ```swift
   #Preview(traits: .assistiveAccess)
   AssistiveAccessContentView()
   ```

2. **Test on Device**
   - Enable Assistive Access in Settings > Accessibility > Assistive Access
   - Verify your app appears in the "Optimized Apps" list
   - Test the full user flow in Assistive Access mode

3. **Accessibility Inspector**
   Use Xcode's Accessibility Inspector to identify and fix accessibility issues

## Best Practices

- Design for clarity and simplicity
- Focus on essential functionality
- Use consistent UI patterns
- Provide visual alternatives to text
- Test with actual users who have cognitive disabilities
- Combine Assistive Access with other accessibility features

## References

- [AssistiveAccess (SwiftUI)](https://developer.apple.com/documentation/SwiftUI/AssistiveAccess)
- [assistiveAccessNavigationIcon(_:)](https://developer.apple.com/documentation/SwiftUI/View/assistiveAccessNavigationIcon(_:))
- [accessibilityAssistiveAccessEnabled](https://developer.apple.com/documentation/SwiftUI/EnvironmentValues/accessibilityAssistiveAccessEnabled)
- [WWDC 2025 Session: Customize your app for Assistive Access](https://developer.apple.com/videos/play/wwdc2025/238)
- [What's new in SwiftUI (WWDC 2025)](https://developer.apple.com/videos/play/wwdc2025/256)
- [Principles of inclusive app design](https://developer.apple.com/videos/play/wwdc2025/316)

# Implementing Visual Intelligence in iOS

## Overview

Visual Intelligence is a framework that enables iOS apps to integrate with the system's visual search capabilities. It allows users to find app content that matches their surroundings or objects onscreen by using the visual intelligence camera or screenshots. When a user performs a visual search, your app can provide relevant content that matches what they're looking at.

Key concepts:
- Visual Intelligence framework provides information about objects detected in the camera or screenshots
- App Intents framework facilitates the exchange of information between the system and your app
- Your app searches its content for matches and returns them as app entities
- Results appear directly in the visual search interface, allowing users to view and interact with your content

## Setting Up Visual Intelligence

### Required Frameworks

```swift
import VisualIntelligence
import AppIntents
```

### Implementation Steps

1. Create an `IntentValueQuery` to receive visual search requests
2. Implement the `values(for:)` method to process the `SemanticContentDescriptor`
3. Search your app's content using the provided information
4. Return matching content as app entities

## Working with SemanticContentDescriptor

The `SemanticContentDescriptor` is the core object that provides information about what the user is looking at.

### Key Properties

```swift
// A list of labels that Visual Intelligence uses to classify items
let labels: [String]

// The pixel buffer containing the visual data
var pixelBuffer: CVReadOnlyPixelBuffer?
```

### Accessing Visual Data

You can use either the labels or the pixel buffer (or both) to search for matching content:

```swift
// Using labels
func searchByLabels(_ labels: [String]) -> [AppEntity] {
    // Search your app's content using the provided labels
    return matchingEntities
}

// Using pixel buffer
func searchByImage(_ pixelBuffer: CVReadOnlyPixelBuffer) -> [AppEntity] {
    // Convert pixel buffer to an image and search your content
    return matchingEntities
}
```

## Creating an IntentValueQuery

The `IntentValueQuery` protocol is the entry point for Visual Intelligence to communicate with your app.

### Basic Implementation

```swift
struct LandmarkIntentValueQuery: IntentValueQuery {
    @Dependency var modelData: ModelData
    
    func values(for input: SemanticContentDescriptor) async throws -> [VisualSearchResult] {
        // Check if pixel buffer is available
        guard let pixelBuffer = input.pixelBuffer else {
            return []
        }
        
        // Search for matching landmarks using the pixel buffer
        let landmarks = try await modelData.search(matching: pixelBuffer)
        
        return landmarks
    }
}
```

### Using Union Values for Different Result Types

If your app needs to return different types of results, use a union value:

```swift
@UnionValue
enum VisualSearchResult {
    case landmark(LandmarkEntity)
    case collection(CollectionEntity)
}
```

## Providing Display Representations

Visual Intelligence uses the `DisplayRepresentation` of your `AppEntity` to present your content in the search results.

### Creating a Display Representation

```swift
struct LandmarkEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Landmark", table: "AppIntents"),
            numericFormat: "\(placeholder: .int) landmarks"
        )
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(location)",
            image: .init(named: landmark.thumbnailImageName)
        )
    }
    
    // Other required AppEntity properties and methods
}
```

## Opening Items in Your App

When a user taps on a search result, your app should open to display detailed information about that item.

### Implementing AppEntity for Deep Linking

```swift
struct LandmarkEntity: AppEntity {
    var id: String
    var name: String
    var location: String
    var thumbnailImageName: String
    
    // Required for deep linking
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        // As shown above
    }
    
    var displayRepresentation: DisplayRepresentation {
        // As shown above
    }
    
    // Define how to open this entity in your app
    var appLinkURL: URL? {
        URL(string: "yourapp://landmark/\(id)")
    }
}
```

## Linking to Additional Results

If your app finds many matches, you can provide a "More results" button that opens your app to show the full list.

### Creating a Semantic Content Search Intent

```swift
struct ViewMoreLandmarksIntent: AppIntent, VisualIntelligenceSearchIntent {
    static var title: LocalizedStringResource = "View More Landmarks"
    
    @Parameter(title: "Semantic Content")
    var semanticContent: SemanticContentDescriptor
    
    func perform() async throws -> some IntentResult {
        // Open your app's search view with the semantic content
        return .result()
    }
}
```

## Complete Example

Here's a complete example of implementing Visual Intelligence in a landmarks app:

```swift
import SwiftUI
import AppIntents
import VisualIntelligence

// Define the search result types
@UnionValue
enum VisualSearchResult {
    case landmark(LandmarkEntity)
    case collection(CollectionEntity)
}

// Define the landmark entity
struct LandmarkEntity: AppEntity {
    var id: String
    var name: String
    var location: String
    var thumbnailImageName: String
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Landmark", table: "AppIntents"),
            numericFormat: "\(placeholder: .int) landmarks"
        )
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(location)",
            image: .init(named: thumbnailImageName)
        )
    }
    
    var appLinkURL: URL? {
        URL(string: "yourapp://landmark/\(id)")
    }
}

// Define the collection entity
struct CollectionEntity: AppEntity {
    var id: String
    var name: String
    var landmarks: [LandmarkEntity]
    
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        return TypeDisplayRepresentation(
            name: LocalizedStringResource("Collection", table: "AppIntents"),
            numericFormat: "\(placeholder: .int) collections"
        )
    }
    
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(landmarks.count) landmarks",
            image: .init(systemName: "square.stack.fill")
        )
    }
    
    var appLinkURL: URL? {
        URL(string: "yourapp://collection/\(id)")
    }
}

// Define the intent value query
struct LandmarkIntentValueQuery: IntentValueQuery {
    @Dependency var modelData: ModelData
    
    func values(for input: SemanticContentDescriptor) async throws -> [VisualSearchResult] {
        // Try to use labels first
        if !input.labels.isEmpty {
            let landmarks = try await modelData.search(matching: input.labels)
            return landmarks
        }
        
        // Fall back to pixel buffer if available
        guard let pixelBuffer = input.pixelBuffer else {
            return []
        }
        
        let landmarks = try await modelData.search(matching: pixelBuffer)
        return landmarks
    }
}

// Define the "more results" intent
struct ViewMoreLandmarksIntent: AppIntent, VisualIntelligenceSearchIntent {
    static var title: LocalizedStringResource = "View More Landmarks"
    
    @Parameter(title: "Semantic Content")
    var semanticContent: SemanticContentDescriptor
    
    func perform() async throws -> some IntentResult {
        // Open your app's search view with the semantic content
        return .result()
    }
}

// Example model data service
class ModelData {
    func search(matching labels: [String]) async throws -> [VisualSearchResult] {
        // Search your database for landmarks matching the labels
        // Return matching landmarks as VisualSearchResult objects
        return []
    }
    
    func search(matching pixelBuffer: CVReadOnlyPixelBuffer) async throws -> [VisualSearchResult] {
        // Use image recognition to find landmarks in the pixel buffer
        // Return matching landmarks as VisualSearchResult objects
        return []
    }
}
```

## Best Practices

1. **Performance**: Return results quickly for a good search experience
   - Limit the number of returned items (consider showing 10-20 most relevant results)
   - Use the "More results" button for additional items
   - Optimize your search algorithms for speed

2. **Quality**: Provide high-quality display representations
   - Use clear, concise titles and subtitles
   - Include relevant images that help identify the content
   - Ensure all text is properly localized

3. **Relevance**: Focus on returning the most relevant results
   - Prioritize exact matches over partial matches
   - Consider the context of the search (location, time, etc.)
   - Filter out irrelevant or low-confidence matches

4. **User Experience**: Make it easy to navigate from search results to your app
   - Implement deep linking to open specific content
   - Maintain context when transitioning to your app
   - Provide a consistent experience between search results and your app

## Testing

To test your Visual Intelligence integration:
1. Build and run your app on a device
2. Use the visual intelligence camera or take a screenshot
3. Perform a visual search on content relevant to your app
4. Verify that your app's results appear in the search results
5. Test tapping on results to ensure they open correctly in your app

## References

- [Integrating your app with visual intelligence](https://developer.apple.com/documentation/VisualIntelligence/integrating-your-app-with-visual-intelligence)
- [SemanticContentDescriptor](https://developer.apple.com/documentation/VisualIntelligence/SemanticContentDescriptor)
- [IntentValueQuery](https://developer.apple.com/documentation/AppIntents/IntentValueQuery)
- [DisplayRepresentation](https://developer.apple.com/documentation/AppIntents/DisplayRepresentation)
- [TypeDisplayRepresentation](https://developer.apple.com/documentation/appintents/TypeDisplayRepresentation)
- [App Intents framework](https://developer.apple.com/documentation/AppIntents)
- [Making actions and content discoverable and widely available](https://developer.apple.com/documentation/AppIntents/Making-actions-and-content-discoverable-and-widely-available)

# Using Place Descriptors with MapKit and GeoToolbox

## Overview

Place descriptors provide a standardized way to represent physical locations across different mapping services. The `GeoToolbox` framework allows you to create `PlaceDescriptor` structures that can be used with MapKit and third-party mapping systems. This guide covers how to work with place descriptors, integrate them with MapKit, and leverage their capabilities for location-based applications.

Key concepts:
- **PlaceDescriptor**: A structure containing identifying information about a place
- **PlaceRepresentation**: Common ways to represent a place (coordinates, addresses)
- **SupportingPlaceRepresentation**: Proprietary identifiers for places from different mapping services
- **MapKit integration**: Converting between MapKit objects and place descriptors

## Creating Place Descriptors

### From an Address String

```swift
import GeoToolbox

// Create a place descriptor with an address and common name
let fountain = PlaceDescriptor(
    representations: [.address("121-122 James's St \n Dublin 8 \n D08 ET27 \n Ireland")],
    commonName: "Obelisk Fountain"
)
```

### From Coordinates

```swift
import GeoToolbox

// Create a place descriptor with coordinates
let eiffelTower = PlaceDescriptor(
    representations: [.coordinate(CLLocationCoordinate2D(latitude: 48.8584, longitude: 2.2945))],
    commonName: "Eiffel Tower"
)
```

### From an MKMapItem

```swift
import MapKit
import GeoToolbox

// Convert an MKMapItem to a PlaceDescriptor
func convertMapItemToDescriptor(mapItem: MKMapItem) -> PlaceDescriptor? {
    guard let descriptor = PlaceDescriptor(item: mapItem) else {
        print("Failed to create place descriptor from map item")
        return nil
    }
    return descriptor
}
```

### With Multiple Representations

```swift
// Create a place descriptor with multiple representations
let statue = PlaceDescriptor(
    representations: [
        .coordinate(CLLocationCoordinate2D(latitude: 40.6892, longitude: -74.0445)),
        .address("Liberty Island, New York, NY 10004, United States")
    ],
    commonName: "Statue of Liberty"
)
```

## Working with Place Representations

### Understanding PlaceRepresentation

`PlaceRepresentation` is an enumeration that represents a physical place using common mapping concepts:

```swift
// Available PlaceRepresentation cases
// .coordinate(CLLocationCoordinate2D) - A location with latitude and longitude
// .address(String) - A full address string
```

### Accessing Representations

```swift
// Access the representations from a place descriptor
func printPlaceRepresentations(descriptor: PlaceDescriptor) {
    for representation in descriptor.representations {
        switch representation {
        case .coordinate(let coordinate):
            print("Coordinate: \(coordinate.latitude), \(coordinate.longitude)")
        case .address(let address):
            print("Address: \(address)")
        }
    }
}
```

### Extracting Coordinate

```swift
// Get the coordinate from a place descriptor if available
func getCoordinate(from descriptor: PlaceDescriptor) -> CLLocationCoordinate2D? {
    return descriptor.coordinate
}
```

### Extracting Address

```swift
// Get the address from a place descriptor if available
func getAddress(from descriptor: PlaceDescriptor) -> String? {
    return descriptor.address
}
```

## Supporting Place Representations

### Understanding SupportingPlaceRepresentation

`SupportingPlaceRepresentation` contains proprietary identifiers for places from different mapping services:

```swift
// Available SupportingPlaceRepresentation cases
// .serviceIdentifiers([String: String]) - Maps service provider IDs to place IDs
```

### Working with Service Identifiers

```swift
// Create a place descriptor with service identifiers
let landmark = PlaceDescriptor(
    representations: [.address("1 Infinite Loop, Cupertino, CA 95014")],
    commonName: "Apple Park",
    supportingRepresentations: [
        .serviceIdentifiers(["com.apple.maps": "ABC123XYZ", 
                            "com.google.maps": "ChIJq6qq6jK1j4ARzl-WRHNx9CI"])
    ]
)
```

### Retrieving Service Identifiers

```swift
// Get a specific service identifier
func getAppleMapsIdentifier(from descriptor: PlaceDescriptor) -> String? {
    return descriptor.serviceIdentifier(for: "com.apple.maps")
}
```

## Geocoding with MapKit

### Forward Geocoding (Address to Coordinates)

```swift
// Convert an address string to coordinates
func geocodeAddress(address: String) async throws -> [MKMapItem] {
    guard let request = MKGeocodingRequest(addressString: address) else {
        throw NSError(domain: "GeocodingError", code: 1, userInfo: nil)
    }
    
    return try await request.mapItems
}
```

### Reverse Geocoding (Coordinates to Address)

```swift
// Convert coordinates to address information
func reverseGeocode(coordinate: CLLocationCoordinate2D) async throws -> [MKMapItem] {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    
    guard let request = MKReverseGeocodingRequest(location: location) else {
        throw NSError(domain: "ReverseGeocodingError", code: 1, userInfo: nil)
    }
    
    return try await request.mapItems
}
```

### Creating PlaceDescriptor from Geocoding Results

```swift
// Create a place descriptor from geocoding results
func createDescriptorFromGeocodingResult(address: String) async throws -> PlaceDescriptor? {
    let mapItems = try await geocodeAddress(address: address)
    
    guard let firstItem = mapItems.first else {
        return nil
    }
    
    return PlaceDescriptor(item: firstItem)
}
```

## Practical Examples

### Creating and Using Place Descriptors

```swift
// Example: Creating and using a place descriptor for a landmark
func workWithLandmark() {
    // Create a place descriptor for a landmark
    let landmark = PlaceDescriptor(
        representations: [
            .coordinate(CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)),
            .address("San Francisco, CA, USA")
        ],
        commonName: "San Francisco"
    )
    
    // Access the common name
    if let name = landmark.commonName {
        print("Landmark name: \(name)")
    }
    
    // Access the coordinate
    if let coordinate = landmark.coordinate {
        print("Latitude: \(coordinate.latitude), Longitude: \(coordinate.longitude)")
    }
    
    // Access the address
    if let address = landmark.address {
        print("Address: \(address)")
    }
}
```

### Converting Between MapKit and GeoToolbox

```swift
// Example: Converting between MKMapItem and PlaceDescriptor
func convertBetweenMapKitAndGeoToolbox() async throws {
    // Start with an address
    let address = "1 Apple Park Way, Cupertino, CA 95014"
    
    // Geocode to get MKMapItem
    guard let request = MKGeocodingRequest(addressString: address) else {
        print("Failed to create geocoding request")
        return
    }
    
    let mapItems = try await request.mapItems
    
    guard let mapItem = mapItems.first else {
        print("No results found")
        return
    }
    
    // Convert MKMapItem to PlaceDescriptor
    guard let descriptor = PlaceDescriptor(item: mapItem) else {
        print("Failed to create descriptor from map item")
        return
    }
    
    // Use the descriptor
    print("Created descriptor for: \(descriptor.commonName ?? "Unknown place")")
    
    // Create a new MKMapItem from the descriptor's information
    if let coordinate = descriptor.coordinate {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let address = MKAddress()
        let newMapItem = MKMapItem(location: location, address: address)
        
        print("Created new map item at: \(newMapItem.location.coordinate.latitude), \(newMapItem.location.coordinate.longitude)")
    }
}
```

### Working with Multiple Mapping Services

```swift
// Example: Working with identifiers from multiple mapping services
func workWithMultipleServices() {
    // Create a place descriptor with identifiers for multiple services
    let place = PlaceDescriptor(
        representations: [.coordinate(CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278))],
        commonName: "London Eye",
        supportingRepresentations: [
            .serviceIdentifiers([
                "com.apple.maps": "AppleMapsID123",
                "com.google.maps": "GoogleMapsID456",
                "com.openstreetmap": "OSM789"
            ])
        ]
    )
    
    // Get identifiers for different services
    if let appleID = place.serviceIdentifier(for: "com.apple.maps") {
        print("Apple Maps ID: \(appleID)")
    }
    
    if let googleID = place.serviceIdentifier(for: "com.google.maps") {
        print("Google Maps ID: \(googleID)")
    }
    
    if let osmID = place.serviceIdentifier(for: "com.openstreetmap") {
        print("OpenStreetMap ID: \(osmID)")
    }
}
```

## References

- [GeoToolbox Framework](https://developer.apple.com/documentation/GeoToolbox)
- [PlaceDescriptor](https://developer.apple.com/documentation/GeoToolbox/PlaceDescriptor)
- [MapKit Framework](https://developer.apple.com/documentation/MapKit)
- [MKMapItem](https://developer.apple.com/documentation/MapKit/MKMapItem)
- [MKGeocodingRequest](https://developer.apple.com/documentation/MapKit/MKGeocodingRequest)
- [MKReverseGeocodingRequest](https://developer.apple.com/documentation/MapKit/MKReverseGeocodingRequest)
- [MKAddress](https://developer.apple.com/documentation/MapKit/MKAddress)
- [MKAddressRepresentations](https://developer.apple.com/documentation/MapKit/MKAddressRepresentations)

# StoreKit Updates

## Overview

StoreKit is Apple's framework for implementing in-app purchases, subscriptions, and App Store interactions. Recent updates have introduced significant enhancements to the core framework, new SwiftUI views for merchandising subscriptions, and improved tools for testing and development.

## Core Framework Updates

### AppTransaction Updates (iOS 18.4+)

`AppTransaction` now includes two new fields:

- **appTransactionID**: A globally unique identifier for each Apple Account that downloads your app
  - Unique for each family group member for apps supporting Family Sharing
  - Back-deployed to iOS 15
  
- **originalPlatform**: Indicates the platform on which the customer originally purchased the app
  - Values include iOS, macOS, tvOS, or visionOS
  - Helps support business model changes and entitle customers appropriately

```swift
// Example of accessing AppTransaction properties
Task {
    do {
        let appTransaction = try await AppTransaction.shared
        
        // Access the new properties
        let transactionID = appTransaction.appTransactionID
        let platform = appTransaction.originalPlatform
        
        // Use these values for business logic
        if platform == .iOS {
            // Handle iOS-specific logic
        }
    } catch {
        print("Failed to get app transaction: \(error)")
    }
}
```

### Transaction Updates (iOS 18.4+)

The `Transaction` type represents a successful In-App Purchase and has been enhanced with:

- **New API**: `Transaction.currentEntitlements(for:)` replaces `Transaction.currentEntitlement(for:)`
  - Returns an asynchronous sequence of transactions entitling the customer to a given product
  - Supports multiple entitlements through different means

- **New Fields**:
  - `appTransactionID`: Links transactions to the app download
  - `offerPeriod`: Details the subscription period associated with a redeemed offer
  - `advancedCommerceInfo`: Applies only to apps using the Advanced Commerce API

```swift
// Example of using the new currentEntitlements API
Task {
    for await verificationResult in Transaction.currentEntitlements(for: "your.product.id") {
        switch verificationResult {
        case .verified(let transaction):
            // Handle verified transaction
            let appTransactionID = transaction.appTransactionID
            if let offerPeriod = transaction.offerPeriod {
                // Handle offer period information
            }
        case .unverified(let transaction, let verificationError):
            // Handle unverified transaction
            print("Verification failed: \(verificationError)")
        }
    }
}
```

### RenewalInfo Updates (iOS 18.4+)

The `RenewalInfo` type for auto-renewable subscriptions has been enhanced with:

- **Enhanced API**: `SubscriptionStatus` can now query subscription statuses using a Transaction ID
- **Four New Fields**: Providing more comprehensive insights into subscription details
- **Expiration Reasons**: Valuable for understanding customer behavior and tailoring strategies
  - Example: If a subscription expires due to a price increase, you can offer win-back promotions

```swift
// Example of accessing subscription status with a transaction ID
Task {
    do {
        let status = try await Product.SubscriptionInfo.Status(transactionID: "transaction_id_here")
        
        // Access renewal info
        if let renewalInfo = status.renewalInfo {
            // Check expiration reason if applicable
            if let expirationReason = renewalInfo.expirationReason {
                switch expirationReason {
                case .priceIncrease:
                    // Offer a win-back promotion
                case .billingError:
                    // Prompt to update payment method
                default:
                    // Handle other expiration reasons
                }
            }
        }
    } catch {
        print("Failed to get subscription status: \(error)")
    }
}
```

## StoreKit Views

### SubscriptionOfferView

A new SwiftUI view for merchandising auto-renewable subscriptions:

```swift
// Basic usage with product ID
SubscriptionOfferView(productID: "your.subscription.id")
    .prefersPromotionalIcon(true)

// Using a loaded product
SubscriptionOfferView(product: loadedSubscriptionProduct)

// With custom icon
SubscriptionOfferView(productID: "your.subscription.id") {
    Image("custom_icon")
        .resizable()
        .frame(width: 40, height: 40)
}

// With placeholder icon while loading
SubscriptionOfferView(productID: "your.subscription.id") {
    Image("custom_icon")
        .resizable()
        .frame(width: 40, height: 40)
} placeholderIcon: {
    Image(systemName: "hourglass")
        .resizable()
        .frame(width: 40, height: 40)
}
```

### Configuring SubscriptionOfferView

Add detail action to direct customers to subscription store:

```swift
SubscriptionOfferView(productID: "your.subscription.id")
    .subscriptionOfferViewDetailAction {
        // Action when detail link is tapped
        isShowingSubscriptionStore = true
    }
```

### Displaying Different Plans Based on Customer Status

Configure which subscription plan to display using the `visibleRelationship` parameter:

```swift
// Using a subscription group ID
SubscriptionOfferView(groupID: "your.group.id", visibleRelationship: .upgrade)

// Available relationships:
// - .upgrade: Shows a plan one level higher than current
// - .downgrade: Shows a plan one level lower than current
// - .crossgrade: Shows equivalent tier plans with best value
// - .current: Shows customer's current plan
// - .all: Shows all plans in the group
```

### Tracking Subscription Status

Use the `subscriptionStatusTask` modifier to determine customer status:

```swift
@main
struct MyApp: App {
    @State private var customerStatus: SubscriptionStatus = .unknown
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.customerSubscriptionStatus, customerStatus)
                .subscriptionStatusTask(for: "your.group.id") { statuses in
                    // Translate StoreKit statuses to your app's model
                    if statuses.contains(where: { $0.state == .subscribed }) {
                        customerStatus = .subscribed
                    } else if statuses.contains(where: { $0.state == .expired }) {
                        customerStatus = .expired
                    } else {
                        customerStatus = .notSubscribed
                    }
                }
        }
    }
}
```

## In-App Purchase Request Signing

StoreKit now requires JSON Web Signatures (JWS) for certain Purchase Option and View Modifier APIs:

- Setting customer eligibility for introductory offers
- Signing promotional offers

The App Store Server Library simplifies the JWS signing process:

1. Retrieve your In-App Purchase signing key from App Store Connect
2. Use the key with the App Store Server Library to create signed requests

```swift
// Example of using the App Store Server Library for signing
import AppStoreServerLibrary

// Create a signed JWS for a promotional offer
func createSignedOfferJWS(productID: String, offerID: String) async throws -> String {
    let signingKey = try SigningKey(
        privateKeyFilePath: "path/to/key.p8",
        keyID: "YOUR_KEY_ID",
        issuerID: "YOUR_ISSUER_ID"
    )
    
    let library = try AppStoreServerLibrary(
        signingKey: signingKey,
        environment: .production
    )
    
    return try library.createOfferSignature(
        productIdentifier: productID,
        subscriptionOfferID: offerID,
        applicationUsername: nil,
        nonce: UUID().uuidString,
        keyIdentifier: "YOUR_KEY_ID",
        timestamp: Int(Date().timeIntervalSince1970)
    )
}
```

## Testing and Development

### StoreKit Testing in Xcode

Create a local StoreKit configuration file to test In-App Purchases without App Store Connect setup:

1. Select File > New > File From Template
2. Search for "storekit" and select "StoreKit Configuration File"
3. Name the file (e.g., `LocalConfiguration.storekit`)
4. Define products in the configuration file

### Transaction Manager

Use the Transaction Manager window in Xcode to:

- Create and inspect transactions
- Modify transaction properties
- Test different purchase scenarios

### Testing Subscription Offers

1. Set up subscription offers in your local configuration file
2. Implement the necessary JWS signing for offers
3. Test different offer scenarios using the Transaction Manager

## Advanced Commerce API

The Advanced Commerce API enables easier support for:

- In-App Purchases for large content catalogs
- Creator experiences
- Subscriptions with optional add-ons

This API is accessible through the new `advancedCommerceInfo` field in the `Transaction` model.

## References

- [StoreKit Documentation](https://developer.apple.com/documentation/storekit)
- [What's new in StoreKit and In-App Purchase (WWDC 2025)](https://developer.apple.com/videos/play/wwdc2025/241/)
- [Getting started with In-App Purchase using StoreKit views](https://developer.apple.com/documentation/StoreKit/getting-started-with-in-app-purchases-using-storekit-views)
- [Understanding StoreKit workflows](https://developer.apple.com/documentation/StoreKit/understanding-storekit-workflows)
- [App Store Server Library on GitHub](https://github.com/apple/app-store-server-library-swift)

