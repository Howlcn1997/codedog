import { Code2 } from "lucide-react";
import {
  siGo,
  siJavascript,
  siNodedotjs,
  siOpenjdk,
  siPython,
  siRust,
  siTypescript,
  type SimpleIcon,
} from "simple-icons";

const icons: Record<string, SimpleIcon> = {
  go: siGo,
  java: siOpenjdk,
  javascript: siJavascript,
  "node.js": siNodedotjs,
  nodejs: siNodedotjs,
  python: siPython,
  rust: siRust,
  typescript: siTypescript,
};

export default function TechStackIcon({
  stack,
  size = 20,
}: {
  stack?: string;
  size?: number;
}) {
  const icon = stack ? icons[stack.toLocaleLowerCase()] : undefined;
  if (!icon) return <Code2 className="tech-stack-icon fallback" size={size} />;

  const neutral = icon.hex === "000000";
  return (
    <svg
      aria-hidden="true"
      className={`tech-stack-icon${neutral ? " neutral" : ""}`}
      viewBox="0 0 24 24"
      width={size}
      height={size}
      style={neutral ? undefined : { color: `#${icon.hex}` }}
    >
      <path d={icon.path} fill="currentColor" />
    </svg>
  );
}
