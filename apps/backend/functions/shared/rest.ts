// The one way the edge functions in this directory talk back to the stack:
// PostgREST against the local project or the hosted one, with the service key
// from the environment the Supabase Edge Runtime injects (`SUPABASE_URL`,
// `SUPABASE_SERVICE_KEY`). A function never writes to a table itself: it calls
// the same guarded functions the members' app calls, so the function's word is
// never more trusted than the function's own guard allows (`private.is_service()`
// inside those functions). The tests build a `Db` over fakes instead of the
// network, so they need no stack, no Docker and no signed requests.

/** One object in a private bucket, or `undefined` when it was never stored. */
interface StorageReader {
  read(bucket: string, path: string): Promise<ArrayBuffer | undefined>;
  write(bucket: string, path: string, bytes: ArrayBuffer): Promise<void>;
}

/** One database-function call as the service role; throws on a refusal. */
interface RpcCaller {
  call(name: string, args: Record<string, unknown>): Promise<unknown>;
}

export interface Db {
  storage(): StorageReader;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
}

/** The row `redact-evidence` reads before it touches a file. */
export interface EvidenceRow {
  id: string;
  request_id: string;
  original_path: string;
  /** The original's lower-case hex SHA-256 (`evidence.sha256`). */
  sha256: string;
  redaction_status: string;
}

/**
 * The redacted copy's path for a row. The original lives in the private
 * `evidence-original` bucket as `<member id>/<request id>/<capture id>.<ext>`
 * (the upload policy requires the member's id first); the redacted copy keeps
 * the same shape in `evidence-redacted`, with the capture id replaced by `redacted`
 * so nothing of the original's name survives, and the row stays unique because
 * the pair member/request/capture is unique.
 */
export function redactedPath(originalPath: string): string {
  const parts = originalPath.split("/");
  if (parts.length < 3 || !/^[0-9a-f]{8}-[0-9a-f-]*$/i.test(parts[0])) {
    throw new Error(
      `the original's path doesn't follow the member folder: ${originalPath}`,
    );
  }
  const ext = /\.[a-z0-9]{1,8}$/i.test(parts[parts.length - 1])
    ? parts[parts.length - 1].replace(/^[^.]+/, "")
    : ".bin";
  return `${parts[0]}/${parts[1]}/redacted${ext}`;
}

/** The environment the Edge Runtime injects; read on use so tests need no env. */
function stackUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}

function serviceKey(): string {
  return Deno.env.get("SUPABASE_SERVICE_KEY") ?? "";
}

/** The real client, for a handler running in the runtime rather than a test. */
export const liveDb: Db = {
  storage: (): StorageReader => restStorage(stackUrl(), serviceKey()),
  rpc: (name: string, args: Record<string, unknown>): Promise<unknown> =>
    restRpc(stackUrl(), serviceKey()).call(name, args),
};

function restStorage(base: string, key: string): StorageReader {
  return {
    read: (bucket: string, path: string): Promise<ArrayBuffer | undefined> =>
      getObject(`${base}/storage/v1/object/${bucket}/${path}`, key),
    write: (bucket: string, path: string, bytes: ArrayBuffer): Promise<void> =>
      putObject(`${base}/storage/v1/object/${bucket}/${path}`, key, bytes),
  };
}

function restRpc(base: string, key: string): RpcCaller {
  return {
    call: (name: string, args: Record<string, unknown>): Promise<unknown> =>
      post(`${base}/rpc/${name}`, key, args),
  };
}

/**
 * Read rows of a table as the service role (a cron-time job, mostly). The
 * service bypasses RLS, but only the tables the schema grants it; a job never
 * writes through this — writes go through the guarded functions.
 */
export async function queryRows(
  table: string,
  params: Record<string, string>,
): Promise<unknown[]> {
  const base = stackUrl();
  const key = serviceKey();
  if (key === "" || base === "") {
    throw new Error("no stack: the job cannot read the database");
  }
  const filter = Object.entries(params)
    .map(([name, value]) => `${encodeURIComponent(name)}=${encodeURIComponent(value)}`)
    .join("&");
  const response = await fetch(
    `${base}/${table}${filter === "" ? "" : `?${filter}`}`,
    {
      headers: {
        accept: "application/json",
        authorization: `Bearer ${key}`,
      },
    },
  );
  if (!response.ok) {
    throw new Error(`the read refused: ${response.status}`);
  }
  return await response.json();
}

async function getObject(
  url: string,
  key: string,
): Promise<ArrayBuffer | undefined> {
  if (key === "") {
    throw new Error("no service key: the function cannot read the bucket");
  }
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${key}` },
  });
  // A 403 or 404 is the honest answer for a file that was never stored.
  if (!response.ok) return undefined;
  return (await response.bytes()).buffer;
}

async function putObject(
  url: string,
  key: string,
  bytes: ArrayBuffer,
): Promise<void> {
  if (key === "") {
    throw new Error("no service key: the function cannot write the bucket");
  }
  const response = await fetch(url, {
    method: "POST",
    headers: { authorization: `Bearer ${key}` },
    body: bytes,
  });
  if (!response.ok) {
    throw new Error(`the bucket refused the redacted copy: ${response.status}`);
  }
}

async function post(
  url: string,
  key: string,
  args: Record<string, unknown>,
): Promise<unknown> {
  if (key === "") {
    throw new Error("no service key: the function cannot call the database");
  }
  const response = await fetch(url, {
    method: "POST",
    headers: { authorization: `Bearer ${key}` },
    body: JSON.stringify(args),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`the database refused the call: ${text}`);
  return text === "" ? null : JSON.parse(text);
}
