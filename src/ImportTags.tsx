import { useState } from "react";
import { Check, Plus, X } from "lucide-react";
export default function ImportTags({
  available,
  value,
  onChange,
  disabled,
  batch,
}: {
  available: string[];
  value: string[];
  onChange: (tags: string[]) => void;
  disabled: boolean;
  batch: boolean;
}) {
  const [query, setQuery] = useState("");
  const name = query.trim();
  const options = [...new Set([...available, ...value])].sort((a, b) =>
    a.localeCompare(b, "zh-CN"),
  );
  const filtered = options.filter((tag) =>
    tag.toLocaleLowerCase().includes(name.toLocaleLowerCase()),
  );
  const exact = options.find(
    (tag) => tag.toLocaleLowerCase() === name.toLocaleLowerCase(),
  );
  const full = value.length >= 20;
  const toggle = (tag: string) => {
    if (disabled) return;
    if (value.includes(tag)) onChange(value.filter((t) => t !== tag));
    else if (!full) onChange([...value, tag]);
  };
  const create = () => {
    if (disabled || !name || full) return;
    const tag = exact || name;
    if (!value.includes(tag)) onChange([...value, tag]);
    setQuery("");
  };
  return (
    <section className="import-tags" aria-label="导入标签">
      <div className="import-tags-heading">
        <span>项目标签</span>
        <small>{value.length} / 20</small>
      </div>
      <p>
        {batch ? "统一应用到本次勾选的所有项目。" : "导入时为项目添加标签。"}
        可选择已有标签，或新建标签。
      </p>
      {!!value.length && (
        <div className="import-tags-selected">
          {value.map((tag) => (
            <button
              type="button"
              disabled={disabled}
              key={tag}
              aria-label={`移除标签 ${tag}`}
              onClick={() => toggle(tag)}
            >
              {tag}
              <X size={12} />
            </button>
          ))}
        </div>
      )}
      <div className="input-action">
        <input
          aria-label="搜索或新建标签"
          placeholder="搜索或输入新标签，按 Enter 添加"
          maxLength={40}
          value={query}
          disabled={disabled}
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing) {
              e.preventDefault();
              create();
            }
          }}
        />
        <button
          type="button"
          className="button"
          disabled={
            disabled || !name || full || (!!exact && value.includes(exact))
          }
          onClick={create}
        >
          <Plus size={14} />
          {exact ? "添加" : "新建"}
        </button>
      </div>
      <div className="import-tags-options" aria-label="可选标签">
        {filtered.map((tag) => (
          <button
            type="button"
            key={tag}
            aria-pressed={value.includes(tag)}
            disabled={disabled || (full && !value.includes(tag))}
            onClick={() => toggle(tag)}
          >
            {value.includes(tag) && <Check size={12} />} {tag}
          </button>
        ))}
      </div>
      {!filtered.length && (
        <small>
          {name
            ? "没有匹配标签，点击「新建」即可创建并选中。"
            : "还没有标签，输入名称创建第一个。"}
        </small>
      )}
      {full && <small>已选择 20 个标签，移除一个后可以继续添加。</small>}
    </section>
  );
}
