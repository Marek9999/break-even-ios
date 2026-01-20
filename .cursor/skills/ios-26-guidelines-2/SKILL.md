---
name: ios-26-guidelines-2
description: This is a new rule
---

# Overview
# Using 3D Charts with Swift Charts

## Overview

Swift Charts provides powerful 3D visualization capabilities through the `Chart3D` component, allowing developers to create immersive three-dimensional data visualizations. This guide covers how to create, customize, and interact with 3D charts in SwiftUI applications using the Swift Charts framework.

Key components for 3D charts include:
- `Chart3D`: The main container view for 3D chart content
- `SurfacePlot`: For visualizing 3D surface data
- `Chart3DPose`: For controlling the viewing angle and perspective
- `Chart3DSurfaceStyle`: For styling the appearance of 3D surfaces

## Basic Setup

### Importing Required Frameworks

```swift
import SwiftUI
import Charts
```

### Creating a Simple 3D Chart

The most basic 3D chart can be created using a mathematical function that maps x,y coordinates to z values:

```swift
struct Basic3DChartView: View {
    var body: some View {
        Chart3D {
            SurfacePlot(
                x: "X Axis",
                y: "Y Axis",
                z: "Z Axis",
                function: { x, y in
                    // Simple mathematical function: z = sin(x) * cos(y)
                    sin(x) * cos(y)
                }
            )
        }
    }
}
```

### Creating a 3D Chart from Data

You can also create 3D charts from collections of data:

```swift
struct DataPoint3D: Identifiable {
    var x: Double
    var y: Double
    var z: Double
    var id = UUID()
}

struct Data3DChartView: View {
    let dataPoints: [DataPoint3D] = [
        // Your 3D data points
    ]
    
    var body: some View {
        Chart3D(dataPoints) { point in
            // Create appropriate 3D visualization for each point
        }
    }
}
```

## Customizing 3D Charts

### Setting the Chart Pose (Viewing Angle)

Control the viewing angle of your 3D chart using `Chart3DPose`:

```swift
struct CustomPose3DChartView: View {
    // Create a state variable to store the pose
    @State private var chartPose: Chart3DPose = .default
    
    var body: some View {
        Chart3D {
            SurfacePlot(
                x: "X Axis",
                y: "Y Axis",
                z: "Z Axis",
                function: { x, y in
                    sin(x) * cos(y)
                }
            )
        }
        // Apply the pose to the chart
        .chart3DPose(chartPose)
    }
}
```

You can use predefined poses:
- `.default`: The default viewing angle
- `.front`: View from the front
- `.back`: View from the back
- `.top`: View from the top
- `.bottom`: View from the bottom
- `.right`: View from the right side
- `.left`: View from the left side

Or create a custom pose with specific azimuth and inclination angles:

```swift
Chart3DPose(azimuth: .degrees(45), inclination: .degrees(30))
```

### Interactive Pose Control

Allow users to interact with the chart by binding the pose to a state variable:

```swift
struct Interactive3DChartView: View {
    @State private var chartPose: Chart3DPose = .default
    
    var body: some View {
        Chart3D {
            SurfacePlot(
                x: "X Axis",
                y: "Y Axis",
                z: "Z Axis",
                function: { x, y in
                    sin(x) * cos(y)
                }
            )
        }
        // Bind the pose to enable interactive rotation
        .chart3DPose($chartPose)
    }
}
```

### Setting the Camera Projection

Control the camera projection of the points in a 3D chart using `Chart3DCameraProjection`:

```swift
struct CustomProjection3DChartView: View {
    // Create a state variable to store the pose
    @State private var cameraProjection: Chart3DCameraProjection = .perspective
    
    var body: some View {
        Chart3D {
            SurfacePlot(
                x: "X Axis",
                y: "Y Axis",
                z: "Z Axis",
                function: { x, y in
                    sin(x) * cos(y)
                }
            )
        }
        // Apply the camera projection to the chart
        .chart3DCameraProjection(cameraProjection)
    }
}
```

You can use the following camera projection styles:
- `.automatic`: Automatically determines the camera projection
- `.orthographic`: Objects maintain size regardless of depth
- `.perspective`: Objects appear smaller with distance

## Working with Surface Plots

### Basic Surface Plot

```swift
SurfacePlot(
    x: "X Axis",
    y: "Y Axis",
    z: "Z Axis",
    function: { x, y in
        // Mathematical function defining the surface
        sin(sqrt(x*x + y*y))
    }
)
```

