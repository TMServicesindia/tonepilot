import Foundation

// Android's C library overlay has no Float overloads for some math functions (Darwin and
// Glibc do). These forward to the C `…f` functions; declarations in this module take
// precedence over imported ones, so call sites stay the same on every platform.
#if os(Android)
import Android

@inline(__always) func sin(_ x: Float) -> Float { sinf(x) }
@inline(__always) func cos(_ x: Float) -> Float { cosf(x) }
@inline(__always) func tan(_ x: Float) -> Float { tanf(x) }
@inline(__always) func exp(_ x: Float) -> Float { expf(x) }
@inline(__always) func exp2(_ x: Float) -> Float { exp2f(x) }
@inline(__always) func expm1(_ x: Float) -> Float { expm1f(x) }
@inline(__always) func log(_ x: Float) -> Float { logf(x) }
@inline(__always) func log2(_ x: Float) -> Float { log2f(x) }
@inline(__always) func log10(_ x: Float) -> Float { log10f(x) }
@inline(__always) func log1p(_ x: Float) -> Float { log1pf(x) }
@inline(__always) func pow(_ x: Float, _ y: Float) -> Float { powf(x, y) }
@inline(__always) func sqrt(_ x: Float) -> Float { sqrtf(x) }
#endif
