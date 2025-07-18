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
    var imageData: Data? = nil // Add image data for folder image
    
    init(name: String, icons: [SpeakingIcon] = [], isDefault: Bool = false, imageData: Data? = nil) {
        self.name = name
        self.icons = icons
        self.isDefault = isDefault
        self.imageData = imageData
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
    @State private var newIconTitle: String = ""
    @State private var newFolderName: String = ""
    @State private var newFolderImage: UIImage? = nil // For folder image
    @State private var newFolderImageItem: PhotosPickerItem? = nil // For folder image picker
    @State private var isShowingAddIcon = false
    @State private var isShowingEditIcon = false
    @State private var isShowingAddFolder = false
    @State private var isShowingMoveToFolder = false
    @State private var editingIcon: SpeakingIcon?
    @State private var editingIconIndex: Int?
    @State private var movingIcon: SpeakingIcon?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentPage = 0
    @State private var isLoading = false
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    private let synthesizer = AVSpeechSynthesizer()
    
    private let iconsPerPage = 6
    private let screenWidth = UIScreen.main.bounds.width
    private let screenHeight = UIScreen.main.bounds.height
    
    private var iconSize: CGFloat {
        // Calculate size to fit 2x3 grid with padding
        let padding: CGFloat = 12
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
    
    private var totalPages: Int {
        (currentIcons.count + iconsPerPage - 1) / iconsPerPage
    }
    
    private var paginatedIcons: [SpeakingIcon] {
        let startIndex = currentPage * iconsPerPage
        let endIndex = min(startIndex + iconsPerPage, currentIcons.count)
        return Array(currentIcons[startIndex..<endIndex])
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
                    // Show folder list
                    folderListView
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
                        if let imageData = folder.imageData, let uiImage = UIImage(data: imageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 40, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                                .font(.title2)
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
                .contextMenu {
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
                            GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)
                        ], spacing: 12) {
                            ForEach(paginatedIcons) { icon in
                                IconView(icon: icon, onTap: {
                                    playIconAudio(icon)
                                }, onEdit: {
                                    editIcon(icon)
                                }, onDelete: {
                                    Task {
                                        await deleteIconAsync(icon)
                                    }
                                }, onMove: {
                                    movingIcon = icon
                                    isShowingMoveToFolder = true
                                })
                                .frame(width: iconSize, height: iconSize * 0.8)
                            }
                        }
                        .padding(12)
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
                    if let image = newFolderImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 120)
                    }
                    PhotosPicker(
                        selection: $newFolderImageItem,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.fill")
                            Text("Choose Folder Image")
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
                        newFolderImage = nil
                        newFolderImageItem = nil
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if !newFolderName.isEmpty {
                            Task {
                                await addFolderAsync(newFolderName, image: newFolderImage)
                                newFolderName = ""
                                newFolderImage = nil
                                newFolderImageItem = nil
                                isShowingAddFolder = false
                            }
                        }
                    }
                    .disabled(newFolderName.isEmpty)
                }
            }
            .onChange(of: newFolderImageItem) { newItem in
                Task {
                    await loadNewFolderImageAsync(newItem)
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
                            Image(systemName: "folder.fill")
                                .foregroundColor(.blue)
                            
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
                    selectedImage = icon.image
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
        audioRecorder.audioData = nil
        editingIcon = nil
        editingIconIndex = nil
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
        if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }),
           let iconIndex = folders[folderIndex].icons.firstIndex(where: { $0.id == icon.id }) {
            await MainActor.run {
                folders[folderIndex].icons.remove(at: iconIndex)
                saveFolders()
            }
        }
    }
    
    private func addFolderAsync(_ name: String, image: UIImage? = nil) async {
        let imageData = image?.jpegData(compressionQuality: 0.8)
        let newFolder = Folder(name: name, imageData: imageData)
        await MainActor.run {
            folders.append(newFolder)
            saveFolders()
        }
    }
    
    private func moveIconToFolderAsync(_ icon: SpeakingIcon, destinationFolder: Folder) async {
        if let sourceFolderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }),
           let iconIndex = folders[sourceFolderIndex].icons.firstIndex(where: { $0.id == icon.id }),
           let destFolderIndex = folders.firstIndex(where: { $0.id == destinationFolder.id }) {
            await MainActor.run {
                let movedIcon = folders[sourceFolderIndex].icons.remove(at: iconIndex)
                folders[destFolderIndex].icons.append(movedIcon)
                saveFolders()
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
                        selectedImage = image
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
        // Process icon creation on background thread
        let newIcon = await Task.detached(priority: .userInitiated) {
            return SpeakingIcon(
                title: newIconTitle.isEmpty ? "Untitled" : newIconTitle,
                image: image,
                audioData: audioRecorder.audioData
            )
        }.value
        
        await MainActor.run {
            if isEditing, let index = editingIconIndex {
                // Update existing icon in current folder
                if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }) {
                    folders[folderIndex].icons[index] = newIcon
                }
            } else {
                // Add new icon to current folder or create default folder
                if let folderIndex = folders.firstIndex(where: { $0.id == selectedFolder?.id }) {
                    folders[folderIndex].icons.append(newIcon)
                } else if !folders.isEmpty {
                    // Add to first folder if no folder is selected
                    folders[0].icons.append(newIcon)
                } else {
                    // Create default folder if no folders exist
                    let defaultFolder = Folder(name: "My Icons", icons: [newIcon], isDefault: true)
                    folders.append(defaultFolder)
                }
            }
            
            saveFolders()
        }
    }
    
    private func loadNewFolderImageAsync(_ item: PhotosPickerItem?) async {
        do {
            if let data = try await item?.loadTransferable(type: Data.self) {
                let processedImage = await Task.detached(priority: .userInitiated) {
                    return UIImage(data: data)
                }.value
                if let image = processedImage {
                    await MainActor.run {
                        newFolderImage = image
                    }
                }
            }
        } catch {
            print("Error loading folder image: \(error)")
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

