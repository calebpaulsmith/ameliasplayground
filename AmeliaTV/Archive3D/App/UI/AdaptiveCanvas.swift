import SwiftUI

/// Scaling helper that lets the same screens serve a 10-foot TV *and* a phone in
/// your hand. The UI is authored at a fixed "TV canvas" size (big, couch-readable
/// fonts and spacing); on iPhone/iPad we lay it out on that canvas and scale the
/// whole thing down to fit the real screen, so nothing crowds or clips. On tvOS
/// it's a no-op — there the screen already *is* the canvas, so the look is
/// unchanged.
extension View {
    func adaptiveTVCanvas(width: CGFloat = 1280, height: CGFloat = 720) -> some View {
        modifier(AdaptiveTVCanvas(design: CGSize(width: width, height: height)))
    }
}

private struct AdaptiveTVCanvas: ViewModifier {
    let design: CGSize

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        GeometryReader { geo in
            // Fit the canvas inside the available (safe-area-respecting) space.
            let fit = min(geo.size.width / design.width, geo.size.height / design.height)
            content
                .frame(width: design.width, height: design.height)
                .scaleEffect(min(fit, 1))                 // shrink to fit, never upscale
                .frame(width: geo.size.width, height: geo.size.height)  // re-center
        }
        #endif
    }
}
