// Clerk authentication configuration for Convex
// The domain should match your Clerk application's issuer URL
import type { AuthConfig } from "convex/server";

export default {
  providers: [
    {
      // Clerk issuer domain - this should match your Clerk app's frontend API URL
      // Format: https://<your-clerk-frontend-api>.clerk.accounts.dev
      // You can find this in your Clerk Dashboard under Settings > API Keys
      domain: process.env.CLERK_JWT_ISSUER_DOMAIN || "https://inviting-pipefish-36.clerk.accounts.dev",
      applicationID: "convex",
    },
  ],
} satisfies AuthConfig;
