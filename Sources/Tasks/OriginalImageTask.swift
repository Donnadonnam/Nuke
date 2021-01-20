// The MIT License (MIT)
//
// Copyright (c) 2015-2021 Alexander Grebenyuk (github.com/kean).

import Foundation

/// Receives data from ``OriginalDataTask` and decodes it as it arrives.
final class OriginalImageTask: ImagePipelineTask<ImageResponse> {
    private var decoder: ImageDecoding?

    override func start() {
        dependency = pipeline.getOriginalImageData(for: request).subscribe(self) { [weak self] in
            self?.didReceiveData($0.0, urlResponse: $0.1, isCompleted: $1)
        }
    }

    /// Receiving data from `OriginalDataTask`.
    private func didReceiveData(_ data: Data, urlResponse: URLResponse?, isCompleted: Bool) {
        if isCompleted {
            operation?.cancel() // Cancel any potential pending progressive decoding tasks
        } else if !configuration.isProgressiveDecodingEnabled || operation != nil {
            return // Back pressure - already decoding another progressive data chunk
        }

        // Sanity check
        guard !data.isEmpty else {
            if isCompleted {
                send(error: .decodingFailed)
            }
            return
        }

        guard let decoder = decoder(data: data, urlResponse: urlResponse, isCompleted: isCompleted) else {
            if isCompleted {
                send(error: .decodingFailed)
            } // Try again when more data is downloaded.
            return
        }

        operation = configuration.imageDecodingQueue.add { [weak self] in
            guard let self = self else { return }

            let response = signpost(self.log, "Decode Image Data", isCompleted ? "Final image" : "Progressive image") {
                decoder.decode(data, urlResponse: urlResponse, isCompleted: isCompleted)
            }

            self.async {
                if let response = response {
                    self.send(value: response, isCompleted: isCompleted)
                } else if isCompleted {
                    self.send(error: .decodingFailed)
                }
            }
        }
    }

    // Lazily creates decoding for task
    private func decoder(data: Data, urlResponse: URLResponse?, isCompleted: Bool) -> ImageDecoding? {
        // Return the existing processor in case it has already been created.
        if let decoder = self.decoder {
            return decoder
        }
        let decoderContext = ImageDecodingContext(request: request, data: data, isCompleted: isCompleted, urlResponse: urlResponse)
        let decoder = configuration.makeImageDecoder(decoderContext)
        self.decoder = decoder
        return decoder
    }
}
