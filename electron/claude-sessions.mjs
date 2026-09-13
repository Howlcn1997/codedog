import fs from "node:fs/promises";
import path from "node:path";
import os from "node:os";
import { createReadStream, createWriteStream } from "node:fs";
import { once } from "node:events";
import readline from "node:readline";

export function claudeProjectKey(projectPath) {
  return projectPath.replace(/[^a-zA-Z0-9]/g, "-");
}

function mappedPath(value, source, target) {
  if (typeof value !== "string") return value;
  const relative = path.relative(source, value);
  if (
    relative === "" ||
    (!relative.startsWith(".." + path.sep) &&
      relative !== ".." &&
      !path.isAbsolute(relative))
  )
    return relative ? path.join(target, relative) : target;
  return value;
}

async function writeJsonlCopy(sourceFile, targetFile, source, target) {
  const temp = `${targetFile}.codedog-${process.pid}-${Date.now()}`;
  const input = createReadStream(sourceFile, { encoding: "utf8" });
  const lines = readline.createInterface({ input, crlfDelay: Infinity });
  const output = createWriteStream(temp, { encoding: "utf8", flags: "wx" });
  try {
    for await (const line of lines) {
      if (!line) continue;
      const record = JSON.parse(line);
      if (Object.hasOwn(record, "cwd"))
        record.cwd = mappedPath(record.cwd, source, target);
      if (!output.write(JSON.stringify(record) + "\n"))
        await once(output, "drain");
    }
    output.end();
    await once(output, "close");
    await fs.link(temp, targetFile);
    // Once the hard link exists, the destination is complete. A leftover
    // temporary name must not turn a successful copy into a failed migration.
    await fs.rm(temp, { force: true }).catch(() => {});
  } catch (error) {
    lines.close();
    output.destroy();
    await fs.rm(temp, { force: true }).catch(() => {});
    throw error;
  }
}

async function rewriteCopiedJsonlFiles(
  sourceDirectory,
  targetDirectory,
  source,
  target,
) {
  for (const entry of await fs.readdir(sourceDirectory, {
    withFileTypes: true,
  })) {
    const sourceEntry = path.join(sourceDirectory, entry.name);
    const targetEntry = path.join(targetDirectory, entry.name);
    if (entry.isDirectory())
      await rewriteCopiedJsonlFiles(sourceEntry, targetEntry, source, target);
    else if (entry.isFile() && entry.name.endsWith(".jsonl")) {
      const rewritten = `${targetEntry}.codedog-rewritten`;
      await writeJsonlCopy(sourceEntry, rewritten, source, target);
      await fs.rename(rewritten, targetEntry);
    }
  }
}

function rewriteIndex(index, source, target, sourceDirectory, targetDirectory) {
  const result = structuredClone(index);
  result.originalPath = mappedPath(result.originalPath, source, target);
  if (Array.isArray(result.entries))
    result.entries = result.entries.map((entry) => ({
      ...entry,
      projectPath: mappedPath(entry.projectPath, source, target),
      fullPath:
        typeof entry.fullPath === "string" &&
        (entry.fullPath === sourceDirectory ||
          entry.fullPath.startsWith(sourceDirectory + path.sep))
          ? targetDirectory + entry.fullPath.slice(sourceDirectory.length)
          : entry.fullPath,
    }));
  return result;
}

/**
 * Copy Claude Code chats to the directory key for a new project path.
 * Source records are never changed or removed, and existing target sessions
 * are never overwritten.
 */
