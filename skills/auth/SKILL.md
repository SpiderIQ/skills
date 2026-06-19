---
name: auth
version: 1.0.0
description: Authenticate with the platform and manage user sessions.
client: auth
client_version: "1.0.0"
category: auth
triggers:
  - /auth
  - /login
  - log in
  - sign in
  - authenticate
  - switch brand
requires_auth: false
requires_brand: false
---

# Authentication & Session Management

Manage user authentication, profile, brand membership, and OAuth connections.

## Context

The platform is multi-tenant:
- Users can belong to multiple **brands** (organizations)
- Each brand has its own campaigns, leads, and team
- Users must select an active brand to work with
- Sessions persist for 7 days, scoped by channel + user_id

## Decision Guidance

### Authentication Flow

1. **Check existing session** -- always verify before asking for credentials. If the user has a valid session, skip login.
2. **Handle brand selection** -- if the user belongs to multiple brands, present a numbered list and let them choose. If only one brand, select it automatically.
3. **Brand switching** -- authenticated users can switch brands without re-entering credentials.

### Signup Paths

| Scenario | Method | What Happens |
|----------|--------|-------------|
| New user, no invite | `completeSignup` | Creates user profile + new brand + membership |
| New user, has invite | `signupWithInvite` | Creates user profile + adds to inviting brand |
| Existing user, has invite | `acceptInvite` | Adds user to inviting brand (no re-auth needed) |

### Profile Management

- `updateProfile` supports partial updates (first name, last name, mobile)
- `uploadProfilePhoto` accepts PNG/JPG/GIF up to 5MB, auto-resizes to 256x256
- `removeProfilePhoto` cleans up the R2 file

### OAuth Connectors

`getConnectors` shows linked social logins (GitHub, Google, etc.). Excludes email/password credential entries.

## Security Rules

- **Never** log, display, or store passwords
- **Never** display auth tokens to users
- Tokens are stored encrypted in Redis with 7-day expiry
- Sessions are scoped by channel + user_id -- no cross-user access possible
- Session data is isolated per brand

## Anti-Patterns

- Do not ask for credentials when a valid session already exists
- Do not attempt to access brand data before brand selection is complete
- Do not store or cache passwords in any form
- Do not show raw session tokens or API keys to users

## Error Handling

| Scenario | Response |
|----------|----------|
| Invalid credentials | "Invalid email or password. Try again or reset your password." |
| Session expired | "Your session has expired. Please log in again." |
| No brand access | Show available brands and ask user to select one |
| Account has no brands | Direct user to create a brand or contact their admin |
| Multiple failed attempts | Suggest password reset after 3 failures |

## Available Methods

| Method | Description |
|--------|-------------|
| `getMe` | Get current user's profile including all brand memberships |
| `completeSignup` | Complete signup by creating user profile, brand, and membership |
| `signupWithInvite` | Complete signup using an invitation token |
| `acceptInvite` | Accept a brand invitation as an existing user |
| `updateProfile` | Update current user's profile (first name, last name, mobile) |
| `uploadProfilePhoto` | Upload a profile picture (PNG/JPG/GIF, max 5MB) |
| `removeProfilePhoto` | Remove the current user's profile picture |
| `getConnectors` | List connected OAuth providers for the current user |
