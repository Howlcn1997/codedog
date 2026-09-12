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
      label: "使用 IDE 打开",
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
    { label: "在终端中打开", click: () => onSelect({ kind: "terminal" }) },
  ];
}
