import { v } from "convex/values";
import {
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import { requireAuthenticatedUser } from "./lib/auth";

const authorizationStatusValidator = v.union(
  v.literal("notDetermined"),
  v.literal("denied"),
  v.literal("authorized"),
  v.literal("provisional"),
  v.literal("ephemeral")
);

const deviceSettingsValidator = v.object({
  deviceId: v.string(),
  apnsToken: v.optional(v.string()),
  notificationsEnabled: v.boolean(),
  authorizationStatus: authorizationStatusValidator,
  platform: v.string(),
  sessionActive: v.boolean(),
  updatedAt: v.number(),
});

async function removeDuplicateTokens(
  ctx: {
    db: {
      query: (table: "notificationDevices") => any;
      patch: (id: Id<"notificationDevices">, value: Record<string, unknown>) => Promise<void>;
    };
  },
  apnsToken: string,
  keepDeviceId: string
) {
  const devices = await ctx.db
    .query("notificationDevices")
    .withIndex("by_token", (q: any) => q.eq("apnsToken", apnsToken))
    .collect();

  for (const device of devices) {
    if (device.deviceId === keepDeviceId) continue;
    await ctx.db.patch(device._id, {
      apnsToken: undefined,
      updatedAt: Date.now(),
    });
  }
}

export const getCurrentDeviceSettings = query({
  args: {
    clerkId: v.string(),
    deviceId: v.string(),
  },
  returns: v.union(deviceSettingsValidator, v.null()),
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const device = await ctx.db
      .query("notificationDevices")
      .withIndex("by_user_deviceId", (q) =>
        q.eq("userId", user._id).eq("deviceId", args.deviceId)
      )
      .unique();

    if (!device) {
      return null;
    }

    return {
      deviceId: device.deviceId,
      apnsToken: device.apnsToken,
      notificationsEnabled: device.notificationsEnabled,
      authorizationStatus: device.authorizationStatus,
      platform: device.platform,
      sessionActive: device.sessionActive,
      updatedAt: device.updatedAt,
    };
  },
});

export const upsertCurrentDevice = mutation({
  args: {
    clerkId: v.string(),
    deviceId: v.string(),
    apnsToken: v.optional(v.string()),
    notificationsEnabled: v.boolean(),
    authorizationStatus: authorizationStatusValidator,
    platform: v.string(),
  },
  returns: deviceSettingsValidator,
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);
    const now = Date.now();

    if (args.apnsToken) {
      await removeDuplicateTokens(ctx, args.apnsToken, args.deviceId);
    }

    const existingDevice = await ctx.db
      .query("notificationDevices")
      .withIndex("by_deviceId", (q) => q.eq("deviceId", args.deviceId))
      .unique();

    if (existingDevice) {
      await ctx.db.patch(existingDevice._id, {
        userId: user._id,
        clerkId: user.clerkId,
        apnsToken: args.apnsToken ?? existingDevice.apnsToken,
        notificationsEnabled: args.notificationsEnabled,
        authorizationStatus: args.authorizationStatus,
        platform: args.platform,
        sessionActive: true,
        updatedAt: now,
      });

      return {
        deviceId: args.deviceId,
        apnsToken: args.apnsToken ?? existingDevice.apnsToken,
        notificationsEnabled: args.notificationsEnabled,
        authorizationStatus: args.authorizationStatus,
        platform: args.platform,
        sessionActive: true,
        updatedAt: now,
      };
    }

    await ctx.db.insert("notificationDevices", {
      userId: user._id,
      clerkId: user.clerkId,
      deviceId: args.deviceId,
      apnsToken: args.apnsToken,
      notificationsEnabled: args.notificationsEnabled,
      authorizationStatus: args.authorizationStatus,
      platform: args.platform,
      sessionActive: true,
      createdAt: now,
      updatedAt: now,
    });

    return {
      deviceId: args.deviceId,
      apnsToken: args.apnsToken,
      notificationsEnabled: args.notificationsEnabled,
      authorizationStatus: args.authorizationStatus,
      platform: args.platform,
      sessionActive: true,
      updatedAt: now,
    };
  },
});

export const markCurrentDeviceSignedOut = mutation({
  args: {
    clerkId: v.string(),
    deviceId: v.string(),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const user = await requireAuthenticatedUser(ctx, args.clerkId);

    const existingDevice = await ctx.db
      .query("notificationDevices")
      .withIndex("by_user_deviceId", (q) =>
        q.eq("userId", user._id).eq("deviceId", args.deviceId)
      )
      .unique();

    if (!existingDevice) {
      return false;
    }

    await ctx.db.patch(existingDevice._id, {
      sessionActive: false,
      updatedAt: Date.now(),
    });

    return true;
  },
});

export const listActiveNotificationDevicesForUser = internalQuery({
  args: {
    userId: v.id("users"),
  },
  returns: v.array(
    v.object({
      deviceId: v.string(),
      apnsToken: v.string(),
    })
  ),
  handler: async (ctx, args) => {
    const devices = await ctx.db
      .query("notificationDevices")
      .withIndex("by_user_notificationsEnabled", (q) =>
        q.eq("userId", args.userId).eq("notificationsEnabled", true)
      )
      .collect();

    return devices
      .filter((device) =>
        device.sessionActive &&
        device.authorizationStatus !== "denied" &&
        device.authorizationStatus !== "notDetermined" &&
        !!device.apnsToken
      )
      .map((device) => ({
        deviceId: device.deviceId,
        apnsToken: device.apnsToken!,
      }));
  },
});

export const clearDeviceToken = internalMutation({
  args: {
    apnsToken: v.string(),
  },
  returns: v.boolean(),
  handler: async (ctx, args) => {
    const devices = await ctx.db
      .query("notificationDevices")
      .withIndex("by_token", (q) => q.eq("apnsToken", args.apnsToken))
      .collect();

    for (const device of devices) {
      await ctx.db.patch(device._id, {
        apnsToken: undefined,
        updatedAt: Date.now(),
      });
    }

    return devices.length > 0;
  },
});
