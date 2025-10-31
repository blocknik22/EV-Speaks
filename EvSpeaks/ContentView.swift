//
//  ContentView.swift
//  Ev Speaks
//
//  Created by Nik on 5/27/25.
//

import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Data Models

struct Folder: Identifiable, Codable {
    let id = UUID()
    var name: String
    var icons: [SpeakingIcon]
    var isDefault: Bool = false
    private var folderImageData: Data?
    
    var folderImage: UIImage? {
        if let data = folderImageData {
            return UIImage(data: data)
        }
        return nil
    }
    
    init(name: String, icons: [SpeakingIcon] = [], isDefault: Bool = false, folderImage: UIImage? = nil) {
        self.name = name
        self.icons = icons
        self.isDefault = isDefault
        self.folderImageData = folderImage?.jpegData(compressionQuality: 0.8)
    }
    
    mutating func setFolderImage(_ image: UIImage?) {
        self.folderImageData = image?.jpegData(compressionQuality: 0.8)
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            IconsView()
                .tabItem {
                    Label("Icons", systemImage: "square.grid.2x2")
                }
            
            StudentInfoView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
        }
    }
}

struct IconsView: View {
    @State private var folders: [Folder] = []
    @State private var selectedFolder: Folder?
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var originalImage: UIImage? // Store original image for rotation
    @State private var imageRotationAngle: CGFloat = 0 // Track rotation angle
    @State private var selectedFolderItem: PhotosPickerItem?
    @State private var selectedFolderImage: UIImage?
    @State private var newIconTitle: String = ""
    @State private var newFolderName: String = ""
    @State private var isShowingAddIcon = false
    @State private var isShowingEditIcon = false
    @State private var isShowingAddFolder = false
    @State private var isShowingEditFolder = false
    @State private var isShowingMoveToFolder = false
    @State private var editingIcon: SpeakingIcon?
    @State private var editingIconIndex: Int?
    @State private var editingFolder: Folder?
    @State private var movingIcon: SpeakingIcon?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentPage = 0
    @State private var quickAccessPage = 0
    @State private var isLoading = false
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    private let synthesizer = AVSpeechSynthesizer()
    
    private let iconsPerPage = 6
    private let quickAccessIconsPerPage = 4 // Quick Access shows 4 icons at a time (2x2 grid)
    private let screenWidth = UIScreen.main.bounds.width
    private let screenHeight = UIScreen.main.bounds.height
    private let gridSpacing: CGFloat = max(10, 40) // Minimum 10dp spacing between grid items (currently 16dp)
    
    private var iconSize: CGFloat {
        // Calculate size to fit 2x3 grid with padding
        let padding: CGFloat = 16 // Increased by ~30% from 12
        let horizontalCount: CGFloat = 2
        let verticalCount: CGFloat = 3
        let availableWidth = screenWidth - (padding * (horizontalCount + 1))
        let availableHeight = (screenHeight * 0.7) - (padding * (verticalCount + 1)) // Use 70% of screen height
        
        // Use the smaller of width-based or height-based size to ensure icons fit
        let widthBasedSize = availableWidth / horizontalCount
        let heightBasedSize = availableHeight / verticalCount
        return min(widthBasedSize, heightBasedSize)
    }
    
    private var currentIcons: [SpeakingIcon] {
        selectedFolder?.icons ?? []
    }
    
    private var quickAccessIcons: [SpeakingIcon] {
        folders.flatMap { $0.icons }.filter { $0.isQuickAccess }
    }
    
    private var totalPages: Int {
        (currentIcons.count + iconsPerPage - 1) / iconsPerPage
    }
    
    private var paginatedIcons: [SpeakingIcon] {
        let startIndex = currentPage * iconsPerPage
        let endIndex = min(startIndex + iconsPerPage, currentIcons.count)
        return Array(currentIcons[startIndex..<endIndex])
    }
    
    private var quickAccessPages: Int {
        (quickAccessIcons.count + quickAccessIconsPerPage - 1) / quickAccessIconsPerPage
    }
    
    private var paginatedQuickAccessIcons: [SpeakingIcon] {
        let startIndex = quickAccessPage * quickAccessIconsPerPage
        let endIndex = min(startIndex + quickAccessIconsPerPage, quickAccessIcons.count)
        return Array(quickAccessIcons[startIndex..<endIndex])
    }
    
