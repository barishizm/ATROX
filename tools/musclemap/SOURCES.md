# Muscle map sources

## react-native-body-highlighter

- Repository: https://github.com/HichamELBSI/react-native-body-highlighter
- Pinned commit: `8ed39ac2ae9cb46fb79d77eedec7e5b029a75174` (package version 3.2.0)
- License: MIT, Copyright (c) 2022 ELABBASSI Hicham — upstream `LICENSE` verified by `convert.py` (it refuses to run otherwise)
- Accessed: 2026-11-12
- Used: male front/back region paths (`assets/bodyFront.ts`, `assets/bodyBack.ts`) and the silhouette outlines from
  `components/SvgMaleWrapper.tsx`. Female variants are not imported.
- Output: `ios/Packages/DesignSystem/Sources/DesignSystem/Components/MuscleMap/MuscleMapData.swift` (generated;
  re-run `convert.py`, never edit by hand). Paths are re-expressed as normalized absolute commands; shapes are unchanged.
- Attribution: listed on the in-app Licenses screen (`LicenseEntry.all`, `ios/App/Features/Profile/AboutView.swift`).

The MIT notice that must accompany the derived data:

> MIT License — Copyright (c) 2022 ELABBASSI Hicham
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated
> documentation files (the "Software"), to deal in the Software without restriction, including without limitation
> the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
> permit persons to whom the Software is furnished to do so, subject to the following conditions: The above copyright
> notice and this permission notice shall be included in all copies or substantial portions of the Software.
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
