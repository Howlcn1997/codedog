import test from "node:test";
import assert from "node:assert/strict";
import {
  chooseEditor,
  projectMenuTemplate,
} from "../electron/project-menu.mjs";
test("explicit IDE selection overrides project/global defaults without mutating them", () => {
  const project = { ide: "Cursor" };
  assert.equal(
    chooseEditor("Visual Studio Code", project.ide, "WebStorm"),
    "Visual Studio Code",
  );
  assert.equal(chooseEditor(undefined, project.ide, "WebStorm"), "Cursor");
  assert.equal(chooseEditor(undefined, undefined, "WebStorm"), "WebStorm");
  assert.equal(project.ide, "Cursor");
  assert.throws(
    () => chooseEditor("/tmp/arbitrary-command", undefined, "Cursor"),
    /不支持/,
  );
});
test("context menu routes VS Code and terminal to separate actions", () => {
  const actions = [];
  const menu = projectMenuTemplate("Cursor", (action) => actions.push(action));
  menu[0].submenu.find((item) => item.label === "VS Code").click();
  menu.find((item) => item.label === "在终端中打开").click();
  assert.deepEqual(actions, [
    { kind: "ide", editor: "Visual Studio Code" },
    { kind: "terminal" },
  ]);
});
test("IDE menu uses available application icons and tolerates missing icons", () => {
  const icon = { app: "VS Code" };
  const menu = projectMenuTemplate("Visual Studio Code", () => {}, {
    "Visual Studio Code": icon,
  });
  assert.equal(menu[0].submenu[0].icon, icon);
  assert.equal(menu[0].submenu.find((i) => i.label === "VS Code").icon, icon);
  assert.equal(
    menu[0].submenu.find((i) => i.label === "Cursor").icon,
    undefined,
  );
});
