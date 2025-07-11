import SwiftUI
import AVFoundation

struct SpeakingIcon: Identifiable, Codable {
    let id = UUID()
    var title: String
    private var imageData: Data
    private var audioData: Data?
    
    var image: UIImage {
        UIImage(data: imageData) ?? UIImage()
    }
    
    var hasCustomAudio: Bool {
        audioData != nil
    }
    
    func getAudioData() -> Data? {
        audioData
    }
    
    init(title: String, image: UIImage, audioData: Data? = nil) {
        self.title = title
        self.imageData = image.jpegData(compressionQuality: 0.8) ?? Data()
        self.audioData = audioData
    }
    
    static let sample = SpeakingIcon(title: "Hello", image: UIImage(systemName: "person.wave.2.fill")?.withTintColor(.blue) ?? UIImage())
}

struct IconView: View {
    let icon: SpeakingIcon
    let onTap: () -> Void
    let onEdit: () -> Void
    @State private var isShowingDeleteConfirmation = false
    var onDelete: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: icon.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 15))
            
            Text(icon.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 40)
                .overlay(alignment: .topTrailing) {
                    if icon.hasCustomAudio {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                            .font(.system(size: 16))
                            .offset(x: 8, y: -8)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 3)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                isShowingDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete Icon",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete?()
            }
        } message: {
            Text("Are you sure you want to delete this icon?")
        }
        .onTapGesture {
            onTap()
        }
    }
} 