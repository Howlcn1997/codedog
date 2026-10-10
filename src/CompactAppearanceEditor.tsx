import type { CSSProperties } from "react";
import {
  Search,
  MoreHorizontal,
  Code2,
  Terminal,
  FolderOpen,
} from "lucide-react";
import type { CompactAppearance } from "./types";

export default function CompactAppearanceEditor({
  value,
  disabled,
  blurError,
  onChange,
}: {
  value: CompactAppearance;
  disabled: boolean;
  blurError?: string;
  onChange: (value: CompactAppearance) => void;
}) {
  return (
    <div className="appearance-editor">
      {blurError && <p role="alert">{blurError}</p>}
      <div className="appearance-preview-wrap">
        <div className="appearance-preview-heading">
          <strong>实时预览</strong>
          <span>
            模糊 {value.blurRadius}px · 不透明度 {value.opacity}%
          </span>
        </div>
        <div
          className="appearance-preview-scene"
          role="img"
          aria-label={`模糊半径 ${value.blurRadius}px、窗口背景不透明度 ${value.opacity}% 的模拟预览`}
        >
          <div className="appearance-preview-landscape" aria-hidden="true">
            <span>DESKTOP</span>
          </div>
          <div
            className="appearance-preview-window"
            data-glass-contrast={value.opacity < 55 ? "high" : undefined}
            style={
              {
                "--preview-opacity": value.opacity / 100,
              } as CSSProperties
            }
            aria-hidden="true"
          >
            <div
              className="appearance-preview-glass"
              style={{
                backdropFilter: value.blurRadius
                  ? `blur(${value.blurRadius}px)`
                  : "none",
              }}
            />
            <div className="appearance-preview-tint" />
            <div className="appearance-preview-search">
              <Search size={14} />
              <span>搜索项目…</span>
              <MoreHorizontal size={16} />
            </div>
            <div className="appearance-preview-project">
              <Code2 size={19} />
              <span>
                <strong>codedog</strong>
                <small>personal / codedog</small>
              </span>
              <span>↵</span>
            </div>
            <div className="appearance-preview-footer">
              <span>文字与图标保持清晰</span>
              <Terminal size={12} />
              <FolderOpen size={12} />
            </div>
          </div>
        </div>
        <label>
          <span className="appearance-range-label">
            模糊半径 <output>{value.blurRadius}px</output>
          </span>
          <input
            type="range"
            aria-label="模糊半径"
            min={0}
            max={80}
            step={1}
            value={value.blurRadius}
            disabled={disabled || !!blurError}
            onChange={(event) =>
              onChange({ ...value, blurRadius: Number(event.target.value) })
            }
          />
        </label>
        <label>
          <span className="appearance-range-label">
            窗口背景不透明度 <output>{value.opacity}%</output>
          </span>
          <input
            type="range"
            aria-label="窗口背景不透明度"
            min={0}
            max={100}
            step={1}
            value={value.opacity}
            disabled={disabled}
            onChange={(event) =>
              onChange({ ...value, opacity: Number(event.target.value) })
            }
          />
        </label>
      </div>
    </div>
  );
}
