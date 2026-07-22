# App Store Login QA Checklist

Run this before every App Store / TestFlight release that touches auth, Convex sync, or onboarding. Do **not** rely only on an existing developer account.

## Builds

- [ ] Test the **Release** configuration (or TestFlight / App Store build), not only Debug.
- [ ] Confirm the build points at production Convex (`beaming-dinosaur-887.convex.cloud`).

## Fresh Apple account

1. Sign out of PayUp (or use a device/simulator with no prior PayUp session).
2. Create or use a **new** Apple ID that has never signed into PayUp.
3. Sign in with **Sign in with Apple**.
4. If prompted, choose **Hide My Email**.
5. Confirm:
   - [ ] No “Reconnecting” / “Couldn't Finish Setup” dead-end
   - [ ] Onboarding or home appears within a few seconds
   - [ ] Pull-to-refresh / relaunch still loads the same account

## Fresh Google account

1. Sign out of PayUp completely.
2. Use a **new** Google account that has never signed into PayUp.
3. Sign in with Google.
4. Confirm the same success criteria as Apple above.

## Existing account regression

- [ ] Your known production account still signs in and loads balances/history.
- [ ] Cold launch with a restored Clerk session still works (kill app → reopen).
- [ ] Foregrounding the app after backgrounding does not bounce to a setup-error screen.

## If login fails

1. Note the exact UI title/message (should be human-readable, not `UniFFI...`).
2. In Convex production dashboard → Logs, search around the failure time for `users:getOrCreateUser` / `users:getCurrentUser`.
3. Confirm `CLERK_JWT_ISSUER_DOMAIN` is still set on production.
4. Do not ship until a brand-new Apple and Google account can complete first login.
