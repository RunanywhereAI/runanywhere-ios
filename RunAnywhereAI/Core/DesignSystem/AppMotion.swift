import SwiftUI

/// The curves the app moves on.
///
/// These existed only as a convention, and a convention is what four people
/// working in parallel each remember slightly differently: the workflow editor
/// alone had four spring parameterisations and five easing durations for six
/// distinct jobs. Naming them makes the choice a decision rather than a number
/// typed from memory.
enum Motion {
    /// A control acknowledging a tap; a value settling into place.
    static let quick = Animation.easeOut(duration: 0.22)

    /// A crossfade between two states of the same thing.
    static let fade = Animation.easeInOut(duration: 0.2)

    /// Something growing or collapsing: a card opening, a node landing on the
    /// canvas. Damped enough not to wobble.
    static let expand = Animation.spring(response: 0.32, dampingFraction: 0.85)

    /// The heartbeat under anything still running. Slower than the rest on
    /// purpose — it repeats, and a fast repeat reads as an alarm.
    static let pulse = Animation.easeInOut(duration: 0.6)

    /// How far a pulse dims at its trough.
    static let pulseFloor: Double = 0.3

    /// A meter tracking a live signal. Shorter than `quick` because the source
    /// samples faster than that, and a longer curve smears the reading into a
    /// straight line.
    static let readout = Animation.easeOut(duration: 0.12)
}
