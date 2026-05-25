import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";

const geistSans = Geist({
  variable: "--font-geist-sans",
  subsets: ["latin"],
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  metadataBase: new URL("https://payupsplits.app"),
  title: {
    default: "PayUp",
    template: "%s | PayUp",
  },
  description:
    "PayUp helps friends split bills, scan receipts, track balances, and record settlements.",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    title: "PayUp",
    description:
      "Split bills, scan receipts, track balances, and record settlements with friends.",
    url: "https://payupsplits.app",
    siteName: "PayUp",
    type: "website",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${geistSans.variable} ${geistMono.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
