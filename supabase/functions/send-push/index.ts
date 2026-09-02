/**
 * send-push — Supabase Edge Function
 *
 * Sends Firebase Cloud Messaging (FCM) push notifications to employees.
 * Called automatically by database triggers or manually from the app.
 *
 * Environment secrets required (set via `supabase secrets set`):
 *   FIREBASE_SERVICE_ACCOUNT — full JSON of Firebase Admin service account
 *
 * Usage (manual):
 *   POST /functions/v1/send-push
 *   {
 *     "employee_id": "uuid-or-employee-id",
 *     "title": "Leave Approved",
 *     "body": "Your sick leave for Aug 30 has been approved.",
 *     "route": "leaves",
 *     "data": { "leave_id": "..." }
 *   }
 */

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// ─── Firebase Admin SDK (lightweight, no npm) ───────────────────────────────

interface FirebaseServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface FCMMessage {
  token: string;
  notification?: { title: string; body: string };
  data?: Record<string, string>;
  android?: {
    notification?: { channel_id: string; icon: string; color: string };
    priority: "high";
  };
  apns?: {
    payload: {
      aps: {
        alert: { title: string; body: string };
        sound: string;
        badge: number;
      };
    };
  };
}

let accessToken: string | null = null;
let tokenExpiry = 0;

async function getFirebaseAccessToken(): Promise<string> {
  if (accessToken && Date.now() < tokenExpiry) return accessToken;

  const saJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!saJson) throw new Error("FIREBASE_SERVICE_ACCOUNT secret not set");

  const sa: FirebaseServiceAccount = JSON.parse(saJson);
  const now = Math.floor(Date.now() / 1000);
  const expiry = now + 3600;

  const header = btoa(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claimSet = btoa(
    JSON.stringify({
      iss: sa.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      exp: expiry,
      iat: now,
    })
  );

  const dataToSign = `${header}.${claimSet}`;

  // Import private key for signing
  const pemKey = sa.private_key.replace(/\\n/g, "\n");
  const encoder = new TextEncoder();
  const keyData = pemKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binaryDer = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(dataToSign)
  );

  const jwt = `${dataToSign}.${btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "")}`;

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  });

  const tokenData = await resp.json();
  if (!tokenData.access_token) {
    throw new Error(`Failed to get Firebase access token: ${JSON.stringify(tokenData)}`);
  }

  accessToken = tokenData.access_token;
  tokenExpiry = Date.now() + (tokenData.expires_in - 60) * 1000;
  return accessToken!;
}

async function sendFCMMessage(message: FCMMessage): Promise<{ success: boolean; error?: string }> {
  try {
    const accessToken = await getFirebaseAccessToken();
    const projectId = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!).project_id;

    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message }),
      }
    );

    const result = await resp.json();
    if (resp.ok) {
      return { success: true };
    }
    return { success: false, error: result.error?.message || JSON.stringify(result) };
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

// ─── Edge Function Handler ──────────────────────────────────────────────────

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const body = await req.json();
    const {
      employee_id,
      auth_user_id,
      title,
      body: messageBody,
      route,
      data: extraData,
    } = body;

    if (!title || !messageBody) {
      return new Response(
        JSON.stringify({ error: "title and body are required" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    // Create Supabase client with service role to read FCM tokens
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Look up FCM tokens for the target employee/user
    const tokens: string[] = [];

    // 1. Try employee_device_tokens table
    if (employee_id) {
      const { data: deviceTokens } = await supabase
        .from("employee_device_tokens")
        .select("fcm_token")
        .eq("employee_id", employee_id)
        .not("fcm_token", "is", null);

      if (deviceTokens) {
        const filtered = deviceTokens.map((t: any) => t.fcm_token).filter(Boolean);
        tokens.push(...filtered);
      }
    }

    // 2. Try profiles table
    if (auth_user_id) {
      const { data: profileToken } = await supabase
        .from("profiles")
        .select("fcm_token")
        .eq("id", auth_user_id)
        .not("fcm_token", "is", null)
        .single();

      if (profileToken?.fcm_token && !tokens.includes(profileToken.fcm_token)) {
        tokens.push(profileToken.fcm_token);
      }
    }

    // 3. Fallback: lookup by employee_id in profiles
    if (tokens.length === 0 && employee_id) {
      const { data: profileByEmp } = await supabase
        .from("profiles")
        .select("fcm_token, id")
        .eq("employee_id", employee_id)
        .not("fcm_token", "is", null)
        .single();

      if (profileByEmp?.fcm_token) {
        tokens.push(profileByEmp.fcm_token);
        if (!auth_user_id) {
          // Also try to send via profiles id
        }
      }
    }

    // Deduplicate
    const uniqueTokens = [...new Set(tokens)].filter((t) => t && t.length > 10);

    if (uniqueTokens.length === 0) {
      return new Response(
        JSON.stringify({ success: true, sent: 0, message: "No FCM tokens found for employee" }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Send to all tokens
    const results = [];
    for (const token of uniqueTokens) {
      const fcmPayload: FCMMessage = {
        token,
        notification: { title, body: messageBody },
        data: {
          route: route || "home",
          ...(extraData ? Object.fromEntries(
            Object.entries(extraData).map(([k, v]) => [k, String(v)])
          ) : {}),
        },
        android: {
          notification: {
            channel_id: "joy_peoplehr_high_importance",
            icon: "ic_launcher",
            color: "#1A56DB",
          },
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              alert: { title, body: messageBody },
              sound: "default",
              badge: 1,
            },
          },
        },
      };

      const result = await sendFCMMessage(fcmPayload);
      results.push({ token: token.substring(0, 20) + "...", ...result });
    }

    const successCount = results.filter((r) => r.success).length;

    return new Response(
      JSON.stringify({
        success: true,
        sent: successCount,
        total: uniqueTokens.length,
        results,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
