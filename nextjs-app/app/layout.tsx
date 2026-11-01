import type { Metadata } from "next";
import { Fredoka, Bebas_Neue } from "next/font/google";
import "./globals.css";

// Matches the Flutter app's GoogleFonts.fredokaTextTheme (body copy) and the
// Bebas Neue headings used across screens like Explore Ideas — see
// lib/core/theme/app_theme.dart and lib/screens/explore/explore_ideas_screen.dart.
const fredoka = Fredoka({
  variable: "--font-fredoka",
  subsets: ["latin"],
});

const bebasNeue = Bebas_Neue({
  variable: "--font-bebas-neue",
  weight: "400",
  subsets: ["latin"],
});

export const metadata: Metadata = {
  title: "ExploriFe",
  description: "ExploriFe — trip planning and local discovery.",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${fredoka.variable} ${bebasNeue.variable} h-full antialiased`}
    >
      <body className="bg-bg text-ink flex min-h-full flex-col font-sans">
        {children}
      </body>
    </html>
  );
}