### Styling Surface Plots

Apply different styles to your surface plots:

```swift
SurfacePlot(
    x: "X Axis",
    y: "Y Axis",
    z: "Z Axis",
    function: { x, y in
        sin(x) * cos(y)
    }
)
.foregroundStyle(Color.blue)
```

Available surface styles:
- `.heightBased`: Colors the surface based on the height (y-value)
- `.normalBased`: Colors the surface based on the surface normal direction

### Custom Gradient Surface Style

Create a custom gradient for your surface:

```swift
let customGradient = Gradient(colors: [.blue, .purple, .red])

SurfacePlot(
    x: "X Axis",
    y: "Y Axis",
    z: "Z Axis",
    function: { x, y in
        sin(x) * cos(y)
    }
)
.foregroundStyle(LinearGradient(gradient: customGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
```

### Controlling Surface Roughness

Adjust the roughness of the surface:

```swift
SurfacePlot(
    x: "X Axis",
    y: "Y Axis",
    z: "Z Axis",
    function: { x, y in
        sin(x) * cos(y)
    }
)
.roughness(0.3) // 0 is smooth, 1 is completely rough
```

## Advanced Techniques

### Combining Multiple Surface Plots

```swift
Chart3D {
    // First surface plot
    SurfacePlot(
        x: "X",
        y: "Y",
        z: "Z",
        function: { x, y in
            sin(x) * cos(y)
        }
    )
    
    // Second surface plot
    SurfacePlot(
        x: "X",
        y: "Y",
        z: "Z",
        function: { x, y in
            cos(x) * sin(y) + 2 // Offset to avoid overlap
        }
    )
}
```

### Specifying Y-Range for Height-Based Styling

Control the color mapping by specifying the y-range:

```swift
SurfacePlot(
    x: "X Axis",
    y: "Y Axis",
    z: "Z Axis",
    function: { x, y in
        sin(x) * cos(y)
    }
)
.foregroundStyle(Chart3DSurfaceStyle.heightBased(yRange: -1.0...1.0))
```

### Custom Gradient with Y-Range

```swift
let customGradient = Gradient(colors: [.blue, .green, .yellow, .red])

SurfacePlot(
    x: "X Axis",
    y: "Y Axis",
    z: "Z Axis",
    function: { x, y in
        sin(x) * cos(y)
    }
)
.foregroundStyle(Chart3DSurfaceStyle.heightBased(customGradient, yRange: -1.0...1.0))
```

## Complete Example: Interactive 3D Visualization

Here's a complete example that demonstrates an interactive 3D chart with customized styling:

```swift
import SwiftUI
import Charts

struct Interactive3DSurfaceView: View {
    // State for interactive rotation
    @State private var chartPose: Chart3DPose = .default
    
    // Custom gradient for surface coloring
    let surfaceGradient = Gradient(colors: [
        .blue,
        .cyan,
        .green,
        .yellow,
        .orange,
        .red
    ])
    
    var body: some View {
        VStack {
            Text("Interactive 3D Surface Visualization")
                .font(.headline)
            
            Chart3D {
                SurfacePlot(
                    x: "X Value",
                    y: "Y Value",
                    z: "Result",
                    function: { x, y in
                        // Interesting mathematical function
                        sin(sqrt(x*x + y*y)) / sqrt(x*x + y*y + 0.1)
                    }
                )
                .roughness(0.2)
            }
            .chart3DPose($chartPose)
            .frame(height: 400)
            
            Text("Drag to rotate the visualization")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Front View") {
                    withAnimation {
                        chartPose = .front
                    }
                }
                
                Button("Top View") {
                    withAnimation {
                        chartPose = .top
                    }
                }
                
                Button("Default View") {
                    withAnimation {
                        chartPose = .default
                    }
                }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}
```

## References

