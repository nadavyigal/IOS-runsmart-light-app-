# Native iOS privacy policy correction draft — 2026-10-17

**Publication status: DRAFT ONLY.** The current live `/privacy` page still describes browser-only IndexedDB storage and anonymous analytics. Replace those statements before submitting 1.1.9. This draft covers the verified native app; preserve accurate web-specific disclosures if this URL serves both products. The release owner must confirm provider retention, support contact ownership, and any additional web processing before publishing.

## Information handled by RunSmart for iOS

RunSmart handles account information, including your account identifier, email address, and name when provided by your sign-in provider. It handles running goals, preferences, training plans, completed activities, and messages you exchange with the coach. Outdoor run recording uses precise location to calculate and save your route, distance, and pace. Background location is used while a run is in progress, including when the phone is locked.

With your permission, RunSmart reads supported Apple Health workouts and wellness data to provide running, readiness, and training information. It writes completed runs to Apple Health only when you grant write access. Apple Health access is optional; you can change permissions in iOS Settings or Health.

## Storage and service providers

The native iOS app stores some information locally and uses authenticated backend services, including Supabase, to store and synchronize account information, training plans, activities, routes, and coach conversations. Clearing browser data does not delete your native app account or server-side records.

AI coaching and plan features send the relevant request and training context to RunSmart's backend and its AI service providers. Do not include information in coach messages that you do not want processed for this purpose. The release owner must verify the current provider list and retention terms before publishing specific promises about retention or model training.

## Usage analytics

RunSmart uses PostHog to understand app usage and reliability. Events include app version/build, screen and feature interactions, operational outcomes, and completed/abandoned-run statistics such as distance, duration, pace and run type. Do not claim analytics has no access to activity data. Once signed in, usage events can be associated with your RunSmart account identifier; this analytics is therefore not described as wholly anonymous. RunSmart's native privacy manifest declares no tracking for advertising across other companies' apps or websites.

## Controls and deletion

You can manage optional Apple Health and location access through iOS controls. The native app includes an account deletion control under Profile's account/settings area. Use account deletion to request removal through the backend; removing the app or clearing browser data alone does not delete server-side information. The release owner must confirm the deletion scope, any necessary retention exceptions, and request contact before publishing precise deletion deadlines.

## Garmin

New Garmin connections are currently unavailable in the native app. If historical Garmin data is retained, retain accurate disclosures describing that storage and deletion; do not promise a currently available connection flow.

## Contact

Use a monitored support address that the owner verifies. The public support page currently lists `support@runsmart-ai.com`; the current privacy page lists a different domain. Resolve that inconsistency before publication.
