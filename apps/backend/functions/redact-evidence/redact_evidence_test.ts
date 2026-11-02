// `redact-evidence` unit tests (`pnpm test:edge`, no stack, no Docker). The
// `Db` is built over fakes; the rules pinned here are the ones the function
// needs to be honest before it touches a file, plus the shape of what it hands
// to `set_redaction_done`.
import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";
import { redact } from "./index.ts";
import { EvidenceRow, redactedPath } from "../shared/rest.ts";
import { sha256Hex } from "./sha256.ts";

const MEMBER = "00000000-0000-0000-000a-0000000000000001";
const REQUEST = "00000000-0000-0000-000b-0000000000000002";
const ORIGINAL =
  `${MEMBER}/${REQUEST}/00000000-0000-0000-000c-0000000000000003.jpg`;
const REDACTED = `${MEMBER}/${REQUEST}/redacted.jpg`;

const ORIGINAL_BYTES = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]).buffer;

interface Files {
  read(bucket: string, path: string): Promise<ArrayBuffer | undefined>;
  write(bucket: string, path: string, bytes: ArrayBuffer): Promise<void>;
}

function makeDb(files: Map<string, ArrayBuffer>, rpcLog: string[]) {
  return {
    storage(): Files {
      return {
        read: (bucket: string, path: string) =>
          Promise.resolve(files.get(`${bucket}/${path}`)),
        write: (bucket: string, path: string, bytes: ArrayBuffer) => {
          files.set(`${bucket}/${path}`, bytes);
          return Promise.resolve();
        },
      };
    },
    rpc: (name: string, _args: Record<string, unknown>) => {
      rpcLog.push(name);
      return Promise.resolve();
    },
  };
}

const DECLARED_SHA = await sha256Hex(ORIGINAL_BYTES);

function row(sha: string) {
  return {
    id: "e1",
    request_id: REQUEST,
    original_path: ORIGINAL,
    sha256: sha,
    redaction_status: "pending",
  } as EvidenceRow;
}

Deno.test("a row whose file reached storage gets a redacted copy and auto_done", async () => {
  const files = new Map([
    [`evidence-original/${ORIGINAL}`, ORIGINAL_BYTES],
  ]);
  const rpcLog: string[] = [];
  const db = makeDb(files, rpcLog);
  const result = await redact(row(DECLARED_SHA), db);
  assertEquals(result.redactedPath, REDACTED);
  assertEquals(files.has(`evidence-redacted/${REDACTED}`), true);
  assertEquals(rpcLog, ["set_redaction_done"]);
});

Deno.test("a row whose file never arrived gets no auto_done", async () => {
  const files = new Map<string, ArrayBuffer>();
  const rpcLog: string[] = [];
  const db = makeDb(files, rpcLog);
  const result = await redact(row(DECLARED_SHA), db);
  assertEquals(result.redactedPath, null);
  assertEquals(result.regionsMasked, 0);
  assertEquals(rpcLog, []);
});

Deno.test("a stored file that doesn't match the row's hash refuses", async () => {
  const files = new Map([
    [`evidence-original/${ORIGINAL}`, new Uint8Array([9, 9, 9]).buffer],
  ]);
  const rpcLog: string[] = [];
  const db = makeDb(files, rpcLog);
  assertRejects(
    async () => redact(row(DECLARED_SHA), db),
    Error,
    "the stored original doesn't match the row",
  );
  assertEquals(rpcLog, []);
});

Deno.test("the redacted copy keeps the member folder and drops the capture id", async () => {
  assertEquals(redactedPath(ORIGINAL), REDACTED);
});

Deno.test("a path outside a member folder is refused", async () => {
  assertThrows(
    () => redactedPath("shared/anything.jpg"),
    Error,
    "the original's path doesn't follow the member folder",
  );
});
