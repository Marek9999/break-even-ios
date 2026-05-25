import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy Policy",
  description: "Privacy Policy for PayUp.",
  alternates: {
    canonical: "/privacy",
  },
};

const sections = [
  {
    title: "Information We Collect",
    body: [
      "Account and profile information, such as your name, email address, phone number, username, avatar, default currency, and authentication identifiers.",
      "Friend and invitation information, such as names, email addresses, phone numbers, invite status, and friend relationships that you create or accept.",
      "Expense information, such as transaction titles, amounts, currencies, descriptions, who paid, participants, split methods, item assignments, settlement records, notes, edit history, and activity feed events.",
      "Receipt information, such as receipt photos you upload or scan and extracted details like merchant names, line items, taxes, tips, totals, and currencies.",
      "Device and notification information, such as device identifiers, Apple Push Notification service tokens, notification preferences, platform, and authorization status.",
    ],
  },
  {
    title: "How We Use Information",
    body: [
      "To provide PayUp's core features, including account setup, friend management, receipt scanning, split creation, balance tracking, settlement records, activity updates, and push notifications.",
      "To sync your data across the app, keep shared expenses visible to the people involved, and help you recover or manage your account.",
      "To maintain, secure, debug, and improve the app and its backend services.",
    ],
  },
  {
    title: "Receipt Scanning and AI Processing",
    body: [
      "When you scan or upload a receipt, PayUp may send the image and related receipt content to Google Gemini so the app can extract structured receipt details. You should only upload receipts you are comfortable sharing for this purpose.",
      "Receipt images and extracted receipt data may also be stored with PayUp's backend provider so they can be attached to your expense records.",
    ],
  },
  {
    title: "How Information Is Shared",
    body: [
      "Expense, split, settlement, invitation, and activity information may be visible to the users who are part of the related friend, invite, or transaction context.",
      "We use service providers to operate PayUp, including Clerk for authentication, Convex for backend database, file storage, and sync, Google Gemini for receipt analysis, ExchangeRate-API for currency exchange rates, Apple Sign in and Google Sign in for login, and Apple Push Notification service for notifications.",
      "We may disclose information if required by law, to protect PayUp or its users, or to respond to valid legal requests.",
    ],
  },
  {
    title: "What We Do Not Do",
    body: [
      "We do not sell your personal information.",
      "We do not use your personal information for third-party advertising.",
      "We do not track you across apps or websites owned by other companies.",
      "PayUp does not process payments, move money, or provide banking services.",
    ],
  },
  {
    title: "Your Choices",
    body: [
      "You can choose whether to enable push notifications in iOS and in PayUp.",
      "You can choose whether to scan or upload receipt photos.",
      "You can contact us to request access, correction, deletion, or other help with your PayUp data.",
    ],
  },
  {
    title: "Data Retention",
    body: [
      "We keep information for as long as needed to provide PayUp, maintain shared expense records, comply with legal obligations, resolve disputes, and enforce our terms. Shared expense records may remain visible to other participants when needed to preserve their records.",
    ],
  },
  {
    title: "Children's Privacy",
    body: [
      "PayUp is not intended for children under 13. If you believe a child has provided personal information to PayUp, contact us and we will review the request.",
    ],
  },
  {
    title: "Changes to This Policy",
    body: [
      "We may update this Privacy Policy from time to time. If we make changes, we will update the effective date on this page.",
    ],
  },
  {
    title: "Contact",
    body: [
      "For privacy questions or requests, contact PayUp at createplus.club@gmail.com.",
    ],
  },
];

export default function PrivacyPolicy() {
  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-12 sm:py-16">
      <Link className="text-sm font-medium hover:underline" href="/">
        Back to PayUp
      </Link>

      <header className="mt-10 space-y-4">
        <p className="text-sm text-zinc-500 dark:text-zinc-400">
          Effective date: May 24, 2026
        </p>
        <h1 className="text-4xl font-semibold tracking-tight text-zinc-950 dark:text-zinc-50">
          Privacy Policy
        </h1>
        <p className="text-base leading-7 text-zinc-600 dark:text-zinc-300">
          This Privacy Policy explains how PayUp collects, uses, and shares
          information when you use the PayUp iOS app and website.
        </p>
      </header>

      <div className="mt-10 space-y-10">
        {sections.map((section) => (
          <section className="space-y-4" key={section.title}>
            <h2 className="text-2xl font-semibold tracking-tight">
              {section.title}
            </h2>
            <div className="space-y-3 text-base leading-7 text-zinc-700 dark:text-zinc-300">
              {section.body.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
            </div>
          </section>
        ))}
      </div>
    </main>
  );
}
