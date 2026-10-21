// Tests for opencode-agent-state.js; run by test.sh or `node --test`.
// agent-state.sh is replaced by a stub that logs the states it receives.

import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { after, beforeEach, test } from "node:test";

const tmp = mkdtempSync(join(tmpdir(), "agent-state-"));
const log = join(tmp, "calls.log");
const stub = join(tmp, "agent-state.sh");
writeFileSync(stub, `#!/bin/sh\necho "$1" >> "${log}"\n`);
chmodSync(stub, 0o755);
process.env.AGENT_STATE_CMD = stub;
process.env.TMUX_PANE = "%1";

const { default: plugin } = await import("./opencode-agent-state.js");

const calls = () => {
  try {
    return readFileSync(log, "utf8").split("\n").filter(Boolean);
  } catch {
    return [];
  }
};

beforeEach(() => rmSync(log, { force: true }));
after(() => rmSync(tmp, { recursive: true, force: true }));

// opencode 1.x server plugin

const v1Event = (type, properties) => ({ event: { type, properties } });

test("v1: prompt, permission prompt and finish", async () => {
  const hooks = await plugin.server();
  await hooks["chat.message"]({ sessionID: "s1" });
  await hooks.event(v1Event("session.status", { sessionID: "s1", status: { type: "busy" } }));
  await hooks.event(v1Event("permission.asked", { sessionID: "s1" }));
  await hooks.event(v1Event("permission.replied", { sessionID: "s1" }));
  await hooks.event(v1Event("session.status", { sessionID: "s1", status: { type: "idle" } }));
  await hooks.event(v1Event("session.idle", { sessionID: "s1" }));
  assert.deepEqual(calls(), ["idle", "working", "waiting", "working", "done"]);
});

test("v1: subagents can ask for permission but don't finish the run", async () => {
  const hooks = await plugin.server();
  await hooks["chat.message"]({ sessionID: "s1" });
  await hooks.event(v1Event("session.created", { info: { id: "c1", parentID: "s1" } }));
  await hooks["chat.message"]({ sessionID: "c1" });
  await hooks.event(v1Event("session.idle", { sessionID: "c1" }));
  await hooks.event(v1Event("question.asked", { sessionID: "c1" }));
  await hooks.event(v1Event("question.replied", { sessionID: "c1" }));
  await hooks.event(v1Event("session.idle", { sessionID: "s1" }));
  assert.deepEqual(calls(), ["idle", "working", "waiting", "working", "done"]);
});

test("v1: interrupts end idle, failures keep waiting", async () => {
  const hooks = await plugin.server();
  await hooks["chat.message"]({ sessionID: "s1" });
  await hooks.event(v1Event("session.error", { sessionID: "s1", error: { name: "MessageAbortedError" } }));
  await hooks.event(v1Event("session.idle", { sessionID: "s1" }));
  await hooks["chat.message"]({ sessionID: "s1" });
  await hooks.event(v1Event("session.error", { sessionID: "s1", error: { name: "APIError" } }));
  await hooks.event(v1Event("session.idle", { sessionID: "s1" }));
  await hooks["chat.message"]({ sessionID: "s1" });
  await hooks.event(v1Event("session.idle", { sessionID: "s1" }));
  assert.deepEqual(calls(), ["idle", "working", "idle", "working", "waiting", "working", "done"]);
});

test("v1: no-op outside tmux", async () => {
  delete process.env.TMUX_PANE;
  try {
    assert.deepEqual(await plugin.server(), {});
  } finally {
    process.env.TMUX_PANE = "%1";
  }
  assert.deepEqual(calls(), []);
});

// opencode 2.x TUI plugin

