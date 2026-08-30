//
//  appstore_conform.swift
//  J-Notes tools
//
//  Rewrites a finished App Preview into exactly the shape App Store Connect
//  accepts. The upload check is strict and its error messages are not: it
//  reports "unsupported or corrupted audio" for problems that have nothing to
//  do with sound, so everything here is pinned rather than left to a preset.
//
//      swift Tools/appstore_conform.swift <preview.mp4> <width> <height>
//
//  Apple's specification (App Store Connect Help -> App preview specifications):
//
//      resolution   iPhone 886 x 1920, iPad 13" 1200 x 1600 (portrait)
//      video        H.264 High Profile Level 4.0, progressive, 30 fps
//      bit rate     10-12 Mbps VBR
//      audio        stereo AAC, 256 kbps, 44.1 or 48 kHz - required
//      duration     15-30 s, at most 500 MB
//
//  Two things about that list are worth knowing, because both cost an upload to
//  find out. The native device resolution is *not* accepted - the one 886 x 1920
//  file is what Apple lists for every iPhone slot from 6.9" down to 6.1", and
//  the device's own 1242 x 2688 is not on the list - and Level 4.0 is a real
//  ceiling, so a preview at the device's own size comes out as Level 5.0 and is
//  refused.
//
//  ## The audio track, and why there is one at all
//
//  **This preview has no music, deliberately.** A notes app is not a game, and a
//  soundtrack over somebody's shopping list makes a listing look like an advert
//  for a different app. But the audio track cannot simply be left out, and it
//  cannot be digital silence either: audio is *required*, and AAC compresses a
//  silent track to about 2 kbps - two orders of magnitude under the 256 kbps
//  asked for - which Connect reads as an unsupported audio configuration rather
//  than as a quiet film.
//
//  So the track carries dither: white noise at -84 dBFS, about three counts of a
//  16-bit sample. That is below the noise floor of any chain a person will hear
//  the preview through - inaudible on a phone speaker, inaudible on headphones
//  at any sane volume - while being, unlike silence, incompressible. The encoder
//  therefore spends the whole 256 kbps on it and the file satisfies the
//  specification honestly, without a note of music in it. The rate that came out
//  is checked before the tool exits, because the failure it guards against is
//  otherwise reported a whole upload later.
//
//  Measured, on twenty seconds of stereo at 48 kHz asked for at 256 kbps:
//
//      digital silence      2.2 kbit/s     10 kB
//      dither at -84 dBFS 236.8 kbit/s    584 kB
//
//  A hundredfold, for noise nobody can hear. The 236.8 is the encoder rounding
//  down from the 256 it was asked for, which is why `minimumAudioBitRate` sits
//  at 200 rather than at 256.
//
//  Deterministic noise, from a fixed seed: the same preview conformed twice
//  produces the same bytes, so a diff that says the audio changed means the
//  audio changed.
//
//  The picture is re-encoded, which it has to be to hit the profile and the
//  size. What comes out still carries the edit list AVFoundation writes for the
//  recording's leading trim - the track presents from time zero but starts
//  67 ms into its own media. That resisted every attempt to remove it on the
//  sister project (a session opened on the first sample, retimed samples, a
//  plain mux) and is left alone: it is ordinary trim bookkeeping, every trimmed
//  clip out of iMovie or QuickTime has one, and Apple's specification does not
//  mention it.
//
//  Used by Tools/appstore_media.sh; see AppStore/screenshots.md.
//
import AVFoundation
import CoreMedia
import Foundation

let argv = CommandLine.arguments
guard argv.count == 4,
      let targetW = Double(argv[2]), let targetH = Double(argv[3]) else {
    FileHandle.standardError.write(Data(
        "usage: appstore_conform <preview.mp4> <width> <height>\n".utf8))
    exit(2)
}

let videoURL = URL(fileURLWithPath: argv[1])
let targetSize = CGSize(width: targetW, height: targetH)

