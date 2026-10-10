import { _electron as electron } from "@playwright/test";
import fs from "node:fs/promises";
import path from "node:path";
import assert from "node:assert/strict";

const base = path.resolve("work/compact-smoke");
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
  console.log("Electron launched");
  const page = await app.firstWindow();
  page.setDefaultTimeout(10000);
  console.log("Window ready", await page.title());
  if (process.platform === "darwin") {
    await app.evaluate(({ BrowserWindow }) => {
      const window = BrowserWindow.getAllWindows()[0];
      const bridge = process
        .getBuiltinModule("module")
        .createRequire(process.cwd() + "/package.json")(
        "./electron/native/window-effects.node",
      );
      const original = bridge.setBlurRadius;
      window.testBlurCalls = [];
      bridge.setBlurRadius = (handle, radius, compact) => {
        const status = original(handle, radius, compact);
        window.testBlurCalls.push({ radius, status });
        return status;
      };
    });
  }

  const errors = [];
  page.on("pageerror", (error) => errors.push(error.message));
  await page.getByText("先看看演示项目").click();
  await page.locator(".sidebar").getByRole("button", { name: /设置/ }).click();
  const settings = page.getByRole("dialog", { name: "设置", exact: true });
  await settings.getByRole("button", { name: "外观", exact: true }).click();
  const opacity = settings.getByRole("slider", { name: "窗口背景不透明度" });
  await opacity.focus();
  await opacity.press("Home");
  assert.equal(await opacity.inputValue(), "0");
  for (let i = 0; i < 20; i++) await opacity.press("ArrowRight");
  const preview = settings.locator(".appearance-preview-window");
  assert.ok(
    Math.abs(
      Number(
        await preview.evaluate((el) =>
          el.style.getPropertyValue("--preview-opacity"),
        ),
      ) - 0.2,
    ) < 0.001,
  );
  assert.equal(await settings.getByRole("radio", { name: /材质/ }).count(), 0);
  const blurSlider = settings.getByRole("slider", { name: "模糊半径" });
  await blurSlider.focus();
  await blurSlider.press("Home");
  assert.equal(
    await preview
      .locator(".appearance-preview-glass")
      .evaluate((el) => getComputedStyle(el).backdropFilter),
    "none",
  );
  await blurSlider.press("End");
  assert.match(
    await preview
      .locator(".appearance-preview-glass")
      .evaluate((el) => getComputedStyle(el).backdropFilter),
    /blur\(80px\)/,
  );
  assert.equal(
    (await page.evaluate(() => window.codedog.state())).compactAppearance
      .opacity,
    70,
  );

  await settings.getByRole("button", { name: "保存外观" }).click();
  await page.waitForFunction(
    async () =>
      (await window.codedog.state()).compactAppearance?.opacity === 20,
  );
  assert.deepEqual(
    await page.evaluate(
      async () => (await window.codedog.state()).compactAppearance,
    ),
    { opacity: 20, blurRadius: 80 },
  );
  await settings.screenshot({
    path: path.join(base, "appearance-settings.png"),
    animations: "disabled",
  });
  await settings.getByRole("button", { name: "关闭", exact: true }).click();
  await page.getByRole("button", { name: "精简模式", exact: true }).click();
  await page.waitForFunction(
    () =>
      Math.abs(
        Number(
          document
            .querySelector(".compact-shell")
            ?.style.getPropertyValue("--compact-opacity"),
        ) - 0.2,
      ) < 0.001,
  );

  await page.locator(".compact-shell").waitFor();
  const assertClip = async (compact) => {
    if (process.platform !== "darwin") return;
    await app.evaluate(({ app, BrowserWindow }) => {
      app.focus({ steal: true });
      BrowserWindow.getAllWindows()[0].focus();
    });
    // Allow native display/resize work to settle before inspecting the server.
    await new Promise((resolve) => setTimeout(resolve, 800));
    const clip = await app.evaluate(({ BrowserWindow }) => {
      const bridge = process
        .getBuiltinModule("module")
        .createRequire(process.cwd() + "/package.json")(
        "./electron/native/window-effects.node",
      );
      const win = BrowserWindow.getAllWindows()[0];
      const actual = bridge.inspectBounds(win.getNativeWindowHandle());
      const expected = win.getBounds();
      for (const key of ["x", "y", "width", "height"])
        if (Math.abs(actual[key] - expected[key]) > 1)
          throw Error(
            `Native window ${key} drifted: ${actual[key]} != ${expected[key]}`,
          );
      return bridge.inspectClip(win.getNativeWindowHandle());
    });
    assert.deepEqual(
      clip,
      compact
        ? [false, false, false, false, true]
        : [true, true, true, true, true],
    );
  };
  await assertClip(true);
  if (process.platform === "darwin") {
    const focusResult = await app.evaluate(({ BrowserWindow }) => {
      const win = BrowserWindow.getAllWindows()[0];
      const bridge = process
        .getBuiltinModule("module")
        .createRequire(process.cwd() + "/package.json")(
        "./electron/native/window-effects.node",
      );
      const original = bridge.refreshBlur;
      let calls = 0;
      bridge.refreshBlur = (...args) => {
        calls++;
        return original(...args);
      };
      const shapesBefore = win.testBlurCalls.length;
      for (let i = 0; i < 3; i++) {
        win.emit("blur");
        win.emit("focus");
      }
      bridge.refreshBlur = original;
      return { calls, shapesBefore, shapesAfter: win.testBlurCalls.length };
    });
    assert.equal(
      focusResult.calls,
      6,
      "Focus and blur restore native blur synchronously",
    );
    assert.equal(
      focusResult.shapesBefore,
      focusResult.shapesAfter,
      "Focus must not rebuild geometry",
    );
    await assertClip(true);
    assert.equal(
      await app.evaluate(
        ({ BrowserWindow }) =>
          BrowserWindow.getAllWindows()[0].testBlurCalls.length,
      ),
      focusResult.shapesBefore,
      "Focus must not schedule a delayed geometry rebuild",
    );
  }
  console.log("Compact mode ready");
  assert.equal(
    await page.locator(".compact-shell").getAttribute("data-glass-contrast"),
    "high",
  );
  assert.equal(
    await page
      .locator(".compact-path")
      .first()
      .evaluate((el) => getComputedStyle(el).color),
    "rgb(238, 244, 252)",
  );
  assert.equal(
    await page
      .locator(".compact-project-name")
      .first()
      .evaluate((el) => getComputedStyle(el).color),
    "rgb(255, 255, 255)",
  );
  const renderedBackground = await page
    .locator(".compact-shell")
    .evaluate((el) => getComputedStyle(el).backgroundColor);
  assert.match(renderedBackground, /, 0\.2\)$/);
  console.log("Saved appearance applied without restart:", renderedBackground);
  if (process.platform === "darwin") {
    const read = () =>
      app.evaluate(({ BrowserWindow }) => {
        const win = BrowserWindow.getAllWindows()[0];
        return { last: win.testBlurCalls.at(-1), opacity: win.getOpacity() };
      });
    assert.deepEqual(await read(), {
      last: { radius: 80, status: 0 },
      opacity: 1,
    });
    for (const blurRadius of [0, 20, 40, 80]) {
      await page.evaluate(
        (value) =>
          window.codedog.setCompactAppearance({
            opacity: 50,
            blurRadius: value,
          }),
        blurRadius,
      );
      assert.deepEqual(await read(), {
        last: { radius: blurRadius, status: 0 },
        opacity: 1,
      });
      await assertClip(true);
    }
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0].setSize(680, 460),
    );
    await page.waitForFunction(() => innerWidth === 680);
    await assertClip(true);
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0].setSize(640, 420),
    );
    await page.waitForFunction(() => innerWidth === 640);
    await assertClip(true);
    await page.evaluate(() =>
      window.codedog.setCompactAppearance({ opacity: 20, blurRadius: 80 }),
    );
    assert.equal(
      (await page.evaluate(() => window.codedog.state())).windowBlurError,
      undefined,
    );
    await app.evaluate(() => {
      const bridge = process
        .getBuiltinModule("module")
        .createRequire(process.cwd() + "/package.json")(
        "./electron/native/window-effects.node",
      );
      bridge.testOriginal = bridge.setBlurRadius;
      bridge.setBlurRadius = () => {
        throw Error("test unavailable");
      };
    });
    await page.evaluate(() =>
      window.codedog.setCompactAppearance({ opacity: 50, blurRadius: 20 }),
    );
    assert.match(
      (await page.evaluate(() => window.codedog.state())).windowBlurError,
      /test unavailable/,
    );
    await app.evaluate(() => {
      const bridge = process
        .getBuiltinModule("module")
        .createRequire(process.cwd() + "/package.json")(
        "./electron/native/window-effects.node",
      );
      bridge.setBlurRadius = bridge.testOriginal;
      delete bridge.testOriginal;
    });
    await page.evaluate(() =>
      window.codedog.setCompactAppearance({ opacity: 20, blurRadius: 80 }),
    );
    assert.equal(
      (await page.evaluate(() => window.codedog.state())).windowBlurError,
      undefined,
    );
  }

  assert.equal(await page.locator(".compact-recent-project").count(), 5);
  assert.deepEqual(
    await page.locator(".compact-recent-name").allTextContents(),
    [
      "atlas-console",
      "gateway-service",
      "data-pipeline",
      "design-system",
      "personal-site",
    ],
  );
  assert.equal(
    await page.locator(".compact-presets, .compact-filters").count(),
    0,
  );
  assert.equal(await page.locator(".compact-project").count(), 8);
  const search = page.getByRole("textbox", { name: "搜索项目", exact: true });
  await search.press("ArrowDown");
  await page.waitForFunction(() =>
    document
      .querySelector(".compact-project.selected")
      ?.textContent.includes("gateway-service"),
  );
  await search.press("ArrowRight");
  assert.equal(
    await page
      .getByRole("button", { name: "打开终端", exact: true })
      .getAttribute("aria-pressed"),
    "true",
  );
  await search.fill("atcon");
  assert.equal(await page.locator(".compact-project").count(), 1);
  assert.equal(await page.locator(".compact-recent").count(), 0);
  await search.fill("nothingmatches");
  await page.getByText("没有匹配的项目", { exact: true }).waitFor();
  await search.press("Escape");
  assert.equal(await page.locator(".compact-recent-project").count(), 5);
  await page.locator(".compact-recent-project").first().click();
  await page.getByRole("alert").waitFor(); // Demo projects must never launch external apps.
  await page.getByRole("button", { name: "关闭错误提示" }).click();
  await page.locator(".compact-menu summary").click();
  await page.getByRole("button", { name: "刷新搜索索引" }).waitFor();
  await page.locator(".compact-menu summary").press("Escape");
  assert.equal(await page.locator(".compact-menu").getAttribute("open"), null);
  for (const theme of ["light", "dark"]) {
    await app.evaluate(({ nativeTheme }, value) => {
      nativeTheme.themeSource = value;
    }, theme);
    await page.evaluate((value) => {
      document.documentElement.dataset.theme = value;
    }, theme);
    await page.screenshot({
      animations: "disabled",
      path: path.join(base, `compact-${theme}.png`),
    });
    if (process.platform === "darwin") {
      const last = await app.evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows()[0].testBlurCalls.at(-1),
      );
      assert.deepEqual(last, { radius: 80, status: 0 });
    }

    await assertClip(true);
    const bounds = await page.locator(".compact-command-bar").boundingBox();
    assert.ok(
      bounds.y + bounds.height <= 420,
      "Actions fit in the compact window",
    );
    assert.equal(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
      true,
    );
    if (process.platform === "darwin") {
      assert.equal(
        await app.evaluate(({ BrowserWindow }) =>
          BrowserWindow.getAllWindows()[0].getBackgroundColor(),
        ),
        "#000000",
      );
    }
  }
  await page.locator(".compact-menu summary").click();
  await page.getByRole("button", { name: "标准模式", exact: true }).click();
  await page.locator(".app-shell").waitFor();
  assert.equal(
    await page.evaluate(() => document.documentElement.dataset.uiMode),
    undefined,
  );
  assert.notEqual(
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0].getBackgroundColor(),
    ),
    "#000000",
  );
  if (process.platform === "darwin") {
    assert.deepEqual(
      await app.evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows()[0].testBlurCalls.at(-1),
      ),
      { radius: 0, status: 0 },
    );
  }
  // Resizing after mode restoration must not leave a stale compact-size shape.
  if (process.platform === "darwin") {
    await app.evaluate(({ BrowserWindow }) =>
      BrowserWindow.getAllWindows()[0].setSize(1100, 740),
    );
    await page.waitForFunction(() => innerWidth === 1100);
    assert.equal(
      (await page.evaluate(() => window.codedog.state())).windowBlurError,
      undefined,
    );
    assert.deepEqual(
      await app.evaluate(({ BrowserWindow }) =>
        BrowserWindow.getAllWindows()[0].testBlurCalls.at(-1),
      ),
      { radius: 0, status: 0 },
    );
  }
  await assertClip(false);
  assert.deepEqual(errors, []);
  console.log(
    "Compact smoke passed: appearance settings, 5 recent projects, search, keyboard actions, menus, themes and mode restoration.",
  );
} catch (error) {
  console.error(error);
  throw error;
} finally {
  await app.evaluate(({ app, BrowserWindow }) => {
    app.removeAllListeners("before-quit");
    for (const window of BrowserWindow.getAllWindows())
      window.removeAllListeners("close");
  });
  await app.close();
  await fs.rm(profile, { recursive: true, force: true });
}
