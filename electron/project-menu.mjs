export const editors = [
  "Cursor",
  "Visual Studio Code",
  "WebStorm",
  "GoLand",
  "PyCharm",
];
export function chooseEditor(override, projectEditor, defaultEditor) {
  const editor = override || projectEditor || defaultEditor;
  if (!editors.includes(editor)) throw Error("不支持的 IDE");
  return editor;
}
export function projectMenuTemplate(defaultEditor, onSelect, icons = {}) {
  return [
    {
      label: "IDE打开",
      submenu: [
        {
          label: `默认 IDE · ${defaultEditor}`,
          icon: icons[defaultEditor],
          click: () => onSelect({ kind: "ide", editor: defaultEditor }),
        },
        { type: "separator" },
        ...editors.map((editor) => ({
          label: editor === "Visual Studio Code" ? "VS Code" : editor,
          icon: icons[editor],
          click: () => onSelect({ kind: "ide", editor }),
        })),
      ],
    },
    { type: "separator" },
    { label: "终端打开", click: () => onSelect({ kind: "terminal" }) },
    { label: "访达打开", click: () => onSelect({ kind: "folder" }) },
    { label: "复制路径", click: () => onSelect({ kind: "copy" }) },
  ];
}
