"use node";

import { internal } from "./_generated/api";
import { internalAction } from "./_generated/server";
import { v } from "convex/values";
import { createPrivateKey, sign as signPayload } from "node:crypto";
import { connect } from "node:http2";

const pushResultValidator = v.object({
  sentCount: v.number(),
  skippedCount: v.number(),
});

type ActivityPushArgs = {
  userId: string;
  activityId: string;
  activityType: string;
  message: string;
  transactionId?: string;
  friendId?: string;
  invitationId?: string;
  settlementId?: string;
};

type APNsResponse = {
  status: number;
  body: string;
};

let cachedProviderToken: { token: string; issuedAt: number } | null = null;

function base64urlEncode(input: string | Buffer) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function normalizePrivateKey(privateKey: string) {
  return privateKey.includes("\\n") ? privateKey.replace(/\\n/g, "\n") : privateKey;
}

function getProviderToken(teamId: string, keyId: string, privateKey: string) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (cachedProviderToken && (nowSeconds - cachedProviderToken.issuedAt) < 50 * 60) {
    return cachedProviderToken.token;
  }

  const header = base64urlEncode(JSON.stringify({
    alg: "ES256",
    kid: keyId,
  }));
  const claims = base64urlEncode(JSON.stringify({
    iss: teamId,
    iat: nowSeconds,
  }));
  const unsignedToken = `${header}.${claims}`;

  const signer = signPayload(
    "sha256",
    Buffer.from(unsignedToken),
    createPrivateKey(normalizePrivateKey(privateKey))
  );
  const signature = base64urlEncode(signer);
  const token = `${unsignedToken}.${signature}`;

  cachedProviderToken = {
    token,
    issuedAt: nowSeconds,
  };
  return token;
}

function routeForActivity(args: ActivityPushArgs) {
  if (args.activityType === "split_created" || args.activityType === "split_edited") {
    if (args.transactionId) {
      return {
        destination: "transaction",
        transactionId: args.transactionId,
      };
    }
  }

  if (
    args.activityType === "invitation_received" ||
    args.activityType === "invitation_accepted" ||
    args.activityType === "invitation_rejected" ||
    args.activityType === "invitation_cancelled" ||
    args.activityType === "friend_removed"
  ) {
    return {
      destination: "friends",
      friendId: args.friendId,
      invitationId: args.invitationId,
    };
  }

  return {
    destination: "activity",
  };
}

async function sendToAPNs(
  host: string,
  token: string,
  bundleId: string,
  providerToken: string,
  payload: Record<string, unknown>
): Promise<APNsResponse> {
  const client = connect(host);

  return await new Promise((resolve, reject) => {
    client.on("error", reject);

    const request = client.request({
      ":method": "POST",
      ":path": `/3/device/${token}`,
      authorization: `bearer ${providerToken}`,
      "apns-topic": bundleId,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
    });

    let status = 0;
    let body = "";

    request.setEncoding("utf8");
    request.on("response", (headers) => {
      const rawStatus = headers[":status"];
      if (typeof rawStatus === "number") {
        status = rawStatus;
      }
    });
    request.on("data", (chunk) => {
      body += chunk;
    });
    request.on("end", () => {
      client.close();
      resolve({ status, body });
    });
    request.on("error", (error) => {
      client.close();
      reject(error);
    });

    request.end(JSON.stringify(payload));
  });
}

function shouldClearToken(response: APNsResponse) {
  if (response.status === 410) {
    return true;
  }

  if (!response.body) {
    return false;
  }

  try {
    const parsed = JSON.parse(response.body) as { reason?: string };
    return parsed.reason === "BadDeviceToken" || parsed.reason === "Unregistered";
  } catch {
    return false;
  }
}

export const sendActivityPush = internalAction({
  args: {
    userId: v.id("users"),
    activityId: v.id("activities"),
    activityType: v.string(),
    message: v.string(),
    transactionId: v.optional(v.id("transactions")),
    friendId: v.optional(v.id("friends")),
    invitationId: v.optional(v.id("invitations")),
    settlementId: v.optional(v.id("settlements")),
  },
  returns: pushResultValidator,
  handler: async (ctx, args) => {
    const teamId = process.env.APNS_TEAM_ID;
    const keyId = process.env.APNS_KEY_ID;
    const privateKey = process.env.APNS_PRIVATE_KEY;
    const bundleId = process.env.APNS_BUNDLE_ID;
    const useSandbox = process.env.APNS_USE_SANDBOX === "true";

    if (!teamId || !keyId || !privateKey || !bundleId) {
      console.warn("APNs configuration is incomplete; skipping activity push delivery.");
      return { sentCount: 0, skippedCount: 1 };
    }

    const devices = await ctx.runQuery(
      (internal as any).notificationDevices.listActiveNotificationDevicesForUser,
      { userId: args.userId }
    ) as Array<{ deviceId: string; apnsToken: string }>;

    if (devices.length === 0) {
      return { sentCount: 0, skippedCount: 0 };
    }

    const providerToken = getProviderToken(teamId, keyId, privateKey);
    const route = routeForActivity({
      userId: args.userId,
      activityId: args.activityId,
      activityType: args.activityType,
      message: args.message,
      transactionId: args.transactionId,
      friendId: args.friendId,
      invitationId: args.invitationId,
      settlementId: args.settlementId,
    });

    const host = useSandbox
      ? "https://api.sandbox.push.apple.com"
      : "https://api.push.apple.com";

    let sentCount = 0;
    let skippedCount = 0;

    for (const device of devices) {
      const payload = {
        aps: {
          alert: {
            title: "Break Even",
            body: args.message,
          },
          sound: "default",
        },
        activityId: args.activityId,
        activityType: args.activityType,
        destination: route.destination,
        transactionId: args.transactionId,
        friendId: args.friendId,
        invitationId: args.invitationId,
        settlementId: args.settlementId,
      };

      try {
        const response = await sendToAPNs(
          host,
          device.apnsToken,
          bundleId,
          providerToken,
          payload
        );

        if (response.status >= 200 && response.status < 300) {
          sentCount += 1;
          continue;
        }

        console.warn(
          `APNs push failed for device ${device.deviceId}: ${response.status} ${response.body}`
        );
        skippedCount += 1;

        if (shouldClearToken(response)) {
          await ctx.runMutation(
            (internal as any).notificationDevices.clearDeviceToken,
            { apnsToken: device.apnsToken }
          );
        }
      } catch (error) {
        console.error(`APNs push request errored for device ${device.deviceId}:`, error);
        skippedCount += 1;
      }
    }

    return { sentCount, skippedCount };
  },
});