export async function copyClaudeCodeChats(
  source,
  target,
  configDirectory = process.env.CLAUDE_CONFIG_DIR ||
    path.join(os.homedir(), ".claude"),
) {
  const projectsDirectory = path.join(configDirectory, "projects");
  const sourceDirectory = path.join(
    projectsDirectory,
    claudeProjectKey(source),
  );
  const targetDirectory = path.join(
    projectsDirectory,
    claudeProjectKey(target),
  );
  if (sourceDirectory === targetDirectory)
    throw Error("Claude Code 路径编码冲突，无法安全复制聊天记录");

  const sourceEntries = await fs
    .readdir(sourceDirectory, { withFileTypes: true })
    .catch((error) => {
      if (error.code === "ENOENT") return [];
      throw error;
    });
  const sessions = sourceEntries.filter(
    (entry) => entry.isFile() && entry.name.endsWith(".jsonl"),
  );
  if (!sessions.length) return { copied: 0, skipped: 0 };

  const targetExisted = await fs.stat(targetDirectory).catch(() => null);
  await fs.mkdir(targetDirectory, { recursive: true });
  const created = [];
  const indexPath = path.join(targetDirectory, "sessions-index.json");
  const previousIndex = await fs.readFile(indexPath, "utf8").catch((error) => {
    if (error.code === "ENOENT") return null;
    throw error;
  });
  let copied = 0;
  let skipped = 0;

  const rollback = async () => {
    for (const item of created.reverse())
      await fs.rm(item, { recursive: true, force: true }).catch(() => {});
    if (previousIndex === null) await fs.rm(indexPath, { force: true });
    else await fs.writeFile(indexPath, previousIndex);
    if (!targetExisted)
      await fs.rm(targetDirectory, { recursive: true, force: true });
  };

  try {
    const copiedSessionIds = new Set();
    for (const session of sessions) {
      const sessionId = session.name.slice(0, -".jsonl".length);
      const sourceFile = path.join(sourceDirectory, session.name);
      const targetFile = path.join(targetDirectory, session.name);
      if (await fs.stat(targetFile).catch(() => null)) {
        skipped++;
        continue;
      }
      await writeJsonlCopy(sourceFile, targetFile, source, target);
      created.push(targetFile);
      copiedSessionIds.add(sessionId);
      copied++;

      const sourceSupport = path.join(sourceDirectory, sessionId);
      const targetSupport = path.join(targetDirectory, sessionId);
      const support = await fs.stat(sourceSupport).catch(() => null);
      if (
        support?.isDirectory() &&
        !(await fs.stat(targetSupport).catch(() => null))
      ) {
        // Track the directory before copying so a partially completed fs.cp is
        // still removed when the destination project already existed.
        created.push(targetSupport);
        await fs.cp(sourceSupport, targetSupport, {
          recursive: true,
          force: false,
          errorOnExist: true,
          verbatimSymlinks: true,
        });
        await rewriteCopiedJsonlFiles(
          sourceSupport,
          targetSupport,
          source,
          target,
        );
      }
    }

    const sourceIndexPath = path.join(sourceDirectory, "sessions-index.json");
    const sourceIndexText = await fs
      .readFile(sourceIndexPath, "utf8")
      .catch((error) => {
        if (error.code === "ENOENT") return null;
        throw error;
      });
    if (sourceIndexText && copiedSessionIds.size) {
      const incoming = rewriteIndex(
        JSON.parse(sourceIndexText),
        source,
        target,
        sourceDirectory,
        targetDirectory,
      );
      if (Array.isArray(incoming.entries))
        incoming.entries = incoming.entries.filter((entry) =>
          copiedSessionIds.has(entry.sessionId),
        );
      let merged = incoming;
      if (previousIndex) {
        const current = JSON.parse(previousIndex);
        const existingIds = new Set(
          Array.isArray(current.entries)
            ? current.entries.map((entry) => entry.sessionId)
            : [],
        );
        merged = {
          ...current,
          entries: [
            ...(Array.isArray(current.entries) ? current.entries : []),
            ...(Array.isArray(incoming.entries)
              ? incoming.entries.filter(
                  (entry) => !existingIds.has(entry.sessionId),
                )
              : []),
          ],
        };
      }
      const tempIndex = `${indexPath}.codedog-${process.pid}-${Date.now()}`;
      try {
        await fs.writeFile(tempIndex, JSON.stringify(merged, null, 2));
        await fs.rename(tempIndex, indexPath);
      } catch (error) {
        await fs.rm(tempIndex, { force: true }).catch(() => {});
        throw error;
      }
    }
    return { copied, skipped, rollback };
  } catch (error) {
    await rollback().catch(() => {});
    throw Error(`Claude Code 聊天记录复制失败：${error.message}`);
  }
}
