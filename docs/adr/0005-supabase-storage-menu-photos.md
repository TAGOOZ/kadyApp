# Supabase Storage for menu photos

Menu item photos live in a public Supabase Storage bucket `menu-photos`; `menu_items.image_url` stores the public URL. Chosen over bundled assets and external CDNs. Owner uploads/updates photos via the Admin menu editor (#015) without rebuilding the app. Consequence: `lib/data/` reads `image_url` directly; no asset pipeline for menu content.
