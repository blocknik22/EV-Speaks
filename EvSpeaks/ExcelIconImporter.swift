//
//  ExcelIconImporter.swift
//  Ev Speaks
//
//  Created for importing icons from Excel file
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import CoreXLSX

struct IconImportData {
    let iconName: String
    let folderName: String
    let s3Link: String
}

class ExcelIconImporter: ObservableObject {
    @Published var isImporting = false
    @Published var importProgress: Double = 0.0
    @Published var importStatus: String = ""
    @Published var createdIconCount: Int = 0
    
    func parseExcelFile(at url: URL) async throws -> [IconImportData] {
        // Read Excel file data
        let data = try Data(contentsOf: url)
        
        // Excel files (.xlsx) are ZIP archives
        // Extract and parse the shared strings and worksheet
        return try await parseExcelData(data)
    }
    
    func parseFoldersWorksheet(at url: URL) async throws -> [String] {
        // Read Excel file data
        let data = try Data(contentsOf: url)
        
        // Create temporary file for CoreXLSX
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let tempFile = tempDir.appendingPathComponent("workbook.xlsx")
        try data.write(to: tempFile)
        
        // Open Excel file using CoreXLSX
        guard let file = XLSXFile(filepath: tempFile.path) else {
            throw NSError(domain: "ExcelIconImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open Excel file"])
        }
        
        // Parse shared strings
        var sharedStrings: [String] = []
        if let sharedStringsFile = try? file.parseSharedStrings() {
            sharedStrings = sharedStringsFile.items.compactMap { $0.text }
        }
        