function fakeTui({ sessions = {}, status = {}, permissions = {}, forms = {} } = {}) {
  let listener;
  const ctx = {
    route: "s1",
    ui: {
      router: {
        current: () => (ctx.route ? { type: "session", sessionID: ctx.route } : { type: "home" }),
      },
    },
    data: {
      listen: (fn) => {
        listener = fn;
        return () => (listener = undefined);
      },
      session: {
        get: (id) => sessions[id],
        status: (id) => status[id] ?? "idle",
        family: (id) => Object.keys(sessions).filter((s) => sessions[s].parentID === id),
        permission: { list: (id) => permissions[id] ?? [] },
        form: { list: (id) => forms[id] ?? [] },
      },
    },
  };
  const emit = (type, data) => listener?.({ details: { type, data } });
  return { ctx, emit };
}

test("v2: runs go working, then done or waiting; dispose clears", async () => {
  const { ctx, emit } = fakeTui({ sessions: { s1: {} } });
  const dispose = plugin.setup(ctx);
  await emit("session.execution.started", { sessionID: "s1" });
  await emit("session.execution.succeeded", { sessionID: "s1" });
  await emit("session.execution.started", { sessionID: "s1" });
  await emit("session.execution.failed", { sessionID: "s1" });
  dispose();
  assert.deepEqual(calls(), ["idle", "working", "done", "working", "waiting", "clear"]);
});

test("v2: subagent prompts wait until answered; subagent runs don't end the run", async () => {
  const { ctx, emit } = fakeTui({ sessions: { s1: {}, c1: { parentID: "s1" } } });
  const dispose = plugin.setup(ctx);
  await emit("session.execution.started", { sessionID: "s1" });
  await emit("session.execution.started", { sessionID: "c1" });
  await emit("permission.asked", { id: "p1", sessionID: "c1" });
  await emit("permission.replied", { requestID: "p1", sessionID: "c1" });
  await emit("session.execution.succeeded", { sessionID: "c1" });
  await emit("form.created", { form: { id: "f1", sessionID: "s1" } });
  await emit("form.cancelled", { id: "f1", sessionID: "s1" });
  await emit("session.execution.interrupted", { sessionID: "s1" });
  dispose();
  assert.deepEqual(calls(), ["idle", "working", "waiting", "working", "waiting", "working", "idle", "clear"]);
});

test("v2: sessions shown in other panes are ignored", async () => {
  const { ctx, emit } = fakeTui({ sessions: { s1: {}, s2: {} } });
  const dispose = plugin.setup(ctx);
  await emit("session.execution.started", { sessionID: "s2" });
  await emit("session.created", { sessionID: "c2", parentID: "s2" });
  await emit("permission.asked", { id: "p2", sessionID: "c2" });
  await emit("session.execution.failed", { sessionID: "s2" });
  dispose();
  assert.deepEqual(calls(), ["idle", "clear"]);
});

test("v2: switching sessions re-seeds state from the cache", async () => {
  const { ctx, emit } = fakeTui({
    sessions: { s1: {}, s2: {}, c2: { parentID: "s2" } },
    status: { s2: "running" },
    permissions: { c2: [{ id: "p9" }] },
  });
  const dispose = plugin.setup(ctx);
  await emit("session.execution.started", { sessionID: "s1" });
  await emit("session.execution.succeeded", { sessionID: "s1" });
  ctx.route = "c2";
  await emit("session.updated", { sessionID: "s2" });
  await emit("permission.replied", { requestID: "p9", sessionID: "c2" });
  ctx.route = undefined;
  await emit("session.updated", { sessionID: "s2" });
  dispose();
  assert.deepEqual(calls(), ["idle", "working", "done", "waiting", "working", "idle", "clear"]);
});

test("v2: server contexts and panes outside tmux are ignored", () => {
  assert.equal(plugin.setup({}), undefined);
  assert.equal(plugin.setup({ data: { listen: () => {} } }), undefined);
  delete process.env.TMUX_PANE;
  try {
    assert.equal(plugin.setup(fakeTui().ctx), undefined);
  } finally {
    process.env.TMUX_PANE = "%1";
  }
  assert.deepEqual(calls(), []);
});
