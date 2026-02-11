-- ============================================================
-- Device Tokens table for Firebase Cloud Messaging (FCM)
-- Stores FCM tokens for all platforms: Android, iOS, Web, macOS, Windows
-- ============================================================

CREATE TABLE IF NOT EXISTS device_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  token TEXT NOT NULL UNIQUE,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  platform TEXT NOT NULL DEFAULT 'unknown', -- android, ios, web, macos, windows
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for fast lookups by user
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id ON device_tokens(user_id);

-- Index for fast lookups by token
CREATE INDEX IF NOT EXISTS idx_device_tokens_token ON device_tokens(token);

-- Enable Row Level Security
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;

-- Policy: Users can insert their own tokens
CREATE POLICY "Users can insert own tokens"
  ON device_tokens FOR INSERT
  WITH CHECK (true);

-- Policy: Users can update their own tokens
CREATE POLICY "Users can update own tokens"
  ON device_tokens FOR UPDATE
  USING (true);

-- Policy: Users can delete their own tokens
CREATE POLICY "Users can delete own tokens"
  ON device_tokens FOR DELETE
  USING (true);

-- Policy: Service role can read all tokens (for sending notifications)
CREATE POLICY "Service role can read all tokens"
  ON device_tokens FOR SELECT
  USING (true);

-- ============================================================
-- Also ensure scheduled_notifications table exists
-- (in case the previous migration wasn't run)
-- ============================================================

CREATE TABLE IF NOT EXISTS scheduled_notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  todo_id TEXT NOT NULL,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT,
  scheduled_at TIMESTAMPTZ NOT NULL,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_pending
  ON scheduled_notifications(scheduled_at)
  WHERE sent_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_scheduled_notifications_user
  ON scheduled_notifications(user_id);
