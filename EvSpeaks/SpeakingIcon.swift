import SwiftUI
import AVFoundation

struct SpeakingIcon: Identifiable, Codable {
    let id = UUID()
    var title: String
    private var imageData: Data
    private var audioData: Data?
    var isQuickAccess: Bool = false
    
    var image: UIImage {
        UIImage(data: imageData) ?? UIImage()
    }
    
    var hasCustomAudio: Bool {
        audioData != nil
    }
    
    func getAudioData() -> Data? {
        audioData
    }
    
    init(title: String, image: UIImage, audioData: Data? = nil, isQuickAccess: Bool = false) {
        self.title = title
        // Process image compression - use slightly lower quality for faster processing
        // Since this is called from background thread in createAsync, it won't block UI
        self.imageData = image.jpegData(compressionQuality: 0.75) ?? Data()
        self.audioData = audioData
        self.isQuickAccess = isQuickAccess
    }
    
    // Optimized image resizing and compression
    private static func optimizeImage(_ image: UIImage) -> UIImage {
        // Resize large images to a reasonable size for icons (max 512x512)
        let maxDimension: CGFloat = 512
        let size = image.size
        
        // Only resize if image is larger than max dimension
        guard size.width > maxDimension || size.height > maxDimension else {
            return image
        }
        
        let aspectRatio = size.width / size.height
        let newSize: CGSize
        
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        // Resize image efficiently
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    
    // Async initializer for better performance with optimized image processing
    static func createAsync(title: String, image: UIImage, audioData: Data? = nil, isQuickAccess: Bool = false) async -> SpeakingIcon {
        return await Task.detached(priority: .userInitiated) {
            // Optimize image before compression (resize if needed)
            let optimizedImage = optimizeImage(image)
            
            // Create icon with optimized image (compression happens in init, but on background thread)
            return SpeakingIcon(title: title, image: optimizedImage, audioData: audioData, isQuickAccess: isQuickAccess)
        }.value
    }
    
    
    static let sample = SpeakingIcon(title: "Hello", image: UIImage(systemName: "person.wave.2.fill")?.withTintColor(.blue) ?? UIImage())
}

struct IconView: View {
    let icon: SpeakingIcon
    let onTap: () -> Void
    let onEdit: () -> Void
    @State private var isShowingDeleteConfirmation = false
    var onDelete: (() -> Void)?
    var onMove: (() -> Void)?
    var onToggleQuickAccess: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 8) {
            Image(uiImage: icon.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 15))
                .drawingGroup() // Optimize rendering performance
            
            Text(icon.title)
                .font(.callout)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 40)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 4) {
                        if icon.isQuickAccess {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.system(size: 16))
                        }
                        if icon.hasCustomAudio {
                            Image(systemName: "speaker.wave.2.fill")
                                .foregroundStyle(.blue)
                                .font(.system(size: 16))
                        }
                    }
                    .offset(x: -8, y: -8)
                }
        }
        .frame(maxWidth: .infinity)
        .padding(13) // Increased by 10% from 12
        .background(Color.gray.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .shadow(radius: 3)
        .contextMenu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            
            if onToggleQuickAccess != nil {
                Button(action: onToggleQuickAccess!) {
                    Label(
                        icon.isQuickAccess ? "Remove from Quick Access" : "Add to Quick Access",
                        systemImage: icon.isQuickAccess ? "star.slash" : "star.fill"
                    )
                }
            }
            
            if onMove != nil {
                Button(action: onMove!) {
                    Label("Move to Folder", systemImage: "folder")
                }
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