- [Apple Developer Documentation: Chart3D](https://developer.apple.com/documentation/Charts/Chart3D)
- [Apple Developer Documentation: SurfacePlot](https://developer.apple.com/documentation/Charts/SurfacePlot)
- [Apple Developer Documentation: Chart3DPose](https://developer.apple.com/documentation/Charts/Chart3DPose)
- [Apple Developer Documentation: Chart3DSurfaceStyle](https://developer.apple.com/documentation/Charts/Chart3DSurfaceStyle)
- [Apple Developer Documentation: Creating a chart using Swift Charts](https://developer.apple.com/documentation/Charts/Creating-a-chart-using-Swift-Charts)

## Concurrent programming updates in Swift 6.2

Concurrent programming is hard because sharing memory between multiple tasks is prone to mistakes that lead to unpredictable behavior.

## Data-race safety

 Data-race safety in Swift 6 prevents these mistakes at compile time, so you can write concurrent code without fear of introducing hard-to-debug runtime bugs. But in many cases, the most natural code to write is prone to data races, leading to compiler errors that you have to address. A class with mutable state, like this `PhotoProcessor` class, is safe as long as you don’t access it concurrently.

```swift
class PhotoProcessor {
  func extractSticker(data: Data, with id: String?) async -> Sticker? {     }
}

@MainActor
final class StickerModel {
  let photoProcessor = PhotoProcessor()

  func extractSticker(_ item: PhotosPickerItem) async throws -> Sticker? {
    guard let data = try await item.loadTransferable(type: Data.self) else {
      return nil
    }

    // Error: Sending 'self.photoProcessor' risks causing data races
    // Sending main actor-isolated 'self.photoProcessor' to nonisolated instance method 'extractSticker(data:with:)' 
    // risks causing data races between nonisolated and main actor-isolated uses
    return await photoProcessor.extractSticker(data: data, with: item.itemIdentifier)
  }
}
```

 It has an async method to extract a `Sticker` by computing the subject of the given image data. But if you try to call `extractSticker` from UI code on the main actor, you’ll get an error that the call risks causing data races. This is because there are several places in the language that offload work to the background implicitly, even if you never needed code to run in parallel.

Swift 6.2 changes this philosophy to stay single threaded by default until you choose to introduce concurrency.

```swift
class PhotoProcessor {
  func extractSticker(data: Data, with id: String?) async -> Sticker? {     }
}

@MainActor
final class StickerModel {
  let photoProcessor = PhotoProcessor()

  func extractSticker(_ item: PhotosPickerItem) async throws -> Sticker? {
    guard let data = try await item.loadTransferable(type: Data.self) else {
      return nil
    }

    // No longer a data race error in Swift 6.2 because of Approachable Concurrency and default actor isolation
    return await photoProcessor.extractSticker(data: data, with: item.itemIdentifier)
  }
}
```

The language changes in Swift 6.2 make the most natural code to write data race free by default. This provides a more approachable path to introducing concurrency in a project.

When you choose to introduce concurrency because you want to run code in parallel, data-race safety will protect you.

First, we've made it easier to call async functions on types with mutable state. Instead of eagerly offloading async functions that aren't tied to a specific actor, the function will continue to run on the actor it was called from. This eliminates data races because the values passed into the async function are never sent outside the actor. Async functions can still offload work in their implementation, but clients don’t have to worry about their mutable state.

Next, we’ve made it easier to implement conformances on main actor types. Here I have a protocol called `Exportable`, and I’m trying to implement a conformance for my main actor `StickerModel` class. The export requirement doesn’t have actor isolation, so the language assumed that it could be called from off the main actor, and prevented `StickerModel` from using main actor state in its implementation.

```swift
protocol Exportable {
  func export()
}

extension StickerModel: Exportable { // error: Conformance of 'StickerModel' to protocol 'Exportable' crosses into main actor-isolated code and can cause data races
  func export() {
    photoProcessor.exportAsPNG()
  }
}
```

Swift 6.2 supports these conformances. A conformance that needs main actor state is called an *isolated* conformance. This is safe because the compiler ensures a main actor conformance is only used on the main actor.

```swift
// Isolated conformances

protocol Exportable {
  func export()
}

extension StickerModel: @MainActor Exportable {
  func export() {
    photoProcessor.exportAsPNG()
  }
}
```

 I can create an `ImageExporter` type that adds a `StickerModel` to an array of any `Exportable` items as long as it stays on the main actor.

```swift
 // Isolated conformances

@MainActor
struct ImageExporter {
  var items: [any Exportable]

  mutating func add(_ item: StickerModel) {
    items.append(item)
  }

  func exportAll() {
    for item in items {
      item.export()
    }
  }
}
```

But if I allow `ImageExporter` to be used from anywhere, the compiler prevents adding `StickerModel` to the array because it isn’t safe to call export on `StickerModel` from outside the main actor.

```swift
// Isolated conformances

nonisolated
struct ImageExporter {
  var items: [any Exportable]

  mutating func add(_ item: StickerModel) {
    items.append(item) // error: Main actor-isolated conformance of 'StickerModel' to 'Exportable' cannot be used in nonisolated context
  }

  func exportAll() {
    for item in items {
      item.export()
    }
  }
}
```

With isolated conformances, you only have to solve data race safety issues when the code indicates that it uses the conformance concurrently.

## Global State

Global and static variables are prone to data races because they allow mutable state to be accessed from anywhere.

```swift
final class StickerLibrary {
  static let shared: StickerLibrary = .init() // error: Static property 'shared' is not concurrency-safe because non-'Sendable' type 'StickerLibrary' may have shared mutable state
}
```

The most common way to protect global state is with the main actor.

```swift
final class StickerLibrary {
  @MainActor
  static let shared: StickerLibrary = .init()
}
```

 And it’s common to annotate an entire class with the main actor to protect all of its mutable state, especially in a project that doesn’t have a lot of concurrent tasks.

```swift
@MainActor
final class StickerLibrary {
  static let shared: StickerLibrary = .init()
}
```

You can model a program that's entirely single-threaded by writing `@MainActor` on everything in your project.

```swift
@MainActor
final class StickerLibrary {
  static let shared: StickerLibrary = .init()
}

@MainActor
final class StickerModel {
  let photoProcessor: PhotoProcessor

  var selection: [PhotosPickerItem]
}

extension StickerModel: @MainActor Exportable {
  func export() {
    photoProcessor.exportAsPNG()
  }
}
```

To make it easier to model single-threaded code, we’ve introduced a mode to infer main actor by default.

```swift
// Mode to infer main actor by default in Swift 6.2

final class StickerLibrary {
  static let shared: StickerLibrary = .init()
}

final class StickerModel {
  let photoProcessor: PhotoProcessor

  var selection: [PhotosPickerItem]
}

extension StickerModel: Exportable {
  func export() {
    photoProcessor.exportAsPNG()
  }
}
```

 This eliminates data-race safety errors about unsafe global and static variables, calls to other main actor functions like ones from the SDK, and more, because the main actor protects all mutable state by default. It also reduces concurrency annotations in code that’s mostly single-threaded. This mode is great for projects that do most of the work on the main actor, and concurrent code is encapsulated within specific types or files. It’s opt-in and it’s recommended for apps, scripts, and other executable targets.

## Offloading work to the background

Offloading work to the background is still important for performance, such as keeping apps responsive when performing CPU-intensive tasks.

Let’s look at the implementation of the `extractSticker` method on `PhotoProcessor`.

```swift
// Explicitly offloading async work

class PhotoProcessor {
  var cachedStickers: [String: Sticker]

  func extractSticker(data: Data, with id: String) async -> Sticker {
      if let sticker = cachedStickers[id] {
        return sticker
      }

      let sticker = await Self.extractSubject(from: data)
      cachedStickers[id] = sticker
      return sticker
  }

  // Offload expensive image processing using the @concurrent attribute.
  @concurrent
  static func extractSubject(from data: Data) async -> Sticker { }
}
```

It first checks whether it already extracted a sticker for an image, so it can return the cached sticker immediately. If the sticker hasn’t been cached, it extracts the subject from the image data and creates a new sticker. The `extractSubject` method performs expensive image processing that I don’t want to block the main actor or any other actor.

I can offload this work using the `@concurrent` attribute. `@concurrent` ensures that a function always runs on the concurrent thread pool, freeing up the actor to run other tasks at the same time.

### An example

Say you have a function called `process` that you would like to run on a background thread. To call that function on a background thread you need to:

- make sure the structure or class is `nonisolated`
- add the `@concurrent` attribute to the function you want to run in the background
- add the keyword `async` to the function if it is not already asynchronous
- and then add the keyword `await` to any callers

Like this:

```swift
nonisolated struct PhotoProcessor {

    @concurrent
    func process(data: Data) async -> ProcessedPhoto? { ... }
}

// Callers with the added await
processedPhotos[item.id] = await PhotoProcessor().process(data: data)
```


## Summary

These language changes work together to make concurrency more approachable.

You start by writing code that runs on the main actor by default, where there’s no risk of data races. When you start to use async functions, those functions run wherever they’re called from. There’s still no risk of data races because all of your code still runs on the main actor. When you’re ready to embrace concurrency to improve performance, it’s easy to offload specific code to the background to run in parallel.

Some of these language changes are opt-in because they require changes in your project to adopt. You can find and enable all of the approachable concurrency language changes under the Swift Compiler - Concurrency section of Xcode build settings. You can also enable these features in a Swift package manifest file using the SwiftSettings API.

 Swift 6.2 includes migration tooling to help you make the necessary code changes automatically. You can learn more about migration tooling at swift.org/migration.


# Swift Standard Library: InlineArray and Span

## Overview

InlineArray and Span are two new types introduced in Swift 6.2 to enhance performance of critical code. These types are designed to provide more efficient memory usage and better performance in specific scenarios where standard Swift collections might introduce overhead.

Key concepts:
- **InlineArray**: A fixed-size array with inline storage that eliminates heap allocation
- **Span**: A safe abstraction for accessing contiguous memory without the dangers of unsafe pointers

## InlineArray

### What is InlineArray?

`InlineArray` is a specialized array type that stores its elements contiguously inline, rather than allocating an out-of-line region of memory with copy-on-write optimization. This means the elements are stored directly within the array's memory layout, not in a separate heap allocation.

### Declaration

```swift
@frozen struct InlineArray<let count: Int, Element> where Element: ~Copyable
```

The `count` parameter uses Swift's value generics feature to make the size part of the type.

### Key Characteristics

- **Fixed size**: Size is specified at compile time and cannot be changed
- **Inline storage**: Elements are stored directly, not via a reference to a buffer
- **No heap allocation**: Can be stored on the stack or directly within other types
- **No dynamic resizing**: Cannot append or remove elements
- **No copy-on-write**: Copies are made eagerly when assigned to a new variable
- **No reference counting**: Eliminates the overhead of retain/release operations
- **No exclusivity checks**: Improves performance in hot paths

### Initialization

Array literals can be used to initialize an InlineArray:

```swift
// Explicit type specification
let a: InlineArray<4, Int> = [1, 2, 4, 8]

// Type inference for count
let b: InlineArray<_, Int> = [1, 2, 4, 8]  // count inferred as 4

// Type inference for element type
let c: InlineArray<4, _> = [1, 2, 4, 8]    // Element type inferred as Int

// Type inference for both
let d: InlineArray = [1, 2, 4, 8]          // InlineArray<4, Int>
```

### Memory Layout

```swift
// Empty array
MemoryLayout<InlineArray<0, UInt16>>.size       // 0
MemoryLayout<InlineArray<0, UInt16>>.stride     // 1
MemoryLayout<InlineArray<0, UInt16>>.alignment  // 1

// Non-empty array
MemoryLayout<InlineArray<3, UInt16>>.size       // 6 (2 bytes × 3 elements)
MemoryLayout<InlineArray<3, UInt16>>.stride     // 6
MemoryLayout<InlineArray<3, UInt16>>.alignment  // 2 (same as UInt16)
```

### Basic Usage

```swift
// Create an inline array
var array: InlineArray<3, Int> = [1, 2, 3]

// Modify elements
array[0] = 4
// array == [4, 2, 3]

// Cannot append or remove elements
// array.append(4)  // Error: Value of type 'InlineArray<3, Int>' has no member 'append'

// Cannot assign to a different sized inline array
// let bigger: InlineArray<6, Int> = array  // Error: Cannot assign value of type 'InlineArray<3, Int>' to type 'InlineArray<6, Int>'

// Copying behavior
var copy = array    // copy happens on assignment
for i in copy.indices {
    copy[i] += 10
}
// array == [4, 2, 3]
// copy == [14, 12, 13]
```

### Common Properties and Methods

```swift
var array: InlineArray<3, Int> = [1, 2, 3]

// Properties
array.count        // 3
array.isEmpty      // false
array.indices      // 0..<3

// Accessing elements
let firstElement = array[0]  // 1

// Iteration
for element in array {
    print(element)
}

// Using indices
for i in array.indices {
    print(array[i])
}
```

### When to Use InlineArray

InlineArray is ideal for:
- Performance-critical code paths
- Fixed-size collections that never change size
- Avoiding heap allocations and reference counting overhead
- Collections that are modified in place but rarely copied
- Embedded systems or low-level programming

Not suitable for:
- Collections that need to grow or shrink
- Collections that benefit from copy-on-write semantics
- Collections that are frequently copied or shared between variables

## Span

### What is Span?

`Span` is an abstraction that provides fast, direct access to contiguous memory without compromising memory safety. It's designed as a safe alternative to unsafe pointers, providing efficient access to the underlying storage of containers like Array and InlineArray.

### Declarations

```swift
@frozen struct Span<Element> where Element : ~Copyable
```

Span<Element> represents a contiguous region of memory which contains initialized instances of Element.

```swift
var span: Span<Element> { get }
var mutableSpan: MutableSpan<Element> { mutating get }
```

Instance Properties of Array.

### Key Characteristics

- **Memory safety**: Ensures memory validity through compile-time checks
- **Lifetime dependency**: Cannot outlive the original container
- **No runtime overhead**: Safety checks are performed at compile time
- **Direct access**: Provides efficient access to contiguous memory
- **Non-escapable**: Cannot be returned from functions or captured in closures
- **Prevents common memory issues**: Use-after-free, overlapping modification, etc.

### Types of Spans

The Span family includes:
- **Span<Element>**: Read-only access to contiguous elements
- **MutableSpan<Element>**: Mutable access to contiguous elements
- **RawSpan**: Read-only access to raw bytes
- **MutableRawSpan**: Mutable access to raw bytes
- **OutputSpan**: For initializing a new collection
- **UTF8Span**: Specialized for safe and efficient Unicode processing

### Accessing Spans

Containers with contiguous storage provide a `span` property:

```swift
let array = [1, 2, 3, 4]
let span = array.span  // Get a Span<Int> over the array's elements

// Data also provides span access
let data = Data([0, 1, 2, 3])
let dataSpan = data.span  // Get a Span<UInt8>
```

### Safe Usage

```swift
// Safe usage of a span
func processUsingSpan(_ array: [Int]) -> Int {
    let intSpan = array.span
    var result = 0
    for i in 0..<intSpan.count {
        result += intSpan[i]
    }
    return result
}
```

### Safety Constraints

Spans have compile-time safety constraints:

1. **Cannot escape their scope**:
```swift
// This won't compile
func getSpan() -> Span<UInt8> {
    let array: [UInt8] = Array(repeating: 0, count: 128)
    return array.span  // Error: Cannot return span that depends on local variable
}
```

2. **Cannot be captured in closures**:
```swift
// This won't compile
func getClosure() -> () -> Int {
    let array: [UInt8] = Array(repeating: 0, count: 128)
    let span = array.span
    return { span.count }  // Error: Cannot capture span in closure
}
```

3. **Cannot access span after modifying the original container**:
```swift
var array = [1, 2, 3]
let span = array.span
array.append(4)
// let x = span[0]  // Error: Cannot access span after modifying the original container
```

### Example: Implementing a Method Using RawSpan

```swift
extension RawSpan {
    mutating func readByte() -> UInt8? {
        guard !isEmpty else { return nil }
        
        let value = unsafeLoadUnaligned(as: UInt8.self)
        self = self._extracting(droppingFirst: 1)
        return value
    }
}
```

### When to Use Span

Span is ideal for:
- Efficiently operating on contiguous memory without unsafe pointers
- Processing large amounts of data with minimal overhead
- Implementing high-performance algorithms that need direct memory access
- Safely working with the underlying storage of collections
- Binary parsing and other low-level operations

## Performance Considerations

### InlineArray vs. Array

Standard Array:
- Stores elements in a separate heap allocation
- Uses reference counting to track copies
- Performs uniqueness checks on mutation
- Enforces exclusivity at runtime in some cases
- Supports dynamic resizing

InlineArray:
- Stores elements directly inline
- No reference counting overhead
- No uniqueness checks
- No runtime exclusivity checks
- Fixed size known at compile time

### Span vs. Unsafe Pointers

Unsafe Pointers:
- Require manual memory management
- Prone to memory safety issues
- No compile-time safety guarantees
- Can lead to crashes or undefined behavior

Span:
- Provides memory safety through compile-time checks
- Prevents use-after-free and similar issues
- No runtime overhead compared to pointers
- Cannot outlive the original container

## References

- [Swift Documentation: InlineArray](https://developer.apple.com/documentation/Swift/InlineArray)
- [Swift Documentation: Span](https://developer.apple.com/documentation/Swift/Span)
- [Swift Documentation: Array.span](https://developer.apple.com/documentation/swift/array/span)
- [Swift Documentation: Array.mutableSpan](https://developer.apple.com/documentation/swift/array/mutablespan)
- [WWDC 2025 Session: What's new in Swift](https://developer.apple.com/videos/play/wwdc2025/245/)
- [WWDC 2025 Session: Improve memory usage and performance with Swift](https://developer.apple.com/videos/play/wwdc2025/312/)

# Adopting Class Inheritance in Swift Data

## Overview

Swift Data supports class inheritance, allowing you to create hierarchical relationships between your model classes. This powerful feature enables you to build more flexible and specialized data models by creating subclasses that inherit properties and capabilities from a base class. Class inheritance in Swift Data follows the same principles as standard Swift inheritance but with additional considerations for persistence and querying.

Key concepts include:
- Base classes that define common properties and behaviors
- Specialized subclasses that extend functionality for specific use cases
- Type-based querying that can filter by specific model types
- Polymorphic relationships that work with different model types

## When to Use Inheritance in Swift Data

### Good Use Cases

- When you have a clear "IS-A" relationship between models (e.g., a `BusinessTrip` IS-A `Trip`)
- When models share fundamental properties but diverge as use cases become more specialized
- When your app needs to perform both deep searches (across all properties) and shallow searches (specific to subclass properties)
- When your data model naturally forms a hierarchical structure

```swift
// Example of a good inheritance relationship
@Model class Vehicle {
    var manufacturer: String
    var model: String
    var year: Int
}

@Model class Car: Vehicle {
    var numberOfDoors: Int
    var fuelType: FuelType
}

@Model class Motorcycle: Vehicle {
    var engineDisplacement: Int
    var hasABS: Bool
}
```

### When to Avoid Inheritance

- When specialized subclasses would only share a few common properties
- When your query strategy only focuses on specialized properties (shallow queries)
- When a Boolean flag or enumeration could represent the type distinction more efficiently
- When protocol conformance would be more appropriate for shared behavior

```swift
// Alternative to inheritance using an enum approach
@Model class Vehicle {
    var manufacturer: String
    var model: String
    var year: Int
    
    enum VehicleType: String, Codable {
        case car(numberOfDoors: Int, fuelType: FuelType)
        case motorcycle(engineDisplacement: Int, hasABS: Bool)
    }
    
    var type: VehicleType
}
```

## Designing Class Hierarchies

### Base Class Design

1. Identify common properties that all subclasses will share
2. Define relationships that apply to all subclasses
3. Use the `@Model` macro on the base class
4. Ensure the base class is declared as a `class` (not a struct)

```swift
import SwiftData

@Model class Trip {
    @Attribute(.preserveValueOnDeletion)
    var name: String
    var destination: String
    
    @Attribute(.preserveValueOnDeletion)
    var startDate: Date
    
    @Attribute(.preserveValueOnDeletion)
    var endDate: Date

    @Relationship(deleteRule: .cascade, inverse: \Accommodation.trip)
    var accommodation: Accommodation?
    
    init(name: String, destination: String, startDate: Date, endDate: Date) {
        self.name = name
        self.destination = destination
        self.startDate = startDate
        self.endDate = endDate
    }
}
```

### Subclass Design

1. Inherit from the base class using standard Swift inheritance syntax
2. Add the `@Model` macro to the subclass
3. Add specialized properties and relationships specific to the subclass
4. Override methods as needed
5. Consider availability annotations if needed

```swift
@Model class BusinessTrip: Trip {
    var purpose: String
    var expenseCode: String
    var perDiemRate: Double
    
    @Relationship(deleteRule: .cascade, inverse: \BusinessMeal.trip)
    var businessMeals: [BusinessMeal] = []
    
    @Relationship(deleteRule: .cascade, inverse: \MileageRecord.trip)
    var mileageRecords: [MileageRecord] = []
    
    init(name: String, destination: String, startDate: Date, endDate: Date,
         purpose: String, expenseCode: String, perDiemRate: Double) {
        self.purpose = purpose
        self.expenseCode = expenseCode
        self.perDiemRate = perDiemRate
        super.init(name: name, destination: destination, startDate: startDate, endDate: endDate)
    }
}
```

```swift
@Model class PersonalTrip: Trip {
    enum Reason: String, CaseIterable, Codable, Identifiable {
        case family, vacation, wellness, other
        var id: Self { self }
    }
    
    var reason: Reason
    var notes: String?
    
    @Relationship(deleteRule: .cascade, inverse: \Attraction.trip)
    var attractions: [Attraction] = []
    
    init(name: String, destination: String, startDate: Date, endDate: Date,
         reason: Reason, notes: String? = nil) {
        self.reason = reason
        self.notes = notes
        super.init(name: name, destination: destination, startDate: startDate, endDate: endDate)
    }
}
```

## Querying with Inheritance

### Basic Queries

You can query for all instances of a base class, which will include all subclass instances:

```swift
// Query for all trips (including BusinessTrip and PersonalTrip)
@Query(sort: \Trip.startDate)
var allTrips: [Trip]
```

### Type-Based Filtering

Filter by specific subclass types using the `is` operator in predicates:

```swift
// Query for only BusinessTrip instances
let businessTripPredicate = #Predicate<Trip> { $0 is BusinessTrip }
@Query(filter: businessTripPredicate)
var businessTrips: [Trip]
```

### Combined Filtering

Combine type filtering with property filtering:

```swift
// Query for PersonalTrip instances with a specific reason
let personalVacationPredicate = #Predicate<Trip> {
    if let personalTrip = $0 as? PersonalTrip {
        return personalTrip.reason == .vacation
    }
    return false
}

@Query(filter: personalVacationPredicate)
var vacationTrips: [Trip]
```

### Using Enums for Filtering

Create an enum to simplify filtering by type:

```swift
enum TripKind: String, CaseIterable {
    case all = "All"
    case personal = "Personal"
    case business = "Business"
}

struct TripListView: View {
    @Query var trips: [Trip]
    
    init(tripKind: TripKind, searchText: String = "") {
        // Create type predicate based on selected kind
        let typePredicate: Predicate<Trip>? = {
            switch tripKind {
            case .all:
                return nil
            case .personal:
                return #Predicate { $0 is PersonalTrip }
            case .business:
                return #Predicate { $0 is BusinessTrip }
            }
        }()
        
        // Create search predicate if needed
        let searchPredicate = searchText.isEmpty ? nil : #Predicate<Trip> {
            $0.name.localizedStandardContains(searchText) || 
            $0.destination.localizedStandardContains(searchText)
        }
        
        // Combine predicates if both exist
        let finalPredicate: Predicate<Trip>?
        if let typePredicate, let searchPredicate {
            finalPredicate = #Predicate { typePredicate.evaluate($0) && searchPredicate.evaluate($0) }
        } else {
            finalPredicate = typePredicate ?? searchPredicate
        }
        
        _trips = Query(filter: finalPredicate, sort: \.startDate)
    }
}
```

## Working with Subclass Properties

### Type Casting

When working with a collection of base class instances, you'll need to cast to access subclass-specific properties:

```swift
func calculateTotalExpenses(for trips: [Trip]) -> Double {
    var total = 0.0
    
    for trip in trips {
        if let businessTrip = trip as? BusinessTrip {
            // Access BusinessTrip-specific properties
            let perDiemTotal = businessTrip.perDiemRate * Double(Calendar.current.dateComponents([.day], from: businessTrip.startDate, to: businessTrip.endDate).day ?? 0)
            
            // Add meal expenses
            let mealExpenses = businessTrip.businessMeals.reduce(0.0) { $0 + $1.cost }
            
            total += perDiemTotal + mealExpenses
        }
    }
    
    return total
}
```

### Polymorphic Relationships

You can create relationships that work with the base class but contain instances of different subclasses:

```swift
@Model class TravelPlanner {
    var name: String
    
    @Relationship(deleteRule: .cascade)
    var upcomingTrips: [Trip] = []  // Can contain both BusinessTrip and PersonalTrip instances
    
    func addTrip(_ trip: Trip) {
        upcomingTrips.append(trip)
    }
}
```

## Best Practices

1. **Keep inheritance hierarchies shallow**: Avoid deep inheritance chains that can become difficult to maintain.

2. **Use meaningful IS-A relationships**: Only use inheritance when there's a true "is-a" relationship between models.

3. **Consider alternatives**: For simpler cases, enums or Boolean flags might be more appropriate than inheritance.

4. **Design for query patterns**: Consider how you'll query your data when designing your class hierarchy.

5. **Be mindful of schema migrations**: Changes to your inheritance hierarchy may require more complex migrations.

6. **Document the inheritance structure**: Make sure other developers understand the relationships between your models.

7. **Test with real data**: Verify that your inheritance structure works well with realistic data and query patterns.

## References

- [Adopting inheritance in SwiftData](https://developer.apple.com/documentation/SwiftData/Adopting-inheritance-in-SwiftData)
- [Design for specialization](https://developer.apple.com/documentation/SwiftData/Adopting-inheritance-in-SwiftData#Design-for-specialization)
- [Determine whether inheritance is right for your use case](https://developer.apple.com/documentation/SwiftData/Adopting-inheritance-in-SwiftData#Determine-whether-inheritance-is-right-for-your-use-case)
- [Fetch and Query Data](https://developer.apple.com/documentation/SwiftData/Adopting-inheritance-in-SwiftData#Fetch-and-Query-Data)