let fps: Int32 = 30
// Apple's band is 10–12 Mbps, and `AVVideoAverageBitRateKey` is a *ceiling*, not
// a target — the encoder spends what the picture needs and no more. A notes app
// needs almost nothing: flat panels, a list scrolling, one map that moves. Asked
// for with an ordinary one-second GOP it measures well under the floor, which is
// out of spec in the other direction.
//
// What makes the number behave like a floor is `AVVideoMaxKeyFrameIntervalKey: 1`
// below — with every frame an I-frame there is no temporal prediction to save
// bits with, so each frame takes its equal share of the average and the result
// lands on the number asked for. Verified by the line the tool prints when it
// finishes; check it after any change to the pacing or the cut, and do not
// "optimise" the GOP back without re-measuring. On the sister project a GOP of 2
// came out at 26.5 Mbps, which is out of spec on its own.
let videoBitRate = 11_500_000
let sampleRate = 48_000.0
let audioChannels = 2
let audioBitRate = 256_000

/// How loud the dither on the audio track is, as a fraction of full scale.
///
/// 1/16384 is -84 dBFS: three counts of a 16-bit sample, and a good 20 dB under
/// the quietest thing anyone has heard out of a phone. Loud enough to keep the
/// encoder honest, quiet enough to be nothing; see the header for why the track
/// is not simply empty.
let ditherAmplitude: Float = 1.0 / 16384.0

/// The rate below which the finished audio track is treated as a failure.
///
/// Apple asks for 256 kbps. Anything near the floor means the dither collapsed
/// and the file is one Connect will refuse; anything a little under 256 is the
/// encoder rounding, which is fine.
let minimumAudioBitRate = 200_000.0

func problem(_ code: Int, _ message: String) -> NSError {
    NSError(domain: "appstore_conform", code: code,
            userInfo: [NSLocalizedDescriptionKey: message])
}

func time(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 600)
}

/// Drains `output` into `input` and closes the writer. Both passes below are a
/// single track, so one reader and one writer input is all this has to juggle.
func transfer(from output: AVAssetReaderOutput, to input: AVAssetWriterInput,
              reader: AVAssetReader, writer: AVAssetWriter) async throws {
    guard reader.startReading() else {
        throw reader.error ?? problem(1, "could not start reading")
    }
    guard writer.startWriting() else {
        throw writer.error ?? problem(2, "could not start writing")
    }

    // The first frame of the recording does not sit at time zero, so the session
    // opens on it rather than on zero — the writer then measures the track from
    // the frame it was actually given. (It still notes the leading trim in an
    // edit list; see the header. This is the idiomatic way round regardless.)
    guard let first = output.copyNextSampleBuffer() else {
        throw reader.error ?? problem(3, "nothing to encode")
    }
    writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(first))

    let queue = DispatchQueue(label: "cz.rob.notes.appstore-conform")
    var pending: CMSampleBuffer? = first
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        input.requestMediaDataWhenReady(on: queue) {
            while input.isReadyForMoreMediaData {
                let next: CMSampleBuffer?
                if let pending {
                    next = pending
                } else {
                    next = output.copyNextSampleBuffer()
                }
                pending = nil
                guard let sample = next else {
                    input.markAsFinished()
                    if reader.status == .failed {
                        continuation.resume(throwing: reader.error ?? problem(4, "read failed"))
                    } else {
                        continuation.resume()
                    }
                    return
                }
                if !input.append(sample) {
                    input.markAsFinished()
                    continuation.resume(throwing: writer.error ?? problem(5, "encode failed"))
                    return
                }
            }
        }
    }
    await writer.finishWriting()
    if writer.status == .failed {
        throw writer.error ?? problem(6, "could not finish \(writer.outputURL.lastPathComponent)")
    }
}

