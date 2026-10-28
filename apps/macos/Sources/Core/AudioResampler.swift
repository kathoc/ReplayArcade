// Streaming resampler for the live audio path (dynamic rate control, see AudioRateControl):
// 4-point Hermite on a continuous int16 mono stream, implemented by the shared frontend core
// (rnf_resampler). Display path only: recordings and MP4 export use the emulator's samples.
// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

struct AudioResampler {
    private var box: RNFHandle
    private var scratch: [Int16] = []
    /// Values per sample frame (1 mono, 2 interleaved stereo).
    let channels: Int

    init(channels: Int = 1) {
        self.channels = channels
        box = RNFHandle(rnf_resampler_new_with_channels(UInt32(channels)), free: { rnf_resampler_free($0) }, clone: { rnf_resampler_clone($0) })
    }

    mutating func reset() { rnf_resampler_reset(RNFHandle.unique(&box)) }

    /// Resamples `input` (interleaved sample frames) with `ratio` output sample frames per input
    /// sample frame, appending to `out`. Output lags the input by one sample frame (interpolation
    /// needs one of look-ahead).
    mutating func process(_ input: UnsafeBufferPointer<Int16>, ratio: Double, into out: inout [Int16]) {
        let frames = input.count / channels
        guard frames > 0, let base = input.baseAddress else { return }
        let bound = rnf_resampler_output_bound(frames)
        if scratch.count < bound * channels { scratch = [Int16](repeating: 0, count: bound * channels) }
        let h = RNFHandle.unique(&box)
        var n = 0
        scratch.withUnsafeMutableBufferPointer { buf in
            _ = rnf_resampler_process(h, base, frames, ratio, buf.baseAddress, bound, &n)
        }
        out.append(contentsOf: scratch[0..<(n * channels)])
    }
}
