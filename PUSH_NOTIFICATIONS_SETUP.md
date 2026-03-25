# Activity Push Notifications Setup

This app now includes APNs-based activity notifications, but Apple account and Xcode capability setup still need to be done manually before pushes can work on a real device.

## 1. Apple Developer Setup

1. Open [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Select the app identifier for `com.rudradsigns.break-even-ios`.
3. Enable the `Push Notifications` capability for that App ID.
4. Open the `Keys` section in Apple Developer.
5. Create a new key with `Apple Push Notifications service (APNs)` enabled.
6. Download the `.p8` file once and store it safely.
7. Record the following values:
   - `APNS_KEY_ID`
   - `APNS_TEAM_ID`
   - the contents of the downloaded `.p8` file for `APNS_PRIVATE_KEY`

## 2. Xcode Capability Setup

1. Open the app target in Xcode.
2. Go to `Signing & Capabilities`.
3. Add the `Push Notifications` capability.
4. For now, `Background Modes` is optional because this implementation uses standard alert pushes, not silent background processing.
5. Make sure the provisioning profile is refreshed after enabling the capability.

Note: the current project already has an entitlements file, but Xcode should be the source of truth for enabling the push capability and provisioning updates.

## 3. Convex Environment Variables

Set these values in your Convex environment:

- `APNS_TEAM_ID`
- `APNS_KEY_ID`
- `APNS_PRIVATE_KEY`
- `APNS_BUNDLE_ID`
- `APNS_USE_SANDBOX`

Recommended values:

- `APNS_BUNDLE_ID=com.rudradsigns.break-even-ios`
- `APNS_USE_SANDBOX=true` while testing debug builds on device

For `APNS_PRIVATE_KEY`, paste the full `.p8` key contents including the begin/end lines. If your secret UI escapes newlines, that is okay; the backend normalizes `\\n` into real line breaks.

## 4. Local Convex Development

If `npx convex dev` is already running, update the environment variables in the Convex dashboard or local environment and let the dev process pick them up. If needed, restart `npx convex dev` after changing the APNs secrets.

## 5. Real-Device Test Checklist

APNs requires a physical iPhone for real end-to-end testing.

1. Install the app on a physical device using a build signed with the push-enabled provisioning profile.
2. Sign in.
3. Open `Profile`.
4. Turn on `Activity Notifications`.
5. Accept the system notification permission prompt.
6. Trigger one of these backend activity events from another account/device or by using app flows:
   - create a split
   - edit a split
   - delete a split
   - send a friend invitation
   - accept or reject an invitation
   - remove a friend
7. Confirm the push appears.
8. Tap the push and verify routing:
   - split-created / split-edited should open the related split detail
   - invitation/friend notifications should open the friends area
   - non-deep-linkable activity should fall back to the Activity tab

## 6. Useful Debugging Notes

- If the toggle is on but no push arrives, confirm the device token exists in the `notificationDevices` table.
- If APNs rejects a token as `BadDeviceToken` or `Unregistered`, the backend now clears that stored token automatically.
- If notifications were enabled and the user signs out, the device is marked inactive for push delivery before sign-out so that signed-out devices stop receiving account activity pushes.
- Foreground notifications are configured to show as banners and play sound.

## 7. Expected Backend Records

The feature stores one row per app installation in the `notificationDevices` table. The important fields are:

- `deviceId`: stable install identifier generated on-device
- `apnsToken`: current APNs token
- `notificationsEnabled`: profile toggle state
- `authorizationStatus`: current iOS notification authorization state
- `sessionActive`: whether the signed-in account on this device should currently receive pushes

Push delivery is only attempted when all of these are true:

- the device row belongs to the target user
- `notificationsEnabled` is `true`
- `sessionActive` is `true`
- authorization is not denied or undetermined
- an `apnsToken` is present
