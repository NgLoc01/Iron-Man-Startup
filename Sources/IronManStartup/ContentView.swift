import SwiftUI
import AppKit
import AVFoundation

/* Things learned:
struct ContentView: View   defines screen as a View
   var body: some View     View protocol, UI description, must return a View
        VStack { }         top-level container, stacks children top to bottom
           ZStack { }      nested container, stacks children front to back
      }  
*/

/*
Current UI setup:
- Main VStack contains all content
    - Header section (VStack)
        - HStack: "J.A.R.V.I.S" title (left) + JARVIS image 128x128 (right)
    - Pulse indicator (ZStack): orange gradient circle + "OFF" label
    - "Standing by" status text (centered)
    - Sensitivity threshold section (VStack)
    - Quit button (bottom left)
*/

struct ContentView: View {
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isHovering = false

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

            ZStack { //ZStack for pulse indicator
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.91, green: 0.44, blue: 0.17),
                                Color(red: 0.76, green: 0.30, blue: 0.10)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 110, height: 110)

                Text("OFF")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.85))
            }
            .frame(maxWidth: .infinity)

            Text("Standing by")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) { //VStack for sensitivity threshold in main VStack
                HStack {
                    Text("Sensitivity threshold")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Spacer()
                    Text("0.05")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.orange)
                }
                Slider(value: .constant(0.05), in: 0.05...0.6, step: 0.01)
                    .tint(.orange)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Quit") { }
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