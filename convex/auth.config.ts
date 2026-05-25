// Clerk authentication configuration for Convex.
// CLERK_JWT_ISSUER_DOMAIN must match the Clerk Frontend API URL for the target deployment.
import type { AuthConfig } from "convex/server";

export default {
  providers: [
    {
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN!,
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