    private func quickAccessIconsForPage(_ page: Int) -> [SpeakingIcon] {
        let startIndex = page * quickAccessIconsPerPage
        let endIndex = min(startIndex + quickAccessIconsPerPage, quickAccessIcons.count)
        guard startIndex < quickAccessIcons.count else { return [] }
        return Array(quickAccessIcons[startIndex..<endIndex])
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if folders.isEmpty {
                    ContentUnavailableView(
                        "No Icons",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap the + button to add your first icon")
                    )
                } else if selectedFolder == nil {
                    // Show home page with two panels
                    homePageView
                } else {
                    // Show icons in selected folder
                    iconsGridView
                }
            }
            .navigationTitle("EVSpeaks")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if selectedFolder != nil {
                        Button("Back") {
                            selectedFolder = nil
                            currentPage = 0
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button(action: {
                            isShowingAddIcon = true
                        }) {
                            Label("Add Icon", systemImage: "plus")
                        }
                        
                        Button(action: {
                            isShowingAddFolder = true
                        }) {
                            Label("Add Folder", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddIcon) {
                addIconView(isEditing: false)
            }
            .sheet(isPresented: $isShowingEditIcon) {
                if let icon = editingIcon {
                    addIconView(isEditing: true, editingIcon: icon)
                }
            }
            .sheet(isPresented: $isShowingAddFolder) {
                addFolderView
            }
            .sheet(isPresented: $isShowingEditFolder) {
                editFolderView
            }
            .sheet(isPresented: $isShowingMoveToFolder) {
                moveToFolderView
            }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
            }
            .task {
                await loadDataAsync()
            }
        }
    }
    
