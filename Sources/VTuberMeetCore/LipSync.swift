import Foundation

public enum LipSync {
    public static func mouthOpen(elapsedSeconds: TimeInterval, speaking: Bool) -> Double {
        guard speaking else { return 0 }

        let fast = sin(elapsedSeconds * 18.0)
        let mid = sin(elapsedSeconds * 11.0 + 0.7)
        let slow = sin(elapsedSeconds * 6.0 + 1.9)
        let mixed = abs(fast * 0.48 + mid * 0.32 + slow * 0.2)
        return min(0.98, max(0.08, 0.14 + mixed * 0.84))
    }
}
