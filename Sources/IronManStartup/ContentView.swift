import SwiftUI
import AppKit
import AVFoundation

/* Things learned:
struct ContentView: View   defines screen as a View
   var body: some View     View protocol, UI description, must return a View
        VStack { }         top-level container, stacks children top to bottom
           ZStack { }      nested container, stacks children front to back
      }

@State                     local value only this view owns (audioPlayer, isHovering below)
@EnvironmentObject         object shared from a parent view, here injected in IronManStartup.swift
@Published (on detector)   changing it auto-refreshes every view that reads it, no manual wiring
.animation(_, value:)      makes SwiftUI smoothly animate when "value" changes, instead of snapping
.transition(_)             how a view animates in/out when it's added/removed (the pulse ring below)
*/


/*
Current UI setup:
- Main VStack contains all content
    - Header section (VStack)
        - HStack: "J.A.R.V.I.S" title (left) + JARVIS image 128x128 (right)
    - Pulse indicator (ZStack): blue gradient circle, pulse ring + "OFF"/"ON"/"DOUBLE" label
    - Soundwave tracker (rolling level history + threshold line)
    - "Standing by" status text (centered), error banner when set
    - Sensitivity threshold section (VStack)
    - Event log (scrollable, timestamped)
    - Quit button (bottom left)
*/

struct ContentView: View {
    @State private var audioPlayer: AVAudioPlayer? 
    @State private var isHovering = false 
    @EnvironmentObject private var detector: DoubleClapDetectorService //shared mic/clap service

    var body: some View {
        VStack(alignment: .leading, spacing: 16) { //Main vertical stack for the entire content

            VStack(alignment: .leading, spacing: 8) { //VStack for header section with title and description
                HStack(alignment: .center) {
                    Text("J.A.R.V.I.S")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(.blue)

                    Spacer()

                    Image(nsImage: Bundle.module.image(forResource: "jarvis")!)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .scaleEffect(isHovering ? 1.12 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: isHovering)
                        .onHover { isHovering = $0 }
                        .onTapGesture {
                            if let url = Bundle.module.url(forResource: "jarvis", withExtension: "mp3") {
                                audioPlayer = try? AVAudioPlayer(contentsOf: url)
                                audioPlayer?.play()
                            }
                        }
                }

            }

            Spacer(minLength: 0)

            Button { //tapping the whole circle starts/stops listening
                detector.toggleListening() //calls start()/stop() on the shared DoubleClapDetectorService
            } label: {
                ZStack { //ZStack for pulse indicator, also doubles as the listen toggle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.25, green: 0.68, blue: 0.95),
                                    Color(red: 0.08, green: 0.35, blue: 0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(1 + min(CGFloat(detector.level) * 2.2, 1.1))
                        .shadow(
                            color: .blue.opacity(0.35 + min(CGFloat(detector.level) * 0.4, 0.4)),
                            radius: 22
                        )

                    if detector.pulseKind != nil { //ring only shows for ~0.7s right after a clap fires
                        Circle()
                            .stroke(
                                detector.pulseKind == .double ? Color.cyan : Color.blue,
                                lineWidth: 2
                            )
                            .frame(width: 120, height: 120)
                            .transition(.scale.combined(with: .opacity))
                    }

                    Text(detector.isListening ? (detector.pulseKind == .double ? "DOUBLE" : "ON") : "OFF") //label inside the circle, changes based on listening state
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .animation(.easeOut(duration: 0.2), value: detector.level) //smooths the scale/glow changes
            .animation(.easeOut(duration: 0.25), value: detector.pulseKind != nil) //smooths the ring in/out

            SoundwaveView(history: detector.history, threshold: detector.threshold) //custom view, defined below
                .frame(height: 70)

            Text(detector.isListening ? "Listening" : "Standing by") //status text, changes based on listening state
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)

            if let errorText = detector.errorText { //only appears once start()/startEngine() sets an error
                Text(errorText)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(10)
                    .background(
                        Color.red.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            }

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) { //VStack for sensitivity threshold in main VStack
                HStack {
                    Text("Sensitivity threshold")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text(String(format: "%.2f", detector.threshold))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.blue)
                }
                Slider(value: $detector.threshold, in: 0.05...0.6, step: 0.01)
                    .tint(.blue)
            }

            Text("EVENT LOG") //header for the log section, always visible
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            ScrollView { //scrolls once the log grows past frame(maxHeight:) below
                VStack(alignment: .leading, spacing: 10) {
                    if detector.logs.isEmpty {
                        Text("No events yet. Clap to begin.")
                            .font(.system(size: 13, weight: .regular, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(detector.logs) { entry in //one HStack per ClapLogEntry, newest first
                            HStack(spacing: 12) {
                                Text(entry.time)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 74, alignment: .leading)
                                Text(entry.text)
                            }
                            .font(.system(size: 12, weight: .regular, design: .monospaced))
                        }
                    }
                }
            }
            .frame(maxHeight: 190)
            .padding(.horizontal, 2)

            Spacer(minLength: 0)

            HStack { //HStack for the Quit button
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                Spacer()
            }
        }
        .padding(22)
        .frame(minWidth: 460, minHeight: 700)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.09, blue: 0.08),
                    Color(red: 0.06, green: 0.06, blue: 0.05)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .foregroundStyle(Color(red: 0.96, green: 0.95, blue: 0.93)) //belongs to main VStack, sets text color
    }
}

private struct SoundwaveView: View { //custom view for the rolling soundwave history + threshold line
    let history: [Float]
    let threshold: Float

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                if history.count < 2 { return }

                let thresholdY = yPosition(for: threshold, height: size.height)
                var thresholdPath = Path()
                thresholdPath.move(to: CGPoint(x: 0, y: thresholdY))
                thresholdPath.addLine(to: CGPoint(x: size.width, y: thresholdY))
                context.stroke(
                    thresholdPath,
                    with: .color(.cyan.opacity(0.7)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )

                var path = Path()
                for (index, value) in history.enumerated() {
                    let x = CGFloat(index) / CGFloat(max(history.count - 1, 1)) * size.width
                    let y = yPosition(for: value, height: size.height)
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                context.stroke(path, with: .color(.blue), lineWidth: 2)
            }
        }
    }

    private func yPosition(for value: Float, height: CGFloat) -> CGFloat { //higher level = higher on screen
        let clamped = min(max(value, 0), 0.8)
        return height - CGFloat(clamped / 0.8) * (height - 2)
    }
}