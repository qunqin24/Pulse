import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import process from "node:process";
import {
  ANALYZE_WALL_MS,
  BotError,
  FIXED_FAILURE,
  NDJSON_AGGREGATE_MAX,
  NDJSON_LINE_MAX,
  PINNED_CLI_VERSION,
  assertPinnedLock,
  assertTrustedToolSources,
  buildChildEnv,
  buildPrompt,
  cloneResult,
  envHasForbiddenKeys,
  extractCompletedAssistantText,
  isMain,
  loadAndValidateConfig,
  parseModelJson,
  rejectIfSecretReflected,
  resolveOpencodeBinary,
  trustedLockPath,
  validateInputDocument,
  writeJsonAtomic,
} from "./opencode-lib.mjs";

export async function runAnalyze({
  env = process.env,
  workspace = process.cwd(),
  inputPath = path.resolve("triage-input.json"),
  outputPath = path.resolve("triage-result.json"),
  spawnImpl = spawn,
  binaryPath,
} = {}) {
  const writeFailure = () => {
    writeJsonAtomic(outputPath, cloneResult(FIXED_FAILURE));
  };

  try {
    const apiKey = env.OPENCODE_API_KEY;
    if (typeof apiKey !== "string" || apiKey.length < 8) {
      writeFailure();
      return { result: cloneResult(FIXED_FAILURE), reason: "missing key" };
    }

    assertTrustedToolSources(workspace);
    assertPinnedLock(trustedLockPath(workspace));
    const { configPath: sourceConfig } = loadAndValidateConfig(workspace);
    const configDir = fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-config-"));
    const configPath = path.join(configDir, "opencode.json");
    fs.copyFileSync(sourceConfig, configPath);
    fs.chmodSync(configPath, 0o444);

    const input = validateInputDocument(JSON.parse(fs.readFileSync(inputPath, "utf8")));
    const prompt = buildPrompt(input);

    const nodeModules = path.join(workspace, ".github", "opencode", "node_modules");
    const binary = binaryPath || resolveOpencodeBinary(nodeModules);
    const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-sandbox-"));
    const home = fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-home-"));
    const tmpdir = fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-tmp-"));
    const xdg = {
      config: fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-xdg-config-")),
      data: fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-xdg-data-")),
      cache: fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-xdg-cache-")),
      state: fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-xdg-state-")),
      runtime: fs.mkdtempSync(path.join(os.tmpdir(), "pulse-triage-xdg-runtime-")),
    };

    const childEnv = buildChildEnv({
      home,
      tmpdir,
      xdg,
      configPath,
      apiKey,
      pathEnv: env.PATH || "/usr/bin:/bin",
      extraSsl: {
        SSL_CERT_FILE: env.SSL_CERT_FILE,
        SSL_CERT_DIR: env.SSL_CERT_DIR,
        REQUESTS_CA_BUNDLE: env.REQUESTS_CA_BUNDLE,
        CURL_CA_BUNDLE: env.CURL_CA_BUNDLE,
      },
    });
    if (envHasForbiddenKeys(childEnv)) {
      writeFailure();
      return { result: cloneResult(FIXED_FAILURE), reason: "forbidden env" };
    }

    const authJson = childEnv.OPENCODE_AUTH_CONTENT;
    if (authJson) {
      for (const dir of [path.join(xdg.data, "opencode"), path.join(home, ".local", "share", "opencode")]) {
        fs.mkdirSync(dir, { recursive: true });
        fs.writeFileSync(path.join(dir, "auth.json"), authJson, { encoding: "utf8", mode: 0o600 });
      }
    }

    const args = [
      "--pure",
      "run",
      "--agent",
      "triage",
      "--model",
      "opencode-go/glm-5.3-flash",
      "--format",
      "json",
    ];
    const ndjson = await runBoundedChild({
      binary,
      args,
      cwd: sandbox,
      env: childEnv,
      stdin: prompt,
      spawnImpl,
      wallMs: ANALYZE_WALL_MS,
    });

    const text = extractCompletedAssistantText(ndjson);
    const result = rejectIfSecretReflected(parseModelJson(text), apiKey);
    writeJsonAtomic(outputPath, result);
    return { result, version: PINNED_CLI_VERSION };
  } catch {
    writeFailure();
    return { result: cloneResult(FIXED_FAILURE), reason: "failed" };
  }
}

export function runBoundedChild({
  binary,
  args,
  cwd,
  env,
  stdin,
  spawnImpl,
  wallMs,
  aggregateMax = NDJSON_AGGREGATE_MAX,
  lineMax = NDJSON_LINE_MAX,
}) {
  return new Promise((resolve, reject) => {
    let child;
    try {
      child = spawnImpl(binary, args, {
        cwd,
        env,
        stdio: ["pipe", "pipe", "pipe"],
        detached: true,
      });
    } catch (error) {
      reject(error);
      return;
    }

    let stdout = "";
    let currentLine = "";
    let killed = false;
    const killGroup = () => {
      if (killed) return;
      killed = true;
      const pid = child.pid;
      if (pid) {
        try {
          process.kill(-pid, "SIGKILL");
        } catch {
          try {
            child.kill("SIGKILL");
          } catch {
            // ignore
          }
        }
      }
    };

    const timer = setTimeout(killGroup, wallMs);

    child.stdout.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      currentLine += chunk;
      if (Buffer.byteLength(stdout, "utf8") > aggregateMax) {
        killGroup();
      }
      const parts = currentLine.split("\n");
      currentLine = parts.pop() ?? "";
      if (Buffer.byteLength(currentLine, "utf8") > lineMax) {
        killGroup();
      }
      for (const part of parts) {
        if (Buffer.byteLength(part, "utf8") > lineMax) killGroup();
      }
    });
    child.stderr.setEncoding("utf8");
    child.stderr.resume();

    child.stdin.write(stdin);
    child.stdin.end();

    child.on("error", (error) => {
      clearTimeout(timer);
      killGroup();
      reject(error);
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      if (killed) {
        reject(new BotError("child exceeded bounds"));
        return;
      }
      if (code !== 0) {
        reject(new BotError("child exit not zero"));
        return;
      }
      resolve(stdout);
    });
  });
}

if (isMain(import.meta.url)) {
  runAnalyze().then(() => {
    process.exit(0);
  });
}
