import { _electron as electron, expect } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
import { ProjectStore } from "../electron/core.mjs";

const base = path.resolve("work/workspaces-smoke");
await fs.mkdir(base, { recursive: true });
const profile = await fs.mkdtemp(path.join(base, "profile-"));
const root = path.join(profile, "projects");
await fs.mkdir(root);
const store = new ProjectStore(path.join(profile, "projects.json"));
await store.init();
await store.setRoot(root);
for (const name of ["mobile-app", "admin-web", "admin-api"]) {
  const source = path.join(root, name);
  await fs.mkdir(source);
  await fs.writeFile(
    path.join(source, "package.json"),
    JSON.stringify({ name }),
  );
  await store.importProject({
    name,
    source,
    mode: "register",
    group: "personal",
    tags: [],
  });
}
const env = {
  ...process.env,
  CODEDOG_DATA_DIR: profile,
  CODEDOG_SKIP_PATH: "1",
};
delete env.ELECTRON_RUN_AS_NODE;
const app = await electron.launch({ args: ["."], env });
try {
  await app.evaluate(({ app }, home) => app.setPath("home", home), profile);
  const page = await app.firstWindow();
  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page
    .locator(".sidebar")
    .getByRole("button", { name: /^项目组/ })
    .click();
  await page.getByRole("button", { name: "新建项目组", exact: true }).click();
  let dialog = page.getByRole("dialog", { name: "新建项目组", exact: true });
  await expect(
    dialog.getByRole("textbox", { name: "项目组保存位置" }),
  ).toHaveCount(0);
  await expect(dialog.getByRole("button", { name: "选择目录" })).toHaveCount(0);
  await dialog
    .getByRole("textbox", { name: "项目组名称", exact: true })
    .fill("商城系统");
  for (const name of ["mobile-app", "admin-web", "admin-api"])
    await dialog.getByRole("checkbox", { name: new RegExp(name) }).check();
  await dialog
    .getByRole("textbox", { name: "关系说明", exact: true })
    .fill(
      [
        "# 商城系统",
        "",
        "App 和 Web 后台通过 **API** 协作。",
        "",
        "- 共享接口",
        "- 独立部署",
        "",
        "| 项目 | 职责 |",
        "| --- | --- |",
        "| App | 客户端 |",
        "",
        "```js",
        "const service = 'api';",
        "```",
        "",
        "```mermaid",
        "flowchart LR",
        "  App --> API",
        "  Web --> API",
        "```",
        "",
        "```mermaid",
        "sequenceDiagram",
        "  App->>API: 请求",
        "  API-->>App: 响应",
        "```",
        "",
        "```mermaid",
        "not a valid diagram",
        "```",
        "",
        "<script>window.markdownUnsafe = true</script>",
      ].join("\n"),
    );
  await dialog.locator(".workspace-form-scroll").evaluate((element) => {
    element.scrollTop = 0;
  });
  const footerBox = await dialog
    .getByRole("button", { name: "保存项目组", exact: true })
    .boundingBox();
  const scrollBox = await dialog
    .locator(".workspace-form-scroll")
    .boundingBox();
  assert.ok(
    footerBox.y >= scrollBox.y + scrollBox.height,
    "save controls must be below the scroll area",
  );
  await page.screenshot({ path: path.join(base, "create.png") });
  await dialog.getByRole("button", { name: "保存项目组", exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page.locator(".workspace-member")).toHaveCount(3);
  await expect(page.locator(".workspace-member").first()).toHaveText(
    "mobile-app",
  );
  await expect(
    page.locator(
      ".workspace-member small, .workspace-member svg, .workspace-member .tag",
    ),
  ).toHaveCount(0);
  await app.evaluate(({ Menu, clipboard }) => {
    globalThis.memberMenuOriginal = Menu.buildFromTemplate;
    globalThis.memberCopyOriginal = clipboard.writeText;
    clipboard.writeText = (text) => {
      globalThis.memberCopiedPath = text;
    };
    Menu.buildFromTemplate = (template) => {
      globalThis.memberMenuLabels = template
        .filter((item) => item.label)
        .map((item) => item.label);
      return {
        popup: ({ callback }) => {
          globalThis.finishMemberMenu = () => {
            template.find((item) => item.label === "复制路径").click();
            callback();
          };
        },
      };
    };
  });
  try {
    await page.locator(".workspace-member").first().click({ button: "right" });
    await expect
      .poll(() => app.evaluate(() => typeof globalThis.finishMemberMenu))
      .toBe("function");
    await expect(page.locator(".workspace-member").first()).toBeEnabled();
    await expect(page.locator(".workspace-member").first()).toHaveCSS(
      "cursor",
      "pointer",
    );
    await app.evaluate(() => globalThis.finishMemberMenu());
    await expect(page.locator('.workspace-message[role="status"]')).toHaveText(
      "路径已复制",
    );
    assert.deepEqual(await app.evaluate(() => globalThis.memberMenuLabels), [
      "IDE打开",
      "终端打开",
      "访达打开",
      "复制路径",
    ]);
    assert.equal(
      await app.evaluate(() => globalThis.memberCopiedPath),
      path.join(root, "mobile-app"),
    );
  } finally {
    await app.evaluate(({ Menu, clipboard }) => {
      Menu.buildFromTemplate = globalThis.memberMenuOriginal;
      clipboard.writeText = globalThis.memberCopyOriginal;
    });
  }
  await expect(page.locator(".workspace-readme")).toContainText(
    "App 和 Web 后台",
  );
  await expect(page.locator(".workspace-readme h1")).toHaveText("商城系统");
  await expect(page.locator(".workspace-readme strong")).toHaveText("API");
  await expect(page.locator(".workspace-readme tbody td")).toHaveCount(2);
  await expect(
    page.locator(".workspace-readme code.language-js"),
  ).toContainText("const service");
  await expect(page.locator(".markdown-diagram svg")).toHaveCount(2, {
    timeout: 20000,
  });
  await expect(page.locator(".markdown-diagram-error")).toContainText(
    "图表语法有误",
  );
  assert.equal(await page.evaluate(() => window.markdownUnsafe), undefined);
  const lightDiagram = await page
    .locator(".markdown-diagram svg")
    .first()
    .innerHTML();
  await page.evaluate(() => {
    document.documentElement.dataset.theme = "dark";
  });
  await expect(page.locator(".markdown-diagram svg")).toHaveCount(2);
  await expect
    .poll(() => page.locator(".markdown-diagram svg").first().innerHTML())
    .not.toBe(lightDiagram);
  await page
    .locator(".markdown-diagram")
    .first()
    .screenshot({ path: path.join(base, "markdown-dark.png") });
  await page.evaluate(() => {
    document.documentElement.dataset.theme = "light";
  });
  await expect(page.locator(".markdown-diagram svg")).toHaveCount(2);
  await page
    .locator(".markdown-diagram")
    .nth(1)
    .screenshot({ path: path.join(base, "markdown-sequence.png") });
  await store.refresh();
  const workspace = store.state.workspaces[0];
  assert.equal(
    path.dirname(workspace.path),
    await fs.realpath(path.join(profile, "codespace", "workspaces")),
  );
  assert.ok(
    (await fs.lstat(path.join(workspace.path, "mobile-app"))).isSymbolicLink(),
  );
  await page.screenshot({ path: path.join(base, "detail.png") });
  const second = await page.evaluate(
    async (member) =>
      window.codedog.createWorkspace({
        name: "独立调试",
        members: [member],
        description: "调试空间",
      }),
    workspace.members[0],
  );
  await page.reload();
  const search = page.getByRole("textbox", { name: "搜索项目", exact: true });
  await search.fill("mobile-app");
  await expect(page.locator(".project-table tbody tr")).toHaveCount(3);
  await expect(
    page.locator(".project-table .result-kind.is-workspace"),
  ).toHaveCount(2);
  await expect(
    page.locator(".project-table .result-kind:not(.is-workspace)"),
  ).toHaveCount(1);
  await page.screenshot({ path: path.join(base, "search-list.png") });
  await page.getByRole("button", { name: "卡片视图", exact: true }).click();
  await expect(
    page.locator(".project-card .result-kind.is-workspace"),
  ).toHaveCount(2);
  await page.getByRole("button", { name: "列表视图", exact: true }).click();
  await page
    .locator(".project-table tbody tr")
    .filter({ has: page.getByText("独立调试", { exact: true }) })
    .click();
  await expect(page.locator(".workspace-detail h2")).toHaveText("独立调试");
  await expect(page.locator(".workspace-member")).toHaveCount(1);
  await page.getByRole("button", { name: "精简模式", exact: true }).click();
  await page.locator(".compact-search input").fill("独立调试");
  await expect(page.locator(".compact-project")).toHaveCount(1);
  await expect(page.locator(".compact-project .result-kind")).toHaveText(
    "项目组",
  );
  await expect(page.getByRole("button", { name: /访问仓库/ })).toBeDisabled();
  await page.screenshot({ path: path.join(base, "search-compact.png") });
  await app.evaluate(({ shell }) => {
    globalThis.workspaceOpenedPath = "";
    shell.openPath = async (folder) => {
      globalThis.workspaceOpenedPath = folder;
      return "";
    };
  });
  await page.getByRole("button", { name: /在访达中打开/ }).click();
  await expect
    .poll(() => app.evaluate(() => globalThis.workspaceOpenedPath))
    .toBe(second.path);
  await page.getByRole("button", { name: "标准模式", exact: true }).click();
  await page.evaluate(
    async (id) => window.codedog.forgetWorkspace(id),
    second.id,
  );
  await page.reload();
  await page
    .locator(".sidebar")
    .getByRole("button", { name: /^项目组/ })
    .click();
  await expect(page.locator(".workspace-detail h2")).toHaveText("商城系统");

  await page.getByRole("button", { name: "编辑项目组", exact: true }).click();
  dialog = page.getByRole("dialog", { name: "编辑项目组", exact: true });
  await dialog
    .getByRole("textbox", { name: "项目组名称", exact: true })
    .fill("商城协作");
  await dialog
    .getByRole("button", { name: "移除 admin-web", exact: true })
    .click();
  await dialog.getByRole("button", { name: "保存项目组", exact: true }).click();
  await expect(dialog).not.toBeVisible();
  await expect(page.locator(".workspace-member")).toHaveCount(2);
  await fs.unlink(path.join(workspace.path, "mobile-app"));
  await page.getByRole("button", { name: "刷新", exact: true }).click();
  await expect(page.locator(".workspace-choice.active")).toContainText(
    "需要检查",
  );
  await page
    .getByRole("button", { name: "检查并修复链接", exact: true })
    .click();
  await expect(page.locator(".workspace-choice.active")).not.toContainText(
    "需要检查",
  );
  assert.ok(
    (await fs.lstat(path.join(workspace.path, "mobile-app"))).isSymbolicLink(),
  );
  await page.getByRole("button", { name: "编辑项目组", exact: true }).click();
  dialog = page.getByRole("dialog", { name: "编辑项目组", exact: true });
  await fs.writeFile(path.join(workspace.path, "README.md"), "外部编辑保留");
  await dialog
    .getByRole("textbox", { name: "关系说明", exact: true })
    .fill("stale edit");
  await dialog.getByRole("button", { name: "保存项目组", exact: true }).click();
  await expect(dialog.getByRole("alert")).toContainText("外部修改");
  await dialog.getByRole("button", { name: "取消", exact: true }).click();
  await page.getByRole("button", { name: "移出管理", exact: true }).click();
  dialog = page.getByRole("dialog", { name: "移出项目组管理", exact: true });
  await dialog.getByRole("button", { name: "移出管理", exact: true }).click();
  await expect(
    page.getByText("把相关项目放在一起", { exact: true }),
  ).toBeVisible();
  assert.equal(
    await fs.readFile(path.join(workspace.path, "README.md"), "utf8"),
    "外部编辑保留",
  );
  assert.ok(
    (await fs.lstat(path.join(workspace.path, "mobile-app"))).isSymbolicLink(),
  );
  for (const name of ["mobile-app", "admin-web", "admin-api"])
    assert.ok(await fs.stat(path.join(root, name, "package.json")));
  assert.deepEqual(errors, []);
  console.log(
    "Project group desktop smoke passed: create, edit, repair, conflict protection, removal.",
  );
} finally {
  await app.close();
}
