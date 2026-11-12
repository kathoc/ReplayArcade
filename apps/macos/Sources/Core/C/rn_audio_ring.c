// SPDX-License-Identifier: GPL-2.0-or-later
#include "rn_audio_ring.h"
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct rn_audio_ring {
  int16_t* buf;               /* (mask + 1) sample frames of RN_RING_MAX_CHANNELS values */
  uint32_t channels;          /* values per sample frame (rn_ring_set_channels) */
  uint32_t mask;
  uint32_t prime, high_water;
  _Atomic uint32_t write_pos; /* producer-owned */
  _Atomic uint32_t read_pos;  /* consumer-owned */
  _Atomic int muted;
  int primed;                 /* consumer-only */
  _Atomic uint64_t underruns, dropped, pulled;
  _Atomic uint32_t last_request;
};

rn_audio_ring* rn_ring_create(uint32_t capacity, uint32_t prime, uint32_t high_water) {
  uint32_t cap = 1;
  while (cap < capacity) cap <<= 1;
  rn_audio_ring* r = (rn_audio_ring*)calloc(1, sizeof(rn_audio_ring));
  if (!r) return NULL;
  r->buf = (int16_t*)calloc((size_t)cap * RN_RING_MAX_CHANNELS, sizeof(int16_t));
  r->channels = 1;
  if (!r->buf) { free(r); return NULL; }
  r->mask = cap - 1;
  r->prime = prime < cap ? prime : cap / 2;
  r->high_water = high_water < cap ? high_water : cap - 1;
  if (r->high_water < r->prime) r->high_water = r->prime;
  atomic_init(&r->muted, 1);
  return r;
}

void rn_ring_destroy(rn_audio_ring* r) {
  if (!r) return;
  free(r->buf);
  free(r);
}

void rn_ring_set_channels(rn_audio_ring* r, uint32_t channels) {
  if (channels < 1) channels = 1;
  if (channels > RN_RING_MAX_CHANNELS) channels = RN_RING_MAX_CHANNELS;
  r->channels = channels;
  atomic_store_explicit(&r->read_pos, atomic_load_explicit(&r->write_pos, memory_order_acquire), memory_order_release);
  r->primed = 0;
}

uint32_t rn_ring_channels(const rn_audio_ring* r) { return r->channels; }

uint32_t rn_ring_push(rn_audio_ring* r, const int16_t* s, uint32_t n) {
  uint32_t w = atomic_load_explicit(&r->write_pos, memory_order_relaxed);
  uint32_t rd = atomic_load_explicit(&r->read_pos, memory_order_acquire);
  uint32_t space = (r->mask + 1) - (w - rd);
  uint32_t take = n < space ? n : space;
  const uint32_t ch = r->channels;
  for (uint32_t i = 0; i < take; ++i)
    memcpy(r->buf + (size_t)((w + i) & r->mask) * RN_RING_MAX_CHANNELS, s + (size_t)i * ch, ch * sizeof(int16_t));
  atomic_store_explicit(&r->write_pos, w + take, memory_order_release);
  if (take < n) atomic_fetch_add_explicit(&r->dropped, n - take, memory_order_relaxed);
  return take;
}

void rn_ring_pull(rn_audio_ring* r, float* out, uint32_t n) { rn_ring_pull_channels(r, &out, 1, n); }

void rn_ring_pull_channels(rn_audio_ring* r, float* const* outs, uint32_t nout, uint32_t n) {
  atomic_store_explicit(&r->last_request, n, memory_order_relaxed);
  uint32_t w = atomic_load_explicit(&r->write_pos, memory_order_acquire);
  uint32_t rd = atomic_load_explicit(&r->read_pos, memory_order_relaxed);
  if (atomic_load_explicit(&r->muted, memory_order_acquire)) {
    atomic_store_explicit(&r->read_pos, w, memory_order_release); /* flush */
    r->primed = 0;
    for (uint32_t c = 0; c < nout; ++c) memset(outs[c], 0, sizeof(float) * n);
    return;
  }
  uint32_t fill = w - rd;
  if (!r->primed) {
    if (fill < r->prime) { for (uint32_t c = 0; c < nout; ++c) memset(outs[c], 0, sizeof(float) * n); return; }
    r->primed = 1;
  }
  if (fill > r->high_water) {
    uint32_t skip = fill - r->prime;
    rd += skip;
    fill -= skip;
    atomic_fetch_add_explicit(&r->dropped, skip, memory_order_relaxed);
  }
  uint32_t take = fill < n ? fill : n;
  /* Output channel c takes the ring's channel c (the last one when the ring has fewer: mono to both). */
  const uint32_t ch = r->channels;
  for (uint32_t c = 0; c < nout; ++c) {
    const uint32_t src = c < ch ? c : ch - 1;
    float* out = outs[c];
    for (uint32_t i = 0; i < take; ++i)
      out[i] = (float)r->buf[(size_t)((rd + i) & r->mask) * RN_RING_MAX_CHANNELS + src] * (1.0f / 32768.0f);
    if (take < n) memset(out + take, 0, sizeof(float) * (n - take));
  }
  if (take < n) {
    atomic_fetch_add_explicit(&r->underruns, 1, memory_order_relaxed);
    r->primed = 0;
  }
  atomic_fetch_add_explicit(&r->pulled, take, memory_order_relaxed);
  atomic_store_explicit(&r->read_pos, rd + take, memory_order_release);
}

void rn_ring_set_muted(rn_audio_ring* r, int muted) {
  atomic_store_explicit(&r->muted, muted ? 1 : 0, memory_order_release);
}

int rn_ring_is_muted(const rn_audio_ring* r) {
  return atomic_load_explicit((_Atomic int*)&r->muted, memory_order_acquire);
}

void rn_ring_get_stats(const rn_audio_ring* r, rn_audio_ring_stats* o) {
  rn_audio_ring* m = (rn_audio_ring*)r;
  uint32_t w = atomic_load_explicit(&m->write_pos, memory_order_acquire);
  uint32_t rd = atomic_load_explicit(&m->read_pos, memory_order_acquire);
  o->underruns = atomic_load_explicit(&m->underruns, memory_order_relaxed);
  o->dropped_samples = atomic_load_explicit(&m->dropped, memory_order_relaxed);
  o->pulled_samples = atomic_load_explicit(&m->pulled, memory_order_relaxed);
  o->fill = w - rd;
  o->last_request = atomic_load_explicit(&m->last_request, memory_order_relaxed);
}