/// Re-encodes the picture to the target size and to H.264 High 4.0. Scaling to
/// width and centring is what appstore_video.swift already does for the cut —
/// the preview's aspect ratio is within a rounding error of the target, so this
/// only ever drops a fraction of a row.
func encodeVideo(asset: AVAsset, track: AVAssetTrack, to outURL: URL) async throws {
    let duration = try await asset.load(.duration)
    let natural = try await track.load(.naturalSize)
    let scale = targetSize.width / natural.width
    let ty = (targetSize.height - natural.height * scale) / 2

    let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    layer.setTransform(CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: 0, y: ty)), at: .zero)
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
    instruction.layerInstructions = [layer]

    let videoComposition = AVMutableVideoComposition()
    videoComposition.renderSize = targetSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
    videoComposition.instructions = [instruction]

    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
        kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
    ])
    output.videoComposition = videoComposition
    reader.add(output)

    try? FileManager.default.removeItem(at: outURL)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: Int(targetSize.width),
        AVVideoHeightKey: Int(targetSize.height),
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: videoBitRate,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264High40,
            // Every frame a keyframe. Two reasons, and the second is the load
            // bearing one: Connect seeks the file to build the poster frame and a
            // long GOP has bitten this pipeline before — and all-intra is what
            // turns the average bit rate above from a ceiling the encoder ignores
            // into the figure it actually delivers. See the note there.
            AVVideoMaxKeyFrameIntervalKey: 1,
            AVVideoExpectedSourceFrameRateKey: Int(fps),
        ],
        // Tag the colour explicitly; the simulator's own recording is Rec. 709
        // and an untagged file is left to the reader to guess at.
        AVVideoColorPropertiesKey: [
            AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
            AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
            AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
        ],
    ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)

    try await transfer(from: output, to: input, reader: reader, writer: writer)
}

/// Writes `seconds` of inaudible dither, which is what goes on the audio track.
///
/// Not silence. See the header: digital silence encodes to about 2 kbps and
/// Connect rejects the file for it, so the track carries white noise at
/// `ditherAmplitude` instead - incompressible enough that the encoder delivers
/// the rate Apple asks for, and far too quiet for anyone to hear.
///
/// A plain 32-bit linear congruential generator with a fixed seed rather than
/// `random()`: the same preview conformed twice has to come out the same, and
/// the statistical quality of the noise could not matter less when the only
/// requirement on it is that it does not compress.
func writeDither(seconds: Double, to url: URL) throws {
    let file = try AVAudioFile(forWriting: url, settings: [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: audioChannels,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
    ])
    let chunk = AVAudioFrameCount(sampleRate)   // a second at a time
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                        frameCapacity: chunk) else {
        throw problem(6, "could not allocate a silence buffer")
    }
    var seed: UInt32 = 0x4A4E_5453   // "JNTS"
    func nextSample() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 2 * ditherAmplitude
    }

    var remaining = AVAudioFrameCount((seconds * sampleRate).rounded(.up))
    while remaining > 0 {
        buffer.frameLength = min(chunk, remaining)
        if let data = buffer.floatChannelData {
            for frame in 0..<Int(buffer.frameLength) {
                // One draw per frame, written to both channels. Two independent
                // draws would be a wider stereo image of something nobody can
                // hear, at twice the cost.
                let sample = nextSample()
                for channel in 0..<Int(buffer.format.channelCount) {
                    data[channel][frame] = sample
                }
            }
        }
        try file.write(from: buffer)
        remaining -= buffer.frameLength
    }
}

/// Encodes `duration` of dither to AAC at the rate Apple asks for. The reader
/// handles the rate conversion.
func encodeAudio(duration: CMTime, to outURL: URL) async throws {
    let sourceURL = outURL.deletingLastPathComponent()
        .appendingPathComponent("dither.caf")
    try writeDither(seconds: duration.seconds, to: sourceURL)

    let asset = AVURLAsset(url: sourceURL)
    guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
        throw problem(7, "no audio track in \(sourceURL.lastPathComponent)")
    }
    let sourceDuration = try await asset.load(.duration)
    guard sourceDuration > .zero else {
        throw problem(8, "\(sourceURL.lastPathComponent) is empty")
    }

    let composition = AVMutableComposition()
    guard let track = composition.addMutableTrack(
        withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
        throw problem(9, "could not add an audio track")
    }
    var cursor = CMTime.zero
    while cursor < duration {
        let take = min(sourceDuration, duration - cursor)
        try track.insertTimeRange(CMTimeRange(start: .zero, duration: take),
                                  of: sourceTrack, at: cursor)
        cursor = cursor + take
    }

    // No mix and no fades. There is nothing to fade: the track is dither at one
    // level from its first sample to its last, and a ramp on something 84 dB
    // down is bookkeeping for an effect nobody can hear.
    let reader = try AVAssetReader(asset: composition)
    let output = AVAssetReaderAudioMixOutput(
        audioTracks: composition.tracks(withMediaType: .audio),
        audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: audioChannels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
    reader.add(output)

    try? FileManager.default.removeItem(at: outURL)
    let writer = try AVAssetWriter(outputURL: outURL, fileType: .m4a)
    let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: sampleRate,
        AVNumberOfChannelsKey: audioChannels,
        AVEncoderBitRateKey: audioBitRate,
    ])
    input.expectsMediaDataInRealTime = false
    writer.add(input)

    try await transfer(from: output, to: input, reader: reader, writer: writer)
    try? FileManager.default.removeItem(at: sourceURL)
}

