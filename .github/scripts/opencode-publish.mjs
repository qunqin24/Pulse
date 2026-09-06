import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import {
  BotError,
  DEDUP_MARKER_PREFIX,
  FIXED_FAILURE,
  FOLLOWUP_MARKER_PREFIX,
  HTTP_ISSUE_MAX,
  HTTP_POST_MAX,
  OWNER_PING,
  botAlreadyCommented,
  botMarkerPresent,
  cloneResult,
  commentApiPath,
  dedupMarker,
  fixedFailureComment,
  githubRequestJson,
  isMain,
  listIssueComments,
  loadEventPayload,
  parseTrustedTarget,
  pullMatchesTarget,
  readPullIdentity,
  renderComment,
  resourceApiPath,
  sourceMatchesTarget,
  validateInputDocument,
  validateResult,
} from "./opencode-lib.mjs";
import { collectFollowup as collectFollowupFromCollect } from "./opencode-collect.mjs";

export async function runPublish({
  env = process.env,
  fetchImpl,
  inputPath = path.resolve("triage-input.json"),
  resultPath = path.resolve("triage-result.json"),
} = {}) {
  let payload;
  let target;
  try {
    payload = loadEventPayload(env.GITHUB_EVENT_PATH);
    target = parseTrustedTarget(env, payload);
  } catch {
    return { posted: false, reason: "invalid target" };
  }

  const token = env.GITHUB_TOKEN;
  if (typeof token !== "string" || !token) {
    throw new BotError("missing token");
  }

  if (target.kind === "pull_request") {
    let identity;
    try {
      const { json } = await githubRequestJson({
        method: "GET",
        pathname: resourceApiPath("pull_request", target.number),
        number: target.number,
        token,
        fetchImpl,
        maxBytes: HTTP_ISSUE_MAX,
      });
      identity = readPullIdentity(json);
    } catch {
      return { posted: false, reason: "noverify" };
    }
    if (!pullMatchesTarget(identity, target)) {
      return { posted: false, reason: "stale" };
    }
  } else if (target.kind === "issue") {
    let issue;
    try {
      ({ json: issue } = await githubRequestJson({
        method: "GET",
        pathname: resourceApiPath("issue", target.number),
        number: target.number,
        token,
        fetchImpl,
        maxBytes: HTTP_ISSUE_MAX,
      }));
    } catch {
      return { posted: false, reason: "noverify" };
    }
    if (issue.state !== "open" || issue.pull_request) return { posted: false, reason: "stale" };
    const eventTitle = payload.issue && payload.issue.title;
    const eventBody = payload.issue && payload.issue.body;
    if (issue.title !== eventTitle || (issue.body || "") !== (eventBody || "")) {
      return { posted: false, reason: "stale" };
    }
  } else if (target.kind === "issue_followup") {
    let live;
    try {
      live = await collectFollowupFromCollect({ target, payload, token, fetchImpl });
    } catch {
      return { posted: false, reason: "noverify" };
    }
    if (live.skip) return { posted: false, reason: live.reason || "stale" };
    target = { ...target, fingerprint: live.discussion.fingerprint };
    if (fs.existsSync(inputPath)) {
      try {
        const input = validateInputDocument(JSON.parse(fs.readFileSync(inputPath, "utf8")));
        if (!sourceMatchesTarget(input.source, target) || input.source.fingerprint !== live.discussion.fingerprint) {
          return { posted: false, reason: "stale" };
        }
      } catch {
        // invalid input cannot become a normal model comment
      }
    }
  }

  const result =
    target.kind === "issue_followup" && !followupInputMatches(inputPath, target)
      ? { fixed: true, value: cloneResult(FIXED_FAILURE) }
      : loadPublishResult(inputPath, resultPath, target);
  const body = result.fixed ? fixedFailureComment(target) : renderComment(result.value, target);
  const marker = dedupMarker(target);
  if (
    !body.includes(marker) ||
    (!marker.startsWith(DEDUP_MARKER_PREFIX) && !marker.startsWith(FOLLOWUP_MARKER_PREFIX))
  ) {
    throw new BotError("missing marker");
  }
  if ((result.fixed || result.value.status === "risk" || result.value.status === "failure") && !body.includes(OWNER_PING)) {
    throw new BotError("missing owner ping");
  }

  let comments;
  try {
    ({ comments } = await listIssueComments({ token, number: target.number, fetchImpl }));
  } catch (error) {
    if (error instanceof BotError && error.message === "comment page cap") {
      return { posted: false, reason: "comment-page-cap" };
    }
    return { posted: false, reason: "noverify" };
  }
  if (botAlreadyCommented(comments, marker) || botMarkerPresent(comments, marker)) {
    return { posted: false, reason: "duplicate" };
  }

  await githubRequestJson({
    method: "POST",
    pathname: commentApiPath(target.number),
    number: target.number,
    token,
    fetchImpl,
    maxBytes: HTTP_POST_MAX,
    body: { body },
  });
  return { posted: true, number: target.number, fixed: result.fixed };
}

function followupInputMatches(inputPath, target) {
  try {
    if (!fs.existsSync(inputPath)) return false;
    const input = validateInputDocument(JSON.parse(fs.readFileSync(inputPath, "utf8")));
    return sourceMatchesTarget(input.source, target) && input.source.fingerprint === target.fingerprint;
  } catch {
    return false;
  }
}

export function loadPublishResult(inputPath, resultPath, target) {
  try {
    if (!fs.existsSync(inputPath)) {
      return { fixed: true, value: cloneResult(FIXED_FAILURE) };
    }
    const input = validateInputDocument(JSON.parse(fs.readFileSync(inputPath, "utf8")));
    if (!sourceMatchesTarget(input.source, target)) {
      return { fixed: true, value: cloneResult(FIXED_FAILURE) };
    }
  } catch {
    return { fixed: true, value: cloneResult(FIXED_FAILURE) };
  }

  try {
    if (!fs.existsSync(resultPath)) {
      return { fixed: true, value: cloneResult(FIXED_FAILURE) };
    }
    const parsed = validateResult(JSON.parse(fs.readFileSync(resultPath, "utf8")));
    if (parsed.status === "failure") {
      return { fixed: true, value: cloneResult(FIXED_FAILURE) };
    }
    return { fixed: false, value: parsed };
  } catch {
    return { fixed: true, value: cloneResult(FIXED_FAILURE) };
  }
}

if (isMain(import.meta.url)) {
  runPublish().catch((error) => {
    const message = error instanceof BotError ? error.message : "publish failed";
    console.error(message);
    process.exit(1);
  });
}
