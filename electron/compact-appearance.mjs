export const defaultCompactAppearance = { opacity: 70, blurRadius: 20 };

// Migrate the previous transparency/material settings without changing the saved file.
export function normalizeCompactAppearance(value) {
  const opacity =
    value?.opacity ??
    (Number.isInteger(value?.transparency) ? 100 - value.transparency : 70);
  const blurRadius = value?.blurRadius ?? (value?.material === "off" ? 0 : 20);
  return {
    opacity:
      Number.isInteger(opacity) && opacity >= 0 && opacity <= 100
        ? opacity
        : 70,
    blurRadius:
      Number.isInteger(blurRadius) && blurRadius >= 0 && blurRadius <= 80
        ? blurRadius
        : 20,
  };
}
