# Push Notifications Setup Guide

This guide explains how to enable background push notifications for your Todo app. These notifications work even when the browser tab is closed or the phone is locked.

## How It Works

1. **Web Push API** - Browser receives push messages via service worker
2. **Supabase Database** - Stores push subscriptions and scheduled notifications  
3. **Supabase Edge Function** - Sends push notifications at scheduled times

## Setup Steps

### 1. Run the Database Migration

Go to your Supabase Dashboard → SQL Editor and run:

```sql
-- Create push_subscriptions table for Web Push notifications
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT,
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint ON push_subscriptions(endpoint);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow anonymous insert" ON push_subscriptions FOR INSERT WITH CHECK (true);
CREATE POLICY "Allow anonymous update" ON push_subscriptions FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "Allow anonymous select" ON push_subscriptions FOR SELECT USING (true);

-- Create scheduled_notifications table
CREATE TABLE IF NOT EXISTS scheduled_notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  todo_id TEXT NOT NULL,
  user_id TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  scheduled_at TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_pending 
  ON scheduled_notifications(scheduled_at) 
  WHERE sent_at IS NULL;

ALTER TABLE scheduled_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on scheduled_notifications" ON scheduled_notifications
  FOR ALL USING (true) WITH CHECK (true);
```

### 2. Deploy the Edge Function

Install Supabase CLI if not already:
```bash
npm install -g supabase
```

Login and link your project:
```bash
supabase login
supabase link --project-ref pujfapldlclvykjjphjy
```

Set the VAPID keys as secrets:
```bash
supabase secrets set VAPID_PUBLIC_KEY="BO4yFsSAS7yzsoyY1EEHGDZgdO2dIXhFrWRXHQDked9r0AuZcq6udQYxImmVC5Nu08XilvSNs48zXUCNXwmPuuo"
supabase secrets set VAPID_PRIVATE_KEY="8YscsrUwZX793jG776oHgUpwP2DFvfKAOkDlVzl-T-0"
```

Deploy the function:
```bash
supabase functions deploy send-push-notifications
```

### 3. Set Up a Cron Job (Scheduled Trigger)

To send notifications at the scheduled time, you need to call the edge function periodically.

**Option A: Use Supabase pg_cron (Recommended)**

Go to Supabase Dashboard → SQL Editor and run:
```sql
-- Enable pg_cron extension (if not enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Create a cron job that calls the edge function every minute
SELECT cron.schedule(
  'send-push-notifications',
  '* * * * *', -- Every minute
  $$
  SELECT net.http_post(
    url := 'https://pujfapldlclvykjjphjy.supabase.co/functions/v1/send-push-notifications',
    headers := '{"Authorization": "Bearer YOUR_SERVICE_ROLE_KEY"}'::jsonb
  );
  $$
);
```

**Option B: Use External Cron Service**

Use a service like cron-job.org to call your edge function URL every minute:
- URL: `https://pujfapldlclvykjjphjy.supabase.co/functions/v1/send-push-notifications`
- Method: POST
- Headers: `Authorization: Bearer YOUR_ANON_KEY`

## VAPID Keys

These are your generated VAPID keys (already configured in the app):

- **Public Key**: `BO4yFsSAS7yzsoyY1EEHGDZgdO2dIXhFrWRXHQDked9r0AuZcq6udQYxImmVC5Nu08XilvSNs48zXUCNXwmPuuo`
- **Private Key**: `8YscsrUwZX793jG776oHgUpwP2DFvfKAOkDlVzl-T-0`

⚠️ **Keep the private key secret!** Never expose it in client-side code.

## Platform Support

| Platform | Support | Notes |
|----------|---------|-------|
| Chrome (Desktop) | ✅ Full | Works in background |
| Firefox (Desktop) | ✅ Full | Works in background |
| Edge (Desktop) | ✅ Full | Works in background |
| Safari (Desktop) | ✅ macOS 13+ | Requires permission |
| Chrome (Android) | ✅ Full | Works when phone locked |
| Safari (iOS) | ⚠️ iOS 16.4+ | Must add to Home Screen |
| Firefox (Android) | ✅ Full | Works in background |

### iOS Safari Notes

For iOS Safari to receive push notifications:
1. User must add the website to their Home Screen
2. iOS version must be 16.4 or later
3. User must grant notification permission

## Troubleshooting

### Notifications not appearing?

1. **Check browser permission**: Make sure notifications are allowed for the site
2. **Check Service Worker**: In DevTools → Application → Service Workers
3. **Check Console**: Look for any errors in the browser console
4. **Verify subscription**: Check the `push_subscriptions` table in Supabase

### Notifications delayed?

The edge function runs based on your cron schedule. If using a 1-minute cron, notifications may be up to 1 minute late.

### iOS not working?

Make sure:
- iOS version is 16.4+
- Website is added to Home Screen
- Notification permission is granted in Settings
