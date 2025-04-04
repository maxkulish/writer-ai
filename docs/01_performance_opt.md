# WriterAI Performance Optimization Plan

This document outlines specific steps to improve the performance of the WriterAI application, specifically targeting the Swift agent which handles text selection, LLM processing, and result pasting. Currently, the process takes 2-3 seconds total, with the LLM response taking 600-1200 ms. The remaining 1.4-1.8 seconds is spent in the Swift agent's copy and paste operations.

## Performance Bottlenecks Identified

1. **Fixed Delays in Code:**
   - Copy operation: 750ms total fixed delays (250ms before + 500ms after)
   - Paste operation: 500ms total fixed delays (300ms before + 200ms after)
   - **Total fixed Swift delays:** ~1.25 seconds

2. **AppleScript Execution:**
   - IPC with System Events is slow and variable
   - Thread switching overhead

3. **Pasteboard Operations:**
   - `NSPasteboard` operations are relatively fast but still add overhead

4. **CGEvent Simulation:**
   - Currently used as fallback, but can be more efficient than AppleScript

## Action Plan

### 1. Reduce Fixed Delays

#### In `simulatePaste` method:
```swift
// CURRENT:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { ... }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { ... }

// PROPOSED:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ... }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { ... }
```

#### In `simulateCopy` method:
```swift
// CURRENT:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { ... }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { ... }

// PROPOSED:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ... }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { ... }
```

### 2. Optimize Pasting Strategy

Refactor `simulatePaste` to use CGEvent first with reduced delays:

```swift
private func simulatePaste(text: String, completion: @escaping (Bool) -> Void) {
    print("Simulating Cmd+V...")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)

    // Reduced delay before paste
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        print("DEBUG: Attempting paste via CGEvent first")
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let source = source else {
            print("ERROR: Failed to create CGEventSource")
            self.fallbackToAppleScriptPaste(completion: completion)
            return
        }

        let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)

        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)

        print("DEBUG: CGEvent paste sequence posted.")

        // Reduced delay after paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("DEBUG: Paste complete via CGEvent.")
            completion(true)
        }
    }
}

// Helper for fallback
private func fallbackToAppleScriptPaste(completion: @escaping (Bool) -> Void) {
    print("DEBUG: Falling back to AppleScript paste.")
    let pasteScript = "tell application \"System Events\" to keystroke \"v\" using command down"
    self.runAppleScript(script: pasteScript) { success in
        print("DEBUG: Paste complete via AppleScript fallback - success: \(success)")
        completion(success)
    }
}
```

### 3. Add Precise Timing Instrumentation

Add timing measurements to identify exactly how long each operation takes:

```swift
// In handleHotkey
let handleStart = Date()
simulateCopy { success in
    guard success else { /* ... */ return }
    let copyDuration = Date().timeIntervalSince(handleStart)
    print("TIMING: simulateCopy took \(copyDuration * 1000) ms")

    // ... get text ...
    let sendStart = Date()
    self.processTextWithFallbacks(selectedText, ...) { /* result handling */
         let networkDuration = Date().timeIntervalSince(sendStart)
         print("TIMING: processTextWithFallbacks took \(networkDuration * 1000) ms")
    }
}

// Inside sendToRustService completion
case .success(let llmResponse):
    let pasteStart = Date()
    self.simulatePaste(text: llmResponse) { pasteSuccess in
         let pasteDuration = Date().timeIntervalSince(pasteStart)
         print("TIMING: simulatePaste took \(pasteDuration * 1000) ms")
         // ... rest of logic ...
    }
```

### 4. Testing and Iteration

1. Implement the delay reduction changes first
2. Test in a variety of applications (browsers, text editors, IDE, etc.)
3. If reliability issues occur, incrementally increase delays until reliable
4. Implement CGEvent-first approach with fallback
5. Add timing instrumentation to identify remaining bottlenecks
6. Iterate based on timing data

### 5. Future Optimizations (If Needed)

If the above changes don't achieve desired performance, consider:

1. **Direct Text Insertion via Accessibility API:**
   - Use `AXUIElementSetAttributeValue` with `kAXSelectedTextAttribute` instead of pasteboard
   - More complex but potentially faster
   - Requires additional permission handling

2. **Parallel Processing:**
   - Begin sending text to Rust service immediately after copying
   - Prepare pasteboard while waiting for response

## Expected Results

With these optimizations, we aim to reduce the Swift agent overhead from 1.4-1.8 seconds to under 0.5 seconds, bringing the total operation time (including LLM processing) to under 2 seconds in most cases.

## Implementation Priority

1. Delay reduction (highest impact, lowest risk)
2. CGEvent-first approach for paste
3. Timing instrumentation
4. Testing and fine-tuning
5. Advanced techniques (only if needed)