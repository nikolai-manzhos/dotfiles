// Reports opencode's state for the tmux pane it runs in through agent-state.sh
// (see tmux/agent-status/agent-status.conf). One file serves both versions;
// install.sh links it as plugins/tmux-agent-state.js and
// plugins/tmux-agent-state/tui.js in the opencode config dir:
//   - opencode 1.x loads the .js file and calls server().
//   - opencode 2.x calls setup() for the .js file on its shared server and for
//     tui.js in the TUI. The server serves every pane, so only the TUI process
//     knows which pane (and session) it belongs to; setup() does nothing on the server.

import { execFile, execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const SCRIPT =
  process.env.AGENT_STATE_CMD ??
  join(dirname(realpathSync(fileURLToPath(import.meta.url))), "agent-state.sh");

const BUSY_STATUSES = new Set(["active", "busy", "pending", "retry", "running", "streaming", "working"]);

const EXECUTION_STATES = {
  "session.execution.started": "working",
  "session.execution.succeeded": "done",
  "session.execution.interrupted": "idle",
  "session.execution.failed": "waiting",
};

// Calls are chained so tmux sees states in order, and repeats are skipped.
function reporter() {
  let last;
  let chain = Promise.resolve();
  const report = (state) => {
    if (state === last) return chain;
    last = state;
    chain = chain.then(() => new Promise((resolve) => execFile(SCRIPT, [state], () => resolve())));
    return chain;
  };
  // Synchronous so it still runs while the process is exiting.
  const clear = () => {
    last = "clear";
    try {
      execFileSync(SCRIPT, ["clear"], { stdio: "ignore" });
    } catch {}
  };
  return { report, clear };
}

async function server() {
  if (!process.env.TMUX_PANE) return {};

  const { report, clear } = reporter();
  // Subagents run as child sessions; only their permission prompts and questions count.
  const childSessions = new Set();
  // What the next idle means: a finished run, an interrupt, or a failure.
  let outcome = "done";

  process.once("exit", clear);
  report("idle");

  const working = () => {
    outcome = "done";
    return report("working");
  };

  return {
    "chat.message": async ({ sessionID } = {}) => {
      if (!childSessions.has(sessionID)) await working();
    },
    event: async ({ event }) => {
      const props = event?.properties ?? {};
      if (props.info?.parentID) childSessions.add(props.info.id);

      switch (event?.type) {
        case "permission.asked":
        case "question.asked":
          return report("waiting");
        case "permission.replied":
        case "question.replied":
        case "question.rejected":
          return report("working");
      }
      if (childSessions.has(props.sessionID)) return;

      switch (event?.type) {
        case "session.status": {
          const status = typeof props.status === "string" ? props.status : props.status?.type;
          const kind = String(status ?? "").toLowerCase();
          if (kind === "idle") return report(outcome);
          if (BUSY_STATUSES.has(kind)) return working();
          return;
        }
        case "session.idle":
          return report(outcome);
        case "session.error":
          outcome = props.error?.name === "MessageAbortedError" ? "idle" : "waiting";
          return report(outcome);
      }
    },
  };
}

function setup(ctx) {
  // Server contexts have no router or data cache; the TUI owns reporting.
  if (!process.env.TMUX_PANE || typeof ctx?.data?.listen !== "function" || !ctx?.ui?.router) return;

  const { report, clear } = reporter();
  const parents = new Map();
  let selected; // root session shown in this pane
  let base = "idle";
  let pending = new Set(); // unanswered permission prompts and forms

  const root = (id) => {
    const seen = new Set();
    while (typeof id === "string" && !seen.has(id)) {
      seen.add(id);
      const parentID = ctx.data.session.get?.(id)?.parentID ?? parents.get(id);
      if (!parentID) return id;
      id = parentID;
    }
  };

  const publish = () => report(pending.size ? "waiting" : base);

  // Re-seeds state when the TUI switches to a different session.
  const sync = () => {
    const route = ctx.ui.router.current?.();
    const id = route?.type === "session" ? root(route.sessionID) : undefined;
    if (id === selected) return publish();
    selected = id;
    base = "idle";
    pending = new Set();
    if (id) {
      if (ctx.data.session.status?.(id) === "running") base = "working";
      for (const member of [id, ...(ctx.data.session.family?.(id) ?? [])]) {
        for (const item of ctx.data.session.permission?.list?.(member) ?? []) pending.add(`permission:${item.id}`);
        for (const item of ctx.data.session.form?.list?.(member) ?? []) pending.add(`form:${item.id}`);
      }
    }
    return publish();
  };

  const unsubscribe = ctx.data.listen(({ details: event } = {}) => {
    const data = event?.data;
    if (!data) return;
    if (event.type === "session.created" && data.parentID) parents.set(data.sessionID, data.parentID);
    const synced = sync();

    const id = event.type === "form.created" ? data.form?.sessionID : data.sessionID;
    if (!selected || root(id) !== selected) return synced;
    switch (event.type) {
      case "permission.asked":
        pending.add(`permission:${data.id}`);
        break;
      case "permission.replied":
        pending.delete(`permission:${data.requestID}`);
        break;
      case "form.created":
        pending.add(`form:${data.form.id}`);
        break;
      case "form.replied":
      case "form.cancelled":
        pending.delete(`form:${data.id}`);
        break;
      default:
        // Subagent runs start and finish inside the parent's run.
        if (!EXECUTION_STATES[event.type] || id !== selected) return synced;
        base = EXECUTION_STATES[event.type];
    }
    return publish();
  });

  process.once("exit", clear);
  report("idle");
  sync();
  const timer = setInterval(sync, 1000);
  timer.unref?.();

  return () => {
    clearInterval(timer);
    unsubscribe?.();
    process.removeListener("exit", clear);
    clear();
  };
}

export default {
  id: "tmux-agent-state",
  server,
  setup,
};
