// Web Push notification registration
const VAPID_PUBLIC_KEY = (window.SUPABASE_VAPID_PUBLIC_KEY || '').trim();

async function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) outputArray[i] = rawData.charCodeAt(i);
  return outputArray;
}

// Check if push notifications are supported
export function isPushSupported() {
  return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

// Get current notification permission status
export function getNotificationPermission() {
  if (!('Notification' in window)) return 'unsupported';
  return Notification.permission;
}

// Request notification permission
export async function requestNotificationPermission() {
  if (!('Notification' in window)) return 'unsupported';
  return await Notification.requestPermission();
}

// Register service worker and subscribe to push notifications
export async function registerAndSubscribePush(supabaseUrl, anonKey, userId) {
  if (!isPushSupported()) {
    console.log('Push notifications not supported');
    return { ok: false, reason: 'unsupported' };
  }
  
  try {
    // Request notification permission first
    const permission = await requestNotificationPermission();
    if (permission !== 'granted') {
      console.log('Notification permission denied');
      return { ok: false, reason: 'permission_denied' };
    }

    // Register Service Worker relative to base href (supports GitHub Pages subpath)
    const swPath = new URL('push-sw.js', document.baseURI).pathname;
    console.log('Registering service worker at:', swPath);
    
    const reg = await navigator.serviceWorker.register(swPath, { scope: document.baseURI });
    console.log('Service worker registered:', reg);
    
    // Wait for the service worker to be ready
    await navigator.serviceWorker.ready;
    console.log('Service worker ready');

    // Check for existing subscription
    let sub = await reg.pushManager.getSubscription();
    
    // If no subscription or VAPID key changed, create new subscription
    if (!sub) {
      if (!VAPID_PUBLIC_KEY) {
        console.log('Missing VAPID public key');
        return { ok: false, reason: 'missing_vapid' };
      }
      
      console.log('Creating new push subscription...');
      sub = await reg.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: await urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
      });
      console.log('Push subscription created:', sub.endpoint);
    }

    // Send subscription to Supabase REST API
    const { endpoint, keys } = sub.toJSON();
    console.log('Saving subscription to Supabase...');
    
    const response = await fetch(`${supabaseUrl}/rest/v1/push_subscriptions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': anonKey,
        'Authorization': `Bearer ${anonKey}`,
        'Prefer': 'resolution=merge-duplicates',
      },
      body: JSON.stringify({
        user_id: userId,
        endpoint,
        p256dh: keys.p256dh,
        auth: keys.auth,
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('Failed to save subscription:', errorText);
      // Don't fail - subscription still works, just won't persist across sessions
    } else {
      console.log('Push subscription saved to Supabase');
    }

    return { ok: true, subscription: sub };
  } catch (e) {
    console.error('Push registration error:', e);
    return { ok: false, reason: String(e) };
  }
}

// Expose functions globally for Flutter to call
window.pushNotifications = {
  isPushSupported,
  getNotificationPermission,
  requestNotificationPermission,
  registerAndSubscribePush,
};


