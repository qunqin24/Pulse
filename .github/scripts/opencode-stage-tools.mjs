import path from "node:path";
import process from "node:process";
import { BotError, isMain, stageTrustedTools } from "./opencode-lib.mjs";

export function runStageTools({ workspace = process.cwd(), dest = path.join(process.cwd(), "trusted-tools") } = {}) {
  stageTrustedTools(workspace, dest);
  return dest;
}

if (isMain(import.meta.url)) {
  try {
    runStageTools();
  } catch (error) {
    const message = error instanceof BotError ? error.message : "stage tools failed";
    console.error(message);
    process.exit(1);
  }
}
