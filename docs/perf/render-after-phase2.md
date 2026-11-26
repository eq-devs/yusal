# 2D and 3D paint, before and after (host)

`flutter test` on the M-series Mac (JIT, test font, painted into a
`PictureRecorder`): Dart-side cost only. Same probe and plans both times
(typical: 9 rooms and 36 furniture on the floor; large: 36 rooms, 84 wall
segments, 144 furniture). Read as ratios; nothing here was run on a phone.

| ms per paint / frame build | typical before | typical after | large before | large after |
| --- | --- | --- | --- | --- |
| 2D plan, fixed zoom | 0.9 | 1.1 | 1.8 | 1.7 |
| 2D plan, zoom changing every frame | 3.4 | 1.2 | 5.6 | 2.4 |
| GPU frame build | 1.5 | 1.2 | 2.1 | 1.5 |
| GPU translucent batches | 28 | 1 | 0 | 0 |
| GPU vertex bytes allocated per frame | 2.69 MB | 0.92 MB | 1.57 MB | 1.57 MB |

Not in the table, because a probe cannot show it: during a drag the 2D plan
now repaints only its overlay (drafts, handles, guides) unless the plan
itself changed, and the 3D view no longer repaints when the editor around
it rebuilds.