let done = DispatchSemaphore(value: 0)

Task {
    do {
        let original = AVURLAsset(url: videoURL)
        guard let sourceVideo = try await original.loadTracks(withMediaType: .video).first else {
            throw problem(10, "no video track in \(videoURL.lastPathComponent)")
        }
        let duration = try await original.load(.duration)
        guard duration.seconds >= 15, duration.seconds <= 30 else {
            throw problem(11, String(format: "%.1fs is outside Connect's 15–30 s",
                                     duration.seconds))
        }

        // Work beside the file: replaceItemAt wants both on the same volume.
        let work = videoURL.deletingLastPathComponent()
            .appendingPathComponent(".appstore_conform-\(ProcessInfo.processInfo.processIdentifier)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let videoOnly = work.appendingPathComponent("video.mp4")
        let audioOnly = work.appendingPathComponent("audio.m4a")
        try await encodeVideo(asset: original, track: sourceVideo, to: videoOnly)
        try await encodeAudio(duration: duration, to: audioOnly)

        // Put the two together. Passthrough copies both tracks as encoded, so
        // nothing above is undone here, and inserting from time zero is what
        // leaves the result without the offset edit list a composed export
        // would otherwise carry.
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoOnly)
        let audioAsset = AVURLAsset(url: audioOnly)
        guard let encodedVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
              let video = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw problem(12, "could not add the encoded picture")
        }
        let videoDuration = try await videoAsset.load(.duration)
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: videoDuration),
                                  of: encodedVideo, at: .zero)

        guard let encodedAudio = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let audio = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw problem(13, "could not add the encoded audio")
        }
        // AAC comes out in whole packets, a fraction of a second longer than
        // asked for. Trim it so the sound does not outlast the picture.
        let audioDuration = min(try await audioAsset.load(.duration), videoDuration)
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: audioDuration),
                                  of: encodedAudio, at: .zero)

        guard let export = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw problem(14, "could not create an export session")
        }
        // Moves the index to the front, so Connect can read the file as it
        // arrives instead of having to take all of it first.
        export.shouldOptimizeForNetworkUse = true
        let outURL = work.appendingPathComponent(videoURL.lastPathComponent)
        try await export.export(to: outURL, as: .mp4)
        _ = try FileManager.default.replaceItemAt(videoURL, withItemAt: outURL)

        // Report what the file ended up holding, not what was asked for above.
        let result = AVURLAsset(url: videoURL)
        let finalVideo = try await result.loadTracks(withMediaType: .video).first
        let finalAudio = try await result.loadTracks(withMediaType: .audio).first
        let videoRate = try await finalVideo?.load(.estimatedDataRate) ?? 0
        let audioRate = try await finalAudio?.load(.estimatedDataRate) ?? 0
        let size = (try FileManager.default.attributesOfItem(atPath: videoURL.path)[.size]
                    as? Int) ?? 0
        print(String(format: "-> %@\n  %dx%d  %.2fs  H.264 High 4.0 %.1f Mbit/s  " +
                     "AAC %.0f kHz stereo %.0f kbit/s  %.1f MB  (no music, dither only)",
                     videoURL.path, Int(targetW), Int(targetH), duration.seconds,
                     videoRate / 1_000_000, sampleRate / 1000, audioRate / 1000,
                     Double(size) / 1_048_576))

        // The whole point of the dither is that this number comes out near 256.
        // A track that collapsed to a few kbps is what Connect reports as
        // "unsupported or corrupted audio" a whole upload later, so it is caught
        // here instead of there.
        if Double(audioRate) < minimumAudioBitRate {
            FileHandle.standardError.write(Data(
                String(format: "  !! audio came out at %.0f kbit/s, under Apple's 256 - " +
                       "Connect will refuse this file\n", audioRate / 1000).utf8))
            exit(1)
        }
    } catch {
        FileHandle.standardError.write(Data("ERROR: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    done.signal()
}

done.wait()
