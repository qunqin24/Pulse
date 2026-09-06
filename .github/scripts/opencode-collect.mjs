import path from "node:path";
import process from "node:process";
import {
  API_ORIGIN,
  BotError,
  HTTP_ISSUE_MAX,
  botMarkerPresent,
  buildInputDocument,
  capDiscussionComments,
  commentByIdApiPath,
  debounceWaitMs,
  dedupMarker,
  fetchDiscussionPages,
  fingerprintHash,
  getPullFilesPage,
  githubRequestJson,
  isAuthorizedIssueCommenter,
  isHumanUser,
  isMain,
  mergeTriggerComment,
  loadEventPayload,
  loginsEqual,
  parseTrustedTarget,
  pullMatchesTarget,
  readPullIdentity,
  resourceApiPath,
  selectHistoryWindows,
  writeGithubOutput,
  writeJsonAtomic,
} from "./opencode-lib.mjs";

export async function runCollect({
  env = process.env,
  fetchImpl,
  outPath,
  now = () => Date.now(),
  sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
} = {}) {
  const payload = loadEventPayload(env.GITHUB_EVENT_PATH);
  let target;
  try {
    target = parseTrustedTarget(env, payload);
  } catch (error) {
    if (error instanceof BotError && (error.message === "excluded author" || error.message === "ineligible followup")) {
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
  let discussion;

  if (target.kind === "issue_followup") {
    const wait = debounceWaitMs(target.triggeredAt, now());
    if (wait > 0) await sleep(wait);
    const built = await collectFollowup({ target, payload, token, fetchImpl });
    if (built.skip) {
      writeGithubOutput(env, "disposition", "skip");
      return { disposition: "skip" };
    }
    title = built.title;
    body = built.body;
    discussion = built.discussion;
    target = { ...target, fingerprint: built.discussion.fingerprint };
  } else if (target.kind === "issue") {
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

  const document = buildInputDocument({ target, title, body, files, extraNotices, discussion });
  writeJsonAtomic(output, document);
  writeGithubOutput(env, "disposition", "analyze");
  return { output, document, disposition: "analyze" };
}

export async function collectFollowup({ target, payload, token, fetchImpl }) {
  const { json: issue } = await githubRequestJson({
    method: "GET",
    pathname: resourceApiPath("issue", target.number),
    number: target.number,
    token,
    fetchImpl,
    maxBytes: HTTP_ISSUE_MAX,
  });
  if (!issueLiveForFollowup(issue, target)) return { skip: true, reason: "stale" };
  const title = typeof issue.title === "string" ? issue.title : "";
  const body = typeof issue.body === "string" ? issue.body : "";
  if (target.action === "edited") {
    const eventTitle = payload.issue && payload.issue.title;
    const eventBody = payload.issue && payload.issue.body;
    if (title !== eventTitle || body !== (eventBody || "")) return { skip: true, reason: "stale" };
  }
  let triggerComment = null;
  if (target.commentID) {
    let comment;
    try {
      ({ json: comment } = await githubRequestJson({
        method: "GET",
        pathname: commentByIdApiPath(target.commentID),
        number: target.commentID,
        token,
        fetchImpl,
        maxBytes: HTTP_ISSUE_MAX,
      }));
    } catch (error) {
      if (error instanceof BotError && error.status === 404) return { skip: true, reason: "stale" };
      throw error;
    }
    if (!commentMatchesEvent(comment, target, payload)) return { skip: true, reason: "stale" };
    triggerComment = comment;
  }
  const listed = await fetchDiscussionPages({ token, number: target.number, fetchImpl });
  const fetched = mergeTriggerComment(listed, triggerComment);
  const reserveId = triggerComment ? triggerComment.id : undefined;
  const windows = selectHistoryWindows(fetched, { reserveId });
  const fingerprint = fingerprintHash({ title, body, nonbotComments: windows.fingerprintComments });
  const markerTarget = { ...target, fingerprint };
  const marker = dedupMarker(markerTarget);
  if (botMarkerPresent(fetched, marker)) return { skip: true, reason: "duplicate" };
  const discussion = {
    comments: capDiscussionComments(windows.contextComments, { reserveId }),
    fingerprint,
  };
  return { skip: false, title, body, discussion };
}

export function issueLiveForFollowup(issue, target) {
  if (!issue || issue.state !== "open" || issue.pull_request) return false;
  const author = issue.user && issue.user.login;
  return loginsEqual(author, target.issueAuthor);
}

export function commentMatchesEvent(comment, target, payload) {
  if (!comment || typeof comment !== "object") return false;
  if (comment.id !== target.commentID) return false;
  if (!isHumanUser(comment.user)) return false;
  const login = comment.user && comment.user.login;
  if (!isAuthorizedIssueCommenter(login, target.issueAuthor)) return false;
  if (target.commentAuthor && !loginsEqual(login, target.commentAuthor)) return false;
  const eventBody = payload.comment && payload.comment.body;
  if ((comment.body || "") !== (eventBody || "")) return false;
  const expected = `${API_ORIGIN}/repos/qunqin24/Pulse/issues/${target.number}`;
  return comment.issue_url === expected;
}

if (isMain(import.meta.url)) {
  runCollect().catch((error) => {
    const message = error instanceof BotError ? error.message : "collect failed";
    console.error(message);
    process.exit(1);
  });
}
