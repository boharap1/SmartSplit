import 'dart:math';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';

/// Plays brief in-app sound effects.
/// Tones are generated at runtime — no bundled asset file needed.
class SoundService {
  static final SoundService instance = SoundService._();
  SoundService._();

  AudioPlayer? _player;

  /// Plays a short, pleasant success ding. Fire-and-forget; never throws.
  Future<void> playSuccess() async {
    try {
      _player ??= AudioPlayer();
      await _player!.setVolume(0.35);
      await _player!.play(BytesSource(_buildSuccessWav()));
    } catch (_) {
      // Audio failure must never surface to the user.
    }
  }

  void dispose() {
    _player?.dispose();
    _player = null;
  }

  // ── PCM generation ─────────────────────────────────────────────────────────

  static Uint8List _buildSuccessWav() {
    const sampleRate  = 44100;
    const durationMs  = 220;
    const numSamples  = sampleRate * durationMs ~/ 1000; // 9702
    const frequency   = 988.0; // B5 — bright but not harsh

    final samples = Int16List(numSamples);
    for (var i = 0; i < numSamples; i++) {
      final t        = i / sampleRate;
      final attack   = i < 80 ? i / 80.0 : 1.0;           // ~1.8 ms ramp-up
      final decay    = exp(-6.0 * i / numSamples);          // exponential tail
      final sample   = sin(2 * pi * frequency * t) * attack * decay * 28000;
      samples[i]     = sample.round().clamp(-32768, 32767);
    }

    return _wrapWav(samples, sampleRate);
  }

  static Uint8List _wrapWav(Int16List samples, int sampleRate) {
    final pcm    = samples.buffer.asUint8List();
    final header = ByteData(44);

    void ascii(int off, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(off + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4,  36 + pcm.length, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16,              Endian.little); // fmt chunk size
    header.setUint16(20, 1,               Endian.little); // PCM
    header.setUint16(22, 1,               Endian.little); // mono
    header.setUint32(24, sampleRate,      Endian.little);
    header.setUint32(28, sampleRate * 2,  Endian.little); // byte rate
    header.setUint16(32, 2,               Endian.little); // block align
    header.setUint16(34, 16,              Endian.little); // bits per sample
    ascii(36, 'data');
    header.setUint32(40, pcm.length,      Endian.little);

    return Uint8List.fromList([...header.buffer.asUint8List(), ...pcm]);
  }
}
