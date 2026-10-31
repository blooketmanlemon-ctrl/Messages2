# Chatly — full replacement package

This folder contains the complete website files and the Supabase SQL setup:

- `index.html` — Chatly web app
- `chatly-2.0-upgrade.sql` — database tables, policies, RPC, avatar bucket and realtime setup
- `sw.js` — service worker with a refreshed cache name
- `manifest.webmanifest` — installable web-app metadata
- `icon.svg` — app icon

## Before uploading

1. Keep a backup of your existing repository and Supabase database.
2. This frontend is configured with the Supabase project URL and browser publishable key currently present in `index.html`. Confirm these match your Supabase project before publishing.
3. Never put a Supabase `service_role` key in browser code or a public GitHub repository.

## Supabase setup

The SQL file is designed to be rerunnable and uses `IF NOT EXISTS` checks for its objects and policies. If you already ran an earlier Chatly migration, do not blindly rerun migrations that produced errors. Review the SQL Editor result first. Run this SQL in the same Supabase project used by Chatly.

The SQL expects an existing `public.profiles` table with at least an `id` column referencing the authenticated user's ID and a `username` column. It adds `display_name` and `avatar_url`. If your profile table has a different structure, stop and adjust the SQL before running it.

## GitHub Pages

Upload the files from this folder to the root of your GitHub repository, replacing the matching files. Keep any other project files you still need. In repository Settings → Pages, publish from the `main` branch and `/(root)`.

After publishing, do a hard refresh (Ctrl+Shift+R). If an old installed app still appears, close it and reopen the website.

## Notes

- Avatar images are stored in a public Supabase Storage bucket. Do not upload private photos.
- Messages are not end-to-end encrypted. Avoid sharing sensitive information.
- This is a basic direct-message app, not a full secure messaging service.
