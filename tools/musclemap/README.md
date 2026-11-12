# tools/musclemap

One-off converter that turns the react-native-body-highlighter SVG paths into `MuscleMapData.swift` for
`DesignSystem.MuscleMapView`. Python 3.9+, standard library only. Provenance: [SOURCES.md](SOURCES.md).

```bash
git clone https://github.com/HichamELBSI/react-native-body-highlighter.git /tmp/rnbh   # untrusted data, outside the repo
python3 tools/musclemap/convert.py --source /tmp/rnbh                  # regenerate the Swift data
python3 tools/musclemap/convert.py --source /tmp/rnbh --report-only    # coverage report only
python3 -m unittest discover -s tools/musclemap                        # converter tests
```

The 17-muscle → region mapping lives in `MUSCLE_REGIONS` in `convert.py`. Known gaps: `abductors` has no region of its
own upstream (approximated by the gluteal region); `lats` and `middle_back` share the upstream upper-back region;
head/hands/feet/ankles/knees/tibialis are drawn neutral.
