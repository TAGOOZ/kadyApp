# Strict performance budget

Web initial load <1.5s on Fast 3G and Android APK <20MB. Chosen over a relaxed 3s/30MB budget to force deferred imports, image downscaling via `cached_network_image`, and tree-shaking discipline from day one. Consequence: `flutter build web --analyze-size` / `apk --analyze-size` must be checked before merge; Stitch placeholder images replaced with optimized Supabase Storage variants.
