import { assertEquals } from "jsr:@std/assert";
import { stub } from "jsr:@std/testing/mock";

Deno.test("CORS allows only configured production origins and supports push unsubscribe", async () => {
  const allowed = "https://admin.example.test";
  const env = stub(Deno.env, "get", (key: string) => key === "ALLOWED_ORIGINS" ? allowed : undefined);
  try {
    const { corsHeaders, json } = await import("./cors.ts");
    const requestFor = (origin: string) => new Request("https://edge.example.test", {
      headers: { Origin: origin },
    });
    const request = requestFor(allowed);
    assertEquals(json(request, {}).headers.get("access-control-allow-origin"), allowed);
    assertEquals(corsHeaders(request)["Access-Control-Allow-Methods"], "POST, OPTIONS");
    assertEquals(corsHeaders(request, "POST, DELETE, OPTIONS")["Access-Control-Allow-Methods"], "POST, DELETE, OPTIONS");
    for (const origin of ["https://unlisted.example.test", "http://localhost:4173", "null"]) {
      assertEquals(json(requestFor(origin), {}).headers.get("access-control-allow-origin"), null);
    }
    const native = json(new Request("https://edge.example.test"), { ok: true });
    assertEquals(native.status, 200);
    assertEquals(native.headers.get("access-control-allow-origin"), null);
  } finally {
    env.restore();
  }
});