    private var folderListView: some View {
        List {
            ForEach(folders) { folder in
                Button(action: {
                    selectedFolder = folder
                    currentPage = 0
                }) {
                    HStack {
                        // Show custom folder image or default icon
                        if let folderImage = folder.folderImage {
                            Image(uiImage: folderImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
                                .frame(width: 50, height: 50)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(folder.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("\(folder.icons.count) icon\(folder.icons.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .id(folder.id) // Ensure proper view identity for performance
                .contextMenu {
                    Button(action: {
                        editingFolder = folder
                        selectedFolderImage = folder.folderImage
                        isShowingEditFolder = true
                    }) {
                        Label("Edit Folder", systemImage: "pencil")
                    }
                    
                    Button(action: {
                        Task {
                            await deleteFolderAsync(folder)
                        }
                    }) {
                        Label("Delete Folder", systemImage: "trash")
                    }
                    .disabled(folder.isDefault)
                }
            }
        }
    }
    
    private var homePageView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Quick Access Panel - Limited to half screen height
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Quick Access", systemImage: "star.fill")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 30) // Bring down title by 30 dp
                    
                    if quickAccessIcons.isEmpty {
                        ContentUnavailableView(
                            "No Quick Access Icons",
                            systemImage: "star",
                            description: Text("Add icons to Quick Access from any folder")
                        )
                        .frame(height: screenHeight * 0.25 - 80) // Reduced by 40 dp top and bottom
                    } else {
                        // Horizontal scrollable view showing 4 icons at a time (2x2 grid)
                        ScrollView(.horizontal, showsIndicators: true) {
                            HStack(spacing: 0) {
                                ForEach(0..<quickAccessPages, id: \.self) { page in
                                    LazyVGrid(columns: [
                                        GridItem(.flexible(), spacing: gridSpacing),
                                        GridItem(.flexible(), spacing: gridSpacing)
                                    ], spacing: gridSpacing) {
                                        ForEach(quickAccessIconsForPage(page)) { icon in
                                            IconView(
                                                icon: icon,
                                                onTap: {
                                                    playIconAudio(icon)
                                                },
                                                onEdit: {
                                                    editIcon(icon)
                                                },
                                                onDelete: {
                                                    Task {
                                                        await deleteIconAsync(icon)
                                                    }
                                                },
                                                onMove: {
                                                    movingIcon = icon
                                                    isShowingMoveToFolder = true
                                                },
                                                onToggleQuickAccess: {
                                                    Task {
                                                        await toggleQuickAccessAsync(icon)
                                                    }
                                                }
                                            )
                                            .frame(width: iconSize, height: iconSize * 0.8)
                                            .id(icon.id)
                                        }
                                    }
                                    .padding(16)
                                    .frame(width: screenWidth - 32)
                                }
                            }
                        }
                        .frame(height: screenHeight * 0.5 - 80) // Reduced by 40 dp top and bottom
                    }
                }
                .padding(.top, -24) // Reduced top padding by 40 dp (from 16 to -24)
                .padding(.bottom, -24) // Reduced bottom padding by 40 dp (from 16 to -24)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .frame(maxHeight: screenHeight * 0.5 - 80) // Reduced by 40 dp top and bottom
                
                // Folders Panel
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("All Folders", systemImage: "folder.fill")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Spacer()
                        EditButton()
                            .font(.subheadline)
                    }
                    .padding(.horizontal, 16)
                    
                    List {
                        ForEach(folders) { folder in
                            Button(action: {
                                selectedFolder = folder
                                currentPage = 0
                            }) {
                                HStack {
                                    // Show custom folder image or default icon
                                    if let folderImage = folder.folderImage {
                                        Image(uiImage: folderImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Image(systemName: "folder.fill")
                                            .foregroundColor(.blue)
                                            .font(.title2)
                                            .frame(width: 50, height: 50)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(folder.name)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text("\(folder.icons.count) icon\(folder.icons.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .id(folder.id)
                            .contextMenu {
                                Button(action: {
                                    editingFolder = folder
                                    selectedFolderImage = folder.folderImage
                                    isShowingEditFolder = true
                                }) {
                                    Label("Edit Folder", systemImage: "pencil")
                                }
                                
                                Button(action: {
                                    Task {
                                        await deleteFolderAsync(folder)
                                    }
                                }) {
                                    Label("Delete Folder", systemImage: "trash")
                                }
                                .disabled(folder.isDefault)
                            }
                        }
                        .onMove(perform: moveFolders)
                    }
                    .listStyle(PlainListStyle())
                    .scrollContentBackground(.hidden)
                    .frame(height: CGFloat(folders.count * 70) + 20) // Dynamic height based on folder count
                }
                .padding(.vertical, 16)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 8)
        }
    }
    
    private var iconsGridView: some View {
        VStack {
            if currentIcons.isEmpty {
                ContentUnavailableView(
                    "No Icons in \(selectedFolder?.name ?? "Folder")",
                    systemImage: "square.grid.2x2",
                    description: Text("Tap the + button to add your first icon to this folder")
                )
            } else {
                TabView(selection: $currentPage) {
                    ForEach(0..<totalPages, id: \.self) { page in
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: gridSpacing), // Minimum 10dp spacing between grid columns
                            GridItem(.flexible(), spacing: gridSpacing)  // Minimum 10dp spacing between grid columns
                        ], spacing: gridSpacing) { // Minimum 10dp spacing between grid rows
                            ForEach(paginatedIcons) { icon in
                                IconView(
                                    icon: icon,
                                    onTap: {
                                        playIconAudio(icon)
                                    },
                                    onEdit: {
                                        editIcon(icon)
                                    },
                                    onDelete: {
                                        Task {
                                            await deleteIconAsync(icon)
                                        }
                                    },
                                    onMove: {
                                        movingIcon = icon
                                        isShowingMoveToFolder = true
                                    },
                                    onToggleQuickAccess: {
                                        Task {
                                            await toggleQuickAccessAsync(icon)
                                        }
                                    }
                                )
                                .frame(width: iconSize, height: iconSize * 0.8)
                                .id(icon.id) // Ensure proper view identity for performance
                            }
                        }
                        .padding(16) // Increased by ~30% from 12
                        .tag(page)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
    }
    
    private var addFolderView: some View {
        NavigationStack {
            Form {
                Section(header: Text("Folder Details")) {
                    TextField("Folder Name", text: $newFolderName)
                    
                    if let image = selectedFolderImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                    }
                    
                    PhotosPicker(
                        selection: $selectedFolderItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text(selectedFolderImage == nil ? "Choose Folder Image" : "Change Folder Image")
                        }
                    }
                }
            }
            .navigationTitle("Add New Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingAddFolder = false
                        newFolderName = ""
                        selectedFolderImage = nil
                        selectedFolderItem = nil
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !newFolderName.isEmpty {
                            Task {
                                await addFolderAsync(newFolderName, folderImage: selectedFolderImage)
                                newFolderName = ""
                                selectedFolderImage = nil
                                selectedFolderItem = nil
                                isShowingAddFolder = false
                            }
                        }
                    }
                    .disabled(newFolderName.isEmpty)
                }
            }
            .onChange(of: selectedFolderItem) { newItem in
                Task {
                    await loadFolderImageAsync(newItem)
                }
            }
        }
    }
    
    private var editFolderView: some View {
        NavigationStack {
            Form {
                Section(header: Text("Folder Details")) {
                    TextField("Folder Name", text: $newFolderName)
                    
                    if let image = selectedFolderImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                    }
                    
                    PhotosPicker(
                        selection: $selectedFolderItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text(selectedFolderImage == nil ? "Choose Folder Image" : "Change Folder Image")
                        }
                    }
                }
            }
            .navigationTitle("Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingEditFolder = false
                        editingFolder = nil
                        newFolderName = ""
                        selectedFolderImage = nil
                        selectedFolderItem = nil
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if !newFolderName.isEmpty, let folder = editingFolder {
                            Task {
                                await updateFolderAsync(folder, newName: newFolderName, newImage: selectedFolderImage)
                                newFolderName = ""
                                selectedFolderImage = nil
                                selectedFolderItem = nil
                                editingFolder = nil
                                isShowingEditFolder = false
                            }
                        }
                    }
                    .disabled(newFolderName.isEmpty)
                }
            }
            .onAppear {
                if let folder = editingFolder {
                    newFolderName = folder.name
                    selectedFolderImage = folder.folderImage
                }
            }
            .onChange(of: selectedFolderItem) { newItem in
                Task {
                    await loadFolderImageAsync(newItem)
                }
            }
        }
    }
    
    private var moveToFolderView: some View {
        NavigationStack {
            List {
                ForEach(folders.filter { $0.id != selectedFolder?.id }) { folder in
                    Button(action: {
                        if let icon = movingIcon {
                            Task {
                                await moveIconToFolderAsync(icon, destinationFolder: folder)
                                isShowingMoveToFolder = false
                                movingIcon = nil
                            }
                        }
                    }) {
                        HStack {
                            // Show custom folder image or default icon
                            if let folderImage = folder.folderImage {
                                Image(uiImage: folderImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                                    .frame(width: 40, height: 40)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(folder.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("\(folder.icons.count) icon\(folder.icons.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Move to Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isShowingMoveToFolder = false
                        movingIcon = nil
                    }
                }
            }
        }
    }
    
    private func addIconView(isEditing: Bool, editingIcon: SpeakingIcon? = nil) -> some View {
        NavigationStack {
            Form {
                Section(header: Text("Icon Details")) {
                    TextField("Icon Title", text: $newIconTitle)
                    
                    if let image = selectedImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                        
                        // Rotation controls
                        HStack(spacing: 20) {
                            Button(action: {
                                rotateImageClockwise()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Rotate Clockwise")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            
                            Button(action: {
                                rotateImageCounterClockwise()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Rotate Counter-Clockwise")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    
                    PhotosPicker(
                        selection: $selectedItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text(isEditing ? "Change Image" : "Choose Image")
                        }
                    }
                }
                
                Section(header: Text("Audio")) {
                    HStack {
                        if audioRecorder.isRecording {
                            Button(action: {
                                print("Stopping recording")
                                audioRecorder.stopRecording()
                            }) {
                                Label("Stop Recording", systemImage: "stop.circle.fill")
                                    .foregroundColor(.red)
                            }
                        } else {
                            Button(action: {
                                print("Starting recording")
                                audioRecorder.startRecording()
                            }) {
                                Label("Record Audio", systemImage: "record.circle")
                            }
                        }
                        
                        if let audioData = audioRecorder.audioData {
                            Button(action: {
                                print("Playing test recording")
                                audioRecorder.playRecording()
                            }) {
                                Label("Play Recording", systemImage: "play.circle.fill")
                            }
                            
                            Text("(\(audioData.count) bytes)")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Icon" : "Add New Icon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if isEditing {
                            isShowingEditIcon = false
                        } else {
                            isShowingAddIcon = false
                        }
                        resetForm()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        if let image = selectedImage {
                            Task {
                                await saveIconAsync(image: image, isEditing: isEditing)
                                resetForm()
                                if isEditing {
                                    isShowingEditIcon = false
                                } else {
                                    isShowingAddIcon = false
                                }
                            }
                        }
                    }
                    .disabled(selectedImage == nil)
                }
            }
            .onAppear {
                if isEditing, let icon = editingIcon {
                    newIconTitle = icon.title
                    let iconImage = icon.image
                    originalImage = iconImage // Store original for rotation
                    selectedImage = iconImage
                    imageRotationAngle = 0 // Reset rotation when editing starts
                    if let audioData = icon.getAudioData() {
                        audioRecorder.audioData = audioData
                    }
                }
            }
            .onChange(of: selectedItem) { newItem in
                Task {
                    await loadImageAsync(newItem)
                }
            }
        }
    }
    
    private func editIcon(_ icon: SpeakingIcon) {
        editingIcon = icon
        if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }),
           let iconIndex = folders[folderIndex].icons.firstIndex(where: { $0.id == icon.id }) {
            editingIconIndex = iconIndex
        }
        isShowingEditIcon = true
    }
    
    private func resetForm() {
        newIconTitle = ""
        selectedItem = nil
        selectedImage = nil
        originalImage = nil
        imageRotationAngle = 0
        audioRecorder.audioData = nil
        editingIcon = nil
        editingIconIndex = nil
    }
    
    private func rotateImageClockwise() {
        imageRotationAngle += 90
        if let original = originalImage {
            selectedImage = rotateUIImage(original, by: imageRotationAngle)
        }
    }
    
    private func rotateImageCounterClockwise() {
        imageRotationAngle -= 90
        if let original = originalImage {
            selectedImage = rotateUIImage(original, by: imageRotationAngle)
        }
    }
    
    private func rotateUIImage(_ image: UIImage, by degrees: CGFloat) -> UIImage {
        // Normalize angle to 0-360 range
        let normalizedAngle = degrees.truncatingRemainder(dividingBy: 360)
        let radians = normalizedAngle * .pi / 180
        
        // Calculate new size
        let size = image.size
        let rotatedRect = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: radians))
        let newSize = CGSize(
            width: abs(rotatedRect.width),
            height: abs(rotatedRect.height)
        )
        
        // Create graphics context
        UIGraphicsBeginImageContextWithOptions(newSize, false, image.scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return image
        }
        
        // Move to center
        context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
        // Rotate
        context.rotate(by: radians)
        // Draw image
        context.translateBy(x: -size.width / 2, y: -size.height / 2)
        image.draw(in: CGRect(origin: .zero, size: size))
        
        let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return rotatedImage ?? image
    }
    
    private func playIconAudio(_ icon: SpeakingIcon) {
        if let audioData = icon.getAudioData() {
            print("Playing custom audio")
            audioPlayer.playAudio(data: audioData)
        } else {
            print("Using text-to-speech")
            speak(text: icon.title)
        }
    }
    
    private func speak(text: String) {
        Task.detached(priority: .userInitiated) {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.5
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            
            synthesizer.speak(utterance)
        }
    }
    
    private func deleteIcon(_ icon: SpeakingIcon) {
        if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }),
           let iconIndex = folders[folderIndex].icons.firstIndex(where: { $0.id == icon.id }) {
            folders[folderIndex].icons.remove(at: iconIndex)
            saveFolders()
        }
    }
    
    private func loadDataAsync() async {
        await MainActor.run {
            isLoading = true
        }
        
        // Load data on background thread
        let (loadedFolders, loadedIcons) = await Task.detached(priority: .userInitiated) {
            let folders = loadFolders()
            let icons = loadIcons()
            return (folders, icons)
        }.value
        
        await MainActor.run {
            folders = loadedFolders
            // Migrate old icons to folder structure if needed
            if !loadedIcons.isEmpty && folders.isEmpty {
                let defaultFolder = Folder(name: "My Icons", icons: loadedIcons, isDefault: true)
                folders.append(defaultFolder)
            }
            isLoading = false
        }
    }
    
    private func saveFolders() {
        Task.detached(priority: .utility) {
            if let encoded = try? JSONEncoder().encode(folders) {
                UserDefaults.standard.set(encoded, forKey: "SavedFolders")
                print("Successfully saved \(folders.count) folders")
            }
        }
    }
    
    private func loadFolders() -> [Folder] {
        if let data = UserDefaults.standard.data(forKey: "SavedFolders"),
           let decoded = try? JSONDecoder().decode([Folder].self, from: data) {
            print("Successfully loaded \(decoded.count) folders")
            return decoded
        }
        print("No saved folders found")
        return []
    }
    
    private func loadIcons() -> [SpeakingIcon] {
        if let data = UserDefaults.standard.data(forKey: "SavedIcons"),
           let decoded = try? JSONDecoder().decode([SpeakingIcon].self, from: data) {
            print("Successfully loaded \(decoded.count) icons")
            return decoded
        }
        print("No saved icons found")
        return []
    }
    
    private func moveIconToFolder(_ icon: SpeakingIcon, destinationFolder: Folder) {
        if let sourceFolderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }),
           let iconIndex = folders[sourceFolderIndex].icons.firstIndex(where: { $0.id == icon.id }),
           let destFolderIndex = folders.firstIndex(where: { $0.id == destinationFolder.id }) {
            let movedIcon = folders[sourceFolderIndex].icons.remove(at: iconIndex)
            folders[destFolderIndex].icons.append(movedIcon)
            saveFolders()
        }
    }
    
    private func deleteFolder(_ folder: Folder) {
        if folder.isDefault {
            errorMessage = "Cannot delete default folder."
            showError = true
            return
        }
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders.remove(at: index)
            saveFolders()
        }
    }
    
    private func deleteFolderAsync(_ folder: Folder) async {
        if folder.isDefault {
            await MainActor.run {
                errorMessage = "Cannot delete default folder."
                showError = true
            }
            return
        }
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            await MainActor.run {
                folders.remove(at: index)
                saveFolders()
            }
        }
    }
    
    private func deleteIconAsync(_ icon: SpeakingIcon) async {
        // Find the icon in all folders (works from both folder view and Quick Access)
        var foundFolderIndex: Int?
        var foundIconIndex: Int?
        
        for folderIndex in folders.indices {
            if let iconIndex = folders[folderIndex].icons.firstIndex(where: { $0.id == icon.id }) {
                foundFolderIndex = folderIndex
                foundIconIndex = iconIndex
                break
            }
        }
        
        if let folderIndex = foundFolderIndex, let iconIndex = foundIconIndex {
            await MainActor.run {
                // Remove icon immediately by creating updated folder
                var updatedFolder = folders[folderIndex]
                updatedFolder.icons.remove(at: iconIndex)
                folders[folderIndex] = updatedFolder
                
                // Refresh selectedFolder to trigger view update if deleting from selected folder
                if let currentSelectedFolder = selectedFolder, folders[folderIndex].id == currentSelectedFolder.id {
                    self.selectedFolder = updatedFolder
                    // Adjust page if we deleted the last icon on the current page
                    let iconCount = updatedFolder.icons.count
                    let newTotalPages = (iconCount + iconsPerPage - 1) / iconsPerPage
                    if newTotalPages > 0 && currentPage >= newTotalPages {
                        currentPage = max(0, newTotalPages - 1)
                    }
                }
                
                // Save in background without blocking UI
                saveFolders()
            }
        }
    }
    
    private func moveFolders(from source: IndexSet, to destination: Int) {
        folders.move(fromOffsets: source, toOffset: destination)
        saveFolders()
        
        // Update selectedFolder if it was moved
        if let currentSelectedFolder = selectedFolder,
           let newIndex = folders.firstIndex(where: { $0.id == currentSelectedFolder.id }) {
            selectedFolder = folders[newIndex]
        }
    }
    
    private func addFolderAsync(_ name: String, folderImage: UIImage? = nil) async {
        let newFolder = Folder(name: name, folderImage: folderImage)
        await MainActor.run {
            folders.append(newFolder)
            saveFolders()
        }
    }
    
    private func updateFolderAsync(_ folder: Folder, newName: String, newImage: UIImage?) async {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            await MainActor.run {
                folders[index].name = newName
                folders[index].setFolderImage(newImage)
                saveFolders()
            }
        }
    }
    
    private func loadFolderImageAsync(_ item: PhotosPickerItem?) async {
        do {
            if let data = try await item?.loadTransferable(type: Data.self) {
                // Process image on background thread
                let processedImage = await Task.detached(priority: .userInitiated) {
                    return UIImage(data: data)
                }.value
                
                if let image = processedImage {
                    await MainActor.run {
                        selectedFolderImage = image
                        print("Successfully loaded folder image from photo library")
                    }
                } else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create image from data"])
                }
            }
        } catch {
            print("Error loading folder image: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load folder image: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func moveIconToFolderAsync(_ icon: SpeakingIcon, destinationFolder: Folder) async {
        if let sourceFolderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }),
           let iconIndex = folders[sourceFolderIndex].icons.firstIndex(where: { $0.id == icon.id }),
           let destFolderIndex = folders.firstIndex(where: { $0.id == destinationFolder.id }) {
            await MainActor.run {
                let movedIcon = folders[sourceFolderIndex].icons.remove(at: iconIndex)
                folders[destFolderIndex].icons.append(movedIcon)
                
                // Refresh selectedFolder to trigger view update
                if let currentSelectedFolder = selectedFolder, folders[sourceFolderIndex].id == currentSelectedFolder.id {
                    self.selectedFolder = folders[sourceFolderIndex]
                    // Adjust page if we moved the last icon on the current page
                    let iconCount = folders[sourceFolderIndex].icons.count
                    let newTotalPages = (iconCount + iconsPerPage - 1) / iconsPerPage
                    if newTotalPages > 0 && currentPage >= newTotalPages {
                        currentPage = max(0, newTotalPages - 1)
                    }
                }
                
                saveFolders()
            }
        }
    }
    
    private func toggleQuickAccessAsync(_ icon: SpeakingIcon) async {
        // Find the icon in all folders and toggle its quick access status
        for folderIndex in folders.indices {
            if let iconIndex = folders[folderIndex].icons.firstIndex(where: { $0.id == icon.id }) {
                await MainActor.run {
                    folders[folderIndex].icons[iconIndex].isQuickAccess.toggle()
                    
                    // Refresh selectedFolder to trigger view update if toggling from selected folder
                    if let currentSelectedFolder = selectedFolder, folders[folderIndex].id == currentSelectedFolder.id {
                        self.selectedFolder = folders[folderIndex]
                    }
                    
                    saveFolders()
                }
                break
            }
        }
    }
    
    private func loadImageAsync(_ item: PhotosPickerItem?) async {
        do {
            if let data = try await item?.loadTransferable(type: Data.self) {
                // Process image on background thread
                let processedImage = await Task.detached(priority: .userInitiated) {
                    return UIImage(data: data)
                }.value
                
                if let image = processedImage {
                    await MainActor.run {
                        originalImage = image // Store original for rotation
                        selectedImage = image
                        imageRotationAngle = 0 // Reset rotation when new image is loaded
                        print("Successfully loaded image from photo library")
                    }
                } else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not create image from data"])
                }
            }
        } catch {
            print("Error loading image: \(error)")
            await MainActor.run {
                errorMessage = "Failed to load image: \(error.localizedDescription)"
                showError = true
            }
        }
    }
    
    private func saveIconAsync(image: UIImage, isEditing: Bool) async {
        // Create icon on background thread first
        let newIcon = await SpeakingIcon.createAsync(
            title: newIconTitle.isEmpty ? "Untitled" : newIconTitle,
            image: image,
            audioData: audioRecorder.audioData
        )
        
        // Update UI immediately on main thread
        await MainActor.run {
            if isEditing, let index = editingIconIndex {
                // Update existing icon in current folder
                if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }) {
                    var updatedFolder = folders[folderIndex]
                    updatedFolder.icons[index] = newIcon
                    folders[folderIndex] = updatedFolder
                    // Refresh selectedFolder to trigger view update
                    selectedFolder = updatedFolder
                }
            } else {
                // Add new icon to current folder or create default folder
                if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }) {
                    var updatedFolder = folders[folderIndex]
                    updatedFolder.icons.append(newIcon)
                    folders[folderIndex] = updatedFolder
                    // Refresh selectedFolder to trigger view update immediately
                    selectedFolder = updatedFolder
                    // Calculate new total pages and navigate to last page to show the newly added icon
                    let iconCount = updatedFolder.icons.count
                    let newTotalPages = (iconCount + iconsPerPage - 1) / iconsPerPage
                    currentPage = max(0, newTotalPages - 1)
                } else if !folders.isEmpty {
                    // Add to first folder if no folder is selected
                    var updatedFolder = folders[0]
                    updatedFolder.icons.append(newIcon)
                    folders[0] = updatedFolder
                } else {
                    // Create default folder if no folders exist
                    let defaultFolder = Folder(name: "My Icons", icons: [newIcon], isDefault: true)
                    folders.append(defaultFolder)
                }
            }
            
            // Save in background without blocking UI
            saveFolders()
        }
    }
    
    init() {
        // The init function is now primarily for initial loading and migration.
        // Data loading and saving are handled by async functions.
    }
}

#Preview {
    ContentView()
}

