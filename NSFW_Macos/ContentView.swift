//
//  ContentView.swift
//  NSFW_Macos
//
//  Created by yanguo sun on 2024/4/22.
//

import SwiftUI

import SwiftUI
import Vision
import Combine


import Foundation
import CoreML
import Vision
import AppKit // Import AppKit for NSImage


struct NSFWCheckResult {
    let filename: String
    let confidence: Float
}

@available(macOS 10.14, *) // Make sure to specify the correct macOS version
public class NSFWDetector {
    
    public static let shared = NSFWDetector()
    
    private let model: VNCoreMLModel
    
    public required init() {
        guard let model = try? VNCoreMLModel(for: NSFW(configuration: MLModelConfiguration()).model) else {
            fatalError("NSFW should always be a valid model")
        }
        self.model = model
    }
    
    public enum DetectionResult {
        case error(Error)
        case success(nsfwConfidence: Float)
    }
    
    public func check(image: NSImage, completion: @escaping (_ result: DetectionResult) -> Void) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.error(NSError(domain: "Could not convert NSImage to CGImage", code: 0, userInfo: nil)))
            return
        }
        let requestHandler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        self.check(requestHandler, completion: completion)
    }
    
    public func check(cvPixelbuffer: CVPixelBuffer, completion: @escaping (_ result: DetectionResult) -> Void) {
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: cvPixelbuffer, options: [:])
        self.check(requestHandler, completion: completion)
    }
}

@available(macOS 10.14, *)
private extension NSFWDetector {
    
    func check(_ requestHandler: VNImageRequestHandler?, completion: @escaping (_ result: DetectionResult) -> Void) {
        guard let requestHandler = requestHandler else {
            completion(.error(NSError(domain: "Request handler could not be initialized", code: 0, userInfo: nil)))
            return
        }
        
        let request = VNCoreMLRequest(model: self.model, completionHandler: { (request, error) in
            if let error = error {
                completion(.error(error))
                return
            }
            guard let observations = request.results as? [VNClassificationObservation],
                  let observation = observations.first(where: { $0.identifier == "NSFW" }) else {
                completion(.error(NSError(domain: "Detection failed: No NSFW Observation found", code: 0, userInfo: nil)))
                return
            }
            
            completion(.success(nsfwConfidence: observation.confidence))
        })
        
        do {
            try requestHandler.perform([request])
        } catch {
            completion(.error(error))
        }
    }
}

import SwiftUI
import AppKit

struct ContentView: View {
    @State private var isDetecting: Bool = false  // 添加一个状态来追踪检测状态
    @State private var results: [NSFWCheckResult] = []
    @State private var inputPath: String = "/Users/yanguosun/Developer/NSFW_Macos/nsfwtest"
    // "/Users/yanguosun/Sites/localhost/aiheadshot-report/output-aiphoto"
    // "/Users/yanguosun/Sites/localhost/aiheadshot-report/testaaqaa"
    
    var body: some View {
        VStack {
            HStack{
                Button("Select Folder") {
                    selectFolder()
                }
                .padding()
                
                if isDetecting {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else {
                    Button("Start Detection") {
                        loadAndCheckImages()
                    }
                    .disabled(isDetecting || inputPath.isEmpty)  // 当没有选择文件夹或正在检测时禁用按钮
                }
            }

            Text(inputPath)
//                .font(.headline)
//                .padding()
//            
            List {
                ForEach(results, id: \.filename) { result in
                    HStack {
                        if let image = NSImage(contentsOfFile: "\(inputPath)/\(result.filename)") {
                            Button(action: {
                                NSWorkspace.shared.selectFile("\(inputPath)/\(result.filename)", inFileViewerRootedAtPath: inputPath)
                            }) {
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 100, height: 100)
                            }
                        }
                        
                        VStack(alignment: .leading) {
                            Text("File: \(result.filename)")
                            Text("Confidence: \(result.confidence * 100, specifier: "%.1f")%")
                                .foregroundColor(result.confidence > 0.5 ? .red : .green)
                        }

                        Spacer()

                        Button(action: {
                            deleteImage(result: result)
                        }) {
                            Text("Delete")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }
    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK {
                self.inputPath = panel.url?.path ?? ""
            }
        }
    }
    
    private func loadAndCheckImages() {
        isDetecting = true  // 开始检测前，设置正在检测的状态为true
        DispatchQueue.global(qos: .userInitiated).async {
            let fileManager = FileManager.default
            guard let items = try? fileManager.contentsOfDirectory(atPath: self.inputPath) else {
                return
            }
            
            for item in items where item.hasSuffix("png") {
                let fullPath = "\(self.inputPath)/\(item)"
                if let image = NSImage(contentsOfFile: fullPath) {
                    NSFWDetector.shared.check(image: image) { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .error(let error):
                                print("Detection failed for \(item): \(error.localizedDescription)")
                            case let .success(nsfwConfidence: confidence):
                                let newResult = NSFWCheckResult(filename: item, confidence: confidence)
                                self.insertSorted(result: newResult)
                            }
                        }
                    }
                }
            }
            DispatchQueue.main.async {
                self.isDetecting = false  // 检测结束后，设置正在检测的状态为false
            }
        }
    }

    /// Inserts a new result in sorted order into the results array
    private func insertSorted(result: NSFWCheckResult) {
        let index = results.firstIndex { $0.confidence < result.confidence } ?? results.count
        results.insert(result, at: index)
    }

    /// Function to delete the selected image from the filesystem and update the UI
    private func deleteImage(result: NSFWCheckResult) {
        guard let index = results.firstIndex(where: { $0.filename == result.filename }) else { return }
        let fullPath = "\(inputPath)/\(result.filename)"
        do {
            try FileManager.default.removeItem(atPath: fullPath)
            results.remove(at: index)
        } catch {
            print("Failed to delete file: \(error)")
        }
    }
}




#Preview {
    ContentView()
}
