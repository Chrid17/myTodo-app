// Supabase Edge Function - Push notifications via FCM v1 API + Web Push
// Sends to ALL platforms: Android, iOS, Web, macOS, Windows
//
// SECRETS to set:
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account",...}' 
//   supabase secrets set VAPID_PRIVATE_KEY=your_private_key  (optional, for web push)
//   supabase secrets set VAPID_PUBLIC_KEY=your_public_key    (optional, for web push)
//
// Deploy: supabase functions deploy send-push-notifications
// Cron: Run every minute - see FIREBASE_PUSH_SETUP.md

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v4.14.4/index.ts"

import webpush from "https://esm.sh/web-push@3.6.7";

const FIREBASE_SERVICE_ACCOUNT = Deno.env.get('FIREBASE_SERVICE_ACCOUNT') || '';
const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY') || '';
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY') || '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

/** Get OAuth2 access token from Firebase service account */
async function getAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const jwt = await new SignJWT({})
    .setProtectedHeader({ alg: 'RS256' })
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .setIssuer(serviceAccount.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setSubject(serviceAccount.client_email)
    .addClaim('scope', 'https://www.googleapis.com/auth/firebase.messaging')
    .sign(await importPKCS8(serviceAccount.private_key, 'RS256'));

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const data = await res.json();
  if (data.error) throw new Error(data.error_description || data.error);
  return data.access_token;
}

/** Send FCM v1 message to a single device */
async function sendFcmV1(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  todoId: string
): Promise<{ success: boolean; error?: string }> {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: {
            todo_id: todoId,
            type: 'todo_reminder',
          },
          android: {
            priority: 'high',
            notification: { sound: 'default', channel_id: 'todo_reminders' },
          },
          apns: {
            headers: { 'apns-priority': '10' },
            payload: {
              aps: {
                alert: { title, body },
                sound: 'default',
                badge: 1,
                'content-available': 1,
              },
            },
          },
        },
      }),
    }
  );

  const data = await res.json();
  if (data.error) {
    return { success: false, error: data.error.message };
  }
  return { success: true };
}

serve(async (req) => {
  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const now = new Date().toISOString();
    const { data: pendingNotifications, error: fetchError } = await supabase
      .from('scheduled_notifications')
      .select('*')
      .is('sent_at', null)
      .lte('scheduled_at', now);

    if (fetchError) {
      console.error('Error fetching notifications:', fetchError);
      return new Response(JSON.stringify({ error: fetchError.message }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    if (!pendingNotifications || pendingNotifications.length === 0) {
      return new Response(JSON.stringify({ message: 'No pending notifications' }), {
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const results: any[] = [];
    let accessToken: string | null = null;

    // Get FCM access token if service account is configured
    if (FIREBASE_SERVICE_ACCOUNT) {
      try {
        const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
        accessToken = await getAccessToken(sa);
        console.log('FCM: Got access token for project', sa.project_id);
      } catch (e: any) {
        console.error('FCM: Failed to get access token:', e);
      }
    }

    for (const notification of pendingNotifications) {
      const { title, body, todo_id: todoId, user_id: userId } = notification;

      // ----- Send via FCM v1 -----
      if (accessToken) {
        try {
          let tokenQuery = supabase.from('device_tokens').select('*');
          if (userId) {
            tokenQuery = tokenQuery.or(`user_id.eq.${userId},user_id.is.null`);
          }
          const { data: devices } = await tokenQuery;

          if (devices && devices.length > 0) {
            const sa = JSON.parse(FIREBASE_SERVICE_ACCOUNT);
            let sent = 0, failed = 0;
            for (const d of devices) {
              const r = await sendFcmV1(
                accessToken,
                sa.project_id,
                d.token,
                title,
                body,
                todoId
              );
              if (r.success) {
                sent++;
              } else {
                failed++;
                if (r.error?.includes('NOT_FOUND') || r.error?.includes('INVALID_ARGUMENT')) {
                  await supabase.from('device_tokens').delete().eq('token', d.token);
                }
              }
            }
            results.push({ id: notification.id, method: 'fcm', sent, failed });
          }
        } catch (fcmError: any) {
          console.error('FCM send error:', fcmError);
          results.push({ id: notification.id, method: 'fcm', status: 'failed', error: fcmError.message });
        }
      }

      // ----- Send via Web Push -----
      if (VAPID_PUBLIC_KEY && VAPID_PRIVATE_KEY) {
        try {
          webpush.setVapidDetails('mailto:todo-app@example.com', VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
          let subQuery = supabase.from('push_subscriptions').select('*');
          if (userId) subQuery = subQuery.or(`user_id.eq.${userId},user_id.is.null`);
          const { data: subs } = await subQuery;

          if (subs?.length) {
            const payload = JSON.stringify({ title, body, tag: todoId, url: '/' });
            for (const sub of subs) {
              try {
                await webpush.sendNotification(
                  { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
                  payload
                );
                results.push({ id: notification.id, method: 'webpush', status: 'sent' });
              } catch (e: any) {
                if (e.statusCode === 410) {
                  await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
                }
              }
            }
          }
        } catch (_) {}
      }

      await supabase
        .from('scheduled_notifications')
        .update({ sent_at: new Date().toISOString() })
        .eq('id', notification.id);
    }

    return new Response(JSON.stringify({
      message: `Processed ${pendingNotifications.length} notifications`,
      results
    }), { headers: { 'Content-Type': 'application/json' } });

  } catch (error: any) {
    console.error('Function error:', error);
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});
