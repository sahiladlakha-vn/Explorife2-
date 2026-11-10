import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * Merge Tailwind class lists safely — `clsx` handles conditional
 * classes/arrays, `twMerge` resolves conflicting utility classes (e.g.
 * `"p-2"` + `"p-4"` -> `"p-4"`) so later classes reliably win. Standard
 * helper for any component that accepts a `className` override prop.
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
