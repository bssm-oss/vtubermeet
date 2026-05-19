import AppKit

final class MessageTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let pressedReturn = event.keyCode == 36 || event.keyCode == 76
        if pressedReturn, !event.modifierFlags.contains(.shift), !hasMarkedText() {
            onSubmit?()
            return
        }

        super.keyDown(with: event)
    }
}
