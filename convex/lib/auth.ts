import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { Doc, Id } from "../_generated/dataModel";

type PublicCtx = MutationCtx | QueryCtx;

export async function getAuthenticatedClerkId(ctx: PublicCtx): Promise<string> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    throw new Error("Not authenticated");
  }

  if (!identity.subject) {
    throw new Error("Authenticated identity is missing a Clerk subject");
  }

  return identity.subject;
}

export async function requireIdentity(
  ctx: PublicCtx,
  clerkId: string
) {
  const authenticatedClerkId = await getAuthenticatedClerkId(ctx);
  if (authenticatedClerkId !== clerkId) {
    throw new Error("Unauthorized");
  }

  return authenticatedClerkId;
}

export async function requireAuthenticatedUser(
  ctx: PublicCtx,
  clerkId?: string
): Promise<Doc<"users">> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    throw new Error("Not authenticated");
  }

  const resolvedClerkId = identity.subject;
  if (!resolvedClerkId) {
    throw new Error("Authenticated identity is missing a subject");
  }

  if (clerkId && identity.subject !== clerkId) {
    throw new Error("Unauthorized");
  }

  const user = await ctx.db
    .query("users")
    .withIndex("by_clerkId", (q) => q.eq("clerkId", resolvedClerkId))
    .unique();

  if (!user) {
    throw new Error("User not found");
  }

  return user;
}

export async function getAuthenticatedUser(
  ctx: PublicCtx,
  clerkId?: string
): Promise<Doc<"users">> {
  const authenticatedClerkId = clerkId
    ? await requireIdentity(ctx, clerkId)
    : await getAuthenticatedClerkId(ctx);

  const user = await ctx.db
    .query("users")
    .withIndex("by_clerkId", (q) => q.eq("clerkId", authenticatedClerkId))
    .unique();

  if (!user) {
    throw new Error("User not found");
  }

  return user;
}

export function requireOwner(
  ownerId: Id<"users">,
  currentUserId: Id<"users">,
  message = "Unauthorized"
) {
  if (ownerId.toString() !== currentUserId.toString()) {
    throw new Error(message);
  }
}

export function normalizeEmail(email: string | undefined): string | undefined {
  if (!email) {
    return undefined;
  }

  const normalized = email.trim().toLowerCase();
  return normalized.length > 0 ? normalized : undefined;
}

export function isSplitSelectableStatus(status: string): boolean {
  return (
    status === "accepted" ||
    status === "invite_sent" ||
    status === "none"
  );
}