        // Get all worksheet paths
        guard let worksheetPaths = try? file.parseWorksheetPaths() else {
            throw NSError(domain: "ExcelIconImporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse workbook or find worksheets"])
        }
        
        // Try to find a worksheet that looks like a Folders worksheet
        // We'll check all worksheets and find one that doesn't have icon/s3link headers
        var folderNames: [String] = []
        
        for worksheetPath in worksheetPaths {
            guard let worksheet = try? file.parseWorksheet(at: worksheetPath) else {
                continue
            }
            
            let names = extractFolderNames(from: worksheet, sharedStrings: sharedStrings)
            if !names.isEmpty {
                folderNames = names
                break
            }
        }
        
        return folderNames
    }
    
    private func extractCellsFromRow(_ row: Row, sharedStrings: [String]) -> [String] {
        var cells: [String] = []
        
        // Extract cell values in order
        let sortedCells = (row.cells ?? []).sorted { cell1, cell2 in
            let ref1String = String(describing: cell1.reference)
            let ref2String = String(describing: cell2.reference)
            let col1 = String(ref1String.prefix(while: { $0.isLetter }))
            let col2 = String(ref2String.prefix(while: { $0.isLetter }))
            return col1 < col2
        }
        
        for cell in sortedCells {
            var cellValue = ""
            if let value = cell.value {
                if cell.type == .sharedString,
                   let stringIndex = Int(value), stringIndex < sharedStrings.count {
                    cellValue = sharedStrings[stringIndex]
                } else {
                    cellValue = value
                }
            }
            cells.append(cellValue)
        }
        
        return cells
    }
    
    private func extractFolderNames(from worksheet: Worksheet, sharedStrings: [String]) -> [String] {
        var folderNames: [String] = []
        var isFirstRow = true
        
        for row in worksheet.data?.rows ?? [] {
            let cells = extractCellsFromRow(row, sharedStrings: sharedStrings)
            
            if isFirstRow {
                // Check if this row contains headers that suggest it's NOT the Folders sheet
                let headerText = cells.joined(separator: " ").lowercased()
                if headerText.contains("icon") || headerText.contains("s3link") || headerText.contains("s3 link") {
                    // This is likely the Icons worksheet, return empty
                    return []
                }
                isFirstRow = false
                // Check if first cell is a header we should skip
                if !cells.isEmpty {
                    let firstCell = cells[0].lowercased().trimmingCharacters(in: .whitespaces)
                    if firstCell == "folder" || firstCell == "folders" || firstCell == "name" {
                        // Skip header row
                        continue
                    }
                }
            }
            
            // Extract folder name from first column
            if !cells.isEmpty {
                let folderName = cells[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !folderName.isEmpty {
                    folderNames.append(folderName)
                }
            }
        }
        
        return folderNames
    }
    
    private func parseExcelData(_ data: Data) async throws -> [IconImportData] {
        // Use CoreXLSX to parse the Excel file
        return try await parseExcelManually(data)
    }
    
    private func parseExcelManually(_ data: Data) async throws -> [IconImportData] {
        // Create temporary file for CoreXLSX (it requires a file path, not Data)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let tempFile = tempDir.appendingPathComponent("workbook.xlsx")
        try data.write(to: tempFile)
        
        // Open Excel file using CoreXLSX
        guard let file = XLSXFile(filepath: tempFile.path) else {
            throw NSError(domain: "ExcelIconImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to open Excel file"])
        }
        
        var importData: [IconImportData] = []
        
        // Get worksheet paths directly from file
        guard let worksheetPaths = try? file.parseWorksheetPaths() else {
            throw NSError(domain: "ExcelIconImporter", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse workbook or find worksheets"])
        }
        
        // Parse shared strings
        var sharedStrings: [String] = []
        if let sharedStringsFile = try? file.parseSharedStrings() {
            sharedStrings = sharedStringsFile.items.compactMap { $0.text }
        }
        
        // Find the "Icons" worksheet by looking for one with icon/folder/s3link headers
        var iconsWorksheet: Worksheet?
        var iconsWorksheetPath: String?
        
        for worksheetPath in worksheetPaths {
            guard let worksheet = try? file.parseWorksheet(at: worksheetPath) else {
                continue
            }
            
            // Check if this worksheet has the expected headers (icon, folder, s3link)
            if let worksheetData = worksheet.data,
               let firstRow = worksheetData.rows.first {
                let headerCells = extractCellsFromRow(firstRow, sharedStrings: sharedStrings)
                let headerText = headerCells.joined(separator: " ").lowercased()
                
                // Check if this looks like the Icons worksheet
                if headerText.contains("icon") && 
                   (headerText.contains("s3link") || headerText.contains("s3 link")) &&
                   headerText.contains("folder") {
                    iconsWorksheet = worksheet
                    iconsWorksheetPath = worksheetPath
                    break
                }
            }
        }
        
        // Fallback to first worksheet if Icons worksheet not found
        let worksheet: Worksheet
        if let foundWorksheet = iconsWorksheet {
            worksheet = foundWorksheet
        } else if let firstPath = worksheetPaths.first,
                  let firstWorksheet = try? file.parseWorksheet(at: firstPath) {
            worksheet = firstWorksheet
        } else {
            throw NSError(domain: "ExcelIconImporter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse worksheet"])
        }
        
        var headerRow: [String] = []
        var isFirstRow = true
        
        // Process rows
        for row in worksheet.data?.rows ?? [] {
            let cells = extractCellsFromRow(row, sharedStrings: sharedStrings)
            
            if isFirstRow {
                headerRow = cells
                isFirstRow = false
                continue
            }
            
            // Find column indices (case-insensitive)
            guard let iconIndex = headerRow.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "icon" }),
                  let folderIndex = headerRow.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "folder" }),
                  let s3LinkIndex = headerRow.firstIndex(where: { $0.lowercased().trimmingCharacters(in: .whitespaces) == "s3link" || $0.lowercased().trimmingCharacters(in: .whitespaces) == "s3 link" }),
                  cells.count > max(iconIndex, folderIndex, s3LinkIndex) else {
                continue
            }
            
            let iconName = cells[iconIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let folderName = cells[folderIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let s3Link = cells[s3LinkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !iconName.isEmpty && !folderName.isEmpty && !s3Link.isEmpty {
                importData.append(IconImportData(
                    iconName: iconName,
                    folderName: folderName,
                    s3Link: s3Link
                ))
            }
        }
        
        return importData
    }
    
    private func parseSharedStrings(_ data: Data) throws -> [String] {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            return []
        }
        
        var strings: [String] = []
        let pattern = #"<t[^>]*>([^<]*)</t>"#
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(xmlString.startIndex..., in: xmlString)
        
        regex.enumerateMatches(in: xmlString, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let stringRange = Range(match.range(at: 1), in: xmlString) else { return }
            strings.append(String(xmlString[stringRange]))
        }
        
        return strings
    }
    
    private func parseWorksheet(_ data: Data, sharedStrings: [String]) throws -> [IconImportData] {
        guard let xmlString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ExcelIconImporter", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to parse worksheet"])
        }
        
        var importData: [IconImportData] = []
        
        // Parse rows - looking for icon, folder, and S3Link columns
        // This assumes the first row is headers: icon, folder, S3Link
        let rows = xmlString.components(separatedBy: "<row")
        var headerRow: [String] = []
        var isFirstRow = true
        
        for row in rows.dropFirst() { // Skip first empty part
            let cells = extractCells(from: row, sharedStrings: sharedStrings)
            
            if isFirstRow {
                headerRow = cells
                isFirstRow = false
                continue
            }
            
            // Find column indices
            guard let iconIndex = headerRow.firstIndex(where: { $0.lowercased() == "icon" }),
                  let folderIndex = headerRow.firstIndex(where: { $0.lowercased() == "folder" }),
                  let s3LinkIndex = headerRow.firstIndex(where: { $0.lowercased() == "s3link" || $0.lowercased() == "s3 link" }),
                  cells.count > max(iconIndex, folderIndex, s3LinkIndex) else {
                continue
            }
            
            let iconName = cells[iconIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let folderName = cells[folderIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let s3Link = cells[s3LinkIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            
            if !iconName.isEmpty && !folderName.isEmpty && !s3Link.isEmpty {
                importData.append(IconImportData(
                    iconName: iconName,
                    folderName: folderName,
                    s3Link: s3Link
                ))
            }
        }
        
        return importData
    }
    
    private func extractCells(from row: String, sharedStrings: [String]) -> [String] {
        var cells: [String] = []
        
        // Extract cell values
        let cellPattern = #"<c[^>]*r="([A-Z]+)(\d+)"[^>]*>.*?<v>(\d+)</v>"#
        let regex = try? NSRegularExpression(pattern: cellPattern, options: [])
        let range = NSRange(row.startIndex..., in: row)
        
        var cellMap: [Int: String] = [:]
        
        regex?.enumerateMatches(in: row, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let rowRange = Range(match.range(at: 2), in: row),
                  let valueRange = Range(match.range(at: 3), in: row) else { return }
            
            let rowNum = Int(row[rowRange]) ?? 0
            let valueIndex = Int(row[valueRange]) ?? 0
            
            if valueIndex < sharedStrings.count {
                cellMap[rowNum] = sharedStrings[valueIndex]
            }
        }
        
        // Also handle inline strings
        let inlinePattern = #"<c[^>]*r="([A-Z]+)(\d+)"[^>]*>.*?<is>.*?<t>([^<]*)</t>"#
        let inlineRegex = try? NSRegularExpression(pattern: inlinePattern, options: [])
        
        inlineRegex?.enumerateMatches(in: row, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let rowRange = Range(match.range(at: 2), in: row),
                  let valueRange = Range(match.range(at: 3), in: row) else { return }
            
            let rowNum = Int(row[rowRange]) ?? 0
            let value = String(row[valueRange])
            cellMap[rowNum] = value
        }
        
        // Convert to array
        let maxIndex = cellMap.keys.max() ?? 0
        for i in 1...maxIndex {
            cells.append(cellMap[i] ?? "")
        }
        
        return cells
    }
    
    func downloadImage(from urlString: String) async throws -> UIImage? {
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "ExcelIconImporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        return UIImage(data: data)
    }
    
    func importIcons(from excelURL: URL, folders: inout [Folder]) async throws {
        await MainActor.run {
            isImporting = true
            importProgress = 0.0
            importStatus = "Parsing Excel file..."
            createdIconCount = 0 // Reset count for new import
        }
        
        // First, parse and create folders from the 'Folders' worksheet
        await MainActor.run {
            importStatus = "Creating folders from 'Folders' worksheet..."
        }
        
        do {
            let folderNames = try await parseFoldersWorksheet(at: excelURL)
            await MainActor.run {
                // Create folders if they don't already exist
                for folderName in folderNames {
                    if !folders.contains(where: { $0.name == folderName }) {
                        let newFolder = Folder(name: folderName, icons: [])
                        folders.append(newFolder)
                    }
                }
            }
        } catch {
            // If 'Folders' worksheet doesn't exist or can't be parsed, continue with icon import
            print("Warning: Could not parse 'Folders' worksheet: \(error.localizedDescription)")
        }
        
        // Parse Excel file for icons
        await MainActor.run {
            importStatus = "Parsing icons from Excel file..."
        }
        let importData = try await parseExcelFile(at: excelURL)
        
        await MainActor.run {
            importStatus = "Downloading images and creating icons..."
        }
        
        var folderMap: [String: Folder] = [:]
        var folderIconMap: [String: [SpeakingIcon]] = [:]
        var createdCount = 0
        var skippedCount = 0
        
        // Get existing folder structure for duplicate checking
        let existingFoldersMap = await MainActor.run {
            var map: [String: [String]] = [:]
            for folder in folders {
                map[folder.name] = folder.icons.map { $0.title }
            }
            return map
        }
        
        // Group icons by folder
        for (index, data) in importData.enumerated() {
            await MainActor.run {
                importProgress = Double(index) / Double(importData.count)
                importStatus = "Processing \(data.iconName)..."
            }
            
            // Check if icon already exists in the folder
            if let existingIcons = existingFoldersMap[data.folderName],
               existingIcons.contains(where: { $0.lowercased() == data.iconName.lowercased() }) {
                skippedCount += 1
                print("Skipping existing icon: \(data.iconName) in folder: \(data.folderName)")
                continue
            }
            
            // Download image
            guard let image = try? await downloadImage(from: data.s3Link) else {
                print("Failed to download image for \(data.iconName) from \(data.s3Link)")
                continue
            }
            
            // Create icon
            let icon = SpeakingIcon(
                title: data.iconName,
                image: image,
                audioData: nil
            )
            
            // Add to folder map
            if folderIconMap[data.folderName] == nil {
                folderIconMap[data.folderName] = []
            }
            folderIconMap[data.folderName]?.append(icon)
            createdCount += 1
        }
        
        // Create or update folders
        await MainActor.run {
            for (folderName, icons) in folderIconMap {
                if let existingFolderIndex = folders.firstIndex(where: { $0.name == folderName }) {
                    // Update existing folder - only add icons that don't already exist
                    var updatedFolder = folders[existingFolderIndex]
                    let existingIconNames = Set(updatedFolder.icons.map { $0.title.lowercased() })
                    let newIcons = icons.filter { !existingIconNames.contains($0.title.lowercased()) }
                    updatedFolder.icons.append(contentsOf: newIcons)
                    folders[existingFolderIndex] = updatedFolder
                } else {
                    // Create new folder
                    let newFolder = Folder(name: folderName, icons: icons)
                    folders.append(newFolder)
                }
            }
            
            importProgress = 1.0
            createdIconCount = createdCount
            let statusMessage: String
            if skippedCount > 0 {
                statusMessage = "Import complete! Created \(createdCount) new icons, skipped \(skippedCount) existing icons in \(folderIconMap.count) folders."
            } else {
                statusMessage = "Import complete! Created \(createdCount) icons in \(folderIconMap.count) folders."
            }
            importStatus = statusMessage
            isImporting = false
        }
    }
}

