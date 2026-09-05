import path from "node:path";
import process from "node:process";
import {
  BotError,
  HTTP_ISSUE_MAX,
  buildInputDocument,
  getPullFilesPage,
  githubRequestJson,
  isMain,
  loadEventPayload,
  parseTrustedTarget,
  pullMatchesTarget,
  readPullIdentity,
  resourceApiPath,
  writeGithubOutput,
  writeJsonAtomic,
} from "./opencode-lib.mjs";

export async function runCollect({ env = process.env, fetchImpl, outPath } = {}) {
  let target;
  try {
    target = parseTrustedTarget(env, loadEventPayload(env.GITHUB_EVENT_PATH));
  } catch (error) {
    if (error instanceof BotError && error.message === "excluded author") {
      writeGithubOutput(env, "disposition", "skip");
      return { disposition: "skip" };
    }
    throw error;
  }
  const token = env.GITHUB_TOKEN;
  if (typeof token !== "string" || !token) throw new BotError("missing token");
  const output = outPath || path.resolve("triage-input.json");

  let title = "";
  let body = "";
  let files = [];
  const extraNotices = [];

  if (target.kind === "issue") {
    const { json } = await githubRequestJson({
      method: "GET",
      pathname: resourceApiPath("issue", target.number),
      number: target.number,
      token,
      fetchImpl,
      maxBytes: HTTP_ISSUE_MAX,
    });
    title = typeof json.title === "string" ? json.title : "";
    body = typeof json.body === "string" ? json.body : "";
  } else {
    const first = await githubRequestJson({
      method: "GET",
      pathname: resourceApiPath("pull_request", target.number),
      number: target.number,
      token,
      fetchImpl,
      maxBytes: HTTP_ISSUE_MAX,
    });
    if (!pullMatchesTarget(readPullIdentity(first.json), target)) {
      writeGithubOutput(env, "disposition", "skip");
      return { disposition: "skip" };
    }
    title = typeof first.json.title === "string" ? first.json.title : "";
    body = typeof first.json.body === "string" ? first.json.body : "";
    const page = await getPullFilesPage(fetchImpl, token, target.number);
    files = page.files;
    if (page.truncated) extraNotices.push("Pull request file list exceeded one page of 100.");
    const second = await githubRequestJson({
      method: "GET",
      pathname: resourceApiPath("pull_request", target.number),
      number: target.number,
      token,
      fetchImpl,
      maxBytes: HTTP_ISSUE_MAX,
    });
    if (!pullMatchesTarget(readPullIdentity(second.json), target)) {
      writeGithubOutput(env, "disposition", "skip");
      return { disposition: "skip" };
    }
    title = typeof second.json.title === "string" ? second.json.title : "";
    body = typeof second.json.body === "string" ? second.json.body : "";
  }

  const document = buildInputDocument({ target, title, body, files, extraNotices });
  writeJsonAtomic(output, document);
  writeGithubOutput(env, "disposition", "analyze");
  return { output, document, disposition: "analyze" };
}

if (isMain(import.meta.url)) {
  runCollect().catch((error) => {
    const message = error instanceof BotError ? error.message : "collect failed";
    console.error(message);
    process.exit(1);
  });
}
