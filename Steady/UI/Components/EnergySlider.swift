import SwiftUI

struct EnergySlider: View {
    @Binding var energyLevel: Int
    let label: String
    
    @State private var isHovered = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Label row
            HStack {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("\(energyLevel)/10")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(energyColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(energyColor.opacity(0.15))
                    .cornerRadius(4)
            }
            
            // Slider
            GeometryReader { geometry in
                let width = geometry.size.width
                let segmentWidth = (width - CGFloat(9 * 4)) / 10 // 10 segments with 4pt spacing
                
                HStack(spacing: 4) {
                    ForEach(1...10, id: \.self) { level in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                energyLevel = level
                            }
                        }) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(level <= energyLevel ? energyColor : Color.secondary.opacity(0.2))
                                .frame(width: segmentWidth, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(level <= energyLevel ? energyColor : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .scaleEffect(isHovered ? 1.02 : 1.0)
                    }
                }
            }
            .frame(height: 24)
            
            // Labels row
            HStack {
                Text("Low")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("High")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            // Energy description
            Text(energyDescription)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var energyColor: Color {
        switch energyLevel {
        case 1...3:
            return .red
        case 4...6:
            return .orange
        case 7...8:
            return .yellow
        case 9...10:
            return .green
        default:
            return .gray
        }
    }
    
    private var energyDescription: String {
        switch energyLevel {
        case 1...3:
            return "Low energy - Consider shorter sessions"
        case 4...6:
            return "Moderate energy - Good for focused work"
        case 7...8:
            return "High energy - Great for challenging tasks"
        case 9...10:
            return "Peak energy - Optimal for deep work"
        default:
            return ""
        }
    }
}

struct EnergySlider_Previews: PreviewProvider {
    static var previews: some View {
        EnergySlider(energyLevel: .constant(7), label: "Current Energy Level")
            .padding()
            .frame(width: 400)
    }
}
