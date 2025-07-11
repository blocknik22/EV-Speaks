//
//  ContentView.swift
//  Ev Speaks
//
//  Created by Nik on 5/27/25.
//

import SwiftUI
import AVFoundation
import PhotosUI

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
    @State private var icons: [SpeakingIcon] = []
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var newIconTitle: String = ""
    @State private var isShowingAddIcon = false
    @State private var isShowingEditIcon = false
    @State private var editingIcon: SpeakingIcon?
    @State private var editingIconIndex: Int?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var currentPage = 0
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
    
    private var totalPages: Int {
        (icons.count + iconsPerPage - 1) / iconsPerPage
    }
    
    private var paginatedIcons: [SpeakingIcon] {
        let startIndex = currentPage * iconsPerPage
        let endIndex = min(startIndex + iconsPerPage, icons.count)
        return Array(icons[startIndex..<endIndex])
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if icons.isEmpty {
                    ContentUnavailableView(
                        "No Icons",
                        systemImage: "square.grid.2x2",
                        description: Text("Tap the + button to add your first icon")
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
                                        deleteIcon(icon)
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
            .navigationTitle("EVSpeaks")
            .toolbar {
                Button(action: {
                    isShowingAddIcon = true
                }) {
                    Image(systemName: "plus")
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
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
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
                            if isEditing, let index = editingIconIndex {
                                icons[index] = SpeakingIcon(
                                    title: newIconTitle.isEmpty ? "Untitled" : newIconTitle,
                                    image: image,
                                    audioData: audioRecorder.audioData
                                )
                            } else {
                                icons.append(SpeakingIcon(
                                    title: newIconTitle.isEmpty ? "Untitled" : newIconTitle,
                                    image: image,
                                    audioData: audioRecorder.audioData
                                ))
                            }
                            saveIcons()
                            resetForm()
                            if isEditing {
                                isShowingEditIcon = false
                            } else {
                                isShowingAddIcon = false
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
                    do {
                        if let data = try await newItem?.loadTransferable(type: Data.self) {
                            if let image = UIImage(data: data) {
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
            }
        }
    }
    
    private func editIcon(_ icon: SpeakingIcon) {
        editingIcon = icon
        editingIconIndex = icons.firstIndex(where: { $0.id == icon.id })
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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        
        synthesizer.speak(utterance)
    }
    
    private func deleteIcon(_ icon: SpeakingIcon) {
        if let index = icons.firstIndex(where: { $0.id == icon.id }) {
            icons.remove(at: index)
            saveIcons()
        }
    }
    
    private func saveIcons() {
        if let encoded = try? JSONEncoder().encode(icons) {
            UserDefaults.standard.set(encoded, forKey: "SavedIcons")
            print("Successfully saved \(icons.count) icons")
        }
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
    
    init() {
        _icons = State(initialValue: loadIcons())
    }
}

#Preview {
    ContentView()
}

