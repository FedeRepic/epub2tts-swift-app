# ReaderTTS

A native iOS and iPadOS EPUB reader with on-device text-to-speech powered by Core ML. It is designed for reading and listening to books without sending their contents to external services.

## Highlights

- Local DRM-free EPUB library with covers, search, sorting, and deletion.
- Reading experience powered by [Readium](https://github.com/readium/swift-toolkit), including table of contents, gestures, persistent progress, and bookmarks.
- On-device Supertonic 3 Core ML FP16 speech with ten voice styles, user-selected Spanish or English, adjustable speed, and configurable preloading.
- Background audio, system playback controls, sleep timer, and pause/resume support.
- Configurable visual tracking of the text currently being spoken.
- Global typography, text size, line height, character spacing, margins, and light/dark appearance settings.

## Architecture

- `Features/LibraryView.swift`: library and import experience.
- `Features/ReadiumReaderView.swift`: Readium reader, progress, bookmarks, and reading UI.
- `Features/ReaderSupport.swift`: shared settings, synthesis queue, and playback coordination.
- `TTS/SupertonicCoreMLEngine.swift`: tokenization, duration prediction, ODE denoising, and Core ML vocoding.
- `EPUB/EPUBImporter.swift`: secure import, private extraction, and EPUB metadata.

Books are extracted into the app sandbox. Reading position, bookmarks, and preferences are stored locally.

## Requirements and running the app

1. Open `ReaderTTS.xcodeproj` in Xcode 26.2 or later.
2. Configure target signing and run on an iOS or iPadOS 18+ device.
3. Import a DRM-free EPUB from the library.

The simulator is useful for UI work. Performance, memory, battery, and Apple Neural Engine measurements should be performed on a physical device.

## Speech model

The app integrates the FP16 variant of [aufklarer/Supertonic-3-CoreML-FP16](https://huggingface.co/aufklarer/Supertonic-3-CoreML-FP16). The four compiled models (`TextEncoder`, `DurationPredictor`, `VectorEstimator`, and `Vocoder`), Unicode index, and voice styles must be available as target resources.

The engine uses CPU and Apple Neural Engine execution to avoid the GPU/Metal route that caused instability with this exporter on recent iPadOS releases. Model binaries are not tracked in Git; see [ModelProvenance.md](ReaderTTS/Resources/ModelProvenance.md) for the exact revision, verification information, and redistribution considerations.

To enable TTS in a fresh clone, download the revision documented there and place the compiled `TextEncoder.mlmodelc`, `DurationPredictor.mlmodelc`, `VectorEstimator.mlmodelc`, and `Vocoder.mlmodelc` directories in `ReaderTTS/Resources/CompiledModels/`. The Unicode index and voice styles are included in this repository. Do not add model weights to Git before reviewing the license and confirming redistribution authorization.

## Privacy and limitations

Reading, EPUB processing, and synthesis run locally after a book is imported. DRM-protected EPUBs are not supported. Before distributing the app or model weights, review the OpenRAIL-M license and the model repository terms.
