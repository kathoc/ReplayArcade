// Lock-free single-producer / single-consumer PCM ring for real-time audio output.
// Producer: emulation thread (interleaved int16 sample frames of 1 or 2 channels at the output rate).
// Consumer: Core Audio render thread. Counts (fill, prime, n ...) are sample frames.
// SPDX-License-Identifier: GPL-2.0-or-later
#ifndef RN_AUDIO_RING_H
#define RN_AUDIO_RING_H
#include <stdint.h>

typedef struct rn_audio_ring rn_audio_ring;

typedef struct rn_audio_ring_stats {
  uint64_t underruns;       /* render callbacks that ran dry while audible (not muted) */
  uint64_t dropped_samples; /* samples discarded: ring full or latency above high-water mark */
  uint64_t pulled_samples;
  uint32_t fill;            /* samples currently buffered */
  uint32_t last_request;    /* frames requested by the last render callback */
} rn_audio_ring_stats;

/* capacity is rounded up to a power of two. prime: samples needed before (re)starting output
 * after a mute/underrun. high_water: if more is buffered, the consumer skips ahead to `prime`
 * (bounds latency when the host clock drifts against the audio clock; never touches emulation). */
#define RN_RING_MAX_CHANNELS 2
rn_audio_ring* rn_ring_create(uint32_t capacity, uint32_t prime, uint32_t high_water);
/* Values per sample frame (1 mono, 2 stereo; default 1). Drops what is buffered. Call only while the
 * consumer is stopped (no render callback running). */
void rn_ring_set_channels(rn_audio_ring* r, uint32_t channels);
uint32_t rn_ring_channels(const rn_audio_ring* r);
void rn_ring_destroy(rn_audio_ring* r);
/* producer: n sample frames (n x channels interleaved values) */
uint32_t rn_ring_push(rn_audio_ring* r, const int16_t* samples, uint32_t n);
/* consumer: always writes n floats (silence where no data) per output; rn_ring_pull = the first channel.
 * Output c is the ring's channel c, or its last channel when the ring has fewer (mono on both). */
void rn_ring_pull(rn_audio_ring* r, float* out, uint32_t n);
void rn_ring_pull_channels(rn_audio_ring* r, float* const* outs, uint32_t nout, uint32_t n);
/* any thread: muted => consumer flushes buffered audio and outputs silence */
void rn_ring_set_muted(rn_audio_ring* r, int muted);
int rn_ring_is_muted(const rn_audio_ring* r);
void rn_ring_get_stats(const rn_audio_ring* r, rn_audio_ring_stats* out);
#endif
