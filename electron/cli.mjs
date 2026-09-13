import path from "node:path";
import { ProjectStore, run } from "./core.mjs";
import { chooseEditor } from "./project-menu.mjs";

const editorCommands = {
  Cursor: "cursor",
  "Visual Studio Code": "code",
  WebStorm: "webstorm",
  GoLand: "goland",
  PyCharm: "pycharm",
};

const usage = `用法：
  codedog add .
  codedog list [关键词]
  codedog open <名称或别名>
  codedog path <名称或别名>`;

function printCandidates(candidates, stderr) {
  stderr("找到多个候选项目，请使用唯一别名：\n");
  for (const project of candidates) {
    const aliases = (project.aliases || []).join(", ") || "-";
    stderr(`  ${project.name}\t${aliases}\t${project.path}\n`);
  }
}

async function requireProject(store, query, stderr) {
  const { project, candidates } = await store.resolve(query);
  if (project) return project;
  if (candidates.length) {
    printCandidates(candidates, stderr);
    const error = Error("项目名称或关键词不唯一");
    error.reported = true;
    throw error;
  }
  throw Error(`未找到项目：${query}`);
}

export async function executeCli(
  args,
  {
    dataFile,
    cwd = process.cwd(),
    platform = process.platform,
    runCommand = run,
    stdout = (text) => process.stdout.write(text),
    stderr = (text) => process.stderr.write(text),
  },
) {
  const [command, ...rest] = args;
  if (!command || ["help", "--help", "-h"].includes(command)) {
    stdout(usage + "\n");
    return 0;
  }
  if (!["add", "list", "open", "path"].includes(command)) {
    stderr(`未知命令：${command}\n${usage}\n`);
    return 2;
  }
  try {
    const store = new ProjectStore(dataFile);
    await store.init();
    if (command === "add") {
      if (rest.length > 1) throw Error("add 只接受一个项目目录");
      const folder = path.resolve(cwd, rest[0] || ".");
      const { project, existed } = await store.add(folder);
      stdout(
        existed
          ? `项目已存在：${project.name} (${project.path})\n`
          : `已登记项目：${project.name} (${project.path})\n`,
      );
      return 0;
    }
    if (command === "list") {
      if (rest.length > 1) throw Error("list 只接受一个关键词");
      const projects = await store.search(rest[0] || "");
      for (const project of projects) {
        const aliases = (project.aliases || []).join(", ") || "-";
        stdout(`${project.name}\t${aliases}\t${project.path}\n`);
      }
      return 0;
    }
    if (rest.length !== 1) throw Error(`${command} 需要项目名称或别名`);
    const project = await requireProject(store, rest[0], stderr);
    const resolvedPath = await store.get(project.id);
    if (command === "path") {
      stdout(resolvedPath.path + "\n");
      return 0;
    }
    const editor = chooseEditor(undefined, project.ide, store.state.ide);
    if (platform === "darwin")
      await runCommand(
        "open",
        ["-a", editor, resolvedPath.path],
        resolvedPath.path,
      );
    else
      await runCommand(
        editorCommands[editor],
        [resolvedPath.path],
        resolvedPath.path,
      );
    await store.transaction(async () => {
      const item = store.state.projects.find(
        (entry) => entry.id === project.id,
      );
      if (item) item.lastOpened = Date.now();
      await store.save();
    });
    return 0;
  } catch (error) {
    if (!error.reported) stderr(`codedog: ${error.message}\n`);
    return 1;
  }
}

export { usage };
