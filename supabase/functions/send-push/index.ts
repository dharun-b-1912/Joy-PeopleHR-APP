import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

interface FirebaseServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface FCMTarget {
  token?: string;
  topic?: string;
  notification?: { title: string; body: string };
  data?: Record<string, string>;
  android?: {
    notification?: {
      channel_id: string;
      sound?: string;
      default_vibrate_timings?: boolean;
      notification_priority?: string;
      icon?: string;
      color?: string;
    };
    priority?: "HIGH" | "NORMAL";
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

  const pemKey = sa.private_key.replace(/\\n/g, "\n");
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
    new TextEncoder().encode(dataToSign)
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

async function sendFCMMessage(target: FCMTarget): Promise<{ success: boolean; messageId?: string; error?: string }> {
  try {
    const token = await getFirebaseAccessToken();
    const sa: FirebaseServiceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
    const projectId = sa.project_id;

    const resp = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ message: target }),
      }
    );

    const result = await resp.json();
    if (resp.ok) {
      return { success: true, messageId: result.name };
    }
    return { success: false, error: result.error?.message || JSON.stringify(result) };
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

serve(async (req) => {
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
      topic,
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

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    const stringData: Record<string, string> = {
      title: String(title),
      body: String(messageBody),
      message: String(messageBody),
      route: String(route || "home"),
      timestamp: String(Date.now()),
      ...(extraData ? Object.fromEntries(
        Object.entries(extraData).map(([k, v]) => [k, String(v)])
      ) : {}),
    };

    const androidConfig = {
      priority: "HIGH" as const,
      notification: {
        channel_id: "joy_peoplehr_high_importance",
        sound: "default",
        default_vibrate_timings: true,
        notification_priority: "PRIORITY_MAX",
        icon: "ic_launcher",
        color: "#1A56DB",
      },
    };

    const apnsConfig = {
      payload: {
        aps: {
          alert: { title, body: messageBody },
          sound: "default",
          badge: 1,
        },
      },
    };

    const results: any[] = [];

    // If explicit topic specified or broadcast
    if (topic) {
      const topicResult = await sendFCMMessage({
        topic: topic.replace(/^\/topics\//, ""),
        notification: { title, body: messageBody },
        data: stringData,
        android: androidConfig,
        apns: apnsConfig,
      });
      results.push({ target: `topic:${topic}`, ...topicResult });
    }

    // Lookup device tokens
    const tokens: string[] = [];

    if (employee_id) {
      const { data: dt } = await supabase
        .from("employee_device_tokens")
        .select("fcm_token")
        .eq("employee_id", employee_id);
      if (dt) {
        tokens.push(...dt.map((r: any) => r.fcm_token).filter(Boolean));
      }
    }

    if (auth_user_id) {
      const { data: dt2 } = await supabase
        .from("employee_device_tokens")
        .select("fcm_token")
        .eq("auth_user_id", auth_user_id);
      if (dt2) {
        tokens.push(...dt2.map((r: any) => r.fcm_token).filter(Boolean));
      }

      const { data: ps } = await supabase
        .from("push_subscriptions")
        .select("endpoint")
        .eq("user_id", auth_user_id);
      if (ps) {
        tokens.push(...ps.map((r: any) => r.endpoint).filter((e: string) => e && !e.startsWith("https://")));
      }
    }

    const uniqueTokens = [...new Set(tokens)].filter((t) => t && t.length > 10);

    for (const token of uniqueTokens) {
      const tokenResult = await sendFCMMessage({
        token,
        notification: { title, body: messageBody },
        data: stringData,
        android: androidConfig,
        apns: apnsConfig,
      });
      results.push({ target: `token:${token.substring(0, 15)}...`, ...tokenResult });
    }

    // If no tokens found and no explicit topic, broadcast to fallback topics for safety
    if (uniqueTokens.length === 0 && !topic) {
      // Send to employee-specific topic or all_employees topic
      const fallbackTopic = employee_id ? `emp_${employee_id}` : "all_employees";
      const topicFallbackResult = await sendFCMMessage({
        topic: fallbackTopic,
        notification: { title, body: messageBody },
        data: stringData,
        android: androidConfig,
        apns: apnsConfig,
      });
      results.push({ target: `fallback_topic:${fallbackTopic}`, ...topicFallbackResult });

      // Also send to all_employees if this was a broadcast/announcement
      if (route === 'announcement' || route === 'broadcast' || !employee_id) {
        const allEmployeesResult = await sendFCMMessage({
          topic: "all_employees",
          notification: { title, body: messageBody },
          data: stringData,
          android: androidConfig,
          apns: apnsConfig,
        });
        results.push({ target: "fallback_topic:all_employees", ...allEmployeesResult });
      }
    }

    const successful = results.filter((r) => r.success).length;

    return new Response(
      JSON.stringify({
        success: successful > 0,
        sent: successful,
        total: results.length,
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
