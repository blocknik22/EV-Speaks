import SwiftUI

struct StudentInfo: Codable {
    var studentName: String
    var studentAddress: String
    var parentName: String
    var parentPhone: String
    var parentEmail: String
    
    static let empty = StudentInfo(
        studentName: "",
        studentAddress: "",
        parentName: "",
        parentPhone: "",
        parentEmail: ""
    )
}

struct StudentInfoView: View {
    @AppStorage("studentInfo") private var studentInfoData: Data?
    @State private var studentInfo: StudentInfo = .empty
    @State private var showingSaveAlert = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Student Information")) {
                    TextField("Student Name", text: $studentInfo.studentName)
                    TextField("Address", text: $studentInfo.studentAddress)
                }
                
                Section(header: Text("Parent Information")) {
                    TextField("Parent Name", text: $studentInfo.parentName)
                    TextField("Phone Number", text: $studentInfo.parentPhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $studentInfo.parentEmail)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("Student Profile")
            .toolbar {
                Button("Save") {
                    saveStudentInfo()
                    showingSaveAlert = true
                }
            }
            .alert("Success", isPresented: $showingSaveAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Student information saved successfully")
            }
            .onAppear {
                loadStudentInfo()
            }
        }
    }
    
    private func saveStudentInfo() {
        if let encoded = try? JSONEncoder().encode(studentInfo) {
            studentInfoData = encoded
        }
    }
    
    private func loadStudentInfo() {
        if let data = studentInfoData,
           let decoded = try? JSONDecoder().decode(StudentInfo.self, from: data) {
            studentInfo = decoded
        }
    }
} 