import { _electron as electron } from "@playwright/test";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import assert from "node:assert/strict";

const profile = await fs.mkdtemp(path.join(os.tmpdir(), "codedog-create-"));
const root = path.join(profile, "projects");
await fs.mkdir(root);
const env = {
  ...process.env,
  CODEDOG_DATA_DIR: profile,
  CODEDOG_SKIP_PATH: "1",
};
delete env.ELECTRON_RUN_AS_NODE;
let app;
try {
  app = await electron.launch({ args: ["."], env });
  const page = await app.firstWindow();
  await page.waitForSelector(".brand");
  await page.evaluate(async (root) => {
    await window.codedog.setRoot(root);
  }, root);
  await page.reload();
  await page
    .getByRole("button", { name: "新建第一个项目", exact: true })
    .click();
  const dialog = page.getByRole("dialog", { name: "新建项目", exact: true });
  await dialog.getByLabel("项目名称", { exact: true }).fill("fresh-project");
  await dialog.getByRole("combobox").selectOption("personal");
  assert.equal(await dialog.locator("input").count(), 1);
  await dialog.getByRole("button", { name: "创建项目", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });
  await page
    .locator(".project-table")
    .getByText("fresh-project", { exact: true })
    .waitFor();
  const state = await page.evaluate(() => window.codedog.state());
  assert.equal(state.projects.length, 1);
  assert.deepEqual(
    await fs.readdir(path.join(root, "personal", "fresh-project")),
    [],
  );
  await page.getByRole("button", { name: "新建项目", exact: true }).click();
  await dialog.getByLabel("项目名称", { exact: true }).fill("fresh-project");
  await dialog.getByRole("button", { name: "创建项目", exact: true }).click();
  await dialog.getByRole("alert").filter({ hasText: "已存在" }).waitFor();
  await dialog.getByLabel("项目名称", { exact: true }).fill("second-project");
  await dialog.getByRole("button", { name: "创建项目", exact: true }).click();
  await dialog.waitFor({ state: "hidden" });
  assert.deepEqual(
    await fs.readdir(path.join(root, "personal", "second-project")),
    [],
  );
  console.log(
    "Create project smoke passed: group selection, automatic folder creation, conflict and retry.",
  );
} finally {
  if (app) {
    const timer = setTimeout(() => app.process().kill("SIGKILL"), 5000);
    try {
      await app.close();
    } finally {
      clearTimeout(timer);
    }
  }
  await fs.rm(profile, { recursive: true, force: true });
}
