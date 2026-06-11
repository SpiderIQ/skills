---
name: upload-host-media
version: 1.0.0
description: Upload images and videos to SpiderMedia (SeaweedFS + PeerTube) for hosted CDN delivery with per-client isolated storage.
client: upload-host-media
client_version: "1.0.0"
category: media
triggers:
  - upload image
  - host video
  - upload file
  - media storage
  - import video
  - list media files
  - storage stats
requires_auth: false
requires_brand: false
metadata:
  openclaw:
    emoji: "\U0001F4E4"
    primaryEnv: OPVS_PAT
---

# Upload & Host Media — SpiderMedia Storage

**PREREQUISITE:** Read `../opvs-foundation/SKILL.md` first.

## Purpose

Upload images, files, and videos to SpiderMedia for hosted CDN delivery. Each brand gets an isolated storage bucket (SeaweedFS) and video channel (PeerTube). Files are accessible via public CDN URLs at `media.spideriq.ai`.

## When to Use

- User wants to upload an image or file for hosting
- User needs to import a video from URL for processing and hosting
- User wants to list or manage stored media files
- User needs storage usage statistics

## Decision Guidance

### Choosing the Right Upload Method

- **Multipart upload** (`uploadImage` / `uploadFile`): Use when you have a file on disk. Preferred for direct user uploads.
- **Base64 upload** (`uploadBase64`): Use when file data comes from an automation pipeline or API response that lacks multipart support. Slightly less efficient due to encoding overhead.

### Video Privacy Levels

- **1 = Public**: Visible to anyone with the link. Use for marketing content, social media embeds.
- **2 = Unlisted** (default): Not discoverable but accessible via direct URL. Use for client previews, internal sharing.
- **3 = Private**: Only accessible with authentication. Use for sensitive or draft content.

### Video Processing States

Videos are processed asynchronously: `importing` -> `transcoding` -> `ready`. When ready, the response includes `file_url` (direct .mp4) and `download_url`. Poll status periodically after import.

## Anti-Patterns

- Do not upload files larger than 100MB -- the request will be rejected
- Do not poll video status more frequently than every 15 seconds
- Do not assume video is ready immediately after import -- always check status first
- Do not construct CDN URLs manually -- always use the URL returned by the upload response

## Response Guidelines

- After upload, always show the public CDN URL to the user
- For video imports, inform user of expected processing time and offer to check status
- Show storage stats in human-readable format (MB/GB)
- Public URL pattern: `https://media.spideriq.ai/{bucket_name}/{key}`

## Available Methods

| Method | Description |
|--------|-------------|
| `uploadImage` | Upload an image file via multipart form data |
| `uploadFile` | Upload a generic file via multipart form data |
| `uploadBase64` | Upload a file encoded as base64 (for programmatic uploads) |
| `listFiles` | List all uploaded files for the current brand |
| `importVideo` | Import a video from an external URL for hosting |
| `getVideoStatus` | Check the processing status of an imported video |
