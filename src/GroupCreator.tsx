import { useState } from "react";
import { Plus, Loader2, X } from "lucide-react";

export default function GroupCreator({
  onCreate,
  onCreated,
  disabled,
  expanded = false,
}: {
  onCreate: (name: string) => Promise<string>;
  onCreated?: (id: string) => void;
  disabled?: boolean;
  expanded?: boolean;
}) {
  const [open, setOpen] = useState(expanded);
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [saving, setSaving] = useState(false);
  async function save() {
    if (saving || disabled || !name.trim()) return;
    setSaving(true);
    setError("");
    try {
      const id = await onCreate(name);
      onCreated?.(id);
      setName("");
      setOpen(expanded);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setSaving(false);
    }
  }
  if (!open)
    return (
      <button
        type="button"
        className="button group-add"
        disabled={disabled}
        onClick={() => setOpen(true)}
      >
        <Plus size={13} />
        新增分组
      </button>
    );
  return (
    <div className="group-create">
      <div className="input-action">
        <input
          autoFocus
          aria-label="新分组名称"
          placeholder="输入分组名称"
          maxLength={40}
          value={name}
          disabled={disabled || saving}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.nativeEvent.isComposing) {
              e.preventDefault();
              e.stopPropagation();
              void save();
            }
          }}
        />
        <button
          type="button"
          className="button"
          disabled={disabled || saving || !name.trim()}
          onClick={save}
        >
          {saving ? <Loader2 size={13} className="spin" /> : "新增"}
        </button>
        {!expanded && (
          <button
            type="button"
            className="icon-button"
            aria-label="取消新增分组"
            disabled={saving}
            onClick={() => {
              setOpen(false);
              setError("");
            }}
          >
            <X size={13} />
          </button>
        )}
      </div>
      {error && <small role="alert">{error}</small>}
    </div>
  );
}
