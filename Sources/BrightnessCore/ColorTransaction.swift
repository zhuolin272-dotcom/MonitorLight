import Foundation

/// Serial, synchronous transaction. Caller supplies hardware I/O and settling delay.
public enum ColorTransaction {
    public static func apply(target: ColorReading,
                             read: () throws -> ColorReading,
                             write: (Int, Int) throws -> Void) throws -> ColorReading {
        let before = try read()
        guard before.maxima == target.maxima else { throw ColorControlError.invalidReply }
        do {
            for (index, value) in target.values.enumerated() { try write(index, value) }
            let actual = try read()
            guard actual.matches(target) else {
                throw ColorControlError.readbackMismatch(expected: target.values, actual: actual.values)
            }
            return actual
        } catch {
            let detail = error.localizedDescription
            for (index, value) in before.values.enumerated() { try? write(index, value) }
            let restored = (try? read())?.matches(before) ?? false
            throw ColorControlError.writeFailed(detail, restored: restored)
        }
    }
}
