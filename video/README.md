# Precis promo video

30-second, 16:9 Remotion composition for the Precis Mac app. The edit uses the app's paper, ink, and bottle-green palette and currently ends with “Coming soon to the Mac App Store.”

## Preview and render

```sh
npm install
npm run dev
npx remotion render src/index.ts PrecisPromo out/precis-promo.mp4 --codec h264
```

## Current shots

- Opening brand card with the Precis app icon.
- Desktop panel feature shot, using `public/assets/desktop-capture.png`.
- Newspaper PDF page, using `public/assets/newspaper.png`.
- Daily précis shot, using `public/assets/reader.png` as a temporary stand-in. Replace this with a screenshot showing the generated “Today’s Precis” digest for the finished cut.
- App Store “Coming soon” end card.

The composition and timing live in `src/Composition.tsx`. Captions are rendered as on-screen text so the video still works with sound off.
