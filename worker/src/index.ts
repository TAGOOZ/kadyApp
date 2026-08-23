/**
 * kady-api — Cloudflare Worker for Elkady Café
 * Supabase stays the source of truth (DB/Auth/Realtime).
 * Worker handles bg processes + auth callback so we never use localhost.
 */

export default {
	async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
		const url = new URL(request.url);

		// health check
		if (url.pathname === "/health") {
			return Response.json({ ok: true, supabase: env.SUPABASE_URL, frontend: env.FRONTEND_URL });
		}

		// OAuth PKCE callback — avoids localhost. Supabase redirects here with ?code=
		// Worker exchanges the code for a session and redirects to the real frontend.
		// Configure Supabase Dashboard → Auth → URL Config:
		//   Site URL = https://kady.elkady.cafe
		//   Redirect URLs = https://kady.elkady.cafe/**, https://kady-api.example.workers.dev/auth/callback/**, kadyapp://login-callback/**
		// Flutter web: oauthRedirectTarget() → https://kady-api.example.workers.dev/auth/callback?next=/
		if (url.pathname === "/auth/callback") {
			const code = url.searchParams.get("code");
			const next = url.searchParams.get("next") ?? "/";
			if (!code) return new Response("Missing code", { status: 400 });
			// Supabase JS on the frontend normally calls exchangeCodeForSession().
			// We just redirect to the frontend with the code preserved so the
			// Flutter web client can call `supabase.auth.exchangeCodeForSession(code)`.
			// This keeps the secret in the client (publishable key) and avoids
			// handling service_role in the worker for auth.
			const redirect = new URL(next, env.FRONTEND_URL);
			redirect.searchParams.set("code", code);
			return Response.redirect(redirect.toString(), 302);
		}

		// Supabase Database Webhook → Worker → bg jobs
		// In Supabase Dashboard → Database → Webhooks: create HTTP webhook
		//   Events: INSERT/UPDATE on public.orders
		//   URL: https://kady-api.example.workers.dev/webhooks/supabase
		//   (optionally add secret header and verify below)
		if (url.pathname === "/webhooks/supabase" && request.method === "POST") {
			// Optional: verify `x-webhook-secret` header
			// const secret = request.headers.get("x-webhook-secret");
			// if (secret !== env.WEBHOOK_SECRET) return new Response("Forbidden", { status: 403 });
			const body = await request.json().catch(() => null);
			// Enqueue bg work without blocking the webhook response
			ctx.waitUntil(handleSupabaseWebhook(body, env));
			return Response.json({ received: true });
		}

		return new Response("Not Found", { status: 404 });
	},

	// Cron: runs daily at 02:00 UTC (configured in wrangler.jsonc triggers.crons)
	// Use for: voucher expiry, processed_orders GC, daily reports.
	async scheduled(controller: ScheduledController, env: Env, ctx: ExecutionContext) {
		ctx.waitUntil(runCronTasks(env, controller.cron));
	},
} satisfies ExportedHandler<Env>;

async function handleSupabaseWebhook(payload: unknown, env: Env) {
	// payload shape: { type: "INSERT" | "UPDATE", table: "orders", record, old_record }
	if (!payload || typeof payload !== "object") return;
	const p = payload as { type?: string; table?: string; record?: Record<string, unknown> };
	if (p.table !== "orders") return;

	// Example bg jobs (idempotent, never writes stamps/points — triggers own that):
	// - fan out to Realtime is already done by Supabase
	// - here you would: send FCM push, Telegram for staff, update analytics
	// const orderId = p.record?.["id"];
	// await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/notify_staff`, { ... headers with service_role ... });

	console.log(`webhook orders ${p.type} ${p.record?.["id"]}`);
}

async function runCronTasks(env: Env, cron: string) {
	console.log(`cron ${cron} at ${new Date().toISOString()}`);
	// Example: call a Postgres function via service_role
	// await fetch(`${env.SUPABASE_URL}/rest/v1/rpc/cleanup_expired_vouchers`, {
	//   method: "POST",
	//   headers: {
	//     apikey: env.SUPABASE_SERVICE_ROLE_KEY,
	//     Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
	//     "Content-Type": "application/json",
	//   },
	// });
}
