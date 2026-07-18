import type { Metadata, Viewport } from "next";
import "./globals.css";

const siteURL = process.env.NEXT_PUBLIC_SITE_URL;

if (!siteURL) {
  throw new Error("NEXT_PUBLIC_SITE_URL is required");
}

export const metadata: Metadata = {
  metadataBase: new URL(siteURL),
  title: {
    default: "Desk Setup Switcher — Capture, review, and apply your desk settings",
    template: "%s · Desk Setup Switcher",
  },
  description:
    "A local-only open-source macOS menu-bar app for deliberately capturing, editing, reviewing, and applying display, audio, and network profiles.",
  applicationName: "Desk Setup Switcher",
  keywords: [
    "macOS",
    "menu bar app",
    "display profiles",
    "audio profiles",
    "network profiles",
    "open source",
  ],
  authors: [{ name: "GGULBAE", url: "https://github.com/GGULBAE" }],
  creator: "GGULBAE",
  icons: {
    icon: "/app-icon.svg",
    shortcut: "/app-icon.svg",
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    alternateLocale: "ko_KR",
    title: "Desk Setup Switcher — Bring your desk back, deliberately.",
    description:
      "Capture → Edit → Review & Apply. Local-only macOS profiles with explicit change and rollback boundaries.",
    siteName: "Desk Setup Switcher",
    images: [
      {
        url: "/og.png",
        width: 1280,
        height: 640,
        alt: "Desk Setup Switcher icon and synthetic Display profile editor beside the Capture, Edit, Review & Apply flow.",
      },
    ],
  },
  twitter: {
    card: "summary_large_image",
    title: "Desk Setup Switcher — Bring your desk back, deliberately.",
    description:
      "Capture → Edit → Review & Apply. Local-only macOS profiles with explicit change and rollback boundaries.",
    images: ["/og.png"],
  },
};

export const viewport: Viewport = {
  colorScheme: "light",
  themeColor: "#f3f1eb",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
