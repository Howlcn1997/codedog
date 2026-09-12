import { _electron as electron } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";
const base = path.resolve("work/smoke");
await fs.mkdir(base, { recursive: true });
const profile = await fs.mkdtemp(path.join(base, "profile-"));
const env = {
  ...process.env,
  CODEDOG_DATA_DIR: profile,
  CODEDOG_SKIP_PATH: "1",
};
delete env.ELECTRON_RUN_AS_NODE;
const app = await electron.launch({ args: ["."], env });
try {
  const page = await app.firstWindow();
  await page.waitForSelector(".brand");
  const errors = [];
  page.on("pageerror", (e) => errors.push(e.message));
  await page.getByText("先看看演示项目").click();
  await page.getByText("atlas-console", { exact: true }).first().waitFor();
  await page.screenshot({ path: "work/codedog-desktop.png" });
  await page
    .getByRole("textbox", { name: "搜索项目", exact: true })
    .fill("atcon");
  assert.equal(await page.locator("tbody tr").count(), 1);
  await page
    .getByRole("textbox", { name: "搜索项目", exact: true })
    .fill("nothingmatches");
  await page.getByText("没有找到匹配的项目").waitFor();
  await page.getByRole("button", { name: "清除筛选", exact: true }).click();
  assert.equal(await page.locator("tbody tr").count(), 8);
  await page.getByRole("button", { name: "返回本地项目", exact: true }).click();
  const root = path.join(profile, "projects");
  const source = path.join(profile, "source");
  await fs.mkdir(root);
  await fs.mkdir(source);
  await fs.writeFile(
    path.join(source, "package.json"),
    JSON.stringify({ name: "smoke-project", dependencies: { react: "^19" } }),
  );
  await app.evaluate(({ dialog }, folder) => {
    dialog.showOpenDialog = async () => ({
      canceled: false,
      filePaths: [folder],
    });
  }, root);
  await page
    .locator(".workspace")
    .getByRole("button", { name: "选择项目根目录", exact: true })
    .click();
  await page
    .getByRole("button", { name: "导入第一个项目", exact: true })
    .waitFor();
  await page
    .getByRole("button", { name: "导入第一个项目", exact: true })
    .click();
  await app.evaluate(({ dialog }, folder) => {
    dialog.showOpenDialog = async () => ({
      canceled: false,
      filePaths: [folder],
    });
  }, source);
  await page.getByRole("button", { name: "选择", exact: true }).click();
  await page.getByLabel("项目名称", { exact: true }).fill("smoke-project");
  await page
    .getByRole("dialog")
    .getByRole("button", { name: "导入项目", exact: true })
    .click();
  await page.getByRole("dialog").waitFor({ state: "hidden" });
  await page.getByRole("button", { name: "关闭日志", exact: true }).click();
  await page.getByText("smoke-project", { exact: true }).first().waitFor();
  await page
    .getByRole("button", { name: "收藏 smoke-project", exact: true })
    .click();
  await page
    .getByRole("button", { name: "取消收藏 smoke-project", exact: true })
    .waitFor();
  await page.getByRole("button", { name: "编辑项目信息", exact: true }).click();
  await page
    .getByLabel("备注", { exact: true })
    .fill("Persisted by smoke test");
  await page.getByRole("button", { name: "保存信息", exact: true }).click();
  await page.getByRole("dialog").waitFor({ state: "hidden" });
  await page.getByRole("button", { name: "归档项目", exact: true }).click();
  await page
    .locator(".sidebar")
    .getByRole("button", { name: "已归档", exact: true })
    .click();
  await page.getByText("smoke-project", { exact: true }).first().waitFor();
  await page.getByRole("button", { name: "恢复项目", exact: true }).click();
  assert.deepEqual(errors, []);
  const persisted = JSON.parse(
    await fs.readFile(path.join(profile, "projects.json"), "utf8"),
  );
  assert.equal(persisted.projects[0].notes, "Persisted by smoke test");
  assert.equal(persisted.projects[0].archived, false);
  console.log(
    "PASS: Electron launch, demo, fuzzy search, empty state, native folder selection, copy import, favorite, edit, archive, restore, persistence.",
  );
} finally {
  await app.close();
}
