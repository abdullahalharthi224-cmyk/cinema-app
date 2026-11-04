import SwiftUI
import UIKit

extension View {
    /// Reports this view's frame in the window's own coordinates: top-left origin, in points, and
    /// never mirrored for right-to-left languages, so the same numbers work in Arabic and English.
    func onWindowFrameChange(_ action: @escaping (CGRect) -> Void) -> some View {
        modifier(WindowFrameModifier(action: action))
    }
}

private struct WindowFrameModifier: ViewModifier {
    let action: (CGRect) -> Void
    /// Bumped whenever SwiftUI moves the view (scrolling included), so UIKit measures again.
    @State private var moves = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { _ in moves &+= 1 }
            .background(WindowFrameReader(moves: moves, onChange: action).allowsHitTesting(false))
    }
}

private struct WindowFrameReader: UIViewRepresentable {
    let moves: Int
    let onChange: (CGRect) -> Void

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onChange = onChange
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
        view.report()
    }

    final class ReaderView: UIView {
        var onChange: ((CGRect) -> Void)?
        private var last = CGRect.null

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        func report() {
            guard window != nil else { return }
            let frame = convert(bounds, to: nil)
            guard frame != last else { return }
            last = frame
            DispatchQueue.main.async { [weak self] in self?.onChange?(frame) }
        }
    }
}
