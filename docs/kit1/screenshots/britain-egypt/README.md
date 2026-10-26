# Clipmap journey

Status: implemented; visual and smooth-transition acceptance remains open.

The movie contains actual rendered frames with their recorded timing. Frame intervals include capture overhead; frames after capture are marked in the plot. Noncapture intervals are an observation within this recording, not a separate clean benchmark.

All recorded frames: median 19.93 ms; p95 50.68 ms; maximum 420.61 ms.
Frames without preceding capture: median 19.20 ms; p95 28.12 ms; maximum 43.63 ms.

Capture readback + JPEG/keyframe save: median 25.68 ms; maximum 402.01 ms.

Cache plot reports tile payload accounting; driver allocations and shared scene resources are not represented by that number.
