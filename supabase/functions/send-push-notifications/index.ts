// Supabase Edge Function to send Web Push notifications
// Deploy with: supabase functions deploy send-push-notifications
// Set secrets: supabase secrets set VAPID_PRIVATE_KEY=your_private_key VAPID_PUBLIC_KEY=your_public_key

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

const VAPID_PUBLIC_KEY = Deno.env.get('VAPID_PUBLIC_KEY') || '';
const VAPID_PRIVATE_KEY = Deno.env.get('VAPID_PRIVATE_KEY') || '';
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') || '';
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';

// Web Push library for Deno
import webpush from "https://esm.sh/web-push@3.6.7";

serve(async (req) => {
  try {
    // Set VAPID details
    webpush.setVapidDetails(
      'mailto:todo-app@example.com',
      VAPID_PUBLIC_KEY,
      VAPID_PRIVATE_KEY
    );

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    // Get all pending notifications that are due
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

    // Get all push subscriptions
    const { data: subscriptions, error: subError } = await supabase
      .from('push_subscriptions')
      .select('*');

    if (subError) {
      console.error('Error fetching subscriptions:', subError);
      return new Response(JSON.stringify({ error: subError.message }), { 
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    const results: any[] = [];

    // Send notifications
    for (const notification of pendingNotifications) {
      const payload = JSON.stringify({
        title: notification.title,
        body: notification.body,
        tag: notification.todo_id,
        url: '/'
      });

      // Filter subscriptions for this user (or all if no user_id)
      const targetSubs = notification.user_id 
        ? subscriptions?.filter(s => s.user_id === notification.user_id || !s.user_id)
        : subscriptions;

      for (const sub of targetSubs || []) {
        try {
          const pushSubscription = {
            endpoint: sub.endpoint,
            keys: {
              p256dh: sub.p256dh,
              auth: sub.auth
            }
          };

          await webpush.sendNotification(pushSubscription, payload);
          results.push({ id: notification.id, endpoint: sub.endpoint, status: 'sent' });
        } catch (pushError: any) {
          console.error('Push error:', pushError);
          results.push({ id: notification.id, endpoint: sub.endpoint, status: 'failed', error: pushError.message });
          
          // If subscription is invalid (410 Gone), remove it
          if (pushError.statusCode === 410) {
            await supabase
              .from('push_subscriptions')
              .delete()
              .eq('endpoint', sub.endpoint);
          }
        }
      }

      // Mark notification as sent
      await supabase
        .from('scheduled_notifications')
        .update({ sent_at: new Date().toISOString() })
        .eq('id', notification.id);
    }

    return new Response(JSON.stringify({ 
      message: `Processed ${pendingNotifications.length} notifications`,
      results 
    }), {
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error: any) {
    console.error('Function error:', error);
    return new Response(JSON.stringify({ error: error.message }), { 
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});
