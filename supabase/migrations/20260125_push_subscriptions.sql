-- Create push_subscriptions table for Web Push notifications
CREATE TABLE IF NOT EXISTS push_subscriptions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT, -- Can be null for anonymous users
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_user_id ON push_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_push_subscriptions_endpoint ON push_subscriptions(endpoint);

-- Enable RLS
ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Allow anonymous inserts and updates (for web users without auth)
CREATE POLICY "Allow anonymous insert" ON push_subscriptions
  FOR INSERT WITH CHECK (true);

CREATE POLICY "Allow anonymous update" ON push_subscriptions
  FOR UPDATE USING (true) WITH CHECK (true);

CREATE POLICY "Allow anonymous select" ON push_subscriptions
  FOR SELECT USING (true);

-- Create a scheduled_notifications table to track which notifications to send
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

-- Index for efficient querying of pending notifications
CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_pending 
  ON scheduled_notifications(scheduled_at) 
  WHERE sent_at IS NULL;

-- Enable RLS
ALTER TABLE scheduled_notifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on scheduled_notifications" ON scheduled_notifications
  FOR ALL USING (true) WITH CHECK (true);

-- Function to clean up old sent notifications (older than 7 days)
CREATE OR REPLACE FUNCTION cleanup_old_notifications()
RETURNS void AS $$
BEGIN
  DELETE FROM scheduled_notifications 
  WHERE sent_at IS NOT NULL 
    AND sent_at < NOW() - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;
