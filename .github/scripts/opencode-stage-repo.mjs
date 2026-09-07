import path from "node:path";
import process from "node:process";
import { BotError, SNAPSHOT_DIR, isMain, stageRepoSnapshot } from "./opencode-lib.mjs";

export function runStageRepo({
  workspace = process.cwd(),
  dest = path.join(process.cwd(), SNAPSHOT_DIR),
} = {}) {
  return { dest, ...stageRepoSnapshot(workspace, dest) };
}

if (isMain(import.meta.url)) {
  try {
    const { files, bytes } = runStageRepo();
    console.log(`staged ${files} files, ${bytes} bytes`);
  } catch (error) {
    const message = error instanceof BotError ? error.message : "stage repo failed";
    console.error(message);
    process.exit(1);
  }
}
